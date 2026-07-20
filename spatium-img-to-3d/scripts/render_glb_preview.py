import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    input_path = Path(args[0]).resolve()
    output_path = Path(args[1]).resolve()

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()

    bpy.ops.import_scene.gltf(filepath=str(input_path))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not objects:
        raise RuntimeError(f"No mesh objects found in {input_path}")

    center, radius = scene_bounds(objects)
    for obj in objects:
        obj.location -= center

    bpy.ops.object.light_add(type="AREA", location=(0, -3, 5))
    light = bpy.context.object
    light.name = "Preview key light"
    light.data.energy = 450
    light.data.size = 5

    bpy.ops.object.camera_add(location=(0, -radius * 3.0, radius * 1.3), rotation=(1.2, 0, 0))
    camera = bpy.context.object
    bpy.context.scene.camera = camera
    look_at(camera, Vector((0, 0, 0)))

    bpy.context.scene.render.engine = "BLENDER_EEVEE"
    bpy.context.scene.render.resolution_x = 1200
    bpy.context.scene.render.resolution_y = 900
    bpy.context.scene.render.film_transparent = False
    bpy.context.scene.world.color = (0.94, 0.94, 0.92)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(output_path)
    bpy.ops.render.render(write_still=True)


def scene_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, float]:
    corners: list[Vector] = []
    for obj in objects:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)

    min_corner = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    max_corner = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (min_corner + max_corner) / 2
    radius = max((corner - center).length for corner in corners)
    return center, max(radius, 1.0)


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


if __name__ == "__main__":
    main()
