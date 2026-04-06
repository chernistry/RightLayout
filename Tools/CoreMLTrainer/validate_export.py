#!/usr/bin/env python3
import argparse
import math

import numpy as np
import torch
import coremltools as ct

from train import (
    LayoutClassifier,
    LayoutClassifierV2,
    LayoutTransformer,
    EnsembleModel,
    INPUT_LENGTH,
    VOCAB_SIZE,
)


def softmax_np(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float64)
    x = x - np.max(x, axis=-1, keepdims=True)
    exp_x = np.exp(x)
    return exp_x / np.sum(exp_x, axis=-1, keepdims=True)


def load_torch_model(args) -> torch.nn.Module:
    if args.ensemble:
        model = EnsembleModel(traceable_transformer=True)
    elif args.transformer:
        model = LayoutTransformer(traceable=True)
    elif args.model_v2:
        model = LayoutClassifierV2()
    else:
        model = LayoutClassifier()

    model.load_state_dict(torch.load(args.model_in, weights_only=True))
    model.eval()
    return model


def main():
    parser = argparse.ArgumentParser(description="Validate CoreML export vs PyTorch (probabilities)")
    parser.add_argument("--model_in", default="model.pth")
    parser.add_argument("--mlmodel", default="LayoutClassifier.mlmodel")
    parser.add_argument("--samples", type=int, default=50)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--tol", type=float, default=0.01)
    parser.add_argument("--model_v2", action="store_true")
    parser.add_argument("--transformer", action="store_true")
    parser.add_argument("--ensemble", action="store_true")
    args = parser.parse_args()

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    model = load_torch_model(args)
    mlmodel = ct.models.MLModel(args.mlmodel, compute_units=ct.ComputeUnit.CPU_ONLY)

    max_abs_diff = 0.0
    worst_case = None

    with torch.no_grad():
        for i in range(args.samples):
            input_ids = torch.randint(0, VOCAB_SIZE, (1, INPUT_LENGTH), dtype=torch.long)
            torch_logits = model(input_ids).cpu().numpy()
            torch_probs = softmax_np(torch_logits)

            coreml_input = {"input_ids": input_ids.cpu().numpy().astype(np.int32)}
            coreml_out = mlmodel.predict(coreml_input)
            coreml_logits = np.array(coreml_out["classLogits"])
            coreml_logits = coreml_logits.reshape(1, -1)
            coreml_probs = softmax_np(coreml_logits)

            diff = np.max(np.abs(torch_probs - coreml_probs))
            if diff > max_abs_diff:
                max_abs_diff = float(diff)
                worst_case = i

    ok = max_abs_diff <= args.tol + 1e-12
    status = "OK" if ok else "FAIL"
    print(f"{status}: max_abs_diff={max_abs_diff:.6f} (tol={args.tol})")
    if worst_case is not None:
        print(f"worst_case_sample={worst_case} / {args.samples}")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
