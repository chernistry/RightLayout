"""Beam Cloud training for OMFK layout classifier - ULTRA mode."""
from beam import function, Image, Volume, env

VOLUME_NAME = "omfk-training-data"

if env.is_remote():
    import sys
    sys.path.insert(0, "./data")


def get_image():
    return Image(
        python_version="python3.10",
        python_packages=[
            "torch",
            "pandas",
            "numpy",
        ],
    )


def get_volume():
    return Volume(name=VOLUME_NAME, mount_path="./data")


@function(
    name="train-omfk",
    cpu=8,
    memory="48Gi",
    gpu="A10G",
    image=get_image(),
    volumes=[get_volume()],
    timeout=14400,  # 4 hours
)
def train_model(
    data_file: str = "training_data_combined.csv",
    epochs: int = 120,        # ULTRA: 120 epochs
    batch_size: int = 512,    # A10G safe batch size
    lr: float = 0.001,
    patience: int = 20,       # ULTRA: patience 20
    augment: bool = True,     # ULTRA: augmentation
    mixup: bool = True,       # ULTRA: mixup
) -> dict:
    """Train OMFK ensemble model - ULTRA settings matching train_master.sh."""
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from torch.utils.data import DataLoader
    import os
    import sys
    import random
    import numpy as np
    
    sys.path.insert(0, "./data")
    from train import EnsembleModel, LayoutDataset, CLASSES
    
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"🚀 OMFK ULTRA Training")
    print(f"Device: {device}")
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
    
    data_path = f"./data/{data_file}"
    if not os.path.exists(data_path):
        print(f"Files in ./data: {os.listdir('./data')}")
        return {"error": f"Data file not found: {data_path}"}
    
    print(f"\n📊 Loading data from {data_path}...")
    full_dataset = LayoutDataset(data_path, augment=augment)
    print(f"Total samples: {len(full_dataset):,}")
    
    train_size = int(0.9 * len(full_dataset))
    val_size = len(full_dataset) - train_size
    
    # Split indices, then create separate datasets
    indices = list(range(len(full_dataset)))
    random.shuffle(indices)
    train_indices = indices[:train_size]
    val_indices = indices[train_size:]
    
    # Training with augmentation
    train_dataset = LayoutDataset(data_path, augment=augment)
    train_dataset.data = full_dataset.data.iloc[train_indices].reset_index(drop=True)
    
    # Validation without augmentation
    val_dataset = LayoutDataset(data_path, augment=False)
    val_dataset.data = full_dataset.data.iloc[val_indices].reset_index(drop=True)
    
    train_loader = DataLoader(
        train_dataset, 
        batch_size=batch_size, 
        shuffle=True, 
        num_workers=4, 
        pin_memory=True
    )
    val_loader = DataLoader(
        val_dataset, 
        batch_size=batch_size * 2, 
        shuffle=False, 
        num_workers=4, 
        pin_memory=True
    )
    
    print(f"Train: {len(train_dataset):,}, Val: {len(val_dataset):,}")
    print(f"\n⚙️ Config: epochs={epochs}, batch={batch_size}, lr={lr}, patience={patience}")
    print(f"   Augment={augment}, Mixup={mixup}")
    
    # Model
    model = EnsembleModel().to(device)
    total_params = sum(p.numel() for p in model.parameters())
    print(f"Model: EnsembleModel (CNN + Transformer)")
    print(f"Parameters: {total_params:,}")
    
    criterion = nn.CrossEntropyLoss(label_smoothing=0.1)
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=0.01)
    scheduler = optim.lr_scheduler.CosineAnnealingWarmRestarts(optimizer, T_0=10, T_mult=2)
    
    best_val_acc = 0.0
    patience_counter = 0
    
    print(f"\n🏋️ Starting training...")
    for epoch in range(epochs):
        model.train()
        total_loss, correct, total = 0, 0, 0
        
        for batch_idx, (inputs, labels) in enumerate(train_loader):
            inputs, labels = inputs.to(device), labels.to(device)
            
            # Mixup
            if mixup and random.random() < 0.5:
                lam = np.random.beta(0.2, 0.2)
                batch_size_curr = inputs.size(0)
                index = torch.randperm(batch_size_curr).to(device)
                
                outputs = model(inputs)
                y_a, y_b = labels, labels[index]
                loss = lam * criterion(outputs, y_a) + (1 - lam) * criterion(outputs, y_b)
            else:
                outputs = model(inputs)
                loss = criterion(outputs, labels)
            
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            
            total_loss += loss.item()
            _, pred = outputs.max(1)
            total += labels.size(0)
            correct += (pred == labels).sum().item()
            
            if batch_idx % 500 == 0 and batch_idx > 0:
                print(f"  [{epoch+1}] Batch {batch_idx}/{len(train_loader)}, Loss: {loss.item():.4f}")
        
        train_acc = 100 * correct / total
        
        # Validate
        model.eval()
        val_correct, val_total = 0, 0
        with torch.no_grad():
            for inputs, labels in val_loader:
                inputs, labels = inputs.to(device), labels.to(device)
                _, pred = model(inputs).max(1)
                val_total += labels.size(0)
                val_correct += (pred == labels).sum().item()
        
        val_acc = 100 * val_correct / val_total
        scheduler.step()
        
        print(f"Epoch {epoch+1}/{epochs} | Loss: {total_loss/len(train_loader):.4f} | Train: {train_acc:.2f}% | Val: {val_acc:.2f}%")
        
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            patience_counter = 0
            torch.save(model.state_dict(), "./data/model_ultra.pth")
            print(f"  ✅ New best! Saved model (Val: {val_acc:.2f}%)")
        else:
            patience_counter += 1
            if patience_counter >= patience and epoch >= 20:
                print(f"\n⏹️ Early stopping at epoch {epoch+1} (no improvement for {patience} epochs)")
                break
    
    print(f"\n🎉 Training complete!")
    print(f"Best validation accuracy: {best_val_acc:.2f}%")
    print(f"Model saved to: ./data/model_ultra.pth")
    
    return {
        "best_val_acc": best_val_acc,
        "epochs_trained": epoch + 1,
        "model_path": "./data/model_ultra.pth",
        "samples": len(full_dataset),
    }


if __name__ == "__main__":
    result = train_model()
    print(result)
