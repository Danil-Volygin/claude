"""Deep-Live-Cam pipeline check without the GUI.

Runs every step of a live face swap on one webcam frame and says which step fails:
  1. GPU providers  2. source photo face  3. webcam frame face  4. swap model  5. swap itself
Saves before/after images to the Desktop.

Run (close Deep-Live-Cam first, it holds the webcam):
  C:\\AI\\claude\\deep-live-cam\\Deep-Live-Cam\\venv\\Scripts\\python.exe C:\\AI\\claude\\deep-live-cam\\diag.py [photo] [camera_index]
"""
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "Deep-Live-Cam")
os.chdir(APP)
sys.path.insert(0, APP)

# Same CUDA DLL registration as Deep-Live-Cam's run.py
if sys.platform == "win32":
    sp = os.path.join(APP, "venv", "Lib", "site-packages")
    dirs = [os.path.join(sp, "torch", "lib")]
    nv = os.path.join(sp, "nvidia")
    if os.path.isdir(nv):
        dirs += [os.path.join(nv, p, "bin") for p in os.listdir(nv)]
    for d in dirs:
        if os.path.isdir(d):
            os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]
            try:
                os.add_dll_directory(d)
            except OSError:
                pass

DESKTOP = os.path.join(os.path.expanduser("~"), "Desktop")


def ok(msg):
    print(f"[ OK ] {msg}")


def bad(msg):
    print(f"[FAIL] {msg}")
    sys.exit(1)


def step(n, msg):
    print(f"\n--- Step {n}: {msg}")


try:
    import torch  # noqa: F401  (loads CUDA DLLs before onnxruntime, like the app does)
except ImportError:
    pass
import numpy as np
import cv2
import onnxruntime as ort

import modules.globals as g

g.execution_providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
g.frame_processors = ["face_swapper"]

step(1, "GPU providers")
print("onnxruntime", ort.__version__, ort.get_available_providers())
if "CUDAExecutionProvider" not in ort.get_available_providers():
    bad("CUDA provider missing, swap would run on CPU")
ok("CUDA provider available")

step(2, "face on the source photo")
src_path = sys.argv[1] if len(sys.argv) > 1 else None
if not src_path:
    try:
        import tkinter
        from tkinter import filedialog
        root = tkinter.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        src_path = filedialog.askopenfilename(
            title="Pick the same face photo you use in Deep-Live-Cam",
            filetypes=[("Images", "*.jpg *.jpeg *.png *.webp *.bmp"), ("All", "*.*")],
        )
        root.destroy()
    except Exception as e:
        bad(f"could not open file dialog ({e}); pass the photo path as the first argument")
if not src_path:
    bad("no photo selected")
print("photo:", src_path)

from modules import imread_unicode
from modules.face_analyser import get_one_face, detect_one_face_fast

src = imread_unicode(src_path)
if src is None:
    bad("could not read the photo. Try saving it as .jpg with a short English file name")
print("photo size:", src.shape[1], "x", src.shape[0])
try:
    src_face = get_one_face(src)
except Exception:
    traceback.print_exc()
    bad("face analyser crashed on the photo")
if src_face is None:
    bad("NO FACE found on the photo. Use a sharp frontal photo where the face is large")
emb = getattr(src_face, "normed_embedding", None)
if emb is None:
    bad("face found but no identity embedding (recognition model failed)")
ok(f"face found, score {float(src_face.det_score):.2f}, embedding {emb.shape}")

step(3, "face on a webcam frame")
cam_index = int(sys.argv[2]) if len(sys.argv) > 2 else 0
cap = cv2.VideoCapture(cam_index, cv2.CAP_DSHOW)
if not cap.isOpened():
    bad(f"camera {cam_index} did not open. Close Deep-Live-Cam, Discord, Zoom, Camo and try again")
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
frame = None
for _ in range(30):  # let auto-exposure settle
    r, f = cap.read()
    if r:
        frame = f
cap.release()
if frame is None:
    bad("camera opened but returned no frames")
if frame.mean() < 5:
    bad("camera frame is black. Wrong camera index or the lens is covered")
before = os.path.join(DESKTOP, "dlc_before.jpg")
cv2.imwrite(before, frame)
print("frame:", frame.shape[1], "x", frame.shape[0], "saved to", before)
tgt_face = detect_one_face_fast(frame)
if tgt_face is None:
    bad("NO FACE found on the webcam frame. Face the camera, add light in front of you")
ok(f"face found, score {float(tgt_face.det_score):.2f}")

step(4, "swap model")
from modules.processors.frame import face_swapper as fs

try:
    swapper = fs.get_face_swapper()
except Exception:
    traceback.print_exc()
    bad("swap model crashed while loading")
if swapper is None:
    bad("swap model did not load, see messages above")
print("model:", getattr(swapper, "model_file", "?"))
print("session providers:", swapper.session.get_providers() if hasattr(swapper.session, "get_providers") else type(swapper.session).__name__)
print("CUDA graph session:", bool(fs._cuda_graph_session.get("recorded")))
ok("swap model loaded")

step(5, "swap")
work = frame.copy()
try:
    out = fs.swap_face(src_face, tgt_face, work)
except Exception:
    traceback.print_exc()
    bad("swap crashed")
after = os.path.join(DESKTOP, "dlc_after.jpg")
cv2.imwrite(after, out)
x1, y1, x2, y2 = [int(v) for v in tgt_face.bbox]
h, w = frame.shape[:2]
x1, y1, x2, y2 = max(0, x1), max(0, y1), min(w, x2), min(h, y2)
diff = float(np.abs(out[y1:y2, x1:x2].astype(np.int16) - frame[y1:y2, x1:x2].astype(np.int16)).mean())
print("saved to", after)
print(f"average pixel change inside the face box: {diff:.1f} (0 = nothing changed)")
if diff < 1.0:
    bad("swap ran but the face did not change. Look for 'Error during face swap' lines above")
ok("swap works. Open dlc_before.jpg and dlc_after.jpg on the Desktop and compare")
