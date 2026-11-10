"""Bounded local repair of published derived meshes; never redecimates a source.

Run with Blender, adding -- --apply to publish after every numerical check.
Kept vertices retain their original bindings. Edge rotations/collapses preserve
topology; submillimetre vertex adjustment is a reported fallback, not face dropping.
"""
import argparse
import copy
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.geometry import closest_point_on_tri
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from convert_garments import CONFIG, RESOURCES, distances, make_mesh, render_comparison, validate

TARGET = 1.25e-12
EXPORT_MINIMUM = 1e-12
RUNTIME_MINIMUM = 1e-14


def cross_squared(vertices, faces):
    p = np.asarray(vertices, dtype=np.float32)
    cross = np.cross(p[faces[:, 1]]-p[faces[:, 0]], p[faces[:, 2]]-p[faces[:, 0]])
    return np.sum(cross*cross, axis=1)


def sampled_surface_error(vertices, faces, reference_v, reference_f):
    triangles = vertices[faces]
    samples = np.concatenate([vertices, triangles.mean(axis=1),
        (triangles[:, 0]+triangles[:, 1])/2, (triangles[:, 1]+triangles[:, 2])/2,
        (triangles[:, 2]+triangles[:, 0])/2])
    tree = BVHTree.FromPolygons(reference_v.tolist(), reference_f.tolist(), all_triangles=True)
    errors = np.array([tree.find_nearest(Vector(point))[3] for point in samples])*1000
    return dict(rmsMM=float(np.sqrt((errors*errors).mean())), p95MM=float(np.percentile(errors, 95)),
                maxMM=float(errors.max()), samples=len(samples),
                sampling="all vertices, triangle centroids and three edge midpoints; not an exact Hausdorff bound")


def face_squared(face):
    return 4*face.calc_area()**2


def smooth(value):
    t = np.clip(value, 0, 1)
    return t*t*(3-2*t)


def resize_upper(payload, target):
    points = np.array(payload["vertices"], dtype=np.float32)
    sizing, fit = payload["sizing"], payload["fitting"]
    reference = sizing["reference"]
    shoulder, cuff = np.array(sizing["rightShoulder"]), np.array(sizing["rightCuff"])
    axis = cuff-shoulder
    axis /= np.linalg.norm(axis)
    bottom, top = float(points[:, 1].min()), float(points[:, 1].min()+reference["length"])
    width = target["chestCircumference"]/reference["chestCircumference"]
    shoulder_ratio = target["shoulderWidth"]/reference["shoulderWidth"]
    opening = target["sleeveOpening"]/reference["sleeveOpening"]
    sleeve = target["sleeveLength"]/reference["sleeveLength"]
    new_shoulder = shoulder*np.array([shoulder_ratio, 1, 1])-np.array([0, top, 0])
    chest_y = (new_shoulder[1]-target["armholeDepth"] if "armholeDepth" in target else
               (fit["chest"]["center"][1]-top)*target["length"]/reference["length"])
    hip_y, waist_y, source_chest_y = (fit[k]["center"][1] for k in ("hip", "waist", "chest"))
    lower_width = target.get("hipCircumference", target["chestCircumference"])/reference.get("hipCircumference", reference["chestCircumference"])
    result = []
    for point, weight in zip(points, fit["weights"]):
        y = point[1]
        if y <= source_chest_y:
            height = -target["length"]+(y-bottom)/max(source_chest_y-bottom, .01)*(chest_y+target["length"])
        elif y <= shoulder[1]:
            height = chest_y+(y-source_chest_y)/max(shoulder[1]-source_chest_y, .01)*(new_shoulder[1]-chest_y)
        else:
            height = y-top
        upper = smooth((y-source_chest_y)/max(shoulder[1]-source_chest_y, .01))
        hem = smooth((waist_y-y)/max(waist_y-hip_y, .01))
        body_width = width+(lower_width-width)*hem
        horizontal = body_width+(shoulder_ratio-body_width)*upper
        neck_radius = abs(shoulder[0])*.45
        if abs(point[0]) < neck_radius:
            horizontal += (1-horizontal)*upper*(1-abs(point[0])/neck_radius)
        trunk = np.array([point[0]*horizontal, height, point[2]*body_width])
        hood = smooth((y-top)/.08)
        trunk += (np.array([point[0], y-top, point[2]])-trunk)*hood
        progress = weight["sleeveProgress"]
        if progress:
            mirror = np.array([-1 if point[0] < 0 else 1, 1, 1])
            relative = point*mirror-shoulder
            along = axis*np.dot(relative, axis)
            cuff_progress = smooth((np.dot(relative, axis)/np.linalg.norm(cuff-shoulder)-.25)/.75)
            radius = width+(opening-width)*cuff_progress
            arm = (new_shoulder+along*sleeve+(relative-along)*radius)*mirror
            trunk += (arm-trunk)*progress
        result.append(trunk)
    return np.array(result, dtype=np.float32)


def resize_pants(payload, target):
    points = np.array(payload["vertices"], dtype=np.float32)
    binding = payload["trousers"]
    source = binding["reference"]
    chain = np.array(binding["rightLegCenters"])
    result = []
    for point, weight in zip(points, binding["legWeights"]):
        y = point[1]
        height = y*target["rise"]/source["rise"] if y >= -source["rise"] else -target["rise"]+(y+source["rise"])*target["inseam"]/source["inseam"]
        waist, hip = target["waistCircumference"]/source["waistCircumference"], target["hipCircumference"]/source["hipCircumference"]
        trunk_scale = waist+(hip-waist)*smooth(-y/(source["rise"]*.55))
        progress = smooth((-y-source["rise"])/source["inseam"])
        thigh, hem = target["thighCircumference"]/source["thighCircumference"], target["hemCircumference"]/source["hemCircumference"]
        radius = thigh+(hem-thigh)*progress
        center = np.array([np.interp(y, chain[:, 1], chain[:, 0]), y, np.interp(y, chain[:, 1], chain[:, 2])])
        center[0] *= -1 if point[0] < 0 else 1
        trunk = np.array([point[0]*trunk_scale, height, point[2]*trunk_scale])
        leg = np.array([center[0]*hip+(point[0]-center[0])*radius, height, center[2]*hip+(point[2]-center[2])*radius])
        result.append(trunk+(leg-trunk)*weight)
    return np.array(result, dtype=np.float32)


def edit_checks(payload):
    points = np.array(payload["vertices"], dtype=np.float32)
    faces = np.array(payload["indices"]).reshape(-1, 3)
    cases = {"source": points, "uniform_0.8": points*np.float32(.8),
             "anisotropic_small": points*np.array([.70, .75, .70], dtype=np.float32)}
    catalog = json.loads((RESOURCES / "garments.json").read_text())
    resource = payload["provenance"]["sourceFile"]
    name = next(name for name, cfg in CONFIG.items() if cfg["file"] == resource)
    for item in catalog:
        pattern = item["pattern"]
        if pattern.get("meshResource") != "meshy_"+name:
            continue
        target = pattern.get("dimensions") or pattern.get("trousers") or pattern.get("footwear")
        # Category specifications are also accepted at the pattern's named keys.
        if "sizing" in payload and target and "chestCircumference" in target:
            cases["catalog_"+item["selectionLabel"]] = resize_upper(payload, target)
        elif "trousers" in payload:
            target = pattern.get("trouserDimensions") or pattern.get("trousers") or target
            if target and "rise" in target:
                cases["catalog_"+item["selectionLabel"]] = resize_pants(payload, target)
        elif "footwear" in payload:
            target = pattern.get("footwearDimensions") or pattern.get("footwear") or target
            if target and "width" in target:
                binding = payload["footwear"]
                centers = np.array([binding["rightCenter"] if side > 0 else binding["leftCenter"] for side in binding["sides"]])
                cases["catalog_"+item["selectionLabel"]] = centers+(points-centers)*np.array([
                    target["width"]/binding["reference"]["width"], 1,
                    target["length"]/binding["reference"]["length"]])
    if "sizing" in payload and not any(k.startswith("catalog") for k in cases):
        reference = payload["sizing"]["reference"]
        target = {key: value*.9 for key, value in reference.items()}
        cases["small_upper_90pct"] = resize_upper(payload, target)
    if "trousers" in payload:
        cases["custom_small_pants"] = resize_pants(payload, dict(waistCircumference=.72, hipCircumference=.90,
            rise=.23, inseam=.68, thighCircumference=.50, hemCircumference=.30))
    if "footwear" in payload:
        binding = payload["footwear"]
        centers = np.array([binding["rightCenter"] if side > 0 else binding["leftCenter"] for side in binding["sides"]])
        cases["small_shoe_240x92"] = centers+(points-centers)*np.array([.092/.105, 1, .240/.270])
    result = {}
    for label, vertices in cases.items():
        q = cross_squared(vertices, faces)
        result[label] = dict(minimumCrossSquared=float(q.min()), failingTriangles=int((q <= RUNTIME_MINIMUM).sum()))
        assert result[label]["failingTriangles"] == 0, (name, label, result[label])
    assert result["source"]["minimumCrossSquared"] >= EXPORT_MINIMUM
    return result


def repair_geometry(payload):
    source = np.array(payload["vertices"])
    faces = np.array(payload["indices"]).reshape(-1, 3)
    mesh = bpy.data.meshes.new("sliver working mesh")
    mesh.from_pydata(source.tolist(), [], faces.tolist())
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    layer = bm.verts.layers.int.new("original_runtime_index")
    for i, vertex in enumerate(bm.verts):
        vertex[layer] = i
    protected = set()
    selections = [np.arange(len(source))]
    if "footwear" in payload:
        selections = [np.flatnonzero(np.array(payload["footwear"]["sides"]) == side) for side in (-1, 1)]
    for selection in selections:
        for axis in range(3):
            protected.add(int(selection[np.argmin(source[selection, axis])]))
            protected.add(int(selection[np.argmax(source[selection, axis])]))
    bounds = [(source[selection].min(axis=0), source[selection].max(axis=0)) for selection in selections]
    parents = list(range(len(source)))
    moved = set()
    statistics = Counter()

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def flip(face):
        for edge in sorted(face.edges, key=lambda e: -e.calc_length()):
            if len(edge.link_faces) != 2:
                continue
            first, second = edge.link_faces
            if first.normal.dot(second.normal) < .97:
                continue
            u, v = edge.verts
            a = next(p for p in first.verts if p not in edge.verts)
            b = next(p for p in second.verts if p not in edge.verts)
            if any(b in e.verts for e in a.link_edges):
                continue
            n1, n2 = (b.co-a.co).cross(u.co-a.co), (a.co-b.co).cross(v.co-b.co)
            if min(n1.length_squared, n2.length_squared) < TARGET*1.1:
                continue
            old_area = first.calc_area()+second.calc_area()
            if abs((n1.length+n2.length)/2-old_area) > old_area*.03:
                continue
            try:
                bmesh.ops.rotate_edges(bm, edges=[edge], use_ccw=False)
                statistics["edgeRotations"] += 1
                return True
            except (RuntimeError, ValueError):
                continue
        return False

    def collapse(face):
        candidates = []
        for edge in face.edges:
            if edge.calc_length() > .003:
                continue
            u, v = edge.verts
            common = ({p for e in u.link_edges for p in e.verts}-{u}) & ({p for e in v.link_edges for p in e.verts}-{v})
            opposite = {p for f in edge.link_faces for p in f.verts if p not in (u, v)}
            if common != opposite or (u.is_boundary and v.is_boundary and not edge.is_boundary):
                continue
            for keep, drop in [(u, v), (v, u)]:
                if drop[layer] in protected or (drop.is_boundary and not keep.is_boundary):
                    continue
                if edge.is_boundary:
                    old_ids = {keep[layer], drop[layer]}
                    if any(len({root(i) for i in trim["vertices"]}) <= 3 and old_ids.issubset({root(i) for i in trim["vertices"]})
                           for trim in payload["trims"]):
                        continue
                linked = set(keep.link_faces) | set(drop.link_faces)
                old_bad = sum(face_squared(f) < TARGET for f in linked)
                new_bad, seen, cost, valid = 0, set(), 0., True
                remaining, new_triangles = 0, []
                for other in linked:
                    if keep in other.verts and drop in other.verts:
                        continue
                    verts = [keep if p == drop else p for p in other.verts]
                    key = frozenset(verts)
                    if key in seen:
                        valid = False
                        break
                    seen.add(key)
                    normal = (verts[1].co-verts[0].co).cross(verts[2].co-verts[0].co)
                    squared = normal.length_squared
                    if squared <= RUNTIME_MINIMUM or normal.normalized().dot(other.normal) < .1:
                        valid = False
                        break
                    new_bad += squared < TARGET
                    cost += abs(normal.length/2-other.calc_area())
                    remaining += 1
                    new_triangles.append([v.co for v in verts])
                if valid and remaining and new_bad < old_bad:
                    error = min((closest_point_on_tri(drop.co, *points)-drop.co).length for points in new_triangles)
                    if error <= .00065:
                        candidates.append((error, cost, edge.calc_length(), keep[layer], keep, drop))
        if not candidates:
            return False
        _, _, _, _, keep, drop = min(candidates, key=lambda item: item[:4])
        old_keep, old_drop, position = keep[layer], drop[layer], keep.co.copy()
        bmesh.ops.weld_verts(bm, targetmap={drop: keep})
        keep[layer], keep.co = old_keep, position
        parents[old_drop] = old_keep
        statistics["edgeCollapses"] += 1
        return True

    def adjust(face):
        options = []
        for vertex in face.verts:
            if vertex[layer] in protected:
                continue
            a, b = [v for v in face.verts if v != vertex]
            edge = b.co-a.co
            if edge.length < 1e-7:
                continue
            foot = a.co+edge*((vertex.co-a.co).dot(edge)/edge.length_squared)
            perpendicular = vertex.co-foot
            if perpendicular.length < 1e-9:
                continue
            desired = math.sqrt(TARGET*1.5)/edge.length
            position = foot+perpendicular.normalized()*desired
            if abs(vertex.co.y) < 1e-9 and ("trousers" in payload or "footwear" in payload):
                position.y = 0
            displacement = (position-vertex.co).length
            if displacement > .00075 or (position-Vector(source[vertex[layer]])).length > .00075:
                continue
            old_bad = sum(face_squared(f) < TARGET for f in vertex.link_faces)
            new_bad, valid = 0, True
            for other in vertex.link_faces:
                points = [position if p == vertex else p.co for p in other.verts]
                normal = (points[1]-points[0]).cross(points[2]-points[0])
                if normal.length_squared <= RUNTIME_MINIMUM or normal.normalized().dot(other.normal) < .5:
                    valid = False
                    break
                new_bad += normal.length_squared < TARGET
            if valid and new_bad < old_bad:
                options.append((displacement, vertex[layer], vertex, position))
        if not options:
            return False
        _, _, vertex, position = min(options, key=lambda item: item[:2])
        vertex.co = position
        moved.add(vertex[layer])
        statistics["submillimetreVertexAdjustments"] += 1
        return True

    def adjust_patch(face):
        movable = [v for v in face.verts if v[layer] not in protected]
        incident = set(f for v in movable for f in v.link_faces)
        old_bad = sum(face_squared(f) < TARGET for f in incident)
        old_deficit = sum(max(0, 1-face_squared(f)/TARGET) for f in incident)
        original_positions = {v: v.co.copy() for v in movable}
        center = sum((v.co for v in face.verts), Vector())/3
        scale = (TARGET*1.4/face_squared(face))**.25
        candidates = [{v: center+(v.co-center)*scale for v in movable}]
        directions = [Vector((x, y, z)).normalized() for x in (-1, 0, 1)
                      for y in (-1, 0, 1) for z in (-1, 0, 1) if x or y or z]
        directions += [face.normal, -face.normal]
        for vertex in movable:
            for step in (.000005, .00001, .000025, .00005, .0001, .0002, .0004, .0007):
                for direction in directions:
                    candidates.append({vertex: vertex.co+direction*step})
        options = []
        for proposed in candidates:
            positions, valid = {}, True
            for vertex, position in proposed.items():
                bound_index = 0
                if "footwear" in payload:
                    side = payload["footwear"]["sides"][vertex[layer]]
                    bound_index = 0 if side == -1 else 1
                position = Vector(np.clip(position, *bounds[bound_index]))
                if "fitting" in payload and source[vertex[layer], 1] <= 0:
                    position.y = min(position.y, 0)
                if (position-Vector(source[vertex[layer]])).length > .00075:
                    valid = False
                    break
                positions[vertex] = position
            if not valid:
                continue
            new_bad, deficit = 0, 0.
            for other in incident:
                points = [positions.get(v, v.co) for v in other.verts]
                normal = (points[1]-points[0]).cross(points[2]-points[0])
                # A pre-existing microscopic fold can cross its old normal while
                # being unfolded; keep its winding, and protect all sound faces.
                if normal.length_squared <= RUNTIME_MINIMUM or (
                    face_squared(other) >= TARGET and normal.normalized().dot(other.normal) <= .0001
                ):
                    valid = False
                    break
                new_bad += normal.length_squared < TARGET
                deficit += max(0, 1-normal.length_squared/TARGET)
            if valid and (new_bad < old_bad or deficit < old_deficit*.95):
                cost = max((position-original_positions[v]).length for v, position in positions.items())
                options.append((cost, positions))
        if not options:
            return False
        _, positions = min(options, key=lambda option: option[0])
        for other in incident:
            points = [positions.get(v, v.co) for v in other.verts]
            normal = (points[1]-points[0]).cross(points[2]-points[0])
            if normal.dot(other.normal) < 0:
                statistics["microscopicFoldNormalReorientations"] += 1
        for vertex, position in positions.items():
            vertex.co = position
            moved.add(vertex[layer])
        statistics["constrainedSubmillimetrePatchAdjustments"] += 1
        return True

    for iteration in range(5000):
        bm.normal_update()
        bad = sorted((f for f in bm.faces if face_squared(f) < TARGET), key=face_squared)
        if not bad:
            break
        changed = False
        for face in bad:
            if face.is_valid and (flip(face) or collapse(face) or adjust(face)):
                changed = True
                break
        if not changed:
            changed = any(adjust_patch(face) for face in bad)
        if not changed:
            blocked = [(face_squared(f), [v[layer] for v in f.verts]) for f in bad[:12]]
            raise RuntimeError(f"No topology-safe submillimetre repair for {len(bad)} triangles: {blocked}")
    else:
        raise RuntimeError("Bounded sliver-repair iteration limit reached")
    bm.verts.ensure_lookup_table()
    vertices, original_ids = [], []
    for i, vertex in enumerate(bm.verts):
        vertex.index = i
        original_ids.append(vertex[layer])
        vertices.append(np.round(vertex.co[:], 8).tolist() if vertex[layer] in moved else source[vertex[layer]].tolist())
    triangles = [[v.index for v in face.verts] for face in bm.faces]
    bm.free()
    new_ids = {old: new for new, old in enumerate(original_ids)}
    trims = []
    for trim in payload["trims"]:
        loop = []
        for old in trim["vertices"]:
            value = new_ids[root(old)]
            if not loop or loop[-1] != value:
                loop.append(value)
        if loop[-1] == loop[0]:
            loop.pop()
        assert len(loop) >= 3 and len(set(loop)) == len(loop), "Boundary topology changed"
        trims.append(dict(trim, vertices=loop))
    return np.array(vertices), np.array(triangles), original_ids, trims, dict(statistics)


def topology(vertices, faces):
    edges = Counter(tuple(sorted((int(face[i]), int(face[(i+1) % 3])))) for face in faces for i in range(3))
    adjacency = defaultdict(set)
    for a, b in edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    remaining, components = set(range(len(vertices))), 0
    while remaining:
        stack = [remaining.pop()]
        components += 1
        while stack:
            for other in adjacency[stack.pop()]:
                if other in remaining:
                    remaining.remove(other)
                    stack.append(other)
    return dict(components=components, euler=len(vertices)-len(edges)+len(faces),
                nonmanifoldEdges=sum(n > 2 for n in edges.values()))


def repair(name, apply):
    path = RESOURCES / f"meshy_{name}.json"
    payload = json.loads(path.read_text())
    original = copy.deepcopy(payload)
    old_v, old_f = np.array(payload["vertices"]), np.array(payload["indices"]).reshape(-1, 3)
    minimum = float(cross_squared(old_v, old_f).min())
    if minimum >= TARGET:
        result = dict(id=name, changed=False, beforeVertices=len(old_v), afterVertices=len(old_v),
                    beforeTriangles=len(old_f), afterTriangles=len(old_f), minimumBefore=minimum,
                    minimumAfter=minimum, editChecks=edit_checks(payload),
                    resourceSHA256=hashlib.sha256(path.read_bytes()).hexdigest())
        if apply:
            report_path = ROOT / f"{name}_report.json"
            report = json.loads(report_path.read_text())
            previous = report.get("numericalRepair")
            if previous and previous.get("resourceSHA256") == result["resourceSHA256"]:
                return previous
            report["numericalRepair"] = result
            report_path.write_text(json.dumps(report, indent=2))
        return result
    v, f, source_ids, trims, operations = repair_geometry(payload)
    payload["vertices"], payload["indices"], payload["trims"] = v.tolist(), f.reshape(-1).tolist(), trims
    if "fitting" in payload:
        payload["fitting"]["weights"] = [original["fitting"]["weights"][i] for i in source_ids]
        cuff = np.array(original["sizing"]["rightCuff"])
        loop = min(trims, key=lambda trim: np.linalg.norm(v[trim["vertices"]].mean(axis=0)-cuff))["vertices"]
        payload["sizing"]["rightCuff"] = v[loop].mean(axis=0).tolist()
        payload["sizing"]["reference"]["sleeveOpening"] = float(np.linalg.norm(v[loop]-np.roll(v[loop], 1, axis=0), axis=1).sum())
        payload["sizing"]["reference"]["sleeveLength"] = float(np.linalg.norm(
            np.array(payload["sizing"]["rightCuff"])-np.array(payload["sizing"]["rightShoulder"])))
    elif "trousers" in payload:
        payload["trousers"]["legWeights"] = [original["trousers"]["legWeights"][i] for i in source_ids]
    else:
        payload["footwear"]["sides"] = [original["footwear"]["sides"][i] for i in source_ids]
        assert payload["footwear"]["soleThickness"] == original["footwear"]["soleThickness"]
    checks = validate(payload)
    editing = edit_checks(payload)
    before_topology, after_topology = topology(old_v, old_f), topology(v, f)
    assert before_topology == after_topology, (before_topology, after_topology)
    assert len(trims) == len(original["trims"])
    to_old = distances(v, f, old_v, old_f)
    from_old = distances(old_v, old_f, v, f)
    assert max(to_old["maxMM"], from_old["maxMM"]) < 1.0, (name, to_old, from_old)
    surface_to_old = sampled_surface_error(v, f, old_v, old_f)
    surface_from_old = sampled_surface_error(old_v, old_f, v, f)
    assert max(surface_to_old["maxMM"], surface_from_old["maxMM"]) < 1.0, (name, surface_to_old, surface_from_old)
    result = dict(id=name, changed=True, beforeVertices=len(old_v), afterVertices=len(v),
                  beforeTriangles=len(old_f), afterTriangles=len(f), minimumBefore=minimum,
                  minimumAfter=float(cross_squared(v, f).min()), operations=operations,
                  topology=after_topology, preservedBoundaryLoops=len(trims),
                  repairedToPrevious=to_old, previousToRepaired=from_old, editChecks=editing,
                  sampledSurfaceRepairedToPrevious=surface_to_old, sampledSurfacePreviousToRepaired=surface_from_old,
                  maximumKeptVertexDisplacementMM=float(np.linalg.norm(v-old_v[source_ids], axis=1).max()*1000),
                  previousResourceSHA256=hashlib.sha256(path.read_bytes()).hexdigest())
    print(name, result, flush=True)
    if apply:
        report_path = ROOT / f"{name}_report.json"
        report = json.loads(report_path.read_text())
        report["numericalRepair"] = result
        report["validation"] = checks
        report["selected"]["vertices"], report["selected"]["triangles"] = len(v), len(f)
        report["reduction"] = dict(vertices=1-len(v)/report["original"]["vertices"],
                                   triangles=1-len(f)/report["original"]["triangles"])
        report["measurements"] = {key: {k: val for k, val in payload[key].items() if k not in ("weights", "legWeights", "sides")}
                                  for key in ("sizing", "trousers", "footwear") if key in payload}
        bpy.ops.wm.open_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"))
        old_obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
        properties = dict(old_obj.items())
        previous = make_mesh("Previous derived mesh", old_v, old_f)
        current = make_mesh(f"Meshy_{name}_Runtime", v, f)
        render_comparison(previous, current, ROOT / f"{name}_sliver_repair.png")
        bpy.data.objects.remove(previous, do_unlink=True)
        for key, val in properties.items():
            current[key] = val
        current["sample_measurements"] = json.dumps({key: payload[key]["reference"] for key in ("sizing", "trousers", "footwear") if key in payload})
        if "fitting" in payload:
            for key, component in zip(["Hip", "Waist", "Chest", "Shoulder", "Sleeve"], range(5)):
                group = current.vertex_groups.new(name=key)
                for index, weight in enumerate(payload["fitting"]["weights"]):
                    value = weight["regions"][component] if component < 4 else weight["sleeveProgress"]
                    if value:
                        group.add([index], value, "REPLACE")
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"), compress=True)
        path.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False))
        result["resourceSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        report_path.write_text(json.dumps(report, indent=2))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--only", choices=CONFIG)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    results = [repair(name, args.apply) for name in ([args.only] if args.only else CONFIG)]
    (ROOT / ("sliver_repair_report.json" if args.apply else "sliver_repair_dry_run.json")).write_text(json.dumps(results, indent=2))
    print("ALL NUMERICAL REPAIRS PASS", flush=True)
