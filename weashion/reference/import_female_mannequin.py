import argparse
import hashlib
import json
import math
from pathlib import Path
import runpy
import shutil
import sys
import zipfile

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Meshy_AI_Low_Poly_T_Pose_Figure_20261028_generate.blend"
WORK = Path(__file__).parent
BLEND = WORK / "female_mannequin.blend"
PREVIEW = WORK / "female_mannequin.png"
CANDIDATE = WORK / "female_mannequin_candidate.json"
MORPHS = WORK / "female_mannequin_morphs.json"
BREAST_PREVIEW = WORK / "female_mannequin_breasts.png"
RESOURCES = ROOT / "weashion/weashion/Resources"


def smoothstep(value):
    value = min(max(value, 0), 1)
    return value * value * (3 - 2 * value)


def apply_modifier(body, modifier):
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def relax(body, name, weights, iterations, factor=0.5):
    group = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
    group.remove(list(range(len(body.data.vertices))))
    for index, weight in enumerate(weights):
        if weight > 0.00001:
            group.add([index], min(weight, 1), "REPLACE")
    modifier = body.modifiers.new(name, "SMOOTH")
    modifier.vertex_group = group.name
    modifier.factor = factor
    modifier.iterations = iterations
    apply_modifier(body, modifier)


def prepare_source():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    body = max((model for model in bpy.context.scene.objects if model.type == "MESH"),
               key=lambda model: len(model.data.vertices))
    for model in list(bpy.context.scene.objects):
        if model != body:
            bpy.data.objects.remove(model, do_unlink=True)
    body.name = "FemaleBodyFrames"
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    minimum = min(vertex.co.z for vertex in body.data.vertices)
    maximum = max(vertex.co.z for vertex in body.data.vertices)
    scale = 1.90 / (maximum - minimum)
    for vertex in body.data.vertices:
        vertex.co = Vector((vertex.co.x * scale, vertex.co.y * scale, (vertex.co.z - minimum) * scale))
    source_points = [vertex.co.copy() for vertex in body.data.vertices]
    modifier = body.modifiers.new("Mobile silhouette reduction", "DECIMATE")
    modifier.ratio = 0.29
    modifier.use_collapse_triangulate = True
    apply_modifier(body, modifier)
    reduced_points = [vertex.co.copy() for vertex in body.data.vertices]
    faces = [list(polygon.vertices) for polygon in body.data.polygons]
    tree = BVHTree.FromPolygons(reduced_points, faces, all_triangles=True)
    errors = [tree.find_nearest(point)[3] for point in source_points[::7]]
    errors = sorted(error for error in errors if error is not None)
    print(f"DECIMATE: vertices={len(reduced_points)} triangles={len(faces)} sampled_p95={errors[int((len(errors) - 1) * 0.95)] * 1000:.2f}mm max={max(errors) * 1000:.2f}mm")
    points = [vertex.co.copy() for vertex in body.data.vertices]
    feature_weights = []
    for point in points:
        face = math.exp(-(point.x / 0.075) ** 2 - ((point.z - 1.755) / 0.09) ** 2)
        feature_weights.append(face * smoothstep((-point.y - 0.005) / 0.045))
    relax(body, "Remove facial features", feature_weights, 40, 0.8)
    arm_weights = []
    for vertex in body.data.vertices:
        point = vertex.co
        threshold = 0.15 + max(1.48 - point.z, 0) * 0.22
        arm_weights.append(smoothstep((abs(point.x) - threshold) / 0.055)
                           * smoothstep((point.z - 0.82) / 0.16)
                           * (1 - smoothstep((point.z - 1.53) / 0.08)))
    group = body.vertex_groups.new(name="WEASHION_Arm")
    for index, weight in enumerate(arm_weights):
        if weight > 0:
            group.add([index], weight, "REPLACE")
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    material = bpy.data.materials.new("WEASHION neutral mannequin")
    material.diffuse_color = (0.58, 0.61, 0.60, 1)
    material.roughness = 0.72
    body.data.materials.clear()
    body.data.materials.append(material)
    body["source_file"] = SOURCE.name
    body["source_sha256"] = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    return body


def build_asset(body):
    points = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in body.data.vertices]
    arm_group = body.vertex_groups["WEASHION_Arm"].index
    arms = [sum(group.weight for group in vertex.groups if group.group == arm_group) for vertex in body.data.vertices]
    crotch_height = min(point.y for point in points if abs(point.x) < 0.004 and 0.65 < point.y < 1.15)
    apices = [max((point for point, arm in zip(points, arms)
                   if 0.035 < point.x * sign < 0.16 and 1.28 < point.y < 1.52 and arm < 0.1),
                  key=lambda point: point.z) for sign in (-1, 1)]
    chest_height = sum(point.y for point in apices) * 0.5
    def torso_width(height):
        return max(abs(point.x) for point, arm in zip(points, arms) if abs(point.y - height) < 0.008 and arm < 0.1)
    waist_heights = [crotch_height + 0.18 + step * 0.005 for step in range(50)
                     if crotch_height + 0.18 + step * 0.005 < chest_height - 0.10]
    waist_height = min(waist_heights, key=torso_width)
    hip_heights = [crotch_height + 0.02 + step * 0.005 for step in range(40)
                   if crotch_height + 0.02 + step * 0.005 < waist_height - 0.10]
    hip_height = max(hip_heights, key=torso_width)
    names = ("head neck chest abdomen waist pelvis leftChestVolume rightChestVolume leftFlank rightFlank "
             "upperBack lowerBack leftButtock rightButtock leftShoulder rightShoulder leftUpperArm rightUpperArm "
             "leftElbow rightElbow leftForearm rightForearm leftWrist rightWrist leftHand rightHand "
             "leftThigh rightThigh leftKnee rightKnee leftCalf rightCalf leftAnkle rightAnkle leftFoot rightFoot").split()
    parts = {name: {"indices": [], "weights": []} for name in names}
    for index, (point, arm) in enumerate(zip(points, arms)):
        side = "left" if point.x < 0 else "right"
        weights = {}
        if point.y > 1.64:
            blend = smoothstep((point.y - 1.64) / 0.055)
            weights = {"head": blend, "neck": 1 - blend}
        elif point.y > 1.55:
            blend = smoothstep((point.y - 1.55) / 0.09)
            weights = {"neck": blend, "chest" if point.z >= 0 else "upperBack": 1 - blend}
        else:
            torso = {}
            front = smoothstep((point.z + 0.025) / 0.065)
            if point.y > (waist_height + chest_height) * 0.5:
                volume = math.exp(-((abs(point.x) - 0.09) / 0.075) ** 2 - ((point.y - chest_height) / 0.10) ** 2) * front * 0.88
                torso = {"chest": front * (1 - volume), "upperBack": (1 - front) * (1 - volume),
                         side + "ChestVolume": volume}
            elif point.y > (hip_height + waist_height) * 0.5:
                waist = math.exp(-((point.y - waist_height) / 0.08) ** 2) * 0.45
                flank = smoothstep((abs(point.x) - 0.09) / 0.07) * 0.45
                torso = {"waist": waist, side + "Flank": flank,
                         "abdomen": (1 - waist - flank) * front, "lowerBack": (1 - waist - flank) * (1 - front)}
            else:
                torso = {"pelvis": front, side + "Buttock": 1 - front}
            leg = 1 - smoothstep((point.y - crotch_height + 0.02) / (hip_height - crotch_height + 0.04))
            for name, value in torso.items():
                weights[name] = max(value, 0) * (1 - arm) * (1 - leg)
            limb = (("Foot", 0.055, 0.06), ("Ankle", 0.13, 0.045), ("Calf", 0.36, 0.15),
                    ("Knee", 0.55, 0.055), ("Thigh", 0.78, 0.19))
            values = [math.exp(-((point.y - center) / radius) ** 2) for name, center, radius in limb]
            for (name, center, radius), value in zip(limb, values):
                weights[side + name] = value / sum(values) * (1 - arm) * leg
            upper = (("Hand", 0.94, 0.09), ("Wrist", 1.065, 0.035), ("Forearm", 1.19, 0.11),
                     ("Elbow", 1.31, 0.045), ("UpperArm", 1.43, 0.10), ("Shoulder", 1.515, 0.05))
            values = [math.exp(-((point.y - center) / radius) ** 2) for name, center, radius in upper]
            for (name, center, radius), value in zip(upper, values):
                weights[side + name] = value / sum(values) * arm
        total = sum(weights.values())
        for name, value in weights.items():
            value = value / total
            if value > 1e-8:
                parts[name]["indices"].append(index)
                parts[name]["weights"].append(round(value, 8))
    targets = {"crown": (0, 1.90, 0.0), "chin": (0, 1.67, 0.05), "neckBase": (0, 1.57, 0),
               "chestCenter": (0, chest_height, 0), "waistCenter": (0, waist_height, 0),
               "pelvisCenter": (0, hip_height, 0), "crotch": (0, crotch_height, 0)}
    for side, sign in (("left", -1), ("right", 1)):
        for name, target in {"Shoulder": (0.18, 1.52, 0), "Elbow": (0.24, 1.31, 0),
                             "Wrist": (0.265, 1.065, 0), "Hip": (0.10, hip_height, 0),
                             "Knee": (0.07, 0.55, 0), "Ankle": (0.06, 0.12, 0),
                             "Heel": (0.06, 0.025, -0.035), "Toe": (0.06, 0.02, 0.13)}.items():
            targets[side + name] = (target[0] * sign, target[1], target[2])
    landmarks = {}
    for name, target in targets.items():
        target = Vector(target)
        candidates = sorted(range(len(points)), key=lambda index: (points[index] - target).length_squared)[:16]
        values = [1 / max((points[index] - target).length_squared, 0.00001) for index in candidates]
        pairs = sorted((index, value / sum(values)) for index, value in zip(candidates, values))
        landmarks[name] = {"indices": [index for index, value in pairs], "weights": [round(value, 8) for index, value in pairs]}
    faces = [list(polygon.vertices) for polygon in body.data.polygons]
    regions = []
    for face in faces:
        center = sum((points[index] for index in face), Vector()) / len(face)
        arm = sum(arms[index] for index in face) / len(face)
        regions.append((1 if center.x >= 0 else 2) if arm > 0.45 else
                       ((3 if center.x >= 0 else 4) if center.y < crotch_height else 0))
    def chain(heights, predicate, fallback):
        result = []
        for height in heights:
            candidates = [points[index] for index in range(len(points))
                          if abs(points[index].y - height) < 0.025 and predicate(index)]
            center = sum(candidates, Vector()) / len(candidates) if candidates else Vector((fallback, height, 0))
            result.append([round(center.x, 7), height, round(center.z, 7)])
        return result
    return {"version": 1, "authoring": "female-mannequin-v2", "sourceFile": SOURCE.name,
            "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            "vertices": [[round(value, 7) for value in point] for point in points],
            "indices": [index for face in faces for index in face], "regions": regions,
            "armWeights": [round(value, 7) for value in arms],
            "armCenters": chain([0.84 + step * 0.03 for step in range(24)], lambda index: points[index].x > 0 and arms[index] > 0.7, 0.25),
            "legCenters": chain([0.04 + step * 0.04 for step in range(25)], lambda index: points[index].x > 0.01 and arms[index] < 0.1, 0.07),
            "landmarks": {"height": 1.90, "inseam": crotch_height, "hipHeight": hip_height, "waistHeight": waist_height,
                          "chestHeight": chest_height, "shoulderHeight": 1.52, "shoulderWidth": 0.37},
            "anatomy": {"version": 1, "landmarkSource": "surfaceEstimated", "parts": parts, "landmarks": landmarks}}


def breast_shapes(body, asset):
    points = [Vector(point) for point in asset["vertices"]]
    shapes = {"neutral": [point.copy() for point in points]}
    centers = []
    for sign in (-1, 1):
        candidates = [point for point, arm in zip(points, asset["armWeights"])
                      if point.x * sign > 0.035 and abs(point.x) < 0.16
                      and abs(point.y - asset["landmarks"]["chestHeight"]) < 0.055 and arm < 0.1]
        apex = max(candidates, key=lambda point: point.z)
        centers.append(Vector((apex.x * 0.55, apex.y + 0.03, apex.z - 0.09)))
    for name, strength in (("small", -1), ("large", 1)):
        result = []
        for point, arm in zip(points, asset["armWeights"]):
            apex = centers[0 if point.x < 0 else 1]
            side = -1 if point.x < 0 else 1
            root = apex
            center = Vector((root.x / 0.55, root.y - 0.03, root.z + 0.09))
            horizontal = (point.x - center.x) / 0.105
            lower = point.y < center.y
            vertical = (point.y - center.y) / (0.155 if lower else 0.105)
            falloff = smoothstep(1 - horizontal * horizontal - vertical * vertical)
            front = smoothstep((point.z - (root.z + 0.045)) / 0.04)
            medial = smoothstep(abs(point.x) / 0.035)
            influence = falloff * front * medial * (1 - arm)
            offset = (point - root) * (0.20 * strength * influence)
            result.append(point + offset)
        shapes[name] = result
    body.shape_key_add(name="Basis")
    for name, positions in shapes.items():
        shape = body.shape_key_add(name=f"breast_{name}")
        for vertex, point in zip(shape.data, positions):
            vertex.co = (point.x, -point.z, point.y)
    for name in ("small", "large"):
        body.data.shape_keys.key_blocks[f"breast_{name}"].relative_key = body.data.shape_keys.key_blocks["breast_neutral"]
    return shapes


def validate_asset(asset, shapes, frames):
    count = len(asset["vertices"])
    assert len(asset["armWeights"]) == count
    assert all(0 <= index < count for index in asset["indices"])
    assert len(asset["indices"]) == len(asset["regions"]) * 3
    totals = [0.0] * count
    for binding in asset["anatomy"]["parts"].values():
        assert binding["indices"] and len(binding["indices"]) == len(binding["weights"])
        for index, weight in zip(binding["indices"], binding["weights"]):
            assert 0 < weight <= 1
            totals[index] += weight
    assert all(abs(total - 1) < 0.001 for total in totals)
    assert all(abs(sum(binding["weights"]) - 1) < 0.001 for binding in asset["anatomy"]["landmarks"].values())
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    def intersections(points):
        tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
        return {(first, second) for first, second in tree.overlap(tree)
                if first < second and set(faces[first]).isdisjoint(faces[second])}
    baseline = intersections(shapes["neutral"])
    assert len(baseline) <= 1, ("unexpected neutral intersections", len(baseline))
    for name in ("small", "large"):
        for step in (0.25, 0.5, 0.75, 1):
            positions = [source.lerp(target, step) for source, target in zip(shapes["neutral"], shapes[name])]
            assert all(math.isfinite(value) for point in positions for value in point)
            added = intersections(positions) - baseline
            assert not added, (name, step, "new intersections", len(added))
    for frame_name, frame in frames.items():
        frame_intersections = intersections(frame)
        assert len(frame_intersections) <= 4, (frame_name, "unexpected frame intersections", len(frame_intersections))
        for name in ("small", "neutral", "large"):
            positions = [Vector(point) + target - source
                         for point, target, source in zip(frame, shapes[name], shapes["neutral"])]
            assert not (intersections(positions) - frame_intersections), (frame_name, name, "new combined intersections")
    print(f"ASSET: vertices={count} anatomy=valid breast_interpolations=8 frame_breast_combinations=9 baseline_intersections={len(baseline)} new_intersections=0")


def export_candidates(body):
    asset = build_asset(body)
    print("LANDMARKS:", asset["landmarks"])
    shapes = breast_shapes(body, asset)
    helpers = runpy.run_path(str(WORK / "build_female_body_frames.py"))
    ratios = helpers["reference_ratios"]()
    frames = {name: helpers["frame_positions"](asset, factors, ratios[name]) for name, factors in helpers["PRESETS"].items()}
    helpers["validate"](asset, frames)
    for name, points in frames.items():
        shape = body.shape_key_add(name=name)
        for vertex, point in zip(shape.data, points):
            vertex.co = (point.x, -point.z, point.y)
    validate_asset(asset, shapes, frames)
    data = (json.dumps(asset, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    morphs = {"version": 1, "sourceSHA256": hashlib.sha256(data).hexdigest(), "vertexCount": len(asset["vertices"]),
              "referenceRatios": ratios,
              "presets": {name: [[round(value - source, 7) for value, source in zip(point, original)]
                                  for point, original in zip(points, asset["vertices"])] for name, points in frames.items()},
              "breastPresets": {name: [[round(value - source, 7) for value, source in zip(point, original)]
                                        for point, original in zip(points, asset["vertices"])] for name, points in shapes.items()}}
    CANDIDATE.write_bytes(data)
    MORPHS.write_text(json.dumps(morphs, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
    return asset, shapes


def publish_candidates():
    mesh_data = CANDIDATE.read_bytes()
    mesh = json.loads(mesh_data)
    morphs = json.loads(MORPHS.read_bytes())
    assert morphs["sourceSHA256"] == hashlib.sha256(mesh_data).hexdigest()
    assert morphs["vertexCount"] == len(mesh["vertices"])
    assert mesh["sourceSHA256"] == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    targets = {RESOURCES / "female_body_40k.json": CANDIDATE,
               RESOURCES / "female_body_frame_presets.json": MORPHS}
    previous = {target: target.read_bytes() for target in targets}
    backup = WORK / "female_body_before_mannequin_v2.zip"
    if not backup.exists():
        with zipfile.ZipFile(backup, "w", zipfile.ZIP_DEFLATED) as archive:
            for target, data in previous.items():
                archive.writestr(target.name, data)
            old_blend = WORK / "female_body_frames.blend"
            if old_blend.exists():
                archive.write(old_blend, old_blend.name)
    staged = {target: target.with_suffix(".json.pending") for target in targets}
    try:
        for target, candidate in targets.items():
            shutil.copyfile(candidate, staged[target])
        for target, pending in staged.items():
            pending.replace(target)
    except BaseException:
        for target, data in previous.items():
            target.write_bytes(data)
        raise
    finally:
        for pending in staged.values():
            pending.unlink(missing_ok=True)
    print(f"PUBLISHED: female vertices={len(mesh['vertices'])} sourceSHA256={morphs['sourceSHA256']} backup={backup.name}")


def render_breast_shapes(body, asset, shapes):
    for model in bpy.context.scene.objects:
        model.hide_render = True
    collection = bpy.data.collections.new("BreastShapeComparison")
    bpy.context.scene.collection.children.link(collection)
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)
             if all(1.16 < asset["vertices"][index][1] < 1.59 for index in asset["indices"][offset:offset + 3])]
    for column, name in enumerate(("small", "neutral", "large")):
        mesh = bpy.data.meshes.new(f"{name} mesh")
        mesh.from_pydata([(point.x, -point.z, point.y) for point in shapes[name]], [], faces)
        cropped = bmesh.new()
        cropped.from_mesh(mesh)
        boundary = [edge for edge in cropped.edges if edge.is_boundary]
        if boundary:
            unvisited = set(boundary)
            while unvisited:
                pending = [unvisited.pop()]
                loop = []
                while pending:
                    edge = pending.pop()
                    loop.append(edge)
                    for vertex in edge.verts:
                        for neighbor in vertex.link_edges:
                            if neighbor in unvisited:
                                unvisited.remove(neighbor)
                                pending.append(neighbor)
                height = sum(vertex.co.z for edge in loop for vertex in edge.verts) / (2 * len(loop))
                target = 1.16 if height < 1.375 else 1.59
                for edge in loop:
                    for vertex in edge.verts:
                        vertex.co.z = target
            bmesh.ops.holes_fill(cropped, edges=boundary, sides=0)
        cropped.to_mesh(mesh)
        cropped.free()
        mesh.materials.append(body.data.materials[0])
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        for row, angle in enumerate((0, math.pi / 4, math.pi / 2)):
            model = bpy.data.objects.new(f"{name}_{row}", mesh)
            collection.objects.link(model)
            model.location = (column * 0.65, 0, (2 - row) * 0.56)
            model.rotation_euler.z = angle
    scene = bpy.context.scene
    scene.camera.hide_render = False
    scene.camera.location = (0.65, -8, 1.95)
    scene.camera.rotation_euler = (Vector((0.65, 0, 1.95)) - scene.camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera.data.ortho_scale = 2.15
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 1800
    scene.render.filepath = str(BREAST_PREVIEW)
    bpy.ops.render.render(write_still=True)
    collection.hide_viewport = True


def render_views(body):
    scene = bpy.context.scene
    for model in list(scene.objects):
        if model != body:
            bpy.data.objects.remove(model, do_unlink=True)
    material = body.data.materials[0]
    comparison = bpy.data.collections.new("MannequinComparison")
    scene.collection.children.link(comparison)
    positions = (("FRONT", 0), ("SIDE", math.pi / 2), ("BACK", math.pi), ("THREE QUARTER", math.pi / 4))
    for column, (name, angle) in enumerate(positions):
        model = bpy.data.objects.new(name, body.data.copy())
        comparison.objects.link(model)
        model.location.x = column * 0.85
        model.rotation_euler.z = angle
        text = bpy.data.curves.new(name, "FONT")
        text.body = name
        text.size = 0.05
        label = bpy.data.objects.new(f"{name} label", text)
        comparison.objects.link(label)
        label.location = (column * 0.85 - 0.20, -0.3, 1.99)
        label.rotation_euler.x = math.pi / 2
    body.hide_render = True
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = False
    shading.show_cavity = False
    shading.background_type = "WORLD"
    scene.world.color = (0.93, 0.93, 0.93)
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1500
    scene.render.resolution_percentage = 100
    bpy.ops.object.camera_add(location=(1.275, -8, 1.0))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((1.275, 0, 1.0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.65
    scene.camera = camera
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    comparison.hide_viewport = True
    bpy.context.view_layer.objects.active = body
    for model in bpy.context.selected_objects:
        model.select_set(False)
    body.select_set(True)
    body.hide_set(False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--publish", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    bpy.context.preferences.filepaths.save_version = 0
    body = prepare_source()
    print(f"MANNEQUIN vertices={len(body.data.vertices)} triangles={len(body.data.polygons)}")
    asset, shapes = export_candidates(body)
    render_views(body)
    render_breast_shapes(body, asset, shapes)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)
    if arguments.publish:
        publish_candidates()


if __name__ == "__main__":
    main()