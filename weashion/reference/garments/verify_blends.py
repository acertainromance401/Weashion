"""Verify saved editable .blend meshes against the published runtime JSON."""
import json
import hashlib
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"
results = []
for name in ["long_sleeve", "hoodie", "dress_pants", "jeans", "bomber", "sneakers"]:
    payload = json.loads((RESOURCES / f"meshy_{name}.json").read_text())
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    assert len(meshes) == 1
    obj = meshes[0]
    assert len(obj.data.vertices) == len(payload["vertices"])
    assert [index for polygon in obj.data.polygons for index in polygon.vertices] == payload["indices"]
    error = max(abs(vertex.co[axis]-point[axis]) for vertex, point in zip(obj.data.vertices, payload["vertices"]) for axis in range(3))
    assert error < .000001
    positions, indices = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float32), np.array(payload["indices"]).reshape(-1, 3)
    cross = np.cross(positions[indices[:, 1]]-positions[indices[:, 0]], positions[indices[:, 2]]-positions[indices[:, 0]])
    minimum_cross_squared = float(np.sum(cross*cross, axis=1).min())
    assert minimum_cross_squared >= 1e-12
    assert obj["source_sha256"] == payload["provenance"]["sourceSHA256"]
    assert json.loads(obj["sample_measurements"]) == {
        key: payload[key]["reference"] for key in ["sizing", "trousers", "footwear"] if key in payload
    }
    if "fitting" in payload:
        assert json.loads(obj["sleeves"]) == payload["sleeves"]
        assert obj["sleeve_binding_script"] == payload["provenance"]["sleeveBindingScript"]
        for region, axis in zip(["Hip", "Waist", "Chest", "Shoulder", "Sleeve"], range(5)):
            group = obj.vertex_groups[region]
            for index, weight in enumerate(payload["fitting"]["weights"]):
                try:
                    actual = group.weight(index)
                except RuntimeError:
                    actual = 0
                expected = weight["regions"][axis] if axis < 4 else weight["sleeveProgress"]
                assert abs(actual-expected) < .00001
    section_checks = {}
    if "sleeves" in payload:
        tree = BVHTree.FromPolygons(positions.tolist(), indices.tolist(), all_triangles=True)
        for side in ("right", "left"):
            centers = np.array([knot["center"] for knot in payload["sleeves"][side]])
            hits = []
            for i, center in enumerate(centers[:-1]):
                tangent = centers[i+1]-centers[max(0, i-1)]
                tangent /= np.linalg.norm(tangent)
                depth = np.array([0., 0., 1.])-tangent*tangent[2]
                depth /= np.linalg.norm(depth)
                front = tree.ray_cast(Vector(center), Vector(depth), .35)[0]
                back = tree.ray_cast(Vector(center), Vector(-depth), .35)[0]
                assert front is not None and back is not None, (name, side, i, "center lacks both source walls")
                hits.append(dict(frontDistanceMM=float(np.linalg.norm(np.array(front)-center)*1000),
                                 backDistanceMM=float(np.linalg.norm(np.array(back)-center)*1000)))
            section_checks[side] = hits
    results.append(dict(id=name, editableMeshes=1, vertices=len(obj.data.vertices),
                        triangles=len(obj.data.polygons), maximumCoordinateError=error,
                        minimumCrossSquaredFloat32=minimum_cross_squared,
                        sourceHashMatches=True, referenceMeasurementsMatch=True,
                        sleeveMetadataMatches="sleeves" in payload, independentSleeveSectionRays=section_checks,
                        blendSHA256=hashlib.sha256((ROOT / f"meshy_{name}_optimized.blend").read_bytes()).hexdigest(),
                        resourceSHA256=hashlib.sha256((RESOURCES / f"meshy_{name}.json").read_bytes()).hexdigest()))
    print("BLEND PASS", name, flush=True)
(ROOT / "blend_validation_report.json").write_text(json.dumps(results, indent=2))
