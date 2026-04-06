import torch
import coremltools as ct
from train import LayoutClassifier, LayoutClassifierV2, LayoutTransformer, EnsembleModel, INPUT_LENGTH, CLASSES, VOCAB_SIZE
import argparse

def export(args):
    # Load PyTorch model
    if args.ensemble:
        model = EnsembleModel(traceable_transformer=True)
        print("Loading EnsembleModel (CNN + Transformer)")
    elif args.transformer:
        model = LayoutTransformer(traceable=True)
        print("Loading LayoutTransformer")
    elif args.model_v2:
        model = LayoutClassifierV2()
        print("Loading LayoutClassifierV2 (enhanced CNN)")
    else:
        model = LayoutClassifier()
        print("Loading LayoutClassifier (basic)")
    
    model.load_state_dict(torch.load(args.model_in, map_location='cpu', weights_only=True))
    model.eval()
    
    # Count parameters
    total_params = sum(p.numel() for p in model.parameters())
    print(f"Total parameters: {total_params:,}")
    
    # Trace the model (CoreML conversion entrypoint).
    example_input = torch.randint(0, VOCAB_SIZE, (1, INPUT_LENGTH), dtype=torch.long)
    torchscript_model = torch.jit.trace(model, example_input)
    
    # Convert to CoreML
    mlmodel = ct.convert(
        torchscript_model,
        inputs=[ct.TensorType(name="input_ids", shape=(1, INPUT_LENGTH), dtype=int)],
        outputs=[ct.TensorType(name="classLogits")],
        convert_to="neuralnetwork"
    )
    
    # Add metadata
    model_type = "ensemble" if args.ensemble else ("transformer" if args.transformer else ("v2" if args.model_v2 else "v1"))
    mlmodel.author = "OMFK Agent"
    mlmodel.short_description = f"Layout Classifier ({model_type}, INPUT_LENGTH={INPUT_LENGTH})"
    mlmodel.user_defined_metadata["classes"] = ",".join(CLASSES)
    mlmodel.user_defined_metadata["input_length"] = str(INPUT_LENGTH)
    mlmodel.user_defined_metadata["model_version"] = model_type
    mlmodel.user_defined_metadata["parameters"] = str(total_params)
    
    # Save
    mlmodel.save(args.output)
    print(f"CoreML model saved to {args.output}")
    print(f"  Input length: {INPUT_LENGTH}")
    print(f"  Classes: {len(CLASSES)}")
    print(f"  Model type: {model_type}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--model_in', default='model.pth')
    parser.add_argument('--output', default='LayoutClassifier.mlmodel')
    parser.add_argument('--model_v2', action='store_true', help="Export V2 CNN architecture")
    parser.add_argument('--transformer', action='store_true', help="Export Transformer architecture")
    parser.add_argument('--ensemble', action='store_true', help="Export Ensemble (CNN+Transformer)")
    args = parser.parse_args()
    export(args)
