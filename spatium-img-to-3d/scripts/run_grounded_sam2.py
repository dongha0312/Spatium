#!/usr/bin/env python3
"""Translate an optional Korean query, detect it, and export a transparent PNG."""

from __future__ import annotations

import argparse
import gc
import inspect
import json
import re
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageOps
from transformers import (
    AutoModelForSeq2SeqLM,
    AutoModelForZeroShotObjectDetection,
    AutoProcessor,
    AutoTokenizer,
    Sam2Model,
    Sam2Processor,
)


KOREAN_PATTERN = re.compile(r"[\uac00-\ud7a3]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    parser.add_argument("--query", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--translation-model", required=True)
    parser.add_argument("--grounding-dino-model", required=True)
    parser.add_argument("--sam2-model", required=True)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--box-threshold", type=float, default=0.30)
    parser.add_argument("--text-threshold", type=float, default=0.25)
    parser.add_argument("--padding", type=float, default=0.06)
    return parser.parse_args()


def release_cuda() -> None:
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


def move_batch_to_device(batch, device: torch.device, dtype: torch.dtype):
    """Move a processor batch while preserving integer and boolean tensor types."""
    for key, value in batch.items():
        if not isinstance(value, torch.Tensor):
            continue
        if torch.is_floating_point(value):
            batch[key] = value.to(device=device, dtype=dtype)
        else:
            batch[key] = value.to(device=device)
    return batch


def translate_query(query: str, model_path: str) -> str:
    query = query.strip()
    if not KOREAN_PATTERN.search(query):
        return query

    tokenizer = AutoTokenizer.from_pretrained(model_path, local_files_only=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(model_path, local_files_only=True)
    inputs = tokenizer(query, return_tensors="pt", truncation=True)
    with torch.inference_mode():
        tokens = model.generate(**inputs, num_beams=4, max_new_tokens=48)
    translated = tokenizer.decode(tokens[0], skip_special_tokens=True).strip()
    del model, tokenizer, inputs, tokens
    release_cuda()
    if not translated:
        raise RuntimeError("Korean-to-English translation returned an empty query.")
    return translated


def select_detection(result: dict, width: int, height: int) -> tuple[torch.Tensor, float, str]:
    boxes = result.get("boxes")
    scores = result.get("scores")
    labels = result.get("text_labels", result.get("labels", []))
    if boxes is None or scores is None or len(boxes) == 0:
        raise RuntimeError("GroundingDINO did not find an object matching the query.")

    center_x, center_y = width / 2, height / 2
    ranks: list[float] = []
    for box, score in zip(boxes, scores):
        x1, y1, x2, y2 = [float(value) for value in box]
        area_ratio = max(0.0, (x2 - x1) * (y2 - y1)) / max(1, width * height)
        object_x, object_y = (x1 + x2) / 2, (y1 + y2) / 2
        distance = ((object_x - center_x) ** 2 + (object_y - center_y) ** 2) ** 0.5
        center_bonus = 1.0 - min(1.0, distance / max(1.0, (width**2 + height**2) ** 0.5))
        ranks.append(float(score) + 0.16 * area_ratio + 0.04 * center_bonus)

    index = int(np.argmax(ranks))
    label = str(labels[index]) if len(labels) > index else "object"
    return boxes[index].detach().cpu(), float(scores[index]), label


def main() -> None:
    args = parse_args()
    if args.device.startswith("cuda") and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but is not available in the segmentation environment.")

    device = torch.device(args.device)
    # GroundingDINO's text-enhancer path produces float32 activations in the
    # Transformers implementation, so running the whole detector in float16
    # causes internal Float/Half matrix multiplication errors. Keep DINO in
    # float32, release it, and then run SAM2 in float16 on CUDA.
    dino_dtype = torch.float32
    sam_dtype = torch.float16 if device.type == "cuda" else torch.float32
    with Image.open(args.image) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
    translated_query = translate_query(args.query, args.translation_model)
    prompt = translated_query.strip().rstrip(".") + "."

    dino_processor = AutoProcessor.from_pretrained(
        args.grounding_dino_model, local_files_only=True
    )
    dino_model = AutoModelForZeroShotObjectDetection.from_pretrained(
        args.grounding_dino_model,
        local_files_only=True,
        dtype=dino_dtype,
    ).to(device)
    dino_inputs = move_batch_to_device(
        dino_processor(images=image, text=prompt, return_tensors="pt"),
        device,
        dino_dtype,
    )
    with torch.inference_mode():
        dino_outputs = dino_model(**dino_inputs)
    post_process = dino_processor.post_process_grounded_object_detection
    post_process_parameters = inspect.signature(post_process).parameters
    threshold_argument = (
        {"box_threshold": args.box_threshold}
        if "box_threshold" in post_process_parameters
        else {"threshold": args.box_threshold}
    )
    detections = post_process(
        dino_outputs,
        dino_inputs.input_ids,
        text_threshold=args.text_threshold,
        target_sizes=[image.size[::-1]],
        **threshold_argument,
    )[0]
    box, confidence, detected_label = select_detection(detections, *image.size)
    del detections, dino_outputs, dino_inputs, dino_model, dino_processor
    release_cuda()

    sam_processor = Sam2Processor.from_pretrained(args.sam2_model, local_files_only=True)
    sam_model = Sam2Model.from_pretrained(
        args.sam2_model,
        local_files_only=True,
        dtype=sam_dtype,
    ).to(device)
    sam_inputs = move_batch_to_device(
        sam_processor(
            images=image,
            input_boxes=[[[float(value) for value in box]]],
            return_tensors="pt",
        ),
        device,
        sam_dtype,
    )
    with torch.inference_mode():
        sam_outputs = sam_model(**sam_inputs, multimask_output=True)
    masks = sam_processor.post_process_masks(
        sam_outputs.pred_masks.detach().cpu(), sam_inputs["original_sizes"].detach().cpu()
    )[0]
    scores = sam_outputs.iou_scores.detach().float().cpu().reshape(-1)
    masks = masks.reshape(-1, masks.shape[-2], masks.shape[-1])
    mask = masks[int(torch.argmax(scores))].numpy() > 0
    if not mask.any():
        raise RuntimeError("SAM2 returned an empty object mask.")

    rgba = np.dstack((np.asarray(image), mask.astype(np.uint8) * 255))
    ys, xs = np.where(mask)
    x1, x2 = int(xs.min()), int(xs.max()) + 1
    y1, y2 = int(ys.min()), int(ys.max()) + 1
    pad = int(max(x2 - x1, y2 - y1) * max(0.0, args.padding))
    x1, y1 = max(0, x1 - pad), max(0, y1 - pad)
    x2, y2 = min(image.width, x2 + pad), min(image.height, y2 + pad)
    output = Image.fromarray(rgba, "RGBA").crop((x1, y1, x2, y2))
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output, format="PNG")

    metadata = {
        "original_query": args.query,
        "translated_query": translated_query,
        "detected_label": detected_label,
        "confidence": confidence,
        "device": str(device),
        "box": [round(float(value), 3) for value in box],
    }
    Path(args.metadata).write_text(json.dumps(metadata, ensure_ascii=False), encoding="utf-8")
    del sam_outputs, sam_inputs, sam_model, sam_processor
    release_cuda()


if __name__ == "__main__":
    main()
