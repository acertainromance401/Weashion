"""Source-derived Meshy conversion. Run with the Blender binary, never system Python.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python \
    weashion/reference/garments/convert_garments.py -- --only long_sleeve

No source is saved. Candidate comparisons use the normalized source's visible skin,
not a procedural replacement. All measurements are editable sample garment values.
"""
import argparse
import hashlib
import json
import math
import mmap
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"
SOURCE = Path("/Users/acertainromance401/Desktop/Meshy Models")
CONFIG = {
    "long_sleeve": dict(file="Gray Long Sleeve Shirt_Meshy_AI_2026-10-28_95f43f.blend",
                       length=.70, chest=1.04, shoulder=.46, sleeve=.61, cuff=.20,
                       sourceShoulder=(.31, .425), kind="upper"),
    "hoodie": dict(file="Grey Hoodie_Meshy_AI_2026-10-28_c679f7.blend",
                   length=.70, chest=1.16, shoulder=.52, sleeve=.60, cuff=.20,
                   sourceShoulder=(.36, .445), kind="upper"),
    "dress_pants": dict(file="Gray Dress Pants Front and Back_Meshy_AI_2026-10-28_ac302b.blend",
                        waist=.82, hip=1.02, rise=.28, inseam=.76, thigh=.60, hem=.38,
                        sourceCrotch=.435, kind="trousers"),
    "jeans": dict(file="Blue Jeans on Black_Meshy_AI_2026-10-28_f1bc1c.blend",
                  waist=.82, hip=1.00, rise=.26, inseam=.78, thigh=.58, hem=.34,
                  sourceCrotch=.385, kind="trousers"),
    "bomber": dict(file="Olive Bomber Jacket_Meshy_AI_2026-10-28_fd0508.blend",
                   length=.66, chest=1.16, shoulder=.50, sleeve=.62, cuff=.20,
                   sourceShoulder=(.34, .435), kind="upper"),
    "sneakers": dict(file="White Sneakers on Black Background_Meshy_AI_2026-10-28_4c0a02.blend",
                     length=.27, width=.105, kind="footwear"),
}


def emit(message):
    print(message, flush=True)


def file_hash(path):
    with path.open("rb") as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            return hashlib.sha256(data).hexdigest()


def smooth(t):
    t = min(1., max(0., t))
    return t * t * (3 - 2 * t)


def arrays(obj):
    vertices = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)
    obj.data.calc_loop_triangles()
    faces = np.array([t.vertices[:] for t in obj.data.loop_triangles], dtype=np.int32)
    return vertices, faces


def compact_arrays(vertices, faces):
    seen, unique = set(), []
    for face in faces:
        key = tuple(sorted(face))
        if key not in seen:
            unique.append(face)
        seen.add(key)
    faces = np.array(unique)
    cross = np.cross(vertices[faces[:, 1]]-vertices[faces[:, 0]], vertices[faces[:, 2]]-vertices[faces[:, 0]])
    faces = faces[np.sum(cross*cross, axis=1) > 1.2e-14]
    used = np.unique(faces)
    remap = np.full(len(vertices), -1, dtype=np.int32)
    remap[used] = np.arange(len(used))
    return vertices[used], remap[faces]


def make_mesh(name, vertices, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices.tolist() if isinstance(vertices, np.ndarray) else vertices, [], faces.tolist() if isinstance(faces, np.ndarray) else faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def decimate(obj, count):
    activate(obj)
    modifier = obj.modifiers.new("Source-aware quadric edge collapse", "DECIMATE")
    modifier.ratio = min(1, count / max(len(obj.data.vertices), 1))
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    clean(obj)


def clean(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.index_update()
    seen, repeated = set(), []
    for face in bm.faces:
        key = tuple(sorted(v.index for v in face.verts))
        if key in seen:
            repeated.append(face)
        seen.add(key)
    bmesh.ops.delete(bm, geom=repeated, context="FACES")
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-7)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bad = [f for f in bm.faces if f.calc_area() <= 5.1e-8]
    bmesh.ops.delete(bm, geom=bad, context="FACES")
    bad = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=bad, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def split_nonmanifold(obj):
    """Separate bow-tie vertex fans and remove redundant source triangles."""
    vertices, faces = arrays(obj)
    incidence = defaultdict(list)
    for i, face in enumerate(faces):
        for a, b in zip(face, np.roll(face, -1)):
            incidence[tuple(sorted((int(a), int(b))))].append(i)
    remove = set()
    for edge, linked in incidence.items():
        if len(linked) > 2:
            ordered = sorted(linked, key=lambda i: np.linalg.norm(np.cross(
                vertices[faces[i, 1]]-vertices[faces[i, 0]],
                vertices[faces[i, 2]]-vertices[faces[i, 0]])), reverse=True)
            remove.update(ordered[2:])
    faces = np.array([face for i, face in enumerate(faces) if i not in remove])
    linked_faces = defaultdict(set)
    linked_edges = defaultdict(list)
    for i, face in enumerate(faces):
        for vertex in face:
            linked_faces[int(vertex)].add(i)
        for a, b in zip(face, np.roll(face, -1)):
            linked_edges[tuple(sorted((int(a), int(b))))].append(i)
    output = vertices.tolist()
    original_faces = faces.copy()
    for vertex, linked in linked_faces.items():
        remaining = set(linked)
        first = True
        while remaining:
            seed = remaining.pop()
            fan, stack = [seed], [seed]
            while stack:
                face_id = stack.pop()
                for other in original_faces[face_id]:
                    if other == vertex:
                        continue
                    for neighbor in linked_edges[tuple(sorted((vertex, int(other))))]:
                        if neighbor in remaining:
                            remaining.remove(neighbor)
                            fan.append(neighbor)
                            stack.append(neighbor)
            if first:
                first = False
            else:
                new_vertex = len(output)
                output.append(vertices[vertex].tolist())
                for face_id in fan:
                    faces[face_id, original_faces[face_id] == vertex] = new_vertex
    mesh = bpy.data.meshes.new(obj.name+" manifold skin")
    mesh.from_pydata(output, [], faces.tolist())
    mesh.update()
    obj.data = mesh


def convex_section(vertices, height, band=.008, side=None):
    points = vertices[np.abs(vertices[:, 1] - height) < band]
    if side is not None:
        points = points[points[:, 0] * side > 0]
    if len(points) < 8:
        points = vertices[np.abs(vertices[:, 1] - height) < band * 3]
        if side is not None:
            points = points[points[:, 0] * side > 0]
    points = sorted(set((float(p[0]), float(p[2])) for p in points))
    def cross(a, b, c):
        return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower, upper = [], []
    for p in points:
        while len(lower) > 1 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) > 1 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = np.array(lower[:-1] + upper[:-1])
    circumference = float(np.linalg.norm(hull - np.roll(hull, 1, axis=0), axis=1).sum())
    center = (hull.max(axis=0) + hull.min(axis=0)) / 2
    return dict(center=[float(center[0]), float(height), float(center[1])],
                halfWidth=float(np.ptp(hull[:, 0]) / 2), halfDepth=float(np.ptp(hull[:, 1]) / 2),
                circumference=circumference)


def mesh_section(tree, vertices, height, side=None, allow_open=False):
    estimate = convex_section(vertices, height, .012, side)
    origin = Vector((estimate["center"][0] if side else 0, height, estimate["center"][2]))
    points = []
    for angle in np.linspace(0, 2*math.pi, 128, endpoint=False):
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        hit = tree.ray_cast(origin, direction, .6)[0]
        if hit is None:
            continue
        # A visible seam/pocket lip or residual thin rim may lie just beyond
        # the primary skin. Never jump the empty gap to a separate sleeve/leg.
        following = tree.ray_cast(hit+direction*.00004, direction, .019)[0]
        if following is not None:
            hit = following
        points.append(hit[:])
    if len(points) < (72 if allow_open else 112):
        raise ValueError(f"Incomplete source cloth section at y={height}: {len(points)}/128 rays")
    points = np.array(points)
    center = (points.min(axis=0)+points.max(axis=0))/2
    return dict(center=center.tolist(), halfWidth=float(np.ptp(points[:, 0])/2),
                halfDepth=float(np.ptp(points[:, 2])/2),
                circumference=float(np.linalg.norm(points-np.roll(points, 1, axis=0), axis=1).sum()))


def open_torso_section(vertices, faces, height):
    triangles = vertices[faces]
    triangles = triangles[(triangles[:, :, 1].min(axis=1) < height)
                          & (triangles[:, :, 1].max(axis=1) > height)]
    adjacency, coordinates = defaultdict(set), {}
    for triangle in triangles:
        hits = []
        for a, b in zip(triangle, np.roll(triangle, -1, axis=0)):
            if (a[1]-height)*(b[1]-height) < 0:
                point = a+(b-a)*((height-a[1])/(b[1]-a[1]))
                key = tuple(np.round(point, 5))
                coordinates[key] = point
                hits.append(key)
        if len(hits) == 2:
            adjacency[hits[0]].add(hits[1])
            adjacency[hits[1]].add(hits[0])
    remaining, body = set(adjacency), []
    while remaining:
        seed = remaining.pop()
        group, stack = [seed], [seed]
        while stack:
            current = stack.pop()
            for other in adjacency[current]:
                if other in remaining:
                    remaining.remove(other)
                    group.append(other)
                    stack.append(other)
        points = np.array([coordinates[key] for key in group])
        if points[:, 0].min() < -.025 and points[:, 0].max() > .025:
            body.extend(points)
    if not body:
        raise ValueError(f"No connected open-front torso section at {height}")
    return convex_section(np.array(body), height, .001)


def opening_envelope(vertices, loop):
    points = vertices[loop].copy()
    height = float(points[:, 1].mean())
    points[:, 1] = height
    return convex_section(points, height, .001)["circumference"]


def normalize(name, cfg, vertices, faces):
    p = vertices[:, [0, 2, 1]].copy()
    p[:, 2] *= -1
    meta = {}
    if cfg["kind"] == "upper":
        sx, sy = cfg["sourceShoulder"]
        ymin = p[:, 1].min()
        sample = p[(abs(p[:, 1] - (sy - .27)) < .012) & (abs(p[:, 0]) < sx * 1.08)]
        section = convex_section(sample, sy - .27, .02)
        horizontal = cfg["chest"] / section["circumference"]
        vertical = cfg["length"] / (sy - ymin)
        distal = p[p[:, 0] > p[:, 0].max()-.25]
        _, vectors = np.linalg.eigh(np.cov(distal.T))
        distal_axis = vectors[:, -1]
        if distal_axis[0] < 0:
            distal_axis *= -1
        axial = p @ distal_axis
        cuff_cloud_absolute = p[(p[:, 0] > sx+.20) & (axial > axial[p[:, 0] > sx+.20].max()-.045)]
        cuff_source = (cuff_cloud_absolute.min(axis=0)+cuff_cloud_absolute.max(axis=0))/2
        shoulder_source = np.array([sx, sy, 0.])
        axis = cuff_source - shoulder_source
        axis /= np.linalg.norm(axis)
        shoulder = np.array([cfg["shoulder"] / 2, 0., 0.])
        cuff = shoulder + axis * (cfg["sleeve"]+.025)
        radial = np.array([-axis[1], axis[0], 0])
        radial /= np.linalg.norm(radial)
        cuff_cloud = cuff_cloud_absolute - cuff_source
        # A convex section in the oblique cuff plane is measured below after opening.
        cuff_radius = max(np.sqrt((cuff_cloud @ radial)**2 + cuff_cloud[:, 2]**2).max(), .025)
        radial_scale = cfg["cuff"] / (2 * math.pi * cuff_radius)
        out = []
        for point in p:
            side = 1 if point[0] >= 0 else -1
            q = point * [side, 1, 1]
            torso = np.array([point[0] * horizontal, (point[1] - sy) * vertical, point[2] * horizontal])
            upper = smooth((point[1] - (sy - .27)) / .27)
            torso[0] *= 1 + (cfg["shoulder"] / (2 * sx * horizontal) - 1) * upper
            t = np.dot(q - shoulder_source, axis)
            r = q - shoulder_source - t * axis
            progress = smooth((q[0] - sx * .93) / .16)
            expected_y = sy+(q[0]-sx)*axis[1]/max(axis[0], .1)
            progress *= max(smooth((q[1]-expected_y+.30)/.12), smooth((q[0]-sx-.10)/.12))
            along = (cfg["sleeve"]+.025) / np.linalg.norm(cuff_source - shoulder_source)
            radial_blend = min(1, max(0, t / np.linalg.norm(cuff_source - shoulder_source)))
            arm = shoulder + t * axis * along + r * (horizontal * (1-radial_blend) + radial_scale * radial_blend)
            arm[0] *= side
            out.append(torso * (1-progress) + arm * progress)
        out = np.array(out)
        levels = [-cfg["length"]*.91, -cfg["length"]*.64, -cfg["length"]*.40, 0.]
        desired = {"long_sleeve": [1., 1., cfg["chest"]],
                   "hoodie": [1.06, 1.12, cfg["chest"]],
                   "bomber": [1.04, 1.10, cfg["chest"]]}[name]
        chest_cloud = out[abs(out[:, 0]) < cfg["shoulder"]*.55]
        section_tree = BVHTree.FromPolygons(out.tolist(), faces.tolist(), all_triangles=True)
        factors = [target/(open_torso_section(out, faces, y) if name == "bomber"
                           else mesh_section(section_tree, chest_cloud, y))["circumference"]
                   for target, y in zip(desired, levels)]
        factors.append(1.)
        for i, point in enumerate(out):
            sleeve = smooth((abs(point[0])-shoulder[0]*.97)/.105)
            expected_y = (abs(point[0])-shoulder[0])*axis[1]/max(axis[0], .1)
            sleeve *= max(smooth((point[1]-expected_y+.20)/.12), smooth((abs(point[0])-shoulder[0]-.10)/.08))
            torso_factor = float(np.interp(point[1], levels, factors))
            scale = 1+(torso_factor-1)*(1-sleeve)
            out[i, [0, 2]] *= scale
        meta.update(rightShoulder=shoulder.tolist(), rightCuff=cuff.tolist(), sleeveAxis=axis.tolist())
        return out, meta
    if cfg["kind"] == "trousers":
        top, bottom = p[:, 1].max(), p[:, 1].min()
        crotch = float(p[abs(p[:, 0]) < .008, 1].min())
        heights = np.linspace(bottom+.025, crotch-.035, 18)
        source_centers = []
        for y in heights:
            s = convex_section(p, y, .012, 1)
            source_centers.append(s["center"])
        top_section = convex_section(p, top-.045, .012)
        hip_section = convex_section(p, top-.27, .012)
        leg_sections = [convex_section(p, h, .012, 1) for h in heights]
        result = []
        for point in p:
            y = point[1]
            out_y = -cfg["rise"] * (top-y)/(top-crotch) if y >= crotch else -cfg["rise"] - cfg["inseam"]*(crotch-y)/(crotch-bottom)
            pelvis_t = min(1, max(0, (top-y)/.27))
            desired = cfg["waist"] * (1-pelvis_t) + cfg["hip"] * pelvis_t
            actual = top_section["circumference"]*(1-pelvis_t) + hip_section["circumference"]*pelvis_t
            torso = point[[0, 2]] * (desired/actual)
            center = np.array([np.interp(y, heights, [s["center"][0] for s in leg_sections]),
                               np.interp(y, heights, [s["center"][2] for s in leg_sections])])
            center[0] *= 1 if point[0] >= 0 else -1
            t = min(1, max(0, (y-bottom)/(crotch-bottom)))
            blend = smooth(t/.75)
            desired_leg = cfg["hem"]*(1-blend) + cfg["thigh"]*blend
            actual_leg = np.interp(y, heights, [s["circumference"] for s in leg_sections])
            scale = desired_leg / actual_leg
            destination = np.array([(.105 + .008*t) * (1 if point[0] >= 0 else -1), center[1]*(desired/actual)])
            leg = destination + (point[[0, 2]] - center) * scale
            weight = smooth((crotch + .16-y)/.20)
            xz = torso*(1-weight) + leg*weight
            result.append([xz[0], out_y, xz[1]])
        meta.update(sourceLegCenters=source_centers)
        return np.array(result), meta
    # Foot components are normalized independently: the source pair gap is never
    # folded into the per-shoe width or length.
    result = p.copy()
    centers = {}
    for side in [-1, 1]:
        selection = p[:, 0]*side > 0
        shoe = p[selection]
        low, high = shoe.min(axis=0), shoe.max(axis=0)
        center = (low+high)/2
        scale = np.array([cfg["width"]/(high[0]-low[0]), cfg["length"]/(high[2]-low[2]), cfg["length"]/(high[2]-low[2])])
        shoe = (shoe-center)*scale
        shoe[:, 0] += .09*side
        shoe[:, 1] -= shoe[:, 1].min()
        result[selection] = shoe
        centers[side] = [.09*side, 0., 0.]
    meta.update(rightCenter=centers[1], leftCenter=centers[-1])
    return result, meta


def extract_skin(obj, name, cfg, meta):
    if cfg["kind"] == "footwear":
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    visibility_tree = BVHTree.FromBMesh(bm)
    shoulder = Vector(meta.get("rightShoulder", [0, 0, 0]))
    axis = Vector(meta.get("sleeveAxis", [1, 0, 0]))
    detail_faces = set()
    if name == "hoodie":
        remaining = set(bm.faces)
        regions = []
        while remaining:
            seed = remaining.pop()
            group, stack = [seed], [seed]
            while stack:
                face = stack.pop()
                for edge in face.edges:
                    for other in edge.link_faces:
                        if other in remaining:
                            remaining.remove(other)
                            group.append(other)
                            stack.append(other)
            regions.append(group)
        regions.sort(key=len, reverse=True)
        for region in regions[1:]:
            detail_faces.update(region)
    source_points = np.array([v.co[:] for v in bm.verts])
    arm_x, arm_y, arm_z = [], [], []
    if cfg["kind"] == "upper":
        for x in np.linspace(shoulder.x+.035, abs(source_points[:, 0]).max()-.012, 36):
            expected_y = (x-shoulder.x)*axis.y/max(axis.x, .1)
            cloud = source_points[(abs(abs(source_points[:, 0])-x) < .016)
                                  & (abs(source_points[:, 1]-expected_y) < .15)]
            if len(cloud) > 5:
                arm_x.append(x)
                arm_y.append(float((np.percentile(cloud[:, 1], 2)+np.percentile(cloud[:, 1], 98))/2))
                arm_z.append(float((np.percentile(cloud[:, 2], 2)+np.percentile(cloud[:, 2], 98))/2))
    inward = set()
    for face in bm.faces:
        if face in detail_faces:
            continue
        center = face.calc_center_median()
        if cfg["kind"] == "upper":
            side = 1 if center.x >= 0 else -1
            q = Vector((abs(center.x), center.y, center.z))
            t = (q-shoulder).dot(axis)
            expected_y = (abs(center.x)-shoulder.x)*axis.y/max(axis.x, .1)
            if abs(center.x) > shoulder.x+.04 and t > .03 and center.y > expected_y-.19:
                radial = Vector((0, center.y-float(np.interp(abs(center.x), arm_x, arm_y)),
                                 center.z-float(np.interp(abs(center.x), arm_x, arm_z))))
            elif name == "hoodie" and center.y > .025:
                radial = center-Vector((0, .13, -.025))
            else:
                radial = Vector((center.x, 0, center.z))
        else:
            radial = center-Vector((.108*(1 if center.x > 0 else -1), center.y, 0)) if center.y < -cfg["rise"]+.015 else Vector((center.x, 0, center.z))
        score = face.normal.dot(radial.normalized()) if radial.length > .001 else 0
        if score < -.10:
            visible = False
            for component in range(3):
                if abs(face.normal[component]) < .16:
                    continue
                direction = Vector((0, 0, 0))
                direction[component] = 1 if face.normal[component] > 0 else -1
                if visibility_tree.ray_cast(center+direction*.00003, direction, 3)[0] is None:
                    visible = True
                    break
            if not visible:
                inward.add(face)
    remove = []
    while inward:
        seed = inward.pop()
        group, stack = [seed], [seed]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for other in edge.link_faces:
                    if other in inward:
                        inward.remove(other)
                        group.append(other)
                        stack.append(other)
        if len(group) > 140:
            remove.extend(group)
    emit(f"{name}: stripped {len(remove)} inward-wall faces (small negative-normal wrinkle patches retained)")
    if cfg["kind"] == "trousers":
        for face in bm.faces:
            y = face.calc_center_median().y
            if (y > -.065 and face.normal.y > .40) or (
                y < -cfg["rise"]-cfg["inseam"]+.055 and face.normal.y < -.35
            ):
                remove.append(face)
    bmesh.ops.delete(bm, geom=list(set(remove)), context="FACES")
    if cfg["kind"] == "upper":
        axis = Vector(meta["sleeveAxis"])
        cuts = [(Vector((0, -cfg["length"]+.008, 0)), Vector((0, -1, 0)))]
        for side in [-1, 1]:
            cuff = Vector(meta["rightCuff"])
            cuff.x *= side
            direction = axis.copy()
            direction.x *= side
            cuts.append((cuff-direction*.025, direction))
        for point, normal in cuts:
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                                  plane_co=point, plane_no=normal, clear_outer=True, dist=1e-7)
    else:
        for point, normal in [(Vector((0, -.008, 0)), Vector((0, 1, 0))),
                              (Vector((0, -cfg["rise"]-cfg["inseam"]+.008, 0)), Vector((0, -1, 0)))]:
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                                  plane_co=point, plane_no=normal, clear_outer=True, dist=1e-7)
    unseen, components = set(bm.faces), []
    while unseen:
        seed = unseen.pop()
        group, stack = [seed], [seed]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for neighbor in edge.link_faces:
                    if neighbor in unseen:
                        unseen.remove(neighbor)
                        group.append(neighbor)
                        stack.append(neighbor)
        components.append(group)
    components.sort(key=lambda group: sum(f.calc_area() for f in group), reverse=True)
    emit(f"{name}: cut shell components {[(len(g), round(sum(f.calc_area() for f in g), 5)) for g in components[:12]]}")
    if len(components) > 1:
        # A true thickness shell has nearly equal inner/outer areas; larger
        # envelopes and relief make its exterior the larger connected sheet.
        retain = set(components[0])
        for group in components[1:]:
            center = sum((f.calc_center_median() for f in group), Vector())/len(group)
            visible_detail = (name == "hoodie" and abs(center.x) < .065 and center.y > -.24 and center.z > .07)
            visible_detail |= name == "dress_pants" and center.y > -.08
            if visible_detail and sum(f.calc_area() for f in group) > .00003:
                retain.update(group)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in retain], context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    clean(obj)
    split_nonmanifold(obj)
    # Repair small residual source defects while leaving real garment openings.
    vertices, faces = arrays(obj)
    loops, _ = boundary_loops(vertices, faces)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    edge_map = {tuple(sorted(v.index for v in edge.verts)): edge for edge in bm.edges}
    for loop in loops:
        p = vertices[loop]
        center = p.mean(axis=0)
        actual_opening = cfg["kind"] == "upper" and (
            abs(center[0]) > meta["rightCuff"][0]-.07 or (center[1] > -.07 and abs(center[0]) < .16))
        actual_opening |= cfg["kind"] == "trousers" and (
            center[1] > -.04 or center[1] < -cfg["rise"]-cfg["inseam"]+.05)
        if not actual_opening and np.linalg.norm(p-np.roll(p, 1, axis=0), axis=1).sum() < .24:
            try:
                bmesh.ops.holes_fill(bm, edges=[edge_map[tuple(sorted((a, b)))] for a, b in zip(loop, np.roll(loop, -1))], sides=0)
            except RuntimeError:
                pass
    bm.to_mesh(obj.data)
    bm.free()
    clean(obj)


def boundary_loops(vertices, faces):
    counts = Counter(tuple(sorted((int(a), int(b)))) for face in faces for a, b in zip(face, np.roll(face, -1)))
    adjacency = defaultdict(list)
    for (a, b), count in counts.items():
        if count == 1:
            adjacency[a].append(b)
            adjacency[b].append(a)
    unused = {e for e, count in counts.items() if count == 1}
    loops = []
    while unused:
        a, b = next(iter(unused))
        loop = [a]
        unused.remove(tuple(sorted((a, b))))
        previous, current = a, b
        for _ in range(len(adjacency)+1):
            if current in loop:
                start = loop.index(current)
                simple = loop[start:]
                if len(simple) >= 3:
                    loops.append(simple)
                break
            loop.append(current)
            candidates = [v for v in adjacency[current] if tuple(sorted((current, v))) in unused]
            if not candidates:
                break
            nxt = candidates[0]
            unused.remove(tuple(sorted((current, nxt))))
            previous, current = current, nxt
    return loops, counts


def distances(vertices, faces, reference_v, reference_f):
    tree = BVHTree.FromPolygons(reference_v.tolist(), reference_f.tolist(), all_triangles=True)
    sample = vertices[::max(1, len(vertices)//18000)]
    ds = np.array([tree.find_nearest(Vector(p))[3] for p in sample])
    return dict(rmsMM=float(np.sqrt((ds*ds).mean())*1000), p95MM=float(np.percentile(ds, 95)*1000),
                maxMM=float(ds.max()*1000), samples=len(ds))


def visible_source_fidelity(vertices, faces, source_v, source_f):
    source_tree = BVHTree.FromPolygons(source_v.tolist(), source_f.tolist(), all_triangles=True)
    runtime_tree = BVHTree.FromPolygons(vertices.tolist(), faces.tolist(), all_triangles=True)
    result = {}
    for label, direction, horizontal in [("front", (0, 0, -1), 0), ("back", (0, 0, 1), 0), ("right", (-1, 0, 0), 2)]:
        direction = Vector(direction)
        errors, intersection, union = [], 0, 0
        axis = 2 if horizontal == 0 else 0
        for u in np.linspace(source_v[:, horizontal].min()-.002, source_v[:, horizontal].max()+.002, 96):
            for y in np.linspace(source_v[:, 1].min()-.002, source_v[:, 1].max()+.002, 96):
                origin = [0., y, 0.]
                origin[horizontal] = u
                origin[axis] = -3*direction[axis]
                a = source_tree.ray_cast(Vector(origin), direction, 6)[0]
                b = runtime_tree.ray_cast(Vector(origin), direction, 6)[0]
                if a is not None or b is not None:
                    union += 1
                if a is not None and b is not None:
                    intersection += 1
                    errors.append(abs(a[axis]-b[axis]))
        e = np.array(errors)*1000
        result[label] = dict(silhouetteIoU=intersection/max(1, union), rmsMM=float(np.sqrt((e*e).mean())),
                             p95MM=float(np.percentile(e, 95)), maxMM=float(e.max()), raysCompared=len(e))
    return result


def silhouette_mask(vertices, faces, projection, bounds, resolution=192):
    p = vertices @ projection.T
    low, high = bounds
    p = (p-low)/(high-low)*(resolution-3)+1
    mask = np.zeros((resolution, resolution), dtype=np.bool_)
    for t in p[faces]:
        lo = np.maximum(0, np.floor(t.min(axis=0)).astype(int))
        hi = np.minimum(resolution-1, np.ceil(t.max(axis=0)).astype(int))
        if (hi < lo).any():
            continue
        xs, ys = np.meshgrid(np.arange(lo[0], hi[0]+1)+.5, np.arange(lo[1], hi[1]+1)+.5)
        signs = []
        for a, b in zip(t, np.roll(t, -1, axis=0)):
            signs.append((b[0]-a[0])*(ys-a[1])-(b[1]-a[1])*(xs-a[0]))
        inside = ((signs[0] >= 0) & (signs[1] >= 0) & (signs[2] >= 0)) | ((signs[0] <= 0) & (signs[1] <= 0) & (signs[2] <= 0))
        mask[lo[1]:hi[1]+1, lo[0]:hi[0]+1] |= inside
    return mask


def silhouettes(vertices, faces, source_v, source_f):
    result = {}
    projections = {"front": np.array([[1, 0, 0], [0, 1, 0]]),
                   "side": np.array([[0, 0, 1], [0, 1, 0]]),
                   "threeQuarter": np.array([[.707107, 0, -.707107], [0, 1, 0]])}
    for name, projection in projections.items():
        p = source_v @ projection.T
        bounds = (p.min(axis=0)-.004, p.max(axis=0)+.004)
        original = silhouette_mask(source_v, source_f, projection, bounds)
        reduced = silhouette_mask(vertices, faces, projection, bounds)
        union = (original | reduced).sum()
        result[name] = float((original & reduced).sum()/max(union, 1))
    return result


def metadata(name, cfg, vertices, faces, meta, loops):
    result = {}
    section_tree = BVHTree.FromPolygons(vertices.tolist(), faces.tolist(), all_triangles=True)
    if cfg["kind"] == "upper":
        shoulder = np.array(meta["rightShoulder"])
        expected = np.array(meta["rightCuff"])
        cuff_candidates = [loop for loop in loops if np.mean(vertices[loop], axis=0)[0] > shoulder[0]+.10
                           and np.linalg.norm(vertices[loop]-np.roll(vertices[loop], 1, axis=0), axis=1).sum() > .08]
        if not cuff_candidates:
            raise ValueError("No open ordered right cuff found")
        cuff_loop = min(cuff_candidates, key=lambda loop: np.linalg.norm(np.mean(vertices[loop], axis=0)-expected))
        cuff = vertices[cuff_loop].mean(axis=0)
        cuff_circumference = float(np.linalg.norm(vertices[cuff_loop]-np.roll(vertices[cuff_loop], 1, axis=0), axis=1).sum())
        hip_y, waist_y, chest_y = -cfg["length"]*.91, -cfg["length"]*.64, -cfg["length"]*.40
        torso_vertices = vertices[abs(vertices[:, 0]) < cfg["shoulder"]*.59]
        sections = [(open_torso_section(vertices, faces, y) if name == "bomber"
                     else mesh_section(section_tree, torso_vertices, y)) for y in [hip_y, waist_y, chest_y]]
        weights = []
        for point in vertices:
            y = point[1]
            if y <= hip_y:
                regions = [1., 0., 0., 0.]
            elif y < waist_y:
                b = smooth((y-hip_y)/(waist_y-hip_y))
                regions = [1-b, b, 0., 0.]
            elif y < chest_y:
                b = smooth((y-waist_y)/(chest_y-waist_y))
                regions = [0., 1-b, b, 0.]
            else:
                b = smooth((y-chest_y)/(-chest_y))
                regions = [0., 0., 1-b, b]
            sleeve = smooth((abs(point[0])-shoulder[0]*.97)/.105)
            axis = np.array(meta["sleeveAxis"])
            expected_y = (abs(point[0])-shoulder[0])*axis[1]/max(axis[0], .1)
            sleeve *= max(smooth((point[1]-expected_y+.20)/.12), smooth((abs(point[0])-shoulder[0]-.10)/.08))
            if name == "hoodie" and (point[1] > 0 or (point[1] > -.12 and point[2] < -.065 and abs(point[0]) < .18)):
                regions, sleeve = [0., 0., 0., 1.], 0.
            weights.append(dict(regions=regions, sleeveProgress=sleeve))
        reference = dict(chestCircumference=sections[2]["circumference"],
                         waistCircumference=sections[1]["circumference"], hipCircumference=sections[0]["circumference"],
                         shoulderWidth=cfg["shoulder"], length=float(-vertices[:, 1].min()),
                         sleeveLength=float(np.linalg.norm(cuff-shoulder)), sleeveOpening=cuff_circumference,
                         armholeDepth=-chest_y)
        result["fitting"] = dict(hip=sections[0], waist=sections[1], chest=sections[2],
                                 shoulderWidth=cfg["shoulder"], shoulderHeight=0.,
                                 referenceCircumferences=[.98, .82, .98], weights=weights)
        result["sizing"] = dict(reference=reference, rightShoulder=shoulder.tolist(), rightCuff=cuff.tolist())
    elif cfg["kind"] == "trousers":
        rise = meta.get("actualRise", cfg["rise"])
        hems = [loop for loop in loops if np.mean(vertices[loop], axis=0)[0] > .025
                and np.mean(vertices[loop], axis=0)[1] < -rise-cfg["inseam"]+.075
                and np.linalg.norm(vertices[loop]-np.roll(vertices[loop], 1, axis=0), axis=1).sum() > .15]
        hem_loop = max(hems, key=lambda ids: opening_envelope(vertices, ids))
        hem_circumference = opening_envelope(vertices, hem_loop)
        waists = [loop for loop in loops if np.mean(vertices[loop], axis=0)[1] > -.09
                  and np.linalg.norm(vertices[loop]-np.roll(vertices[loop], 1, axis=0), axis=1).sum() > .45]
        waist_circumference = max((opening_envelope(vertices, loop) for loop in waists), default=0)
        if not waist_circumference:
            waist_circumference = mesh_section(section_tree, vertices, -.022, allow_open=True)["circumference"]
        reference = dict(waistCircumference=waist_circumference,
                         hipCircumference=mesh_section(section_tree, vertices, -rise*.58)["circumference"],
                         rise=rise, inseam=float(-vertices[:, 1].min()-rise),
                         thighCircumference=mesh_section(section_tree, vertices, -rise-.07, 1)["circumference"],
                         hemCircumference=hem_circumference)
        centers = [convex_section(vertices, y, .015, 1)["center"] for y in np.linspace(-rise-reference["inseam"]+.016, -rise-.025, 14)]
        result["trousers"] = dict(reference=reference, rightLegCenters=centers,
                                  legWeights=[smooth((-p[1]-(rise-.12))/.12) for p in vertices])
    else:
        sides = [1 if p[0] >= 0 else -1 for p in vertices]
        result["footwear"] = dict(reference=dict(length=cfg["length"], width=cfg["width"]),
                                  rightCenter=meta["rightCenter"], leftCenter=meta["leftCenter"], sides=sides,
                                  soleThickness=meta["soleThickness"])
    return result


def validate(payload):
    v, f = np.array(payload["vertices"]), np.array(payload["indices"]).reshape(-1, 3)
    assert len(v) <= 12000 and len(f) <= 40000
    assert np.isfinite(v).all() and np.linalg.norm(v, axis=1).max() < 3
    assert len(np.unique(f)) == len(v)
    cross = np.cross(v[f[:, 1]]-v[f[:, 0]], v[f[:, 2]]-v[f[:, 0]])
    assert (np.sum(cross*cross, axis=1) > 1e-14).all()
    for trim in payload["trims"]:
        loop = trim["vertices"]
        assert len(set(loop)) == len(loop)
    if "fitting" in payload:
        fit = payload["fitting"]
        assert fit["hip"]["center"][1] < fit["waist"]["center"][1] < fit["chest"]["center"][1] < fit["shoulderHeight"]
        assert len(fit["weights"]) == len(v)
        assert all(abs(sum(w["regions"])-1) < .0001 and 0 <= w["sleeveProgress"] <= 1 for w in fit["weights"])
    if "trousers" in payload:
        centers = np.array(payload["trousers"]["rightLegCenters"])
        assert (np.diff(centers[:, 1]) > 0).all() and (centers[:, 0] > 0).all()
    return dict(vertices=len(v), triangles=len(f), unusedVertices=0, degenerateTriangles=0,
                maximumVertexNorm=float(np.linalg.norm(v, axis=1).max()))


def render_comparison(source, optimized, filename):
    for obj in list(bpy.context.scene.objects):
        if obj not in (source, optimized):
            bpy.data.objects.remove(obj, do_unlink=True)
    source.hide_render = optimized.hide_render = False
    sv, _ = arrays(source)
    ov, _ = arrays(optimized)
    width = max(np.ptp(sv[:, 0]), np.ptp(ov[:, 0]))
    source.location.x = -width*.57
    optimized.location.x = width*.57
    for obj in (source, optimized):
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.use_compositing = False
    scene.render.use_sequencer = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.studio_light = "paint.sl"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (.48, .51, .52)
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.show_specular_highlight = True
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (.82, .82, .82)
    camera_data = bpy.data.cameras.new("Source left - runtime right")
    camera = bpy.data.objects.new("Source left - runtime right", camera_data)
    scene.collection.objects.link(camera)
    center_y = float((sv[:, 1].min()+sv[:, 1].max())/2)
    camera.location = (0, center_y+.12, 4)
    target = Vector((0, center_y, 0))
    camera.rotation_euler = (-math.atan2(.12, 4), 0, 0)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(width*2.35, float(np.ptp(sv[:, 1]))*1.9)
    scene.camera = camera
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(filename)
    bpy.ops.render.render(write_still=True)
    camera.location.z = -4
    camera.rotation_euler = (-math.atan2(.12, 4), math.pi, 0)
    scene.render.filepath = str(filename.with_name(filename.stem+"_back.png"))
    bpy.ops.render.render(write_still=True)
    if "sneakers" in filename.stem:
        camera.location = (0, center_y+.75, 4)
        camera.rotation_euler = (-math.atan2(.75, 4), 0, 0)
        scene.render.filepath = str(filename.with_name(filename.stem+"_elevated.png"))
        bpy.ops.render.render(write_still=True)
    camera.location.z = 4
    camera.rotation_euler = (-math.atan2(.12, 4), 0, 0)
    source.location.x = optimized.location.x = 0


def convert(name):
    cfg = CONFIG[name]
    path = SOURCE / cfg["file"]
    bpy.ops.wm.open_mainfile(filepath=str(path))
    before = file_hash(path)
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    source_v, source_f = arrays(obj)
    original_count = dict(vertices=len(source_v), triangles=len(source_f))
    source_v = np.array([obj.matrix_world @ Vector(v) for v in source_v])
    normalized, meta = normalize(name, cfg, source_v, source_f)
    if cfg["kind"] == "footwear":
        tree = BVHTree.FromPolygons(normalized.tolist(), source_f.tolist(), all_triangles=True)
        seating_samples = []
        for side in [-1, 1]:
            for x_offset in [-.010, 0, .010]:
                for z in [-.095, -.080, -.065, -.050]:
                    hit = tree.ray_cast(Vector((side*.09+x_offset, .075, z)), Vector((0, -1, 0)), .09)[0]
                    if hit is not None and .008 < hit.y < .055:
                        seating_samples.append(float(hit.y))
        meta["soleThicknessSamples"] = seating_samples
        meta["soleThickness"] = round(float(np.median(seating_samples)), 4) if seating_samples else .027
    original = make_mesh("Normalized full source (comparison only)", normalized, source_f)
    bpy.data.objects.remove(obj, do_unlink=True)
    working = make_mesh("Source-derived open cloth skin", normalized, source_f)
    # Preserve the input geometry for exact source-to-skin reporting, but keep
    # only a moderate working skin in memory for candidate evaluation.
    decimate(working, 22000 if cfg["kind"] == "footwear" else 18000)
    extract_skin(working, name, cfg, meta)
    if cfg["kind"] == "trousers":
        top = max(v.co.y for v in working.data.vertices)
        for vertex in working.data.vertices:
            vertex.co.y -= top
        normalized[:, 1] -= top
        for vertex in original.data.vertices:
            vertex.co.y -= top
        meta["actualRise"] = cfg["rise"]+top
    skin_v, skin_f = arrays(working)
    skin_v, skin_f = compact_arrays(skin_v, skin_f)
    emit(f"{name}: source {original_count}, reconstructed skin {len(skin_v)} vertices")
    candidates = []
    chosen = None
    budgets = [3000, 4500, 6000, 8000, 11000] if cfg["kind"] == "footwear" else [3000, 4500, 6000, 8000]
    # Rasterize the skin baseline once; the full raw source is measured
    # separately because intentionally discarded inner walls cannot match it.
    for budget in budgets:
        candidate = make_mesh(f"{name} candidate {budget}", skin_v, skin_f)
        decimate(candidate, budget)
        split_nonmanifold(candidate)
        v, f = arrays(candidate)
        v, f = compact_arrays(v, f)
        forward = distances(v, f, skin_v, skin_f)
        reverse = distances(skin_v, skin_f, v, f)
        silhouette = silhouettes(v, f, skin_v, skin_f)
        threshold = .45 if name in ("hoodie", "bomber", "jeans") else (.30 if name in ("sneakers", "dress_pants") else 2.2)
        acceptable = reverse["p95MM"] < threshold and reverse["maxMM"] < 12 and min(silhouette.values()) > .975
        record = dict(budget=budget, vertices=len(v), triangles=len(f), skinToCandidate=reverse,
                      candidateToSkin=forward, silhouetteIoU=silhouette, acceptable=acceptable)
        candidates.append(record)
        emit(f"{name}: candidate {record}")
        if chosen is None and acceptable:
            chosen = (v, f, record)
        bpy.data.objects.remove(candidate, do_unlink=True)
        if len(candidates) >= 3 and chosen is not None:
            break
    if chosen is None:
        raise ValueError(f"No source-faithful candidate for {name}: {candidates}")
    v, f, selected = chosen
    v = np.round(v, 8)
    if cfg["kind"] == "trousers":
        v[abs(v[:, 1]) < .001, 1] = 0
    elif cfg["kind"] == "footwear":
        for side in (-1, 1):
            selection = v[:, 0]*side > 0
            v[selection, 1] -= v[selection, 1].min()
    v, f = compact_arrays(v, f)
    selected["vertices"], selected["triangles"] = len(v), len(f)
    exterior_fidelity = visible_source_fidelity(v, f, normalized, source_f)
    emit(f"{name}: full-source visible exterior fidelity {exterior_fidelity}")
    runtime = make_mesh(f"Meshy_{name}_Runtime", v, f)
    render_comparison(original, runtime, ROOT / f"{name}_comparison.png")
    loops, edge_counts = boundary_loops(v, f)
    payload = dict(vertices=np.round(v, 8).tolist(), indices=f.reshape(-1).tolist(),
                   trims=[dict(vertices=loop, radius=.0015, ribbonWidth=0) for loop in loops])
    payload.update(metadata(name, cfg, v, f, meta, loops))
    payload["provenance"] = dict(sourceFile=cfg["file"], sourceSHA256=before, units="metres", up="+Y", forward="+Z",
                                  sampleMeasurementsOnly=True, conversionScript="reference/garments/convert_garments.py")
    checks = validate(payload)
    raw_error = distances(normalized, source_f, v, f)
    report = dict(id=name, source=payload["provenance"], original=original_count, validation=checks,
                  sourceFileUnchanged=file_hash(path) == before,
                  reconstruction=dict(vertices=len(skin_v), triangles=len(skin_f),
                      method="Source-frame inward-wall removal, small fold-gap repair; independent per-foot scaling for shoes.",
                      rawSourceToRuntime=raw_error,
                      limitation="Discarded opposing thickness walls are intentionally excluded from skin fidelity acceptance. Geometric microtexture is not preserved; no UVs/textures existed."),
                  candidates=candidates, selected=selected,
                  visibleFullSourceFidelity=exterior_fidelity,
                  reduction=dict(vertices=1-len(v)/original_count["vertices"], triangles=1-len(f)/original_count["triangles"]),
                  boundaryLoops=len(loops), nonmanifoldEdges=sum(n > 2 for n in edge_counts.values()),
                  measurements={k: payload[k] for k in ("sizing", "trousers", "footwear") if k in payload})
    if cfg["kind"] == "footwear":
        report["footSeating"] = dict(estimated=True, soleThickness=meta["soleThickness"],
            method="Median downward ray hits in heel opening from y=.075 m; fallback .027 m if unavailable. Inspect elevated comparison.",
            samples=meta["soleThicknessSamples"],
            anchorConvention="Per-foot external bounding-box midpoint in X/Z, sole floor Y=0; +Z toes. Seat body floor at anchorY+soleThickness; shoe pair spacing is independent of sizing.")
    for key in ["trousers", "footwear"]:
        if key in report["measurements"]:
            report["measurements"][key] = {k: val for k, val in report["measurements"][key].items() if k not in ["legWeights", "sides"]}
    assert report["sourceFileUnchanged"]
    (ROOT / f"{name}_report.json").write_text(json.dumps(report, indent=2))
    bpy.data.objects.remove(original, do_unlink=True)
    activate(runtime)
    # Editable morph groups expose the exact runtime binding without adding a rig.
    if "fitting" in payload:
        for region, index in zip(["Hip", "Waist", "Chest", "Shoulder"], range(4)):
            group = runtime.vertex_groups.new(name=region)
            for i, weight in enumerate(payload["fitting"]["weights"]):
                if weight["regions"][index] > 0:
                    group.add([i], weight["regions"][index], "REPLACE")
        group = runtime.vertex_groups.new(name="Sleeve")
        for i, weight in enumerate(payload["fitting"]["weights"]):
            if weight["sleeveProgress"] > 0:
                group.add([i], weight["sleeveProgress"], "REPLACE")
    runtime["coordinate_system"] = "metres, +Y up, +Z forward; JSON coordinates identical"
    runtime["source_sha256"] = before
    runtime["sample_measurements"] = json.dumps({k: payload[k]["reference"] for k in ("sizing", "trousers", "footwear") if k in payload})
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"), compress=True)
    # Publish only after all numerical checks and the editable Blender save.
    validate(json.loads(json.dumps(payload, allow_nan=False)))
    destination = RESOURCES / f"meshy_{name}.json"
    destination.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False))
    emit(f"PUBLISHED {destination}: {checks}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=CONFIG)
    parser.add_argument("--from-garment", choices=CONFIG)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    garments = list(CONFIG)
    if args.from_garment:
        garments = garments[garments.index(args.from_garment):]
    selected = [args.only] if args.only else garments
    for garment in selected:
        convert(garment)
    # Publish robust derived geometry before attaching measured sleeve coordinates.
    sys.path.insert(0, str(ROOT))
    from repair_slivers import repair
    repairs = [repair(garment, True) for garment in selected]
    repair_path = ROOT / "sliver_repair_report.json"
    previous = json.loads(repair_path.read_text()) if repair_path.exists() else []
    updated = {item["id"]: item for item in previous+repairs}
    repair_path.write_text(json.dumps([updated[name] for name in CONFIG if name in updated], indent=2))
    from bind_sleeve_centerlines import bind
    bindings = [bind(garment) for garment in selected if CONFIG[garment]["kind"] == "upper"]
    binding_path = ROOT / "sleeve_binding_report.json"
    previous = json.loads(binding_path.read_text()) if binding_path.exists() else []
    updated = {item["id"]: item for item in previous+bindings}
    binding_path.write_text(json.dumps([updated[name] for name in CONFIG if name in updated], indent=2))
