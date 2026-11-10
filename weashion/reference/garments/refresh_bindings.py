"""Re-measure existing runtime geometry without resimplifying or reading sources."""
import json
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from convert_garments import CONFIG, RESOURCES, boundary_loops, metadata, validate

for name, cfg in CONFIG.items():
    path = RESOURCES / f"meshy_{name}.json"
    payload = json.loads(path.read_text())
    vertices = np.array(payload["vertices"])
    if cfg["kind"] == "trousers":
        vertices[abs(vertices[:, 1]) < .001, 1] = 0
    elif cfg["kind"] == "footwear":
        for side in (-1, 1):
            selection = np.array(payload["footwear"]["sides"]) == side
            vertices[selection, 1] -= vertices[selection, 1].min()
    payload["vertices"] = np.round(vertices, 8).tolist()
    faces = np.array(payload["indices"]).reshape(-1, 3)
    seen, unique = set(), []
    for face in faces:
        key = tuple(sorted(face))
        if key not in seen:
            unique.append(face)
        seen.add(key)
    faces = np.array(unique)
    payload["indices"] = faces.reshape(-1).tolist()
    loops, _ = boundary_loops(vertices, faces)
    payload["trims"] = [dict(vertices=loop, radius=.0015, ribbonWidth=0) for loop in loops]
    if cfg["kind"] == "upper":
        sizing = payload["sizing"]
        shoulder, cuff = np.array(sizing["rightShoulder"]), np.array(sizing["rightCuff"])
        axis = cuff-shoulder
        axis /= np.linalg.norm(axis)
        meta = dict(rightShoulder=shoulder.tolist(), rightCuff=cuff.tolist(), sleeveAxis=axis.tolist())
    elif cfg["kind"] == "trousers":
        meta = dict(actualRise=payload["trousers"]["reference"]["rise"])
    else:
        meta = {k: payload["footwear"][k] for k in ("rightCenter", "leftCenter", "soleThickness")}
    bindings = metadata(name, cfg, vertices, faces, meta, loops)
    payload.update(bindings)
    checks = validate(payload)
    report_path = ROOT / f"{name}_report.json"
    report = json.loads(report_path.read_text())
    report["measurements"] = {key: {k: v for k, v in value.items() if k not in ("weights", "legWeights", "sides")}
                              for key, value in bindings.items() if key != "fitting"}
    report["sectionMeasurement"] = "128 horizontal radial intersections for closed body/hip/thigh sections; source-connected mesh-plane convex envelope for open bomber torso; ordered 3D cuff perimeter; horizontal convex aperture envelope of actual boundary vertices for irregular trouser waist/hems. No closed geometry is added across bomber front."
    report["validation"] = checks
    report["selected"]["triangles"] = len(faces)
    report["boundaryLoops"] = len(loops)
    report["reduction"]["triangles"] = 1-len(faces)/report["original"]["triangles"]
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"))
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    obj.data.clear_geometry()
    obj.data.from_pydata(vertices.tolist(), [], faces.tolist())
    obj.data.update()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj["sample_measurements"] = json.dumps({key: value["reference"] for key, value in bindings.items() if key != "fitting"})
    if "fitting" in bindings:
        obj.vertex_groups.clear()
        for region, index in zip(["Hip", "Waist", "Chest", "Shoulder"], range(4)):
            group = obj.vertex_groups.new(name=region)
            for i, weight in enumerate(bindings["fitting"]["weights"]):
                if weight["regions"][index] > 0:
                    group.add([i], weight["regions"][index], "REPLACE")
        group = obj.vertex_groups.new(name="Sleeve")
        for i, weight in enumerate(bindings["fitting"]["weights"]):
            if weight["sleeveProgress"] > 0:
                group.add([i], weight["sleeveProgress"], "REPLACE")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / f"meshy_{name}_optimized.blend"), compress=True)
    path.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False))
    report_path.write_text(json.dumps(report, indent=2))
    print(name, report["measurements"], flush=True)
