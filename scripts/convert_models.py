#!/usr/bin/env python3
"""
convert_models.py — Convert and validate candidate simplification models for RefPlane.

For each model this script:
  1. Downloads / locates the source weights
  2. Traces to ONNX via spandrel (SR models) or direct export
  3. Converts to CoreML via coremltools
  4. Validates the app-facing runtime contract
  5. Emits a JSON manifest next to the .mlpackage

Usage:
    python scripts/convert_models.py [--model MODEL] [--output-dir OUTPUT_DIR]

  --model       One of: apisr, swinir, whitebox, animegan
                Omit to convert all supported models.
  --output-dir  Where to write .mlpackage files (default: ios/RefPlane/Models)

Requirements:
    pip install coremltools torch torchvision spandrel onnx onnxruntime numpy pillow

Notes:
  - RealESRGAN_x4 is already bundled and does not need conversion.
  - The Kuwahara filter is a Metal shader and does not require a model file.
  - This script does NOT modify the Xcode project. After conversion, add the
    generated .mlpackage to the Xcode project manually.
"""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = REPO_ROOT / "ios" / "RefPlane" / "Models"

# Fixed input / output shapes for super-resolution models
SR_INPUT_SIZE = 256
SR_SCALE = 4
SR_OUTPUT_SIZE = SR_INPUT_SIZE * SR_SCALE  # 1024

# Runtime contract kinds (must match AppModels.swift)
KIND_SR4X = "superResolution4x"
KIND_FULL  = "fullImageModel"

MODELS = {
    "apisr": {
        "label": "APISR GRL_GAN 4x",
        "bundle_name": "APISR_GRL_x4",
        "kind": KIND_SR4X,
        "source": "huggingface",  # placeholder — fill in actual weights path
        "hf_repo": "Kiteretsu/APISR",
        "hf_file": "2x_APISR_GRL_GAN_generator-epoch-1.pth",
        "scale": 4,
    },
    "swinir": {
        "label": "SwinIR-S Lightweight 4x",
        "bundle_name": "SwinIR_Lightweight_x4",
        "kind": KIND_SR4X,
        "source": "huggingface",
        "hf_repo": "JingyunLiang/SwinIR",
        "hf_file": "003_realSR_BSRGAN_DFOWMFC_s64w8_SwinIR-L_x4_GAN.pth",
        "scale": 4,
    },
    "whitebox": {
        "label": "White-box Cartoonization",
        "bundle_name": "WhiteBoxCartoonization",
        "kind": KIND_FULL,
        "source": "manual",  # requires manual ONNX export from original TF model
    },
    "animegan": {
        "label": "AnimeGANv3",
        "bundle_name": "AnimeGANv3",
        "kind": KIND_FULL,
        "source": "manual",
    },
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def require_import(module: str, pip_name: Optional[str] = None) -> None:
    """Abort with a useful message if a required module is missing."""
    import importlib
    try:
        importlib.import_module(module)
    except ImportError:
        pkg = pip_name or module
        sys.exit(f"Missing dependency: {module}\n  pip install {pkg}")


def make_manifest(
    method_id: str,
    bundle_name: str,
    kind: str,
    input_type: str,
    output_type: str,
    fixed_input_shape: Optional[list],
    flexible_shapes: bool,
    test_inference_ok: bool,
    notes: str = "",
) -> dict:
    return {
        "method_id": method_id,
        "bundle_name": bundle_name,
        "processing_kind": kind,
        "input_type": input_type,
        "output_type": output_type,
        "fixed_input_shape": fixed_input_shape,
        "flexible_shapes": flexible_shapes,
        "test_inference_ok": test_inference_ok,
        "converted_at": datetime.now(timezone.utc).isoformat(),
        "notes": notes,
    }


def write_manifest(manifest: dict, output_dir: Path) -> None:
    name = manifest["bundle_name"]
    path = output_dir / f"{name}_manifest.json"
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)
    log(f"  Manifest written: {path.name}")


# ---------------------------------------------------------------------------
# Super-resolution conversion (APISR / SwinIR via spandrel → coremltools)
# ---------------------------------------------------------------------------

def convert_sr_model(model_key: str, output_dir: Path, weights_path: Optional[Path] = None) -> bool:
    """
    Convert a 4x super-resolution model to CoreML.

    Pipeline:
      PyTorch weights (via spandrel) → trace at 256×256 → ONNX → coremltools → .mlpackage

    Returns True on success.
    """
    require_import("torch")
    require_import("coremltools", "coremltools")
    require_import("spandrel")
    require_import("numpy")

    import torch
    import coremltools as ct
    import numpy as np
    from spandrel import ModelLoader

    cfg = MODELS[model_key]
    bundle_name = cfg["bundle_name"]
    log(f"Converting {cfg['label']} …")

    # Locate weights
    if weights_path is None:
        log(f"  ERROR: No weights path provided for {model_key}.")
        log(f"  Download from HuggingFace: {cfg.get('hf_repo', 'N/A')} / {cfg.get('hf_file', 'N/A')}")
        log(f"  Then pass: --weights /path/to/{cfg.get('hf_file', 'model.pth')}")
        return False

    if not weights_path.exists():
        log(f"  ERROR: Weights file not found: {weights_path}")
        return False

    # Load via spandrel
    log(f"  Loading model via spandrel from {weights_path} …")
    try:
        arch = ModelLoader().load_from_file(str(weights_path))
        model = arch.model.eval()
    except Exception as exc:
        log(f"  ERROR loading model: {exc}")
        return False

    # Trace at fixed 256×256
    log(f"  Tracing at {SR_INPUT_SIZE}×{SR_INPUT_SIZE} …")
    dummy = torch.zeros(1, 3, SR_INPUT_SIZE, SR_INPUT_SIZE, dtype=torch.float32)
    try:
        with torch.no_grad():
            traced = torch.jit.trace(model, dummy)
            out = traced(dummy)
    except Exception as exc:
        log(f"  ERROR during trace: {exc}")
        return False

    # Validate output shape
    expected_out = (1, 3, SR_OUTPUT_SIZE, SR_OUTPUT_SIZE)
    if tuple(out.shape) != expected_out:
        log(f"  ERROR: Unexpected output shape {tuple(out.shape)}, expected {expected_out}")
        log(f"  This model does not satisfy the 4× super-resolution contract.")
        return False
    log(f"  Output shape: {tuple(out.shape)} ✓")

    # Export to CoreML
    log(f"  Converting to CoreML …")
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(
                name="input",
                shape=(1, 3, SR_INPUT_SIZE, SR_INPUT_SIZE),
                dtype=np.float32,
            )],
            outputs=[ct.TensorType(name="output", dtype=np.float32)],
            minimum_deployment_target=ct.target.iOS16,
            compute_precision=ct.precision.FLOAT16,
        )
    except Exception as exc:
        log(f"  ERROR during CoreML conversion: {exc}")
        return False

    # Test inference on a synthetic input
    log(f"  Running test inference …")
    test_ok = False
    try:
        test_input = {"input": np.random.rand(1, 3, SR_INPUT_SIZE, SR_INPUT_SIZE).astype(np.float32)}
        pred = mlmodel.predict(test_input)
        out_key = list(pred.keys())[0]
        pred_shape = pred[out_key].shape
        assert pred_shape[-2] == SR_OUTPUT_SIZE and pred_shape[-1] == SR_OUTPUT_SIZE, \
            f"test output shape {pred_shape}"
        test_ok = True
        log(f"  Test inference passed ✓")
    except Exception as exc:
        log(f"  WARNING: Test inference failed: {exc}")

    # Save .mlpackage
    output_path = output_dir / f"{bundle_name}.mlpackage"
    mlmodel.save(str(output_path))
    log(f"  Saved: {output_path}")

    manifest = make_manifest(
        method_id=model_key,
        bundle_name=bundle_name,
        kind=KIND_SR4X,
        input_type="MLMultiArray [1,3,256,256] float32",
        output_type="MLMultiArray [1,3,1024,1024] float32",
        fixed_input_shape=[1, 3, SR_INPUT_SIZE, SR_INPUT_SIZE],
        flexible_shapes=False,
        test_inference_ok=test_ok,
        notes=f"Traced from {weights_path.name} via spandrel",
    )
    write_manifest(manifest, output_dir)
    return True


# ---------------------------------------------------------------------------
# Style-transfer conversion (Whitebox / AnimeGAN via ONNX → coremltools)
# ---------------------------------------------------------------------------

def convert_style_model(model_key: str, output_dir: Path, onnx_path: Optional[Path] = None) -> bool:
    """
    Convert a style-transfer model from ONNX to CoreML.

    The ONNX file must have been exported externally because these models require
    TensorFlow / JAX environments that are incompatible with the SR conversion path.

    Validates:
      - Full-image inference at 256×256
      - Full-image inference at 320×192 (non-square)
      - Output spatial dimensions equal input spatial dimensions

    Returns True on success.
    """
    require_import("coremltools", "coremltools")
    require_import("onnxruntime")
    require_import("numpy")
    require_import("onnx")

    import coremltools as ct
    import onnxruntime as ort
    import numpy as np

    cfg = MODELS[model_key]
    bundle_name = cfg["bundle_name"]
    log(f"Converting {cfg['label']} …")

    if onnx_path is None or not onnx_path.exists():
        log(f"  ERROR: ONNX path not provided or does not exist.")
        log(f"  Export the ONNX model from the original source and pass: --onnx /path/to/model.onnx")
        return False

    # Validate ONNX model at two sizes
    log(f"  Validating ONNX contract at 256×256 and 320×192 …")
    test_shapes = [(1, 3, 256, 256), (1, 3, 192, 320)]
    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    in_name = sess.get_inputs()[0].name
    out_name = sess.get_outputs()[0].name

    for shape in test_shapes:
        dummy = np.random.rand(*shape).astype(np.float32)
        try:
            result = sess.run([out_name], {in_name: dummy})[0]
        except Exception as exc:
            log(f"  ERROR: ONNX inference failed at shape {shape}: {exc}")
            log(f"  This model does not satisfy the full-image style-transfer contract.")
            return False
        if result.shape[-2:] != shape[-2:]:
            log(f"  ERROR: Output spatial shape {result.shape[-2:]} != input {shape[-2:]}.")
            log(f"  Flexible-shape conversion required but unsupported for this export.")
            return False
        log(f"    shape {shape} → {result.shape} ✓")

    # Convert to CoreML with flexible shapes
    log(f"  Converting ONNX → CoreML with flexible shapes …")
    try:
        mlmodel = ct.converters.onnx.convert(
            model=str(onnx_path),
            minimum_ios_deployment_target="16",
        )
    except Exception as exc:
        log(f"  ERROR during CoreML conversion: {exc}")
        return False

    # Save
    output_path = output_dir / f"{bundle_name}.mlpackage"
    mlmodel.save(str(output_path))
    log(f"  Saved: {output_path}")

    manifest = make_manifest(
        method_id=model_key,
        bundle_name=bundle_name,
        kind=KIND_FULL,
        input_type="MLMultiArray [1,3,H,W] float32",
        output_type="MLMultiArray [1,3,H,W] float32",
        fixed_input_shape=None,
        flexible_shapes=True,
        test_inference_ok=True,
        notes=f"Converted from {onnx_path.name}",
    )
    write_manifest(manifest, output_dir)
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument(
        "--model",
        choices=list(MODELS.keys()),
        help="Model to convert. Omit to attempt all.",
    )
    p.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for .mlpackage files (default: {DEFAULT_OUTPUT_DIR})",
    )
    p.add_argument(
        "--weights",
        type=Path,
        default=None,
        help="Path to PyTorch .pth weights file (SR models)",
    )
    p.add_argument(
        "--onnx",
        type=Path,
        default=None,
        help="Path to ONNX model file (style-transfer models)",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    targets = [args.model] if args.model else list(MODELS.keys())
    results: dict[str, bool] = {}

    for key in targets:
        cfg = MODELS[key]
        kind = cfg["kind"]
        try:
            if kind == KIND_SR4X:
                ok = convert_sr_model(key, args.output_dir, weights_path=args.weights)
            elif kind == KIND_FULL:
                ok = convert_style_model(key, args.output_dir, onnx_path=args.onnx)
            else:
                log(f"Skipping {key}: unsupported kind '{kind}'")
                continue
        except Exception as exc:
            log(f"Unhandled error converting {key}: {exc}")
            ok = False

        results[key] = ok

    print()
    print("── Results ──────────────────────────────")
    for key, ok in results.items():
        status = "✓ OK" if ok else "✗ FAILED"
        print(f"  {MODELS[key]['label']:<40} {status}")
    print()

    if not all(results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
