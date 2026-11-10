import bpy
import json
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parent
FILES = {
    "long_sleeve": "Gray Long Sleeve Shirt_Meshy_AI_2026-10-28_95f43f.blend",
    "hoodie": "Grey Hoodie_Meshy_AI_2026-10-28_c679f7.blend",
    "dress_pants": "Gray Dress Pants Front and Back_Meshy_AI_2026-10-28_ac302b.blend",
    "jeans": "Blue Jeans on Black_Meshy_AI_2026-10-28_f1bc1c.blend",
    "bomber": "Olive Bomber Jacket_Meshy_AI_2026-10-28_fd0508.blend",
    "sneakers": "White Sneakers on Black Background_Meshy_AI_2026-10-28_4c0a02.blend",
}

result = {}
for name, filename in FILES.items():
    bpy.ops.wm.open_mainfile(filepath=str(Path("/Users/acertainromance401/Desktop/Meshy Models") / filename))
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    vertices = [obj.matrix_world @ v.co for v in obj.data.vertices]
    faces = [list(p.vertices) for p in obj.data.polygons]
    tree = BVHTree.FromPolygons(vertices, faces)
    samples = []
    for z in [-.9, -.7, -.5, -.3, -.1, .1, .3, .5, .7, .9]:
        for x in [0, .15, .3, .5, .7, .9]:
            origin = Vector((x, -2, z))
            hits = []
            for _ in range(12):
                hit, normal, face, distance = tree.ray_cast(origin, Vector((0, 1, 0)), 4)
                if hit is None:
                    break
                hits.append([round(hit.y, 5), round(normal.y, 3)])
                origin = hit + Vector((0, .0001, 0))
            if hits:
                samples.append({"x": x, "height": z, "depthHitsNormal": hits})
    result[name] = samples
(ROOT / "source_sections.json").write_text(json.dumps(result, indent=2))
