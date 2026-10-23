"""Green screen behind the MetaHuman, aimed at the current editor camera.

Run inside Unreal Editor: bottom console, switch Cmd -> Python is not needed, just type
    py "C:/AI/claude/metahuman/greenscreen.py"
Re-run any time you move the camera: the old wall is replaced.
"""
import math
import unreal

MAT_DIR, MAT_NAME = "/Game", "M_Green"
MAT_PATH = f"{MAT_DIR}/{MAT_NAME}"
LABEL = "GreenScreen"
DIST_BEHIND = 200.0   # cm behind the character
SCALE = 30.0          # plane is 1 m, so 30 m wide

eal = unreal.EditorAssetLibrary
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

# 1. Unlit pure-green two-sided material
if eal.does_asset_exist(MAT_PATH):
    mat = eal.load_asset(MAT_PATH)
else:
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    mat = tools.create_asset(MAT_NAME, MAT_DIR, unreal.Material, unreal.MaterialFactoryNew())
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("two_sided", True)
    mel = unreal.MaterialEditingLibrary
    c = mel.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, -300, 0)
    c.set_editor_property("constant", unreal.LinearColor(0.0, 1.0, 0.0, 1.0))
    mel.connect_material_property(c, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    mel.recompile_material(mat)
    eal.save_asset(MAT_PATH)
    unreal.log("GreenScreen: material created")

# 2. Find the MetaHuman and the editor camera
all_actors = actors.get_all_level_actors()
for a in all_actors:
    if a.get_actor_label() == LABEL:
        actors.destroy_actor(a)

mh = [a for a in all_actors if a.get_actor_label().startswith("BP_") and "MHC" in a.get_actor_label()]
if not mh:
    mh = [a for a in all_actors if "Natasha" in a.get_actor_label()]
if not mh:
    raise RuntimeError("GreenScreen: MetaHuman Blueprint (BP_MHC_...) not found in the level")
char = mh[0]

cam = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_level_viewport_camera_info()
if not cam:
    raise RuntimeError("GreenScreen: could not read the editor camera")
cam_loc = cam[-2]

char_loc = char.get_actor_location()
dx, dy = char_loc.x - cam_loc.x, char_loc.y - cam_loc.y
length = math.hypot(dx, dy) or 1.0
dx, dy = dx / length, dy / length

# 3. Plane behind the character, facing the camera
pos = unreal.Vector(char_loc.x + dx * DIST_BEHIND, char_loc.y + dy * DIST_BEHIND, cam_loc.z)
yaw = math.degrees(math.atan2(dy, dx))
rot = unreal.Rotator(roll=0.0, pitch=90.0, yaw=yaw)

plane_mesh = unreal.load_asset("/Engine/BasicShapes/Plane")
wall = actors.spawn_actor_from_object(plane_mesh, pos, rot)
wall.set_actor_label(LABEL)
wall.set_actor_scale3d(unreal.Vector(SCALE, SCALE, 1.0))
comp = wall.static_mesh_component
comp.set_material(0, mat)
comp.set_editor_property("cast_shadow", False)

unreal.log(f"GreenScreen: wall placed behind {char.get_actor_label()}")
print("GreenScreen OK")
