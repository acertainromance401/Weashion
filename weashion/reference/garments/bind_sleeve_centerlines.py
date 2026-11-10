"""Publish independently measured native-coordinate sleeve curves after sliver repair."""
import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"
ORDER = ["long_sleeve", "hoodie", "bomber"]
SCRIPT = "reference/garments/bind_sleeve_centerlines.py"
sys.path.insert(0, str(ROOT))
from diagnose_upper_sleeves import section


def measure_side(payload, side):
    mirror = np.array([side, 1, 1])
    vertices = np.array(payload["vertices"])*mirror
    faces = np.array(payload["indices"]).reshape(-1, 3)
    weights = np.array([value["sleeveProgress"] for value in payload["fitting"]["weights"]])
    shoulder = np.array(payload["sizing"]["rightShoulder"])
    expected = np.array(payload["sizing"]["rightCuff"])
    cuff_loop = min(payload["trims"], key=lambda trim:
        np.linalg.norm(vertices[trim["vertices"]].mean(axis=0)-expected))["vertices"]
    cuff = vertices[cuff_loop].mean(axis=0)
    assert cuff[0] > shoulder[0]+.10
    axis = cuff-shoulder
    axis /= np.linalg.norm(axis)
    sections = []
    for x in np.linspace(shoulder[0]+.015, cuff[0]-.03, 12):
        expected = shoulder+(cuff-shoulder)*(x-shoulder[0])/(cuff[0]-shoulder[0])
        loop = section(vertices, faces, weights, np.array([x, 0, 0]), np.array([1., 0, 0]), expected)
        if loop is not None:
            sections.append(loop)
    initial = np.array([loop["center"] for loop in sections])
    centers, audit = [], []
    for i, center in enumerate(initial):
        tangent = initial[min(i+1, len(initial)-1)]-initial[max(i-1, 0)]
        tangent /= np.linalg.norm(tangent)
        loop = section(vertices, faces, weights, center, tangent, center)
        if loop is not None and np.linalg.norm(loop["center"]-center) < .07:
            centers.append(loop["center"])
            audit.append(dict(center=(loop["center"]*mirror).tolist(),
                circumference=loop["circumference"], area=loop["area"], sectionVertices=len(loop["points"])))
    assert 10 <= len(centers) <= 12
    stations = (np.array(centers)-shoulder)@axis
    knots = [dict(center=np.round(center*mirror, 8).tolist(), station=round(float(station), 8))
             for center, station in zip(centers, stations)]
    knots.append(dict(center=(cuff*mirror).tolist(), station=payload["sizing"]["reference"]["sleeveLength"]))
    assert all(0 < a["station"] < b["station"] for a, b in zip(knots, knots[1:]))
    return knots, dict(measurementShoulder=(shoulder*mirror).tolist(), measuredCuff=(cuff*mirror).tolist(),
        measuredChordLength=float(np.linalg.norm(cuff-shoulder)),
        stationConvention="Side-specific measurement-shoulder to actual cuff chord projection; final station overridden by canonical right reference sleeveLength.",
        sections=audit)


def bind(name):
    import bpy

    path = RESOURCES / f"meshy_{name}.json"
    original_bytes = path.read_bytes()
    payload = json.loads(original_bytes)
    original = copy.deepcopy(payload)
    sleeves, measurements = {}, {}
    for key, side in (("right", 1), ("left", -1)):
        sleeves[key], measurements[key] = measure_side(payload, side)
    payload["sleeves"] = sleeves
    payload["provenance"]["sleeveBindingScript"] = SCRIPT
    payload["provenance"]["sleeveBindingSource"] = "Independent actual left/right sections of normalized source-derived skin after numerical repair."
    for key in ("vertices", "indices", "trims", "sizing", "fitting"):
        assert payload[key] == original[key], f"{key} must remain untouched"
    blend_path = ROOT / f"meshy_{name}_optimized.blend"
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    previous_property = obj.get("sleeves")
    same = original == payload and previous_property is not None and json.loads(previous_property) == sleeves
    if not same:
        obj["sleeves"] = json.dumps(sleeves, separators=(",", ":"), allow_nan=False)
        obj["sleeve_binding_script"] = SCRIPT
        obj["sleeve_binding_source"] = payload["provenance"]["sleeveBindingSource"]
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)
        path.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False))
    resource_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    result = dict(id=name, rightKnots=len(sleeves["right"]), leftKnots=len(sleeves["left"]),
        geometryAndExistingBindingsUnchanged=True, measurementScript=SCRIPT,
        unchangedFieldsSHA256=hashlib.sha256(json.dumps(
            {key: payload[key] for key in ("vertices", "indices", "trims", "sizing", "fitting")},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        resourceSHA256=resource_hash, sides=measurements)
    report_path = ROOT / f"{name}_report.json"
    report = json.loads(report_path.read_text())
    report["sleeveBinding"] = result
    repair = report["numericalRepair"]
    repair.setdefault("resourceSHA256BeforeSleeveMetadata", repair["resourceSHA256"])
    repair["resourceSHA256"] = resource_hash
    report_path.write_text(json.dumps(report, indent=2))
    aggregate_path = ROOT / "sliver_repair_report.json"
    if aggregate_path.exists():
        repairs = json.loads(aggregate_path.read_text())
        for item in repairs:
            if item["id"] == name:
                item.setdefault("resourceSHA256BeforeSleeveMetadata", item["resourceSHA256"])
                item["resourceSHA256"] = resource_hash
        aggregate_path.write_text(json.dumps(repairs, indent=2))
    print("SLEEVE BINDING READY", name, result["rightKnots"], result["leftKnots"], flush=True)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=ORDER)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    results = [bind(name) for name in ([args.only] if args.only else ORDER)]
    (ROOT / "sleeve_binding_report.json").write_text(json.dumps(results, indent=2))
