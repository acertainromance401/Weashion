"""Independent persisted-artifact validation; system Python or Blender Python."""
import hashlib
import json
import math
import mmap
import argparse
from collections import Counter
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"
SOURCE = Path("/Users/acertainromance401/Desktop/Meshy Models")
ORDER = ["long_sleeve", "hoodie", "dress_pants", "jeans", "bomber", "sneakers"]


def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))


def validate_sleeves(payload, name):
    results = {}
    vertices = np.array(payload["vertices"])
    for label, side in (("right", 1), ("left", -1)):
        knots = payload["sleeves"][label]
        centers = np.array([knot["center"] for knot in knots])
        stations = np.array([knot["station"] for knot in knots])
        assert 10 <= len(knots) <= 16 and centers.shape == (len(knots), 3)
        assert np.isfinite(centers).all() and np.isfinite(stations).all()
        assert (centers[:, 0]*side > 0).all() and (np.diff(stations) > 0).all() and stations[0] > 0
        assert stations[-1] == payload["sizing"]["reference"]["sleeveLength"]
        expected = np.array(payload["sizing"]["rightCuff"])*[side, 1, 1]
        loop = min(payload["trims"], key=lambda trim:
            np.linalg.norm(vertices[trim["vertices"]].mean(axis=0)-expected))["vertices"]
        assert np.linalg.norm(centers[-1]-vertices[loop].mean(axis=0)) < 1e-8
        results[label] = dict(knots=len(knots), finalStation=float(stations[-1]), actualCuffMatches=True)
    if name == "long_sleeve":
        centers = np.array([knot["center"] for knot in payload["sleeves"]["right"]])
        regressions = []
        for index in (2587, 2645, 2630):
            point = vertices[index]
            candidates = []
            for a, b in zip(centers, centers[1:]):
                delta = b-a
                fraction = np.clip(np.dot(point-a, delta)/np.dot(delta, delta), 0, 1)
                center = a+fraction*delta
                tangent = delta/np.linalg.norm(delta)
                depth = np.array([0., 0., 1.])-tangent*tangent[2]
                depth /= np.linalg.norm(depth)
                residual = point-center
                radial = residual-tangent*np.dot(residual, tangent)
                candidates.append((np.dot(residual, residual), np.dot(residual, depth), np.linalg.norm(radial)))
            _, depth, radius = min(candidates, key=lambda item: item[0])
            assert depth > .035 and radius > .04, (index, depth, radius)
            regressions.append(dict(vertex=index, signedSourceDepthMM=float(depth*1000), sourceRadiusMM=float(radius*1000)))
        results["frontTriangle4991"] = regressions
    return results


def validate(name, recheck_sources=True):
    path = RESOURCES / f"meshy_{name}.json"
    payload = json.loads(path.read_text())
    vertices, indices = payload["vertices"], payload["indices"]
    assert 0 < len(vertices) <= 12000
    assert 0 < len(indices) <= 120000 and len(indices) % 3 == 0
    assert all(len(v) == 3 and all(math.isfinite(x) for x in v) and distance(v, [0, 0, 0]) < 3 for v in vertices)
    assert all(type(i) is int and 0 <= i < len(vertices) for i in indices)
    assert set(indices) == set(range(len(vertices)))
    faces = [indices[i:i+3] for i in range(0, len(indices), 3)]
    minimum_cross_squared = math.inf
    for face in faces:
        assert len(set(face)) == 3
        a, b, c = [vertices[i] for i in face]
        u, v = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
        cross = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
        squared = sum(x*x for x in cross)
        assert squared > 1e-14
        minimum_cross_squared = min(minimum_cross_squared, squared)
    assert len({tuple(sorted(face)) for face in faces}) == len(faces), "Duplicate triangle"
    assert minimum_cross_squared >= 1e-12, "Insufficient authored size-edit area margin"
    positions32, triangles = np.array(vertices, dtype=np.float32), np.array(faces)
    numerical_cases = {}
    for label, scale in (("source", (1, 1, 1)), ("uniform_0.8", (.8, .8, .8)),
                         ("anisotropic_small", (.70, .75, .70))):
        points = positions32*np.array(scale, dtype=np.float32)
        cross = np.cross(points[triangles[:, 1]]-points[triangles[:, 0]],
                         points[triangles[:, 2]]-points[triangles[:, 0]])
        squared = np.sum(cross*cross, axis=1)
        assert (squared > 1e-14).all(), (name, label)
        numerical_cases[label] = float(squared.min())
    assert numerical_cases["source"] >= 1e-12
    edges = Counter(tuple(sorted((face[i], face[(i+1) % 3]))) for face in faces for i in range(3))
    assert max(edges.values()) <= 2, "Nonmanifold edge"
    for trim in payload["trims"]:
        loop = trim["vertices"]
        assert len(loop) >= 3 and len(loop) == len(set(loop))
        assert all(edges[tuple(sorted((loop[i], loop[(i+1) % len(loop)])))] == 1 for i in range(len(loop)))
        assert 0 < trim["radius"] < .01 and 0 <= trim["ribbonWidth"] < .02
    if "fitting" in payload:
        fitting, sizing = payload["fitting"], payload["sizing"]
        assert fitting["hip"]["center"][1] < fitting["waist"]["center"][1] < fitting["chest"]["center"][1] < fitting["shoulderHeight"]
        for region in ("hip", "waist", "chest"):
            assert all(fitting[region][k] > 0 for k in ("halfWidth", "halfDepth", "circumference"))
        assert len(fitting["weights"]) == len(vertices)
        for point, weight in zip(vertices, fitting["weights"]):
            assert len(weight["regions"]) == 4 and all(0 <= w <= 1 for w in weight["regions"])
            assert abs(sum(weight["regions"])-1) < 1e-5 and 0 <= weight["sleeveProgress"] <= 1
            if name == "hoodie" and point[1] > .015:
                assert weight["regions"][3] > .99 and weight["sleeveProgress"] < .01
        assert abs(sizing["reference"]["length"]+min(v[1] for v in vertices)) < .00001
        cuff = sizing["rightCuff"]
        loops = [trim["vertices"] for trim in payload["trims"]]
        loop = min(loops, key=lambda ids: distance([sum(vertices[i][j] for i in ids)/len(ids) for j in range(3)], cuff))
        center = [sum(vertices[i][j] for i in loop)/len(loop) for j in range(3)]
        circumference = sum(distance(vertices[loop[i]], vertices[loop[(i+1) % len(loop)]]) for i in range(len(loop)))
        assert distance(center, cuff) < .001
        assert abs(circumference-sizing["reference"]["sleeveOpening"]) < .00001
        assert distance(cuff, sizing["rightShoulder"]) > .1
        sleeve_checks = validate_sleeves(payload, name)
    elif "trousers" in payload:
        assert "sizing" not in payload and "fitting" not in payload
        trousers = payload["trousers"]
        assert len(trousers["legWeights"]) == len(vertices) and all(0 <= w <= 1 for w in trousers["legWeights"])
        centers = trousers["rightLegCenters"]
        assert len(centers) >= 3 and all(c[0] > 0 and all(math.isfinite(x) for x in c) for c in centers)
        assert all(a[1] < b[1] for a, b in zip(centers, centers[1:]))
        assert abs(max(v[1] for v in vertices)) < .0001
        ref = trousers["reference"]
        assert abs(min(v[1] for v in vertices)+ref["rise"]+ref["inseam"]) < .00001
    else:
        assert "sizing" not in payload and "fitting" not in payload
        footwear = payload["footwear"]
        assert .005 <= footwear["soleThickness"] <= .1
        assert len(footwear["sides"]) == len(vertices) and set(footwear["sides"]) == {-1, 1}
        for side in (-1, 1):
            shoe = [point for point, label in zip(vertices, footwear["sides"]) if label == side]
            assert abs(min(p[1] for p in shoe)) < .001
            for axis, key in [(0, "width"), (2, "length")]:
                actual = max(p[axis] for p in shoe)-min(p[axis] for p in shoe)
                assert abs(actual-footwear["reference"][key]) < .003
    provenance = payload["provenance"]
    if recheck_sources:
        with (SOURCE / provenance["sourceFile"]).open("rb") as source:
            with mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
                digest = hashlib.sha256(data).hexdigest()
    else:
        previous = next(item for item in json.loads((ROOT / "validation_report.json").read_text()) if item["id"] == name)
        assert previous["sourceUnchanged"] and previous["sourceSHA256"] == provenance["sourceSHA256"]
        digest = previous["sourceSHA256"]
    assert digest == provenance["sourceSHA256"], "Desktop source modified"
    report = json.loads((ROOT / f"{name}_report.json").read_text())
    assert report["sourceFileUnchanged"] and report["validation"]["vertices"] == len(vertices)
    assert report["selected"]["acceptable"]
    if "sleeves" in payload:
        protected_hash = hashlib.sha256(json.dumps(
            {key: payload[key] for key in ("vertices", "indices", "trims", "sizing", "fitting")},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        assert report["sleeveBinding"]["unchangedFieldsSHA256"] == protected_hash
    repair = report["numericalRepair"]
    resource_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    assert repair["resourceSHA256"] == resource_hash
    assert all(case["failingTriangles"] == 0 and case["minimumCrossSquared"] > 1e-14
               for case in repair["editChecks"].values())
    assert abs(repair["minimumAfter"]-numerical_cases["source"]) < numerical_cases["source"]*1e-5
    assert (ROOT / f"meshy_{name}_optimized.blend").stat().st_size > 10000
    assert (ROOT / f"{name}_comparison.png").stat().st_size > 10000
    assert (ROOT / f"{name}_comparison_back.png").stat().st_size > 10000
    result = dict(id=name, vertices=len(vertices), triangles=len(faces), orderedBoundaryLoops=len(payload["trims"]),
                nonmanifoldEdges=0, minimumCrossSquared=minimum_cross_squared, sourceSHA256=digest,
                minimumCrossSquaredFloat32=numerical_cases["source"], numericalMarginCases=numerical_cases,
                sourceUnchanged=True, sourceHashRechecked=recheck_sources, resourceSHA256=resource_hash)
    if "sleeves" in payload:
        result["sleeveBindings"] = sleeve_checks
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--derived-only", action="store_true",
                        help="Revalidate derived artifacts, retaining previously verified original-source hash evidence without reopening Desktop sources.")
    args = parser.parse_args()
    results = [validate(name, not args.derived_only) for name in ORDER]
    (ROOT / "validation_report.json").write_text(json.dumps(results, indent=2))
    for result in results:
        print(f"PASS {result['id']}: {result['vertices']} vertices / {result['triangles']} triangles; source unchanged")
