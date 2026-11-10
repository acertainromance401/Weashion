import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import zipfile

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import convex_hull_2d


WORK = Path(__file__).resolve().parent
SOURCE = WORK.parent / "weashion/Resources/male_body_40k.json"
CANDIDATE = WORK / "female_from_male_candidate.json"
MORPHS = WORK / "female_from_male_morphs.json"
VIEWS = (("FRONT", 0), ("SIDE", math.pi / 2),
         ("BACK", math.pi), ("THREE QUARTER", math.pi / 4))
HEIGHT = 1.60
REFERENCES = (
    "https://supremedisplay.com/products/sdmz-oz1b2-abstract-female-mannequin",
    "https://www.mannequinsexpress.com/female-abstract-full-body-mannequin-standing-pose-p/ca1wt.htm",
)


def smoothstep(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def bell(value, center, radius):
    return math.exp(-((value - center) / radius) ** 2)


def chain_center(chain, height):
    if height <= chain[0][1]:
        return Vector(chain[0])
    for lower, upper in zip(chain, chain[1:]):
        if height <= upper[1]:
            fraction = (height - lower[1]) / (upper[1] - lower[1])
            return Vector(lower).lerp(Vector(upper), fraction)
    return Vector(chain[-1])


def shape_candidate(asset):
    points = [Vector(point) for point in asset["vertices"]]
    neighbors = [set() for point in points]
    for offset in range(0, len(asset["indices"]), 3):
        corners = asset["indices"][offset:offset + 3]
        for index in corners:
            neighbors[index].update(corner for corner in corners if corner != index)
    arm_weights = list(asset["armWeights"])
    for iteration in range(12):
        arm_weights = [weight * 0.6 + 0.4 * sum(arm_weights[other] for other in adjacent) / len(adjacent)
                       if adjacent else weight for weight, adjacent in zip(arm_weights, neighbors)]
    for iteration in range(28):
        relaxed = []
        for point, adjacent, arm in zip(points, neighbors, arm_weights):
            mask = bell(point.y, 0.94, 0.14) * (1 - arm)
            mask = max(mask, 0.5 * bell(point.y, 1.61, 0.08))
            chest = bell(point.y, 1.35, 0.17) * smoothstep((point.z + 0.01) / 0.08) * (1 - arm)
            mask = max(mask, 0.65 * chest)
            mask = max(mask, 0.45 * bell(point.y, 0.53, 0.065) * (1 - arm))
            mask = max(mask, 0.4 * bell(point.y, 1.20, 0.065) * arm)
            average = sum((points[index] for index in adjacent), Vector()) / len(adjacent)
            relaxed.append(point.lerp(average, 0.45 * mask))
        points = relaxed
    foundation = make_body("Candidate foundation", points, asset["indices"])
    group = foundation.vertex_groups.new(name="Arm influence")
    for index, weight in enumerate(arm_weights):
        group.add([index], weight, "REPLACE")
    group_index = group.index
    for kind in ("parts", "landmarks"):
        for name, binding in asset["anatomy"][kind].items():
            binding_group = foundation.vertex_groups.new(name=f"{kind}.{name}")
            for index, weight in zip(binding["indices"], binding["weights"]):
                binding_group.add([index], weight, "REPLACE")
    bpy.context.view_layer.objects.active = foundation
    subdivide = foundation.modifiers.new("Sculpt surface", "SUBSURF")
    subdivide.levels = 1
    bpy.ops.object.modifier_apply(modifier=subdivide.name)
    triangulate = foundation.modifiers.new("Sculpt triangles", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=triangulate.name)
    points = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in foundation.data.vertices]
    arm_weights = [next((entry.weight for entry in vertex.groups if entry.group == group_index), 0.0)
                   for vertex in foundation.data.vertices]
    hand_weights = [weight for point, weight in zip(points, arm_weights) if point.x > 0.26 and 0.90 < point.y < 1.10]
    print(f"SUBDIVIDED_ARM_WEIGHTS hand_min={min(hand_weights):.4f} hand_max={max(hand_weights):.4f} group={group_index}")
    if min(hand_weights) < 0.95:
        raise RuntimeError("Subdivision did not preserve the source hand's arm influence")
    result = []
    for point, arm in zip(points, arm_weights):
        height = point.y
        side = -1 if point.x < 0 else 1
        absolute = abs(point.x)
        upper = bell(height, 1.48, 0.23)
        waist = bell(height, 1.20, 0.13)
        hip = bell(height, 1.01, 0.16)
        neck = bell(height, 1.62, 0.08)
        head = smoothstep((height - 1.66) / 0.07)
        width = 1 - 0.15 * upper - 0.045 * waist + 0.16 * hip - 0.085 * neck
        width = width * (1 - head) + 1.025 * head
        depth = 1 - 0.11 * upper - 0.04 * waist + 0.02 * hip
        trunk = Vector((point.x * width, height, point.z * depth))
        back = smoothstep((-point.z + 0.015) / 0.10)
        latissimus = bell(height, 1.30, 0.105) * smoothstep((absolute - 0.11) / 0.075) * back
        trunk.x *= 1 - 0.035 * latissimus
        trunk.z += 0.004 * latissimus
        trunk.z -= 0.016 * bell(height, 0.97, 0.13) * back * smoothstep(absolute / 0.055)
        trunk.z += 0.008 * bell(height, 1.17, 0.14) * back
        trunk.y -= 0.026 * bell(height, 1.56, 0.085) * bell(absolute, 0.095, 0.075)
        trunk.y += 0.10 * max(0.0, height - 1.66) * head
        arm_center = chain_center(asset["armCenters"], height)
        arm_center.x *= side
        arm_radius = 0.83 + 0.09 * smoothstep((1.06 - height) / 0.16)
        arm_point = Vector((arm_center.x * 0.90 + (point.x - arm_center.x) * arm_radius,
                            height, arm_center.z + (point.z - arm_center.z) * arm_radius))
        shaped = trunk.lerp(arm_point, arm)
        leg = smoothstep((0.99 - height) / 0.18) * (1 - arm)
        leg_center = chain_center(asset["legCenters"], height)
        leg_center.x *= side
        leg_width = 0.91 + 0.19 * bell(height, 0.78, 0.20)
        leg_depth = 0.93 + 0.15 * bell(height, 0.78, 0.20)
        stance = 1 - 0.20 * smoothstep((0.93 - height) / 0.55)
        leg_point = Vector((point.x * leg_width + leg_center.x * (stance - leg_width) * smoothstep(absolute / 0.075),
                            height, leg_center.z + (point.z - leg_center.z) * leg_depth))
        shaped = shaped.lerp(leg_point, leg)
        front = smoothstep((point.z + 0.005) / 0.095) * (1 - arm)
        shaped.z += 0.015 * bell(height, 1.09, 0.14) * bell(absolute, 0, 0.15) * front
        clavicle_height = 1.495 - 0.11 * absolute + 0.012 * bell(absolute, 0.11, 0.05)
        clavicle = bell(height, clavicle_height, 0.018) * bell(absolute, 0.10, 0.085)
        shaped.z += 0.008 * clavicle * front
        shaped.z -= 0.004 * bell(height, clavicle_height - 0.032, 0.027) * bell(absolute, 0.09, 0.075) * front
        shaped.z -= 0.004 * bell(height, 1.51, 0.025) * bell(absolute, 0, 0.028) * front
        shaped.z -= 0.005 * bell(height, 1.41, 0.13) * bell(absolute, 0.09, 0.055) * back * (1 - arm)
        rear_shoulder = bell(height, 1.50, 0.055) * bell(absolute, 0.21, 0.03) * back * (1 - arm)
        shaped.z += 0.004 * rear_shoulder
        shaped.z += 0.005 * bell(height, 1.29, 0.24) * bell(absolute, 0, 0.025) * back * (1 - arm)
        knee = bell(height, 0.53, 0.055) * leg
        shaped.z += 0.006 * knee * smoothstep((point.z - leg_center.z) / 0.045)
        support = 0.0
        for breast_side in (-1, 1):
            breast_center = breast_side * (0.108 + 0.035 * (1.345 - height))
            horizontal = (shaped.x - breast_center) / 0.13
            vertical = (height - 1.345) / (0.17 if height >= 1.345 else 0.12)
            support += math.exp(-1.7 * (horizontal * horizontal + vertical * vertical))
        shaped.z += 0.052 * support * front
        result.append(shaped * (HEIGHT / asset["landmarks"]["height"]))
    for vertex, point in zip(foundation.data.vertices, result):
        vertex.co = (point.x, -point.z, point.y)
    foundation.name = "Female candidate"
    return foundation


def finish_candidate(body):
    bpy.context.view_layer.objects.active = body
    smooth = body.modifiers.new("Surface relaxation", "SMOOTH")
    smooth.factor = 0.35
    smooth.iterations = 4
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate = body.modifiers.new("Mobile polygon budget", "DECIMATE")
    decimate.ratio = 0.20
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    lowest = min(vertex.co.z for vertex in body.data.vertices)
    span = max(vertex.co.z for vertex in body.data.vertices) - lowest
    for vertex in body.data.vertices:
        vertex.co.z -= lowest
        vertex.co *= HEIGHT / span
    arm_group = body.vertex_groups["Arm influence"].index
    for vertex in body.data.vertices:
        point = vertex.co
        arm = next((entry.weight for entry in vertex.groups if entry.group == arm_group), 0.0)
        posterior_axilla = bell(point.z, 1.20, 0.088) * bell(abs(point.x), 0.145, 0.060)
        posterior_axilla *= smoothstep((point.y - 0.025) / 0.06) * (1 - arm)
        point.x *= 1 - 0.08 * posterior_axilla
        point.y -= 0.014 * posterior_axilla
    refine_posterior_axilla(body)


def refine_posterior_axilla(body):
    arm_group = body.vertex_groups["Arm influence"].index
    offsets = [Vector() for vertex in body.data.vertices]
    neighbors = [set() for vertex in body.data.vertices]
    for polygon in body.data.polygons:
        for index in polygon.vertices:
            neighbors[index].update(other for other in polygon.vertices if other != index)
    affected = []
    for vertex in body.data.vertices:
        point = vertex.co
        lateral, height, posterior = abs(point.x), point.z, point.y
        height_mask = smoothstep((height - 1.10) / 0.06) * (1 - smoothstep((height - 1.25) / 0.055))
        width_mask = smoothstep((lateral - 0.095) / 0.025) * (1 - smoothstep((lateral - 0.190) / 0.03))
        rear = smoothstep((posterior - 0.005) / 0.045)
        mask = height_mask * width_mask * rear
        if mask == 0:
            continue
        arm = next((entry.weight for entry in vertex.groups if entry.group == arm_group), 0.0)
        side = -1 if point.x < 0 else 1
        fold = bell(height, 1.165, 0.060) * bell(lateral, 0.135, 0.040) * (1 - arm) * mask
        # A shallow sulcus separates the posterior deltoid/upper arm from the torso.
        crease_x = 0.156 + 0.20 * (height - 1.20)
        crease = bell(lateral, crease_x, 0.026) * bell(height, 1.195, 0.055) * mask
        lift = bell(lateral, 0.150, 0.030) * bell(height, 1.165, 0.040) * 4 * arm * (1 - arm) * mask
        offsets[vertex.index] = Vector((-side * 0.012 * fold, -0.013 * crease - 0.006 * fold, 0.008 * lift))
        affected.append(vertex.index)
    if not affected:
        raise RuntimeError("The posterior axilla refinement did not affect any vertices")
    for iteration in range(3):
        relaxed = list(offsets)
        for index in affected:
            average = sum((offsets[other] for other in neighbors[index]), Vector()) / len(neighbors[index])
            relaxed[index] = offsets[index].lerp(average, 0.4)
        offsets = relaxed
    for vertex, offset in zip(body.data.vertices, offsets):
        vertex.co += offset
    body["posteriorAxillaRefinement"] = "Connected shoulder, shortened posterior fold and upper-arm sulcus."
    print(f"POSTERIOR_AXILLA vertices={len(affected)} max_offset_m={max(offset.length for offset in offsets):.6f}")


def section_circumference(body, height):
    points = {}
    neighbors = {}
    for polygon in body.data.polygons:
        corners = list(polygon.vertices)
        crossings = []
        for lower_index, upper_index in zip(corners, corners[1:] + corners[:1]):
            lower = body.data.vertices[lower_index].co
            upper = body.data.vertices[upper_index].co
            if (lower.z - height) * (upper.z - height) < 0:
                edge = tuple(sorted((lower_index, upper_index)))
                point = lower.lerp(upper, (height - lower.z) / (upper.z - lower.z))
                points[edge] = Vector((point.x, point.y))
                crossings.append(edge)
        if len(crossings) == 2:
            first, second = crossings
            neighbors.setdefault(first, set()).add(second)
            neighbors.setdefault(second, set()).add(first)
    components = []
    remaining = set(neighbors)
    while remaining:
        pending = [remaining.pop()]
        component = []
        while pending:
            edge = pending.pop()
            component.append(points[edge])
            for other in neighbors[edge]:
                if other in remaining:
                    remaining.remove(other)
                    pending.append(other)
        if min(point.x for point in component) < 0 < max(point.x for point in component):
            components.append(component)
    if len(components) != 1:
        raise RuntimeError(f"Expected one central torso section at height {height}, got {len(components)}")
    section = components[0]
    hull = [section[index] for index in convex_hull_2d(section)]
    return sum((lower - upper).length for lower, upper in zip(hull, hull[1:] + hull[:1]))


def export_runtime(body, source):
    points = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in body.data.vertices]
    names = {group.index: group.name for group in body.vertex_groups}
    weights = [{names[entry.group]: entry.weight for entry in vertex.groups} for vertex in body.data.vertices]
    arms = [values.get("Arm influence", 0.0) for values in weights]
    parts = {name: {"indices": [], "weights": []} for name in source["anatomy"]["parts"]}
    landmarks = {}
    for name in source["anatomy"]["landmarks"]:
        pairs = [(index, values.get(f"landmarks.{name}", 0.0)) for index, values in enumerate(weights)
                 if values.get(f"landmarks.{name}", 0.0) > 1e-10]
        total = sum(weight for index, weight in pairs)
        if total <= 0:
            raise RuntimeError(f"Lost landmark during reduction: {name}")
        landmarks[name] = {"indices": [index for index, weight in pairs],
                           "weights": [weight / total for index, weight in pairs]}

    def anchor(name):
        binding = landmarks[name]
        return sum((points[index] * weight for index, weight in zip(binding["indices"], binding["weights"])), Vector())

    crotch = min(point.y for point in points if abs(point.x) < 0.004 and HEIGHT * 0.35 < point.y < HEIGHT * 0.60)
    apices = [max((point for point, arm in zip(points, arms)
                   if 0.025 < point.x * side < 0.14 and HEIGHT * 0.65 < point.y < HEIGHT * 0.76 and arm < 0.1),
                  key=lambda point: point.z) for side in (-1, 1)]
    chest = sum(point.y for point in apices) * 0.5

    def torso_width(level):
        return max(abs(point.x) for point, arm in zip(points, arms) if abs(point.y - level) < 0.008 and arm < 0.1)

    waist = min((crotch + 0.12 + step * 0.004 for step in range(70)
                 if crotch + 0.12 + step * 0.004 < chest - 0.07), key=torso_width)
    hip = max((crotch + 0.025 + step * 0.004 for step in range(60)
               if crotch + 0.025 + step * 0.004 < waist - 0.07), key=torso_width)
    shoulders = (anchor("leftShoulder"), anchor("rightShoulder"))
    shoulder_height = sum(point.y for point in shoulders) * 0.5
    shoulder_width = abs(shoulders[1].x - shoulders[0].x)
    for name, level in (("chestCenter", chest), ("waistCenter", waist), ("pelvisCenter", hip)):
        candidates = sorted((index for index, arm in enumerate(arms) if arm < 0.1),
                            key=lambda index: (points[index].y - level) ** 2 * 16 + points[index].x ** 2)[:48]
        landmarks[name] = {"indices": sorted(candidates), "weights": [1 / len(candidates)] * len(candidates)}
    for index, (point, values) in enumerate(zip(points, weights)):
        local = {name: values.get(f"parts.{name}", 0.0) for name in parts}
        chest_weight = sum(local[name] for name in ("chest", "leftChestVolume", "rightChestVolume"))
        breast = bell(abs(point.x), 0.09, 0.065) * bell(point.y, chest, 0.10) * smoothstep((point.z + 0.005) / 0.07) * 0.9
        local["chest"] = chest_weight * (1 - breast)
        local["leftChestVolume"] = chest_weight * breast if point.x < 0 else 0
        local["rightChestVolume"] = chest_weight * breast if point.x >= 0 else 0
        groin = bell(point.x, 0, 0.045) * bell(point.y, crotch, 0.065)
        for name in ("leftThigh", "rightThigh"):
            protected = local[name] * groin
            local[name] -= protected
            local["pelvis"] += protected
        total = sum(local.values())
        if total <= 0:
            raise RuntimeError(f"Unbound vertex: {index}")
        for name, weight in local.items():
            if weight > 0:
                parts[name]["indices"].append(index)
                parts[name]["weights"].append(weight / total)
    faces = [list(polygon.vertices) for polygon in body.data.polygons]
    regions = []
    for face in faces:
        center = sum((points[index] for index in face), Vector()) / len(face)
        arm = sum(arms[index] for index in face) / len(face)
        regions.append((1 if center.x >= 0 else 2) if arm > 0.45 else
                       ((3 if center.x >= 0 else 4) if center.y < crotch else 0))

    def chain(lower, upper, count, is_arm):
        result = []
        for step in range(count):
            level = lower + (upper - lower) * step / (count - 1)
            candidates = [point for point, arm in zip(points, arms)
                          if point.x > 0.005 and abs(point.y - level) < 0.025
                          and (arm > 0.7 if is_arm else arm < 0.1)]
            if not candidates:
                raise RuntimeError(f"Missing limb section at {level}")
            center = sum(candidates, Vector()) / len(candidates)
            result.append([center.x, level, center.z])
        return result

    arm_bottom = min(point.y for point, arm in zip(points, arms) if arm > 0.9) + 0.015
    arm_centers = chain(arm_bottom, chest, 21, True)
    arm_centers.append([abs(shoulders[1].x), shoulder_height, shoulders[1].z])
    asset = {"version": 1, "authoring": "female-from-male-v1", "sourceFile": SOURCE.name,
             "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
             "vertices": [list(point) for point in points], "indices": [index for face in faces for index in face],
             "regions": regions, "armWeights": arms, "armCenters": arm_centers,
             "legCenters": chain(0.025, crotch, 22, False),
             "landmarks": {"height": HEIGHT, "inseam": crotch, "hipHeight": hip, "waistHeight": waist,
                           "chestHeight": chest, "shoulderHeight": shoulder_height, "shoulderWidth": shoulder_width},
             "anatomy": {"version": 1, "landmarkSource": "surfaceEstimated", "parts": parts, "landmarks": landmarks}}
    levels = [0, crotch, hip, waist, chest, shoulder_height, HEIGHT]
    if not all(lower < upper for lower, upper in zip(levels, levels[1:])):
        raise RuntimeError(f"Unordered anatomical levels: {levels}")
    if not all(binding["indices"] for binding in parts.values()):
        raise RuntimeError("An anatomical part has no vertices")
    frames = {name: [] for name in ("straight", "wave", "natural")}
    breasts = {name: [] for name in ("small", "neutral", "large")}
    for point, arm, values in zip(points, arms, weights):
        torso = (1 - arm) * smoothstep((point.y - crotch) / max(hip - crotch, 0.02))
        upper = bell(point.y, chest + 0.025, 0.15) * (1 - smoothstep((point.y - shoulder_height + 0.015) / 0.08))
        middle = bell(point.y, waist, 0.10)
        pelvis = bell(point.y, hip, 0.10)
        shoulder = values.get("parts.leftShoulder", 0) + values.get("parts.rightShoulder", 0)
        joint = sum(values.get(f"parts.{side}{part}", 0)
                    for side in ("left", "right") for part in ("Elbow", "Wrist", "Knee", "Ankle"))
        side = -1 if point.x < 0 else 1
        arm_center = chain_center(arm_centers, point.y)
        leg_center = chain_center(asset["legCenters"], point.y)
        limb_center = arm_center if arm > 0.5 else leg_center
        radial = Vector((point.x - side * limb_center.x, 0, point.z - limb_center.z))
        frames["straight"].append(Vector((-point.x * (0.055 * upper + 0.025 * middle) * torso, 0,
                          point.z * (0.18 * upper + 0.06 * middle) * torso)))
        frames["wave"].append(Vector((point.x * (0.07 * pelvis - 0.04 * upper - 0.025 * middle) * torso, 0,
                          point.z * (-0.06 * pelvis - 0.11 * upper + 0.055 * middle) * torso)))
        frames["natural"].append(Vector((point.x * (0.085 * upper + 0.055 * middle) * torso + side * 0.004 * shoulder, 0,
                         -point.z * (0.08 * upper + 0.07 * middle) * torso)) + radial * (0.08 * joint))
        support = sum(math.exp(-1.7 * (((point.x - apex.x) / 0.105) ** 2
                      + ((point.y - chest) / (0.14 if point.y >= chest else 0.10)) ** 2)) for apex in apices)
        influence = support * smoothstep((point.z - 0.015) / 0.065) * (1 - arm)
        for name, depth in (("small", -0.016), ("neutral", 0), ("large", 0.024)):
            breasts[name].append(Vector((side * depth * 0.08 * influence, -max(depth, 0) * 0.10 * influence,
                                         depth * influence)))
    validate_runtime(asset, frames, breasts)
    body.shape_key_add(name="Basis")
    for name, offsets in list(frames.items()) + [("breast_" + name, offsets) for name, offsets in breasts.items()]:
        shape = body.shape_key_add(name=name)
        for vertex, point, offset in zip(shape.data, points, offsets):
            target = point + offset
            vertex.co = (target.x, -target.z, target.y)
    data = (json.dumps(asset, separators=(",", ":"), allow_nan=False) + "\n").encode()
    morphs = {"version": 1, "sourceSHA256": hashlib.sha256(data).hexdigest(), "vertexCount": len(points),
              "presets": {name: [list(offset) for offset in offsets] for name, offsets in frames.items()},
              "breastPresets": {name: [list(offset) for offset in offsets] for name, offsets in breasts.items()}}
    CANDIDATE.write_bytes(data)
    MORPHS.write_text(json.dumps(morphs, separators=(",", ":"), allow_nan=False) + "\n")
    print("RUNTIME_LANDMARKS", json.dumps(asset["landmarks"]))
    print(f"RUNTIME_EXPORTED vertices={len(points)} parts={len(parts)} landmarks={len(landmarks)} frames=3 breast_shapes=3")
    return asset


def validate_runtime(asset, frames, breasts):
    points = [Vector(point) for point in asset["vertices"]]
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    totals = [0.0] * len(points)
    for binding in asset["anatomy"]["parts"].values():
        for index, weight in zip(binding["indices"], binding["weights"]):
            if not 0 < weight <= 1:
                raise RuntimeError("Invalid anatomical weight")
            totals[index] += weight
    if any(abs(total - 1) > 0.00001 for total in totals):
        raise RuntimeError("Unnormalized anatomical weights")
    variants = {"neutral": [Vector() for point in points], **frames}
    for frame_name, frame in variants.items():
        for breast_name, breast in breasts.items():
            positions = [point + frame_offset + breast_offset
                         for point, frame_offset, breast_offset in zip(points, frame, breast)]
            if not all(math.isfinite(value) for point in positions for value in point):
                raise RuntimeError("Nonfinite morph position")
            for face in faces:
                first, second, third = face
                before = (points[second] - points[first]).cross(points[third] - points[first])
                after = (positions[second] - positions[first]).cross(positions[third] - positions[first])
                if before.dot(after) <= 0:
                    raise RuntimeError(f"Flipped morph face: {frame_name}/{breast_name}")
            tree = BVHTree.FromPolygons(positions, faces, all_triangles=True)
            overlaps = [(first, second) for first, second in tree.overlap(tree)
                        if first < second and set(faces[first]).isdisjoint(faces[second])]
            if overlaps:
                raise RuntimeError(f"Intersecting morph: {frame_name}/{breast_name}: {len(overlaps)}")
    print("RUNTIME_MORPHS combinations=12 flipped_faces=0 overlaps=0 weights=normalized")


def publish_runtime():
    mesh_data = CANDIDATE.read_bytes()
    morph_data = MORPHS.read_bytes()
    asset = json.loads(mesh_data)
    morphs = json.loads(morph_data)
    if (morphs["sourceSHA256"] != hashlib.sha256(mesh_data).hexdigest()
            or morphs["vertexCount"] != len(asset["vertices"])
            or asset["sourceSHA256"] != hashlib.sha256(SOURCE.read_bytes()).hexdigest()):
        raise RuntimeError("Candidate and morph data do not match")
    targets = {SOURCE.parent / "female_body_40k.json": mesh_data,
               SOURCE.parent / "female_body_frame_presets.json": morph_data}
    previous = {path: path.read_bytes() for path in targets}
    backup = WORK / "female_body_before_male_derived.zip"
    if not backup.exists():
        with zipfile.ZipFile(backup, "w", zipfile.ZIP_DEFLATED) as archive:
            for path, data in previous.items():
                archive.writestr(path.name, data)
    staged = {path: path.with_suffix(".json.pending") for path in targets}
    try:
        for path, data in targets.items():
            staged[path].write_bytes(data)
        for path, pending in staged.items():
            pending.replace(path)
    except BaseException:
        for path, data in previous.items():
            path.write_bytes(data)
        raise
    finally:
        for pending in staged.values():
            pending.unlink(missing_ok=True)
    print(f"PUBLISHED female-from-male-v1 vertices={len(asset['vertices'])} backup={backup.name}")


def inspect_mesh(body):
    mesh = bmesh.new()
    mesh.from_mesh(body.data)
    nonmanifold = sum(not edge.is_manifold for edge in mesh.edges)
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    mesh.to_mesh(body.data)
    mesh.free()
    points = [vertex.co for vertex in body.data.vertices]
    triangles = [tuple(face.vertices) for face in body.data.polygons]
    tree = BVHTree.FromPolygons(points, triangles, all_triangles=True)
    intersections = [(first, second) for first, second in tree.overlap(tree)
                     if first < second and not set(triangles[first]).intersection(triangles[second])]
    print(f"MESH {body.name!r} vertices={len(points)} triangles={len(triangles)} nonmanifold_edges={nonmanifold} overlaps={len(intersections)}")
    if intersections:
        print("OVERLAP_CENTERS", [tuple(round(value, 5) for value in sum((points[index] for index in triangles[first]), Vector()) / 3)
                                  for first, second in intersections[:12]])
    return {"vertices": len(points), "triangles": len(triangles),
            "nonmanifoldEdges": nonmanifold, "overlaps": len(intersections)}


def make_body(name, positions, indices):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(point[0], -point[2], point[1]) for point in positions], [],
                     [indices[offset:offset + 3] for offset in range(0, len(indices), 3)])
    mesh.update()
    body = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(body)
    material = bpy.data.materials.get("Neutral clay") or bpy.data.materials.new("Neutral clay")
    material.diffuse_color = (0.53, 0.56, 0.55, 1)
    material.roughness = 0.78
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return body


def render_views(body, path, height=1.900415, detail=False):
    scene = bpy.context.scene
    collection = bpy.data.collections.new("Review " + body.name)
    scene.collection.children.link(collection)
    views = (VIEWS[0], VIEWS[3], VIEWS[1]) if detail else VIEWS
    spacing = 0.66 if detail else 0.88
    for column, (name, angle) in enumerate(views):
        model = bpy.data.objects.new(name, body.data)
        collection.objects.link(model)
        model.scale = (1.900415 / height,) * 3
        model.location.x = column * spacing
        model.rotation_euler.z = angle
        if detail:
            continue
        text = bpy.data.curves.new(name, "FONT")
        text.body = name
        text.size = 0.027 if detail else 0.042
        text.align_x = "CENTER"
        label = bpy.data.objects.new(name + " label", text)
        collection.objects.link(label)
        label.location = (column * spacing, -0.5, 1.69 if detail else 2.00)
        label.rotation_euler.x = math.pi / 2
    for model in scene.objects:
        if model.type == "MESH" and model.name not in collection.objects:
            model.hide_render = True
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.studiolight_rotate_z = 0.35
    shading.color_type = "MATERIAL"
    shading.show_shadows = False
    shading.show_cavity = False
    shading.show_specular_highlight = False
    shading.background_type = "WORLD"
    scene.world.color = (0.92, 0.92, 0.92)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1000 if detail else 1500
    scene.render.resolution_percentage = 100
    camera = scene.camera
    if camera is None:
        camera = bpy.data.objects.new("Review camera", bpy.data.cameras.new("Review camera"))
        scene.collection.objects.link(camera)
        scene.camera = camera
    center = Vector((0.66, 0, 1.32)) if detail else Vector((1.32, 0, 1.0))
    camera.location = center + Vector((0, -8, 0))
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.04 if detail else 3.65
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.collections.remove(collection)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    if bpy.context.scene.world is None:
        bpy.context.scene.world = bpy.data.worlds.new("Review world")
    asset = json.loads(SOURCE.read_text())
    male = make_body("Current male reference", asset["vertices"], asset["indices"])
    render_views(male, WORK / "male_app_reference.png")
    print(f"MALE_REFERENCE vertices={len(asset['vertices'])} triangles={len(asset['indices']) // 3}")
    inspect_mesh(male)
    female = shape_candidate(asset)
    finish_candidate(female)
    female["status"] = "Runtime-bound female model with anatomy, frame and breast morphs."
    female["source"] = "Current male_body_40k.json geometry; female proportions authored separately."
    report = inspect_mesh(female)
    if report["nonmanifoldEdges"] or report["overlaps"]:
        raise RuntimeError("The review candidate has an open edge or self-intersection")
    runtime = export_runtime(female, asset)
    report.update({
        "status": "Runtime assets published" if args.publish else "Runtime candidate exported; not published",
        "source": str(SOURCE.relative_to(WORK.parents[1])),
        "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "heightMeters": HEIGHT,
        "runtimeLandmarks": runtime["landmarks"],
        "references": list(REFERENCES),
        "referenceUse": "Surface styling and torso transitions only; not copied meshes or population measurements",
        "sections": {name: {"heightMeters": level * HEIGHT / 1.9,
                            "convexCircumferenceMeters": section_circumference(female, level * HEIGHT / 1.9)}
                     for name, level in (("chest", 1.355), ("waist", 1.20), ("hip", 1.01))},
    })
    print("SECTIONS", json.dumps(report["sections"]))
    render_views(female, WORK / "female_from_male_candidate.png", HEIGHT)
    render_views(female, WORK / "female_from_male_detail.png", HEIGHT, detail=True)
    male.hide_viewport = True
    female.hide_render = False
    bpy.context.view_layer.objects.active = female
    female.select_set(True)
    bpy.context.scene.unit_settings.system = "METRIC"
    scene = bpy.context.scene
    scene.camera.location = (0, -8, HEIGHT / 2)
    scene.camera.rotation_euler = (Vector((0, 0, HEIGHT / 2)) - scene.camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera.data.ortho_scale = 1.9
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1600
    scene.render.filepath = str(WORK / "female_from_male_portrait.png")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_location = (0, 0, HEIGHT / 2)
                area.spaces.active.region_3d.view_distance = 2.6
    notes = bpy.data.texts.new("ABOUT THIS CANDIDATE")
    notes.write(json.dumps(report, indent=2) + "\n")
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "female_from_male_candidate.blend"), check_existing=False)
    (WORK / "female_from_male_report.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.publish:
        publish_runtime()


if __name__ == "__main__":
    main()