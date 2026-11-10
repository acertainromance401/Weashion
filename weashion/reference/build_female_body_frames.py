import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "weashion/weashion/Resources/female_body_40k.json"
OUTPUT = SOURCE.with_name("female_body_frame_presets.json")
BLEND = Path(__file__).with_name("female_body_frames.blend")
PREVIEW = BLEND.with_suffix(".png")
BREAST_PREVIEW = BLEND.with_name("female_body_breasts.png")
BREAST_KEYS = ("small", "neutral", "large")
PRESETS = {
    "straight": {
        "chest": (-0.045, 0.10), "ChestVolume": (-0.025, 0.08),
        "upperBack": (-0.035, 0.075), "abdomen": (-0.015, 0.075),
        "waist": (-0.025, 0.055), "Flank": (-0.015, 0.035),
        "pelvis": (0.01, 0.03), "Buttock": (-0.01, 0.045),
        "Thigh": (-0.025, -0.015),
    },
    "wave": {
        "chest": (0.025, -0.11), "ChestVolume": (0.01, -0.05),
        "upperBack": (0.02, -0.08), "waist": (-0.02, -0.04),
        "pelvis": (0.045, -0.02), "Buttock": (0.02, 0.07),
        "Thigh": (0.04, 0.035),
    },
    "natural": {
        "chest": (0.04, -0.045), "ChestVolume": (-0.025, -0.04),
        "upperBack": (0.065, -0.035), "Flank": (0.02, -0.025),
        "pelvis": (-0.025, -0.015), "Buttock": (-0.02, -0.015),
        "Shoulder": (0.05, 0.02), "Forearm": (0.02, 0.02),
        "Wrist": (0.04, 0.04), "Elbow": (0.06, 0.04), "Knee": (0.05, 0.03),
    },
}
LABELS = {"straight": "스트레이트", "wave": "웨이브", "natural": "내추럴"}


def reference_ratios():
    with (ROOT / "womens_body_frame_synthetic_dataset.csv").open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    columns = {"chest": "가슴둘레_cm", "waist": "허리둘레_cm", "hip": "엉덩이둘레_cm"}
    overall = {
        name: sum(float(row[column]) / float(row["키_cm"]) for row in rows) / len(rows)
        for name, column in columns.items()
    }
    result = {}
    for preset, label in LABELS.items():
        selected = [row for row in rows if row["골격유형"] == label]
        result[preset] = {
            name: sum(float(row[column]) / float(row["키_cm"]) for row in selected)
            / len(selected) / overall[name]
            for name, column in columns.items()
        }
    return result


def frame_positions(asset, factors, ratios):
    points = [Vector(point) for point in asset["vertices"]]
    offsets = [Vector((0, 0, 0)) for point in points]
    region_parts = {
        "chest": {"chest", "upperBack", "leftChestVolume", "rightChestVolume"},
        "waist": {"waist", "abdomen", "lowerBack", "leftFlank", "rightFlank"},
        "hip": {"pelvis", "leftButtock", "rightButtock"},
    }
    centers = {}
    for region, names in region_parts.items():
        total, center = 0, Vector()
        for part in names:
            binding = asset["anatomy"]["parts"][part]
            for index, weight in zip(binding["indices"], binding["weights"]):
                center += points[index] * weight
                total += weight
        centers[region] = center / total
    for part, binding in asset["anatomy"]["parts"].items():
        family = part.removeprefix("left").removeprefix("right")
        width, depth = factors.get(part, factors.get(family, (0, 0)))
        region = "chest" if part in {"chest", "upperBack"} or family == "ChestVolume" else None
        if part in {"waist", "abdomen"} or family == "Flank":
            region = "waist"
        if part == "pelvis" or family == "Buttock":
            region = "hip"
        if region:
            width += (ratios[region] - 1) * 0.5
        if width == 0 and depth == 0:
            continue
        weights = binding["weights"]
        center = sum((points[index] * weight for index, weight in zip(binding["indices"], weights)), Vector()) / sum(weights)
        if region:
            center.x = 0
            center.z = centers[region].z
        for index, weight in zip(binding["indices"], weights):
            radial = points[index] - center
            offsets[index] += Vector((radial.x * width, 0, radial.z * depth)) * weight
    neighbors = [set() for point in points]
    for offset in range(0, len(asset["indices"]), 3):
        corners = asset["indices"][offset:offset + 3]
        for corner in range(3):
            neighbors[corners[corner]].update(corners)
    for index, adjacent in enumerate(neighbors):
        adjacent.discard(index)
    for iteration in range(6):
        offsets = [
            displacement * 0.55 + sum((offsets[neighbor] for neighbor in adjacent), Vector()) * (0.45 / len(adjacent))
            if adjacent else displacement
            for displacement, adjacent in zip(offsets, neighbors)
        ]
    return stabilize_positions(asset, [point + displacement for point, displacement in zip(points, offsets)])


def stabilize_positions(asset, shaped, preserve_height=True):
    points = [Vector(point) for point in asset["vertices"]]
    triangles = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    normals = [(points[second] - points[first]).cross(points[third] - points[first])
               for first, second, third in triangles]
    for iteration in range(48):
        corrections = [Vector() for point in points]
        counts = [0 for point in points]
        conflicts = 0
        for corners, original_normal in zip(triangles, normals):
            area = original_normal.length
            if area < 1e-10:
                continue
            normal = original_normal / area
            first, second, third = (shaped[index] for index in corners)
            edge, other = second - first, third - first
            deficit = area * 0.1 - edge.cross(other).dot(normal)
            if deficit <= 0:
                continue
            gradients = [(second - third).cross(normal), other.cross(normal), normal.cross(edge)]
            for index, gradient in zip(corners, gradients):
                if preserve_height:
                    gradient.y = 0
                if abs(points[index].x) < 1e-6:
                    gradient.x = 0
            denominator = sum(gradient.length_squared for gradient in gradients)
            if denominator < 1e-24:
                continue
            for index, gradient in zip(corners, gradients):
                correction = gradient * (deficit / denominator)
                corrections[index] += correction * min(1, 0.004 / max(correction.length, 1e-12))
                counts[index] += 1
            conflicts += 1
        if conflicts == 0:
            break
        shaped = [point + correction / count if count else point
                  for point, correction, count in zip(shaped, corrections, counts)]
    return shaped


def validate(asset, variants, preserve_height=True, reference=None, front_orientation=False):
    source = [Vector(point) for point in (reference if reference is not None else asset["vertices"])]
    for name, points in variants.items():
        assert len(points) == len(source), name
        assert all(math.isfinite(value) for point in points for value in point), name
        if preserve_height:
            assert all(abs(point.y - original.y) < 1e-6 for point, original in zip(points, source)), name
        flipped = 0
        for offset in range(0, len(asset["indices"]), 3):
            first, second, third = asset["indices"][offset:offset + 3]
            before = (source[second] - source[first]).cross(source[third] - source[first])
            after = (points[second] - points[first]).cross(points[third] - points[first])
            inverted = before.z * after.z <= 0 if front_orientation and abs(before.z) > 1e-12 else before.dot(after) <= 0
            if before.length_squared > 1e-20 and inverted:
                flipped += 1
        assert flipped == 0, (name, "flipped triangles", flipped)
        maximum = max((point - original).length for point, original in zip(points, source))
        print(f"FRAME {name}: vertices={len(points)} flipped={flipped} max_offset={maximum * 1000:.2f}mm")


def chest_wall_sections(points):
    sections = []
    for step in range(12):
        height = 1.15 + step * 0.05
        depths = sorted(point.z for point in points
                        if abs(point.x) < 0.025 and abs(point.y - height) < 0.025 and point.z > 0)
        if depths:
            sections.append((height, depths[len(depths) // 2]))
    return sections


def chest_wall_depth(height, sections):
    if height <= sections[0][0]:
        return sections[0][1]
    for lower, upper in zip(sections, sections[1:]):
        if height <= upper[0]:
            blend = min(max((height - lower[0]) / (upper[0] - lower[0]), 0), 1)
            blend = blend ** 3 * (blend * (blend * 6 - 15) + 10)
            return lower[1] + (upper[1] - lower[1]) * blend
    return sections[-1][1]


def refine_chest(asset, variants):
    points = [Vector(point) for point in asset["vertices"]]
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    selected = {offset for offset, face in enumerate(faces)
                if all(1.23 < points[index].y < 1.60 and abs(points[index].x) < 0.17
                       and points[index].z > 0 and asset["armWeights"][index] < 0.15 for index in face)}
    edges = {}
    for offset in selected:
        face = faces[offset]
        for first, second in zip(face, face[1:] + face[:1]):
            key = tuple(sorted((first, second)))
            edges[key] = edges.get(key, 0) + 1
    boundary_edges = [edge for edge, count in edges.items() if count == 1]
    adjacent = {}
    for first, second in boundary_edges:
        adjacent.setdefault(first, []).append(second)
        adjacent.setdefault(second, []).append(first)
    assert all(len(neighbors) == 2 for neighbors in adjacent.values()), "invalid chest boundary"
    boundary = [min(adjacent)]
    previous = None
    while True:
        following = next(index for index in adjacent[boundary[-1]] if index != previous)
        if following == boundary[0]:
            break
        previous = boundary[-1]
        boundary.append(following)
    assert len(boundary) == len(adjacent), "multiple chest boundary loops"
    outline = [Vector((points[index].x, points[index].y)) for index in boundary]
    if sum(first.x * second.y - second.x * first.y for first, second in zip(outline, outline[1:] + outline[:1])) < 0:
        boundary.reverse()
        outline.reverse()

    def inside(point):
        crossings = 0
        for first, second in zip(outline, outline[1:] + outline[:1]):
            if (first.y > point.y) != (second.y > point.y):
                crossing = first.x + (point.y - first.y) * (second.x - first.x) / (second.y - first.y)
                crossings += point.x < crossing
        return crossings % 2 == 1

    samples = list(outline)
    spacing = 0.0045
    for row in range(84):
        for column in range(77):
            sample = Vector((-0.171 + column * spacing, 1.225 + row * spacing))
            if inside(sample) and min((sample - point).length for point in outline) > spacing * 0.4:
                samples.append(sample)
    constraints = [(index, (index + 1) % len(boundary)) for index in range(len(boundary))]
    coordinates, cdt_edges, patch_faces, origins, original_edges, original_faces = delaunay_2d_cdt(
        samples, constraints, [list(range(len(boundary)))], 1, 1e-7, True)
    tree = BVHTree.FromPolygons(points, [faces[offset] for offset in sorted(selected)], all_triangles=True)
    selected_faces = [faces[offset] for offset in sorted(selected)]
    retained = [offset for offset in range(len(faces)) if offset not in selected]
    used = sorted({index for offset in retained for index in faces[offset]})
    mapping = {index: output for output, index in enumerate(used)}
    transfers = [([index], [1.0]) for index in used]
    result_points = [points[index] for index in used]
    wall_sections = chest_wall_sections(points)
    patch_mapping = []
    for point, original in zip(coordinates, origins):
        border = next((index for index in original if index < len(boundary)), None)
        if border is not None:
            patch_mapping.append(mapping[boundary[border]])
            continue
        nearest, normal, face_index, distance = tree.find_nearest(Vector((point.x, point.y, 0.08)))
        corners = selected_faces[face_index]
        first, second, third = (points[index] for index in corners)
        horizontal, vertical, offset = second - first, third - first, nearest - first
        denominator = horizontal.dot(horizontal) * vertical.dot(vertical) - horizontal.dot(vertical) ** 2
        second_weight = (vertical.dot(vertical) * offset.dot(horizontal) - horizontal.dot(vertical) * offset.dot(vertical)) / denominator
        third_weight = (horizontal.dot(horizontal) * offset.dot(vertical) - horizontal.dot(vertical) * offset.dot(horizontal)) / denominator
        weights = [max(1 - second_weight - third_weight, 0), max(second_weight, 0), max(third_weight, 0)]
        weights = [weight / sum(weights) for weight in weights]
        patch_mapping.append(len(result_points))
        edge_distance = min((point - (first + (second - first) * min(max((point - first).dot(second - first)
                    / max((second - first).length_squared, 1e-12), 0), 1))).length
                    for first, second in zip(outline, outline[1:] + outline[:1]))
        blend = min(edge_distance / 0.025, 1)
        blend = blend * blend * (3 - 2 * blend)
        wall = chest_wall_depth(point.y, wall_sections) - 0.055 * (point.x / 0.16) ** 2
        result_points.append(Vector((point.x, point.y, nearest.z + (wall - nearest.z) * blend)))
        transfers.append((corners, weights))
    result_faces = [[mapping[index] for index in faces[offset]] for offset in retained]
    result_faces.extend([[patch_mapping[index] for index in face] for face in patch_faces])
    result = {**asset, "vertices": [[round(value, 7) for value in point] for point in result_points],
              "indices": [index for face in result_faces for index in face],
              "regions": [asset["regions"][offset] for offset in retained] + [0] * len(patch_faces),
              "armWeights": [round(sum(asset["armWeights"][index] * weight for index, weight in zip(indices, weights)), 7)
                             for indices, weights in transfers], "chestDetailVersion": 2}
    anatomy = {**asset["anatomy"], "parts": {}, "landmarks": {}}
    for family in ("parts", "landmarks"):
        values = {}
        for name, binding in asset["anatomy"][family].items():
            source_weights = dict(zip(binding["indices"], binding["weights"]))
            values[name] = [sum(source_weights.get(index, 0) * weight for index, weight in zip(indices, weights))
                            for indices, weights in transfers]
        for name, weights in values.items():
            normalizers = [sum(part[index] for part in values.values()) for index in range(len(transfers))] if family == "parts" else [sum(weights)] * len(transfers)
            pairs = [(index, round(weight / normalizers[index], 8)) for index, weight in enumerate(weights)
                     if weight > 1e-8 and normalizers[index] > 0]
            anatomy[family][name] = {"indices": [index for index, weight in pairs], "weights": [weight for index, weight in pairs]}
    result["anatomy"] = anatomy
    refined_variants = {
        name: [point + sum(((positions[index] - points[index]) * weight for index, weight in zip(indices, weights)), Vector())
               for point, (indices, weights) in zip(result_points, transfers)]
        for name, positions in variants.items()
    }
    edge_counts = {}
    for face in result_faces:
        for first, second in zip(face, face[1:] + face[:1]):
            key = tuple(sorted((first, second)))
            edge_counts[key] = edge_counts.get(key, 0) + 1
    assert all(count == 2 for count in edge_counts.values()), "chest refinement opened the surface"
    refined_variants = {name: stabilize_positions(result, positions) for name, positions in refined_variants.items()}
    print(f"CHEST DETAIL: vertices={len(points)}->{len(result_points)} triangles={len(result_faces)}")
    return result, refined_variants


def breast_positions(asset):
    points = [Vector(point) for point in asset["vertices"]]
    center_x = asset["landmarks"]["shoulderWidth"] * 0.21
    center_y = asset["landmarks"]["chestHeight"]

    def smoothstep(value):
        value = min(max(value, 0), 1)
        return value ** 3 * (value * (value * 6 - 15) + 10)

    def surface_mask(point):
        lateral = smoothstep((0.18 - abs(point.x)) / 0.045)
        lower = smoothstep((point.y - (center_y - 0.25)) / 0.070)
        upper = smoothstep(((center_y + 0.225) - point.y) / 0.085)
        front = smoothstep((point.z + 0.025) / 0.055)
        return lateral * lower * upper * front

    wall_sections = chest_wall_sections(points)

    masks = [surface_mask(point) * smoothstep((0.4 - arm_weight) / 0.3)
             for point, arm_weight in zip(points, asset["armWeights"])]
    relaxed = relax_breast_surface(asset, points, masks, 55)
    variants = {}
    parameters = (("small", 0.040, 0.072, 0.125, 0.075),
                  ("neutral", 0.056, 0.078, 0.135, 0.087),
                  ("large", 0.074, 0.085, 0.148, 0.098))
    for name, projection, width, upper_height, lower_height in parameters:
        target_points = []
        columns, rows = 160, 180
        for row in range(rows + 1):
            vertical = center_y - 0.24 + row / rows * 0.51
            for column in range(columns + 1):
                horizontal = -0.26 + column / columns * 0.52
                chest = chest_wall_depth(vertical, wall_sections) - 0.055 * (horizontal / 0.16) ** 2
                center_height = center_y - 0.012 - (projection - 0.045) * 0.12
                height = upper_height if vertical >= center_height else lower_height
                vertical_distance = abs((vertical - center_height) / height)
                breast = 0
                for side in (-1, 1):
                    lateral = horizontal - side * center_x
                    root_width = width * (1.10 if lateral * side > 0 else 0.95)
                    lateral_distance = abs(lateral / root_width)
                    profile = max(1 - lateral_distance ** 2 - vertical_distance ** 2, 0)
                    breast += projection * profile ** (1.8 if vertical >= center_height else 0.5)
                target_points.append((horizontal, vertical, chest + breast))
        target_faces = []
        for row in range(rows):
            for column in range(columns):
                first = row * (columns + 1) + column
                target_faces.append((first, first + 1, first + columns + 2, first + columns + 1))
        target_mesh = create_mesh(f"BreastGuide_{name}", target_points, target_faces)
        target = bpy.data.objects.new(f"BreastGuide_{name}", target_mesh)
        bpy.context.collection.objects.link(target)
        shaped = project_breast_surface(asset, relaxed, masks, target)
        variants[name] = relax_breast_surface(asset, shaped, masks, 10)
        bpy.data.objects.remove(target, do_unlink=True)
        bpy.data.meshes.remove(target_mesh)
    return variants


def project_breast_surface(asset, points, masks, target):
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    mesh = create_mesh("BreastRetainedTopology", points, faces)
    model = bpy.data.objects.new("BreastRetainedTopology", mesh)
    bpy.context.collection.objects.link(model)
    group = model.vertex_groups.new(name="ChestTransition")
    for index, weight in enumerate(masks):
        if weight > 0:
            group.add([index], weight, "REPLACE")
    modifier = model.modifiers.new("Fit anatomical breast guide", "SHRINKWRAP")
    modifier.target = target
    modifier.wrap_method = "PROJECT"
    modifier.use_project_x = False
    modifier.use_project_y = True
    modifier.use_project_z = False
    modifier.use_positive_direction = True
    modifier.use_negative_direction = True
    modifier.vertex_group = group.name
    evaluated = model.evaluated_get(bpy.context.evaluated_depsgraph_get())
    projected_mesh = evaluated.to_mesh()
    projected = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in projected_mesh.vertices]
    evaluated.to_mesh_clear()
    bpy.data.objects.remove(model, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    return projected


def relax_breast_surface(asset, points, masks, iterations):
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    mesh = create_mesh("BreastAuthoringSurface", points, faces)
    model = bpy.data.objects.new("BreastAuthoringSurface", mesh)
    bpy.context.collection.objects.link(model)
    group = model.vertex_groups.new(name="BreastSurface")
    for index, weight in enumerate(masks):
        if weight > 0:
            group.add([index], weight, "REPLACE")
    modifier = model.modifiers.new("Relax embedded surface ridges", "SMOOTH")
    modifier.factor = 0.7
    modifier.iterations = iterations
    modifier.use_x = True
    modifier.use_y = True
    modifier.use_z = True
    modifier.vertex_group = group.name
    evaluated = model.evaluated_get(bpy.context.evaluated_depsgraph_get())
    relaxed_mesh = evaluated.to_mesh()
    relaxed = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in relaxed_mesh.vertices]
    evaluated.to_mesh_clear()
    bpy.data.objects.remove(model, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    return relaxed


def validate_breasts(asset, variants):
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    corners = [set(face) for face in faces]

    def intersections(points):
        tree = BVHTree.FromPolygons(points, faces, all_triangles=True)
        return {(first, second) for first, second in tree.overlap(tree)
                if first < second and corners[first].isdisjoint(corners[second])}

    original_intersections = intersections(asset["vertices"])
    checks = {}
    for name in ("small", "large"):
        for step in (0.25, 0.5, 0.75, 1):
            checks[f"breast_{name}_{step}"] = [
                base.lerp(target, step) for base, target in zip(variants["neutral"], variants[name])
            ]
    checks["breast_neutral"] = variants["neutral"]
    validate(asset, checks, preserve_height=False, reference=variants["neutral"], front_orientation=True)
    for name, points in checks.items():
        added = intersections(points) - original_intersections
        assert not added, (name, "new self intersections", len(added))
    print(f"BREASTS: interpolation checks={len(checks)} new_self_intersections=0")


def blender_point(point):
    return (point[0], -point[2], point[1])


def create_mesh(name, points, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([blender_point(point) for point in points], [], faces)
    mesh.update()
    for face in mesh.polygons:
        face.use_smooth = True
    return mesh


def make_scene(asset, variants):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
    material = bpy.data.materials.new("Neutral clay")
    material.diffuse_color = (0.56, 0.60, 0.59, 1)
    label_material = bpy.data.materials.new("Labels")
    label_material.diffuse_color = (0.04, 0.04, 0.04, 1)
    body = bpy.data.objects.new("FemaleBodyFrames", create_mesh("FemaleBase", asset["vertices"], faces))
    bpy.context.collection.objects.link(body)
    body.data.materials.append(material)
    body.shape_key_add(name="Basis")
    for name, points in variants.items():
        shape = body.shape_key_add(name=name)
        for vertex, point in zip(shape.data, points):
            vertex.co = blender_point(point)
    body.hide_render = True
    preview = bpy.data.collections.new("Comparison")
    bpy.context.scene.collection.children.link(preview)
    for column, (name, points) in enumerate({"neutral": asset["vertices"], **variants}.items()):
        mesh = create_mesh(name, points, faces)
        mesh.materials.append(material)
        for row, angle in enumerate((0, math.pi / 2, math.pi)):
            model = bpy.data.objects.new(f"{name}_{row}", mesh)
            preview.objects.link(model)
            model.location = (column * 1.1, 0, (2 - row) * 2.15)
            model.rotation_euler.z = angle
            text = bpy.data.curves.new(f"{name}_label_{row}", "FONT")
            text.body = f"{name.upper()} / {('FRONT', 'SIDE', 'BACK')[row]}"
            text.size = 0.065
            text.materials.append(label_material)
            label = bpy.data.objects.new(text.name, text)
            preview.objects.link(label)
            label.location = (column * 1.1 - 0.40, 0, (2 - row) * 2.15 + 1.98)
            label.rotation_euler.x = math.pi / 2
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (0.92, 0.92, 0.92)
    scene.render.resolution_x = 2000
    scene.render.resolution_y = 2700
    scene.render.resolution_percentage = 100
    bpy.ops.object.camera_add(location=(1.65, -12, 3.18))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((1.65, 0, 3.18)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 6.65
    scene.camera = camera
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    preview.hide_viewport = True
    body.hide_set(False)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)


def render_breasts(asset, variants):
    scene = bpy.context.scene
    for model in scene.objects:
        if model.type in {"MESH", "FONT"}:
            model.hide_render = True
    previous = bpy.data.collections.get("BreastComparison")
    if previous:
        for model in list(previous.objects):
            bpy.data.objects.remove(model, do_unlink=True)
        bpy.data.collections.remove(previous)
    preview = bpy.data.collections.new("BreastComparison")
    scene.collection.children.link(preview)
    faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)
             if all(1.16 <= asset["vertices"][index][1] <= 1.67 for index in asset["indices"][offset:offset + 3])]
    material = bpy.data.materials.get("Neutral clay")
    label_material = bpy.data.materials.get("Labels")
    for column, (name, points) in enumerate({"source": asset["vertices"], **{name: variants[name] for name in BREAST_KEYS}}.items()):
        mesh = create_mesh(f"breast_{name}", points, faces)
        mesh.materials.append(material)
        for row, angle in enumerate((0, math.pi / 4, math.pi / 2)):
            model = bpy.data.objects.new(f"breast_{name}_{row}", mesh)
            preview.objects.link(model)
            model.location = (column * 0.65, 0, (2 - row) * 0.66)
            model.rotation_euler.z = angle
            text = bpy.data.curves.new(f"breast_{name}_label_{row}", "FONT")
            text.body = f"{name.upper()} / {('FRONT', 'THREE QUARTER', 'SIDE')[row]}"
            text.size = 0.028
            text.materials.append(label_material)
            label = bpy.data.objects.new(text.name, text)
            preview.objects.link(label)
            label.location = (column * 0.65 - 0.23, -0.3, (2 - row) * 0.66 + 1.72)
            label.rotation_euler.x = math.pi / 2
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.studiolight_rotate_z = 0.4
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = False
    scene.display.shading.show_shadows = False
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (0.92, 0.92, 0.92)
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 2100
    scene.render.resolution_percentage = 100
    camera = scene.camera
    camera.location = (0.975, -12, 2.08)
    camera.rotation_euler = (Vector((0.975, 0, 2.08)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.65
    scene.render.filepath = str(BREAST_PREVIEW)
    bpy.ops.render.render(write_still=True)
    preview.hide_viewport = True
    body = bpy.data.objects["FemaleBodyFrames"]
    bpy.context.view_layer.objects.active = body
    for model in bpy.context.selected_objects:
        model.select_set(False)
    body.select_set(True)
    body.hide_set(False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-existing", action="store_true")
    parser.add_argument("--breasts", action="store_true")
    parser.add_argument("--rebuild-breasts", action="store_true")
    parser.add_argument("--refine-chest", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    bpy.context.preferences.filepaths.save_version = 0
    source_bytes = SOURCE.read_bytes()
    asset = json.loads(source_bytes)
    if asset.get("authoring") in ("female-mannequin-v2", "female-from-male-v1"):
        raise RuntimeError("Use this mesh's source importer; the legacy body-frame authoring path is disabled.")
    ratios = reference_ratios()
    existing = arguments.export_existing or arguments.breasts or arguments.rebuild_breasts or arguments.refine_chest
    if existing:
        bpy.ops.wm.open_mainfile(filepath=str(BLEND))
        body = bpy.data.objects["FemaleBodyFrames"]
        assert len(body.data.vertices) == len(asset["vertices"])
        assert [index for face in body.data.polygons for index in face.vertices] == asset["indices"]
        variants = {
            name: [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in body.data.shape_keys.key_blocks[name].data]
            for name in PRESETS
        }
    else:
        variants = {name: frame_positions(asset, factors, ratios[name]) for name, factors in PRESETS.items()}
    if arguments.refine_chest and asset.get("chestDetailVersion", 0) < 2:
        asset, variants = refine_chest(asset, variants)
        source_bytes = (json.dumps(asset, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
        previous_mesh = body.data
        faces = [asset["indices"][offset:offset + 3] for offset in range(0, len(asset["indices"]), 3)]
        body.data = create_mesh("FemaleBaseDetailed", asset["vertices"], faces)
        body.data.materials.append(bpy.data.materials["Neutral clay"])
        body.shape_key_add(name="Basis")
        for name, points in variants.items():
            shape = body.shape_key_add(name=name)
            for vertex, point in zip(shape.data, points):
                vertex.co = blender_point(point)
        if previous_mesh.users == 0:
            bpy.data.meshes.remove(previous_mesh)
    validate(asset, variants)
    if not existing:
        make_scene(asset, variants)
    body = bpy.data.objects["FemaleBodyFrames"]
    keys = body.data.shape_keys.key_blocks
    if arguments.rebuild_breasts or arguments.refine_chest or any(f"breast_{name}" not in keys for name in BREAST_KEYS):
        for name, points in breast_positions(asset).items():
            shape = keys.get(f"breast_{name}") or body.shape_key_add(name=f"breast_{name}")
            for vertex, point in zip(shape.data, points):
                vertex.co = blender_point(point)
    breasts = {
        name: [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in keys[f"breast_{name}"].data]
        for name in BREAST_KEYS
    }
    validate_breasts(asset, breasts)
    totals = [0.0] * len(asset["vertices"])
    for binding in asset["anatomy"]["parts"].values():
        assert binding["indices"] == sorted(set(binding["indices"]))
        for index, weight in zip(binding["indices"], binding["weights"]):
            totals[index] += weight
    assert all(abs(total - 1) < 0.001 for total in totals), "invalid part weights"
    assert all(abs(sum(binding["weights"]) - 1) < 0.001 for binding in asset["anatomy"]["landmarks"].values())
    output = {
        "version": 1,
        "sourceSHA256": hashlib.sha256(source_bytes).hexdigest(),
        "vertexCount": len(asset["vertices"]),
        "referenceRatios": ratios,
        "presets": {
            name: [[round(value - original, 7) for value, original in zip(point, source)]
                   for point, source in zip(points, asset["vertices"])]
            for name, points in variants.items()
        },
        "breastPresets": {
            name: [[round(value - original, 7) for value, original in zip(point, source)]
                   for point, source in zip(points, asset["vertices"])]
            for name, points in breasts.items()
        },
    }
    if arguments.refine_chest:
        SOURCE.write_bytes(source_bytes)
    OUTPUT.write_text(json.dumps(output, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
    print(f"EXPORTED {OUTPUT}")
    if not arguments.export_existing or arguments.breasts:
        render_breasts(asset, breasts)
    for shape in keys:
        shape.value = 0
    keys["breast_neutral"].value = 1
    for name in ("small", "large"):
        keys[f"breast_{name}"].relative_key = keys["breast_neutral"]
    body.active_shape_key_index = list(keys).index(keys["breast_neutral"])
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)


if __name__ == "__main__":
    main()