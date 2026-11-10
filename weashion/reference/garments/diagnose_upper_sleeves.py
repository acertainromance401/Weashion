"""Read-only section/binding measurements on the published source-derived skins."""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
RESOURCES = ROOT.parents[1] / "weashion" / "Resources"


def section(vertices, faces, weights, origin, normal, expected):
    normal = normal/np.linalg.norm(normal)
    radial = np.cross(normal, [0., 0., 1.])
    radial /= np.linalg.norm(radial)
    depth = np.cross(normal, radial)
    if depth[2] < 0:
        radial, depth = -radial, -depth
    signed = (vertices-origin)@normal
    candidates = faces[(signed[faces].min(axis=1) < 0) & (signed[faces].max(axis=1) > 0)]
    positions, values, adjacency = {}, {}, defaultdict(set)
    for triangle in candidates:
        hits = []
        for i in range(3):
            a, b = triangle[i], triangle[(i+1) % 3]
            if signed[a]*signed[b] < 0:
                fraction = signed[a]/(signed[a]-signed[b])
                point = vertices[a]+fraction*(vertices[b]-vertices[a])
                key = tuple(np.round(point, 7))
                positions[key] = point
                values[key] = weights[a]+fraction*(weights[b]-weights[a])
                hits.append(key)
        if len(hits) == 2 and hits[0] != hits[1]:
            adjacency[hits[0]].add(hits[1])
            adjacency[hits[1]].add(hits[0])
    remaining = set(adjacency)
    loops = []
    while remaining:
        first = remaining.pop()
        stack, component = [first], {first}
        while stack:
            for other in adjacency[stack.pop()]:
                if other in remaining:
                    remaining.remove(other)
                    component.add(other)
                    stack.append(other)
        if len(component) < 3 or any(len(adjacency[key]) != 2 for key in component):
            continue
        ordered, previous, current = [first], None, first
        while True:
            following = next(key for key in adjacency[current] if key != previous)
            if following == first:
                break
            ordered.append(following)
            previous, current = current, following
            if len(ordered) > len(component):
                raise ValueError("Non-simple section")
        points = np.array([positions[key] for key in ordered])
        xy = np.column_stack(((points-origin)@radial, (points-origin)@depth))
        following = np.roll(xy, -1, axis=0)
        cross = xy[:, 0]*following[:, 1]-following[:, 0]*xy[:, 1]
        area = cross.sum()/2
        if abs(area) < .0001 or np.ptp(points[:, 1]) > .52:
            continue
        center2 = ((xy+following)*cross[:, None]).sum(axis=0)/(6*area)
        center = origin+radial*center2[0]+depth*center2[1]
        arc = np.linalg.norm(points-np.roll(points, -1, axis=0), axis=1)
        progress = np.array([values[key] for key in ordered])
        mean = (progress+np.roll(progress, -1))/2
        loops.append(dict(center=center, points=points, area=abs(area), circumference=float(arc.sum()),
            normal=normal, radial=radial, depth=depth, arc=arc, progress=progress, meanProgress=float(np.dot(arc, mean)/arc.sum()),
            perimeterNearTorso=float(arc[mean < .1].sum()/arc.sum()),
            perimeterNearSleeve=float(arc[mean > .9].sum()/arc.sum())))
    if not loops:
        return None
    # Reject tiny fold loops; select the principal nearby sleeve lumen.
    nearby = [loop for loop in loops if np.linalg.norm(loop["center"]-expected) < .25]
    return max(nearby, key=lambda loop: loop["area"]) if nearby else None


def serial(loop, shoulder, axis):
    center = loop["center"]
    projection = shoulder+axis*np.dot(center-shoulder, axis)
    intersection = shoulder+axis*np.dot(center-shoulder, loop["normal"])/np.dot(axis, loop["normal"])
    points = loop["points"]-intersection
    polygon = np.column_stack((points@loop["radial"], points@loop["depth"]))
    inside = False
    for a, b in zip(polygon, np.roll(polygon, -1, axis=0)):
        if (a[1] > 0) != (b[1] > 0) and 0 < (b[0]-a[0])*(-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    upper = (loop["points"]-center)@loop["radial"] > 0
    return dict(center=center.tolist(), tangent=loop["normal"].tolist(),
        circumference=loop["circumference"], area=loop["area"], sectionVertices=len(loop["points"]),
        assumedAxisProjection=projection.tolist(), centerToAssumedAxisMM=float(np.linalg.norm(center-projection)*1000),
        centerMinusAssumedAxisMM=((center-projection)*1000).tolist(), assumedAxisInsideSection=inside,
        progressMin=float(loop["progress"].min()), progressMax=float(loop["progress"].max()),
        progressPerimeterMean=loop["meanProgress"], perimeterFractionProgressUnderPoint1=loop["perimeterNearTorso"],
        perimeterFractionProgressOverPoint9=loop["perimeterNearSleeve"],
        upperHalfMeanProgress=float(loop["progress"][upper].mean()) if upper.any() else None,
        lowerHalfMeanProgress=float(loop["progress"][~upper].mean()) if (~upper).any() else None)


def measure(name):
    path = RESOURCES / f"meshy_{name}.json"
    original = path.read_bytes()
    payload = json.loads(original)
    vertices = np.array(payload["vertices"])
    faces = np.array(payload["indices"]).reshape(-1, 3)
    weights = np.array([entry["sleeveProgress"] for entry in payload["fitting"]["weights"]])
    shoulder, cuff = np.array(payload["sizing"]["rightShoulder"]), np.array(payload["sizing"]["rightCuff"])
    axis = cuff-shoulder
    axis /= np.linalg.norm(axis)
    samples = np.linspace(shoulder[0]+.015, cuff[0]-.03, 12)
    x_loops = []
    for x in samples:
        expected = shoulder+(cuff-shoulder)*((x-shoulder[0])/(cuff[0]-shoulder[0]))
        loop = section(vertices, faces, weights, np.array([x, 0, 0]), np.array([1., 0, 0]), expected)
        if loop is not None:
            x_loops.append(loop)
    centers = np.array([loop["center"] for loop in x_loops])
    refined = []
    for i, initial in enumerate(x_loops):
        tangent = centers[min(i+1, len(centers)-1)]-centers[max(i-1, 0)]
        tangent /= np.linalg.norm(tangent)
        loop = section(vertices, faces, weights, centers[i], tangent, centers[i])
        if loop is not None and np.linalg.norm(loop["center"]-centers[i]) < .07:
            refined.append(loop)
    rows = [serial(loop, shoulder, axis) for loop in refined]
    if rows:
        stations = np.concatenate(([0.], np.cumsum(np.linalg.norm(np.diff([r["center"] for r in rows], axis=0), axis=1))))
        for row, station in zip(rows, stations):
            row["arcFromFirstMeasuredSection"] = float(station)
    evidence = []
    if name == "long_sleeve":
        for index in [2525, 2587, 2645, 2630]:
            point = vertices[index]
            assumed = shoulder+axis*np.dot(point-shoulder, axis)
            closest = min(refined, key=lambda loop: abs(np.dot(point-loop["center"], loop["normal"])))
            local = point-closest["center"]
            local -= closest["normal"]*np.dot(local, closest["normal"])
            evidence.append(dict(vertex=index, position=point.tolist(), sleeveProgress=float(weights[index]),
                assumedAxisRadiusMM=float(np.linalg.norm(point-assumed)*1000),
                measuredSectionCenter=closest["center"].tolist(), sectionLocalRadiusMM=float(np.linalg.norm(local)*1000),
                signedDistanceFromMeasuredSectionPlaneMM=float(np.dot(point-closest["center"], closest["normal"])*1000),
                assumedAxisDepthMM=float((point-assumed)[2]*1000), measuredCenterDepthMM=float((point-closest["center"])[2]*1000)))
    right = vertices[:, 0] > shoulder[0]
    edge_set = {tuple(sorted((int(face[i]), int(face[(i+1) % 3])))) for face in faces for i in range(3)}
    split_edges = [(a, b) for a, b in edge_set if right[a] and right[b] and abs(weights[a]-weights[b]) > .5]
    result = dict(id=name, inputResource=str(path.relative_to(ROOT.parents[2])), inputSHA256=hashlib.sha256(original).hexdigest(),
        measurementScope="Published normalized, source-derived thin skin; no original/source conversion or native solver rerun.",
        shoulderMeasurementAnchor=shoulder.tolist(), cuffMeasurementAnchor=cuff.tolist(), assumedAxis=axis.tolist(),
        xPlaneSections=[serial(loop, shoulder, axis) for loop in x_loops], tangentPlaneSections=rows,
        suppliedVertexEvidence=evidence, rightSleeveEdgesProgressJumpOverPoint5=len(split_edges),
        largestProgressJumpEdges=[dict(vertices=[a, b], positions=vertices[[a, b]].tolist(),
            progress=weights[[a, b]].tolist(), edgeLengthMM=float(np.linalg.norm(vertices[a]-vertices[b])*1000))
            for a, b in sorted(split_edges, key=lambda pair: -abs(weights[pair[0]]-weights[pair[1]]))[:8]])
    near_shoulder = vertices[(abs(vertices[:, 0]-shoulder[0]) < .01) & (vertices[:, 1] > -.10)]
    result["surfaceNearMeasurementShoulder"] = dict(windowX=0.01,
        highestPoint=near_shoulder[np.argmax(near_shoulder[:, 1])].tolist() if len(near_shoulder) else None)
    centers = np.array([row["center"] for row in rows]+[cuff.tolist()])
    stations = (centers-shoulder)@axis
    assert (np.diff(stations) > 0).all()
    tangents = np.array([centers[min(i+1, len(centers)-1)]-centers[max(i-1, 0)] for i in range(len(centers))])
    tangents /= np.linalg.norm(tangents, axis=1)[:, None]
    depth = np.array([0., 0., 1.])-tangents[0]*tangents[0, 2]
    depth /= np.linalg.norm(depth)
    radial = np.cross(depth, tangents[0])
    knots, arc = [], 0.
    for i, (center, tangent, station) in enumerate(zip(centers, tangents, stations)):
        if i:
            axis_cross = np.cross(tangents[i-1], tangent)
            sine, cosine = np.linalg.norm(axis_cross), np.dot(tangents[i-1], tangent)
            if sine > 1e-10:
                rotation_axis = axis_cross/sine
                radial = radial*cosine+np.cross(rotation_axis, radial)*sine+rotation_axis*np.dot(rotation_axis, radial)*(1-cosine)
            arc += np.linalg.norm(center-centers[i-1])
        radial -= tangent*np.dot(radial, tangent)
        radial /= np.linalg.norm(radial)
        depth = np.cross(tangent, radial)
        knots.append(dict(center=center.tolist(), tangent=tangent.tolist(), radialAxis=radial.tolist(), depthAxis=depth.tolist(),
            legacyAxialCoordinate=float(station), arcFromFirstMeasuredSection=float(arc),
            circumference=rows[i]["circumference"] if i < len(rows) else payload["sizing"]["reference"]["sleeveOpening"],
            role="measured cap/tube section, not anatomically labeled" if i < len(rows) else "existing ordered cuff-loop mean"))
    result["proposedCenterlineKnots"] = knots
    mirrored = vertices*np.array([-1, 1, 1])
    asymmetry = []
    for loop in x_loops[::3]:
        left = section(mirrored, faces, weights, np.array([loop["center"][0], 0, 0]), np.array([1., 0, 0]), loop["center"])
        if left is not None:
            asymmetry.append(dict(rightSectionCenter=loop["center"].tolist(),
                leftCenterMirroredToPositiveX=left["center"].tolist(),
                asymmetryMM=float(np.linalg.norm(left["center"]-loop["center"])*1000)))
    result["leftRightXSectionAsymmetry"] = asymmetry
    validated = next(item for item in json.loads((ROOT / "validation_report.json").read_text()) if item["id"] == name)
    blend_validated = next(item for item in json.loads((ROOT / "blend_validation_report.json").read_text()) if item["id"] == name)
    blend_hash = hashlib.sha256((ROOT / f"meshy_{name}_optimized.blend").read_bytes()).hexdigest()
    assert result["inputSHA256"] == validated["resourceSHA256"]
    assert blend_hash == blend_validated["blendSHA256"]
    result["exportReadOnlyAudit"] = dict(resourceMatchesPreviouslyValidatedHash=True,
        blendMatchesPreviouslyValidatedHash=True, blendSHA256=blend_hash)
    if name == "long_sleeve":
        result["suppliedTriangle4991"] = dict(indices=faces[4991].tolist(),
            weights=weights[faces[4991]].tolist(), positions=vertices[faces[4991]].tolist())
    assert path.read_bytes() == original
    return result


if __name__ == "__main__":
    result = [measure(name) for name in ["long_sleeve", "hoodie", "bomber"]]
    (ROOT / "upper_sleeve_diagnostic.json").write_text(json.dumps(result, indent=2))
    for item in result:
        print(item["id"], "large progress jumps", item["rightSleeveEdgesProgressJumpOverPoint5"])
        for row in item["tangentPlaneSections"]:
            print("  center", np.round(row["center"], 4), "circ", round(row["circumference"], 4),
                  "axis error mm", round(row["centerToAssumedAxisMM"], 1), "inside", row["assumedAxisInsideSection"],
                  "weights", round(row["progressMin"], 2), round(row["progressMax"], 2))
        print("  evidence", item["suppliedVertexEvidence"])
