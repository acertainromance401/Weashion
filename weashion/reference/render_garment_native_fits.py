import argparse
from array import array
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


RESOURCES = [
    "meshy_long_sleeve",
    "meshy_hoodie",
    "meshy_dress_pants",
    "meshy_jeans",
    "meshy_bomber",
    "meshy_sneakers",
]
TITLES = ["Long sleeve", "Hoodie", "Dress pants", "Jeans", "Bomber", "Sneakers"]


def material(name, color):
    result = bpy.data.materials.new(name)
    linear = tuple(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in color)
    result.diffuse_color = (*linear, 1)
    result.use_nodes = True
    shader = next(node for node in result.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*linear, 1)
    shader.inputs["Roughness"].default_value = 0.88
    return result


def geometry(path, name, appearance, elevation=0):
    data = json.loads(path.read_text())
    points = [(x, -z, y + elevation) for x, y, z in data["vertices"]]
    indices = data["indices"]
    faces = [indices[index:index + 3] for index in range(0, len(indices), 3)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(appearance)
    for face in mesh.polygons:
        face.use_smooth = True
    return obj


def light(location, power, size):
    data = bpy.data.lights.new("Softbox", "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new("Softbox", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat("-Z", "Y").to_euler()


def text(label, location, camera, scale):
    data = bpy.data.curves.new("Caption", "FONT")
    data.body = label
    data.align_x = "CENTER"
    data.align_y = "CENTER"
    data.size = scale
    obj = bpy.data.objects.new("Caption", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = camera.rotation_euler
    obj.data.materials.append(material("Caption ink", (0.09, 0.10, 0.11)))


def render(entry, capture, output, color, back):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 520
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("Comparison world")
    scene.world.color = (0.82, 0.82, 0.82)
    scene.world.use_nodes = True
    background = next(node for node in scene.world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.86, 0.87, 0.86, 1)
    background.inputs["Strength"].default_value = 0.7
    scene.view_settings.view_transform = "AgX"
    body = material("Native body", (0.84, 0.84, 0.84))
    garment = material("Native garment", color)
    geometry(capture / f"{entry['body']}-body.json", "Native body", body, entry["bodyElevation"])
    geometry(capture / entry["file"], "Native fitted display surface", garment)
    resource = entry["resource"]
    if resource == "meshy_sneakers":
        level, span = 0.15, 0.62
    elif resource in ("meshy_dress_pants", "meshy_jeans"):
        level, span = 0.56, 1.42
    else:
        level, span = 1.18, 1.60
    camera_data = bpy.data.cameras.new("Comparison camera")
    camera = bpy.data.objects.new("Comparison camera", camera_data)
    bpy.context.collection.objects.link(camera)
    direction = -1 if back else 1
    camera.location = (direction * 1.9, direction * -5.8, level + 0.35)
    target = Vector((0, 0, level))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = span
    scene.camera = camera
    light((2, -4, 5), 650, 5)
    light((-3, 2, 4), 450, 4)
    view = "back" if back else "front"
    label = f"{entry['size']} / {entry['body']} / {view}"
    unit, factor = ("mm", 1000) if resource == "meshy_sneakers" else ("cm", 100)
    label += f"\nease {entry['ease'] * factor:+.1f} {unit}"
    up = camera.rotation_euler.to_matrix() @ Vector((0, 1, 0))
    caption = camera.location + (target - camera.location).normalized() + up * span * 0.43
    text(label, caption, camera, span * 0.031)
    destination = output / f"{Path(entry['file']).stem}-{view}.png"
    scene.render.filepath = str(destination)
    bpy.ops.render.render(write_still=True)
    return destination


def atlas(paths, output, columns):
    images = [bpy.data.images.load(str(path), check_existing=False) for path in paths]
    width, height = images[0].size
    rows = (len(images) + columns - 1) // columns
    total_width, total_height = width * columns, height * rows
    pixels = array("f", [0.94, 0.94, 0.93, 1]) * (total_width * total_height)
    for index, image in enumerate(images):
        source = array("f", [0]) * (width * height * 4)
        image.pixels.foreach_get(source)
        x = index % columns
        y = rows - 1 - index // columns
        for row in range(height):
            start = ((y * height + row) * total_width + x * width) * 4
            pixels[start:start + width * 4] = source[row * width * 4:(row + 1) * width * 4]
    result = bpy.data.images.new("Native fit contact sheet", width=total_width, height=total_height)
    result.pixels.foreach_set(pixels)
    result.filepath_raw = str(output)
    result.file_format = "PNG"
    result.save()
    for image in images:
        bpy.data.images.remove(image)
    bpy.data.images.remove(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "garment_validation")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    entries = json.loads((args.capture / "index.json").read_text())
    catalog_path = Path(__file__).parents[1] / "weashion" / "Resources" / "garments.json"
    catalog = json.loads(catalog_path.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    all_fronts = []
    for resource, title in zip(RESOURCES, TITLES):
        cases = [entry for entry in entries if entry["resource"] == resource]
        if not cases:
            raise ValueError(f"No native captures for {resource}")
        appearance = next(item["appearance"]["color"] for item in catalog if item["pattern"]["meshResource"] == resource)
        fronts = [render(entry, args.capture, args.output, appearance, False) for entry in cases]
        backs = [render(entry, args.capture, args.output, appearance, True) for entry in cases]
        atlas(fronts + backs, args.output / f"{resource}_native_fits.png", len(cases))
        all_fronts.extend(fronts)
        print(f"NATIVE_FIT_RENDER {title}: {len(cases)} cases, front/back", flush=True)
    atlas(all_fronts, args.output / "six_garments_native_fits.png", len(all_fronts) // len(RESOURCES))
    (args.output / "fit_metrics.json").write_text(json.dumps(entries, indent=2) + "\n")


if __name__ == "__main__":
    main()
