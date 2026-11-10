"""Narrow only the derived hoodie sleeves; keep the Meshy source untouched.

Run in Blender with -- --apply to publish, or without it to validate a dry run.
"""
import argparse
import copy
import hashlib
import json
import sys
import tempfile
import zipfile
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from convert_garments import RESOURCES, SOURCE, make_mesh, render_comparison, validate
from diagnose_upper_sleeves import section
from refine_hoodie_sleeves import protected_hash, update_entry
from repair_slivers import cross_squared, edit_checks

RESOURCE = RESOURCES / "meshy_hoodie.json"
BLEND = ROOT / "meshy_hoodie_optimized.blend"
SCRIPT = "reference/garments/narrow_hoodie_sleeves.py"
REDUCTION = .20


def digest(data):
    return hashlib.sha256(data).hexdigest()


def smooth(value):
    t = np.clip(value, 0, 1)
    return t*t*(3-2*t)


def narrow(payload):
    vertices = np.array(payload["vertices"])
    result = vertices.copy()
    scales = np.ones(len(vertices))
    for label, side in (("right", 1), ("left", -1)):
        knots = payload["sleeves"][label]
        centers = np.array([np.array(payload["sizing"]["rightShoulder"])*[side, 1, 1]]
                           + [knot["center"] for knot in knots])
        stations = np.array([0.] + [knot["station"] for knot in knots])
        for index in np.flatnonzero(vertices[:, 0]*side > .25):
            point = vertices[index]
            candidates = []
            for a, b, start, end in zip(centers, centers[1:], stations, stations[1:]):
                delta = b-a
                fraction = np.clip(np.dot(point-a, delta)/np.dot(delta, delta), 0, 1)
                center = a+fraction*delta
                candidates.append((np.dot(point-center, point-center), center,
                                   delta/np.linalg.norm(delta), start+fraction*(end-start)))
            _, center, tangent, station = min(candidates, key=lambda entry: entry[0])
            # Ease in below the shoulder; leave the last 6 cm, including ribbing, alone.
            lateral = smooth((abs(point[0])-.25)/.03)
            amount = REDUCTION*lateral*smooth((station-.07)/.17)*(1-smooth((station-.44)/.10))
            radial = point-center-tangent*np.dot(point-center, tangent)
            result[index] -= amount*radial
            scales[index] = 1-amount
    return result, scales


def section_report(payload, before, after):
    faces = np.array(payload["indices"]).reshape(-1, 3)
    weights = np.array([entry["sleeveProgress"] for entry in payload["fitting"]["weights"]])
    result = {}
    for label in ("right", "left"):
        knots = payload["sleeves"][label]
        rows = []
        for i in (3, 5, 7, 9):
            origin = np.array(knots[i]["center"])
            tangent = np.array(knots[i+1]["center"])-knots[i-1]["center"]
            original = section(before, faces, weights, origin, tangent, origin)
            changed = section(after, faces, weights, origin, tangent, origin)
            assert original is not None and changed is not None, (label, i)
            widths = []
            for loop in (original, changed):
                points = loop["points"]-origin
                widths.append([float(np.ptp(points@loop["radial"])), float(np.ptp(points@loop["depth"]))])
            rows.append(dict(station=knots[i]["station"], beforeWidthDepthMM=(np.array(widths[0])*1000).tolist(),
                             afterWidthDepthMM=(np.array(widths[1])*1000).tolist(),
                             widthDepthRatios=(np.array(widths[1])/widths[0]).tolist()))
        assert all(max(row["widthDepthRatios"]) < 1 for row in rows), label
        result[label] = rows
    return result


def run(apply):
    original_bytes = RESOURCE.read_bytes()
    original = json.loads(original_bytes)
    if original["provenance"].get("sleeveNarrowingScript") == SCRIPT:
        raise ValueError("Already narrowed; restore the recorded backup before authoring a different reduction.")
    source = SOURCE / original["provenance"]["sourceFile"]
    source_hash = digest(source.read_bytes())
    assert source_hash == original["provenance"]["sourceSHA256"]
    before = np.array(original["vertices"])
    vertices, scales = narrow(original)
    payload = copy.deepcopy(original)
    payload["vertices"] = vertices.tolist()
    for key in ("indices", "trims", "sizing", "fitting", "sleeves"):
        assert payload[key] == original[key], key
    protected = (before[:, 1] >= 0) | (np.abs(before[:, 0]) <= .25)
    assert np.array_equal(vertices[protected], before[protected]), "Hood/body changed"
    for label in ("right", "left"):
        cuff = np.array(original["sleeves"][label][-1]["center"])
        loop = min(original["trims"], key=lambda trim:
                   np.linalg.norm(before[trim["vertices"]].mean(axis=0)-cuff))["vertices"]
        assert np.array_equal(vertices[loop], before[loop]), "Cuff changed"
    assert abs(scales.min()-(1-REDUCTION)) < 1e-8
    checks = validate(payload)
    numerical = edit_checks(payload)
    faces = np.array(payload["indices"]).reshape(-1, 3)
    assert float(cross_squared(vertices, faces).min()) >= 1e-12
    report = dict(id="hoodie", script=SCRIPT, maximumWidthDepthReduction=REDUCTION,
                  unchangedVertexCount=int(np.count_nonzero(scales == 1)),
                  changedVertexCount=int(np.count_nonzero(scales < 1)),
                  maximumDisplacementMM=float(np.linalg.norm(vertices-before, axis=1).max()*1000),
                  geometryCountsAndTopologyUnchanged=True, hoodBodyCuffsAndSizingUnchanged=True,
                  sectionMeasurements=section_report(original, before, vertices),
                  numericalChecks=numerical, previousResourceSHA256=digest(original_bytes),
                  originalSourceSHA256=source_hash)
    print(json.dumps(report, indent=2), flush=True)
    if not apply:
        return
    backup_dir = Path(tempfile.gettempdir()) / "weashion-garment-backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / f"hoodie_before_narrowing_{digest(original_bytes)[:12]}.zip"
    if backup.exists():
        with zipfile.ZipFile(backup) as archive:
            assert archive.read(RESOURCE.name) == original_bytes
            assert archive.read(BLEND.name) == BLEND.read_bytes()
    else:
        with zipfile.ZipFile(backup, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in (RESOURCE, BLEND, ROOT / "hoodie_report.json"):
                archive.write(path, path.name)
    report["backup"] = str(backup)
    payload["provenance"].update(sleeveNarrowingScript=SCRIPT, sleeveMaximumWidthDepthReduction=REDUCTION)
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    assert len(obj.data.vertices) == len(vertices)
    assert [i for face in obj.data.polygons for i in face.vertices] == payload["indices"]
    for vertex, point in zip(obj.data.vertices, vertices):
        vertex.co = point
    obj.data.update()
    obj["sleeve_narrowing_script"] = SCRIPT
    obj["sleeve_maximum_width_depth_reduction"] = REDUCTION
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    obj = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    persisted = np.array([v.co[:] for v in obj.data.vertices])
    assert float(np.max(np.abs(persisted-vertices))) < 1e-6
    assert json.loads(obj["sleeves"]) == payload["sleeves"]
    RESOURCE.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False))
    report.update(resourceSHA256=digest(RESOURCE.read_bytes()), blendSHA256=digest(BLEND.read_bytes()),
                  persistedBlendJSONParity=True)
    asset_path = ROOT / "hoodie_report.json"
    asset = json.loads(asset_path.read_text())
    asset.update(sleeveNarrowing=report, validation=checks)
    asset["numericalRepair"].update(resourceSHA256=report["resourceSHA256"],
                                   minimumAfter=numerical["source"]["minimumCrossSquared"], editChecks=numerical)
    asset["sleeveBinding"].update(resourceSHA256=report["resourceSHA256"],
                                 unchangedFieldsSHA256=protected_hash(payload), geometryNarrowedAfterBinding=True)
    asset_path.write_text(json.dumps(asset, indent=2))
    (ROOT / "hoodie_narrowing_report.json").write_text(json.dumps(report, indent=2))
    from validate_garments import validate as validate_persisted
    validation = validate_persisted("hoodie")
    update_entry("validation_report.json", "hoodie", validation)
    update_entry("sliver_repair_report.json", "hoodie", asset["numericalRepair"])
    update_entry("sleeve_binding_report.json", "hoodie", asset["sleeveBinding"])
    update_entry("blend_validation_report.json", "hoodie", dict(
        resourceSHA256=report["resourceSHA256"], blendSHA256=report["blendSHA256"],
        minimumCrossSquaredFloat32=numerical["source"]["minimumCrossSquared"],
        maximumCoordinateError=float(np.max(np.abs(persisted-vertices)))))
    previous = make_mesh("Before sleeve narrowing", before, faces)
    render_comparison(previous, obj, ROOT / "hoodie_narrowing_comparison.png")
    assert digest(source.read_bytes()) == source_hash
    print("HOODIE SLEEVES NARROWED AND VALIDATED", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    run(args.apply)
