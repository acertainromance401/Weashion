"""Conforming, position-preserving hoodie-only sleeve refinement.

Blender --background --python-exit-code 1 --python this_file -- --apply
Without --apply, compute and validate the candidate without publishing it.
"""
import argparse
import copy
import hashlib
import heapq
import json
import sys
import tempfile
import zipfile
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"
RESOURCE = RESOURCES / "meshy_hoodie.json"
BLEND = ROOT / "meshy_hoodie_optimized.blend"
SCRIPT = "reference/garments/refine_hoodie_sleeves.py"
BACKUPS = Path(tempfile.gettempdir()) / "weashion-garment-backups"
sys.path.insert(0, str(ROOT))
from convert_garments import validate as validate_geometry
from repair_slivers import cross_squared, edit_checks, topology


def digest(data):
    return hashlib.sha256(data).hexdigest()


def protected_hash(payload):
    return digest(json.dumps({key: payload[key] for key in ("vertices", "indices", "trims", "sizing", "fitting")},
                             sort_keys=True, separators=(",", ":")).encode())


def refine(original, maximum=.025):
    vertices = [np.array(point) for point in original["vertices"]]
    weights = copy.deepcopy(original["fitting"]["weights"])
    faces = np.array(original["indices"]).reshape(-1, 3).tolist()
    lineage = list(range(len(faces)))
    edge_faces = defaultdict(set)
    split_edges = {}
    heap, blocked = [], {}
    minimum_x = max(abs(original["sizing"]["rightShoulder"][0]),
                    min(abs(original["sleeves"][side][0]["center"][0]) for side in ("right", "left")))

    def eligible(a, b):
        middle = (vertices[a]+vertices[b])*.5
        return abs(middle[0]) > minimum_x and middle[1] < -.10

    def register(index):
        face = faces[index]
        for i in range(3):
            edge = tuple(sorted((face[i], face[(i+1) % 3])))
            edge_faces[edge].add(index)
            a, b = edge
            length = np.linalg.norm(vertices[a]-vertices[b])
            if length > maximum+1e-10 and eligible(a, b):
                heapq.heappush(heap, (-length, a, b))

    for index in range(len(faces)):
        register(index)
    splits = 0
    while heap:
        _, a, b = heapq.heappop(heap)
        edge = (a, b)
        if edge not in edge_faces or edge in split_edges or edge in blocked:
            continue
        attached = sorted(edge_faces[edge])
        midpoint = (vertices[a]+vertices[b])*.5
        new_index = len(vertices)
        replacements = []
        test_vertices = np.array([*vertices, midpoint])
        for index in attached:
            face = faces[index]
            i = next(i for i in range(3) if {face[i], face[(i+1) % 3]} == {a, b})
            u, v, w = face[i], face[(i+1) % 3], face[(i+2) % 3]
            children = [[u, new_index, w], [new_index, v, w]]
            squared = cross_squared(test_vertices, np.array(children))
            if squared.min() < 1.25e-12:
                blocked[edge] = dict(lengthMM=float(np.linalg.norm(vertices[a]-vertices[b])*1000),
                                     minimumChildCrossSquared=float(squared.min()))
                replacements = []
                break
            replacements.append((index, children))
        if not replacements:
            continue
        assert new_index < 12000 and len(faces)+len(replacements) <= 40000, "Refinement exceeds asset limit"
        vertices.append(midpoint)
        weight = {}
        assert weights[a].keys() == weights[b].keys()
        for key in weights[a]:
            value = (np.array(weights[a][key])+np.array(weights[b][key]))*.5
            weight[key] = value.tolist() if value.ndim else float(value)
        weights.append(weight)
        split_edges[edge] = new_index
        for index, children in replacements:
            previous = faces[index]
            for i in range(3):
                old_edge = tuple(sorted((previous[i], previous[(i+1) % 3])))
                edge_faces[old_edge].remove(index)
                if not edge_faces[old_edge]:
                    del edge_faces[old_edge]
            faces[index] = children[0]
            faces.append(children[1])
            lineage.append(lineage[index])
            register(index)
            register(len(faces)-1)
        splits += 1
    assert splits < 6000

    def boundary_segment(a, b):
        midpoint = split_edges.get(tuple(sorted((a, b))))
        return [a] if midpoint is None else boundary_segment(a, midpoint)+boundary_segment(midpoint, b)

    result = copy.deepcopy(original)
    result["vertices"] = np.array(vertices).tolist()
    result["indices"] = np.array(faces).reshape(-1).tolist()
    result["fitting"]["weights"] = weights
    for trim in result["trims"]:
        loop = trim["vertices"]
        trim["vertices"] = [index for a, b in zip(loop, loop[1:]+loop[:1]) for index in boundary_segment(a, b)]
    assert result["vertices"][:len(original["vertices"])] == original["vertices"]
    assert result["fitting"]["weights"][:len(original["vertices"])] == original["fitting"]["weights"]
    assert result["sizing"] == original["sizing"] and result["sleeves"] == original["sleeves"]
    remaining = [dict(vertices=[a, b], lengthMM=float(np.linalg.norm(vertices[a]-vertices[b])*1000))
                 for a, b in edge_faces if eligible(a, b) and np.linalg.norm(vertices[a]-vertices[b]) > maximum+1e-10]
    assert not remaining, f"Authoring area reserve blocks {len(remaining)} target edges: {remaining[:5]}"
    original_faces = np.array(original["indices"]).reshape(-1, 3).tolist()
    stats = dict(maximumTargetEdgeMM=maximum*1000, minimumAbsX=minimum_x, maximumY=-.10,
                 edgeBisections=splits, blockedAreaEdges=len(blocked),
                 affectedOriginalFaces=len({lineage[i] for i in range(len(faces))
                                            if faces[i] != original_faces[lineage[i]]}))
    for source_face in (685, 923, 941):
        descendants = [i for i, parent in enumerate(lineage) if parent == source_face]
        triangles = np.array(vertices)[np.array(faces)[descendants]]
        maximum_edge = np.linalg.norm(triangles-np.roll(triangles, -1, axis=1), axis=2).max()
        stats[f"sourceFace{source_face}"] = dict(descendantFaces=descendants, maximumEdgeMM=float(maximum_edge*1000))
        assert maximum_edge <= maximum+1e-9
    return result, np.array(lineage), stats


def update_entry(filename, identifier, update):
    path = ROOT / filename
    items = json.loads(path.read_text())
    for item in items:
        if item["id"] == identifier:
            item.update(update)
    path.write_text(json.dumps(items, indent=2))


def backup(original_bytes):
    BACKUPS.mkdir(parents=True, exist_ok=True)
    destination = BACKUPS / f"hoodie_before_sleeve_refinement_{digest(original_bytes)[:12]}.zip"
    if not destination.exists():
        files = {"meshy_hoodie.json": original_bytes,
                 "meshy_hoodie_optimized.blend": BLEND.read_bytes(),
                 "hoodie_report.json": (ROOT / "hoodie_report.json").read_bytes()}
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in files.items():
                archive.writestr(name, data)
            archive.writestr("manifest.json", json.dumps({name: digest(data) for name, data in files.items()}, indent=2))
    with zipfile.ZipFile(destination) as archive:
        assert archive.read("meshy_hoodie.json") == original_bytes
    return str(destination.resolve())


def run(apply=False):
    original_bytes = RESOURCE.read_bytes()
    original = json.loads(original_bytes)
    if original["provenance"].get("sleeveRefinementScript") == SCRIPT:
        print("HOODIE REFINEMENT ALREADY PUBLISHED", flush=True)
        return
    result, lineage, operations = refine(original)
    old_v, old_f = np.array(original["vertices"]), np.array(original["indices"]).reshape(-1, 3)
    vertices, faces = np.array(result["vertices"]), np.array(result["indices"]).reshape(-1, 3)
    assert topology(old_v, old_f) == topology(vertices, faces)
    checks = validate_geometry(result)
    numerical = edit_checks(result)
    assert min(numerical["source"]["minimumCrossSquared"], float(cross_squared(vertices, faces).min())) >= 1e-12
    # Every child stays on the exact plane of its original source triangle.
    triangle = old_v[old_f[lineage]]
    normal = np.cross(triangle[:, 1]-triangle[:, 0], triangle[:, 2]-triangle[:, 0])
    normal /= np.linalg.norm(normal, axis=1)[:, None]
    plane_error = np.abs(np.sum((vertices[faces]-triangle[:, :1])*normal[:, None, :], axis=2)).max()
    assert plane_error < 1e-12
    report = dict(id="hoodie", candidate="Conforming sleeve/cap longest-edge bisection; no vertex relocation",
        beforeVertices=len(old_v), afterVertices=len(vertices), appendedVertices=len(vertices)-len(old_v),
        beforeTriangles=len(old_f), afterTriangles=len(faces), appendedTriangles=len(faces)-len(old_f),
        operations=operations, topologyBeforeAndAfter=topology(vertices, faces),
        orderedBoundaryLoops=len(result["trims"]), maximumSourcePlaneErrorMetres=float(plane_error),
        existingVertexPositionsAndWeightsUnchanged=True, sizingAndIndependentSleevesUnchanged=True,
        materialPreserved=True, numericalChecks=numerical, previousResourceSHA256=digest(original_bytes),
        script=SCRIPT, nativeFitsRun=False)
    print(json.dumps(report, indent=2), flush=True)
    if not apply:
        return
    report["backup"] = backup(original_bytes)
    result["provenance"]["sleeveRefinementScript"] = SCRIPT
    result["provenance"]["sleeveRefinementMaximumEdgeMM"] = operations["maximumTargetEdgeMM"]
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    materials = [polygon.material_index for polygon in obj.data.polygons]
    material_names = [material.name if material else None for material in obj.data.materials]
    obj.data.clear_geometry()
    obj.data.from_pydata(vertices.tolist(), [], faces.tolist())
    obj.data.update()
    for index, polygon in enumerate(obj.data.polygons):
        polygon.use_smooth = True
        polygon.material_index = materials[lineage[index]]
    obj.vertex_groups.clear()
    for key, component in zip(("Hip", "Waist", "Chest", "Shoulder", "Sleeve"), range(5)):
        group = obj.vertex_groups.new(name=key)
        for index, weight in enumerate(result["fitting"]["weights"]):
            value = weight["regions"][component] if component < 4 else weight["sleeveProgress"]
            if value:
                group.add([index], value, "REPLACE")
    obj["sleeve_refinement_script"] = SCRIPT
    obj["sleeve_refinement_maximum_edge_mm"] = operations["maximumTargetEdgeMM"]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    # Reopen the persisted candidate, independently checking mesh/index/binding parity.
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    assert len(obj.data.vertices) == len(vertices)
    assert [i for polygon in obj.data.polygons for i in polygon.vertices] == result["indices"]
    persisted = np.array([vertex.co[:] for vertex in obj.data.vertices], dtype=np.float32)
    assert np.max(abs(persisted-vertices)) < 1e-6
    assert float(cross_squared(persisted, faces).min()) >= 1e-12
    assert json.loads(obj["sleeves"]) == result["sleeves"]
    assert [material.name if material else None for material in obj.data.materials] == material_names
    for key, component in zip(("Hip", "Waist", "Chest", "Shoulder", "Sleeve"), range(5)):
        group = obj.vertex_groups[key]
        for index, weight in enumerate(result["fitting"]["weights"]):
            expected = weight["regions"][component] if component < 4 else weight["sleeveProgress"]
            try:
                actual = group.weight(index)
            except RuntimeError:
                actual = 0
            assert abs(actual-expected) < 1e-5
    RESOURCE.write_text(json.dumps(result, separators=(",", ":"), allow_nan=False))
    report.update(resourceSHA256=digest(RESOURCE.read_bytes()), blendSHA256=digest(BLEND.read_bytes()),
                  persistedBlendJSONParity=True, maximumPersistedCoordinateError=float(np.max(abs(persisted-vertices))))
    asset_path = ROOT / "hoodie_report.json"
    asset = json.loads(asset_path.read_text())
    asset["sleeveRefinement"] = report
    asset["validation"] = checks
    asset["selected"].update(vertices=len(vertices), triangles=len(faces))
    asset["reduction"] = dict(vertices=1-len(vertices)/asset["original"]["vertices"],
                              triangles=1-len(faces)/asset["original"]["triangles"])
    asset["numericalRepair"].update(resourceSHA256=report["resourceSHA256"],
        minimumAfter=numerical["source"]["minimumCrossSquared"], editChecks=numerical)
    asset["sleeveBinding"].update(resourceSHA256=report["resourceSHA256"],
        unchangedFieldsSHA256=protected_hash(result), geometryRefinedAfterBinding=True)
    asset_path.write_text(json.dumps(asset, indent=2))
    (ROOT / "hoodie_refinement_report.json").write_text(json.dumps(report, indent=2))
    update_entry("sliver_repair_report.json", "hoodie", asset["numericalRepair"])
    update_entry("sleeve_binding_report.json", "hoodie", asset["sleeveBinding"])
    from validate_garments import validate
    validation = validate("hoodie", recheck_sources=False)
    update_entry("validation_report.json", "hoodie", validation)
    update_entry("blend_validation_report.json", "hoodie", dict(vertices=len(vertices), triangles=len(faces),
        maximumCoordinateError=report["maximumPersistedCoordinateError"],
        minimumCrossSquaredFloat32=numerical["source"]["minimumCrossSquared"],
        resourceSHA256=report["resourceSHA256"], blendSHA256=report["blendSHA256"]))
    print("HOODIE REFINEMENT PUBLISHED AND VALIDATED", len(vertices), len(faces), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    run(args.apply)
