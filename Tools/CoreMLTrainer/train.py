import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np
import argparse
import os
import random
import math
import copy

# Constants
INPUT_LENGTH = 20
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890 -=[]\\;',./`!@#$%^&*()_+{}|:\"<>?~"
ALPHABET += "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
ALPHABET += "אבגדהוזחטיכלמנסעפצקרשתךםןףץ"
CHAR_TO_IDX = {c: i+1 for i, c in enumerate(ALPHABET)}
VOCAB_SIZE = len(ALPHABET) + 1

CLASSES = [
    'ru', 'en', 'he',
    'ru_from_en', 'he_from_en',
    'en_from_ru', 'en_from_he',
    'he_from_ru', 'ru_from_he'
]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}

# ============== DATA AUGMENTATION ==============

def augment_text(text, aug_prob=0.15):
    """Apply random augmentations: typos, case changes, char swaps"""
    if random.random() > aug_prob:
        return text
    
    text = list(text)
    aug_type = random.choice(['typo', 'case', 'swap', 'delete', 'duplicate'])
    
    if len(text) < 2:
        return ''.join(text)
    
    if aug_type == 'typo' and len(text) > 0:
        # Replace a random character with nearby key
        idx = random.randint(0, len(text) - 1)
        if text[idx].isalpha():
            # Simple: just change case or add random offset
            if random.random() > 0.5:
                text[idx] = text[idx].swapcase()
            else:
                offset = random.choice([-1, 1])
                text[idx] = chr(ord(text[idx]) + offset)
    
    elif aug_type == 'case':
        # Random case changes
        for i in range(len(text)):
            if random.random() < 0.3:
                text[i] = text[i].swapcase()
    
    elif aug_type == 'swap' and len(text) > 1:
        # Swap adjacent characters
        idx = random.randint(0, len(text) - 2)
        text[idx], text[idx + 1] = text[idx + 1], text[idx]
    
    elif aug_type == 'delete' and len(text) > 2:
        # Delete a character
        idx = random.randint(0, len(text) - 1)
        text.pop(idx)
    
    elif aug_type == 'duplicate' and len(text) > 0:
        # Duplicate a character
        idx = random.randint(0, len(text) - 1)
        text.insert(idx, text[idx])
    
    return ''.join(text)

class LayoutDataset(Dataset):
    def __init__(self, csv_file, augment=False):
        self.data = pd.read_csv(csv_file)
        self.data = self.data[self.data['label'].isin(CLASSES)]
        self.augment = augment
        
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        text = str(self.data.iloc[idx]['text'])
        label_str = self.data.iloc[idx]['label']
        
        # Apply augmentation during training
        if self.augment:
            text = augment_text(text)
        
        # Tokenize / Pad
        indices = [CHAR_TO_IDX.get(c, 0) for c in text]
        if len(indices) > INPUT_LENGTH:
            indices = indices[:INPUT_LENGTH]
        else:
            indices = indices + [0] * (INPUT_LENGTH - len(indices))
            
        return torch.tensor(indices, dtype=torch.long), torch.tensor(CLASS_TO_IDX[label_str], dtype=torch.long)

# ============== MIXUP ==============

def mixup_data(x, y, alpha=0.2):
    """Apply mixup augmentation"""
    if alpha > 0:
        lam = np.random.beta(alpha, alpha)
    else:
        lam = 1

    batch_size = x.size(0)
    index = torch.randperm(batch_size).to(x.device)
    
    mixed_x = lam * x + (1 - lam) * x[index, :]
    y_a, y_b = y, y[index]
    return mixed_x, y_a, y_b, lam

def mixup_criterion(criterion, pred, y_a, y_b, lam):
    """Mixup loss"""
    return lam * criterion(pred, y_a) + (1 - lam) * criterion(pred, y_b)

# ============== POSITIONAL ENCODING (for Transformer) ==============

class PositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=100):
        super().__init__()
        self.max_len = max_len
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        pe = pe.unsqueeze(0)
        self.register_buffer('pe', pe)
    
    def forward(self, x):
        # Keep the sequence length static for TorchScript/CoreML tracing.
        return x + self.pe[:, : self.max_len, :]

# ============== TRACEABLE TRANSFORMER (CoreML-friendly) ==============

class TraceableMultiheadSelfAttention(nn.Module):
    """Multi-head self-attention implemented with basic ops (trace/CoreML-friendly)."""

    def __init__(self, d_model: int, nhead: int, dropout: float = 0.0):
        super().__init__()
        if d_model % nhead != 0:
            raise ValueError(f"d_model ({d_model}) must be divisible by nhead ({nhead})")

        self.d_model = d_model
        self.nhead = nhead
        self.head_dim = d_model // nhead

        # Match nn.MultiheadAttention parameter names for state_dict compatibility.
        self.in_proj_weight = nn.Parameter(torch.empty(3 * d_model, d_model))
        self.in_proj_bias = nn.Parameter(torch.empty(3 * d_model))
        self.out_proj = nn.Linear(d_model, d_model, bias=True)

        self.attn_dropout = nn.Dropout(dropout)
        self._reset_parameters()

    def _reset_parameters(self):
        nn.init.xavier_uniform_(self.in_proj_weight)
        nn.init.constant_(self.in_proj_bias, 0.0)
        nn.init.xavier_uniform_(self.out_proj.weight)
        nn.init.constant_(self.out_proj.bias, 0.0)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: [Batch, SeqLen, d_model]
        qkv = torch.nn.functional.linear(x, self.in_proj_weight, self.in_proj_bias)
        q, k, v = qkv.chunk(3, dim=-1)

        bsz, seq_len, _ = x.shape
        q = q.view(bsz, seq_len, self.nhead, self.head_dim).transpose(1, 2)
        k = k.view(bsz, seq_len, self.nhead, self.head_dim).transpose(1, 2)
        v = v.view(bsz, seq_len, self.nhead, self.head_dim).transpose(1, 2)

        scale = 1.0 / math.sqrt(self.head_dim)
        attn = torch.matmul(q, k.transpose(-2, -1)) * scale
        attn = torch.softmax(attn, dim=-1)
        attn = self.attn_dropout(attn)

        out = torch.matmul(attn, v)
        out = out.transpose(1, 2).contiguous().view(bsz, seq_len, self.d_model)
        return self.out_proj(out)


class TraceableTransformerEncoderLayer(nn.Module):
    """TransformerEncoderLayer implemented without nn.MultiheadAttention (CoreML-friendly)."""

    def __init__(
        self,
        d_model: int,
        nhead: int,
        dim_feedforward: int = 2048,
        dropout: float = 0.1,
        activation: str = "relu",
    ):
        super().__init__()

        self.self_attn = TraceableMultiheadSelfAttention(d_model, nhead, dropout=dropout)
        self.linear1 = nn.Linear(d_model, dim_feedforward)
        self.dropout = nn.Dropout(dropout)
        self.linear2 = nn.Linear(dim_feedforward, d_model)

        self.norm1 = nn.LayerNorm(d_model)
        self.norm2 = nn.LayerNorm(d_model)
        self.dropout1 = nn.Dropout(dropout)
        self.dropout2 = nn.Dropout(dropout)

        if activation == "gelu":
            self.activation = nn.GELU()
        elif activation == "relu":
            self.activation = nn.ReLU()
        else:
            raise ValueError(f"Unsupported activation: {activation}")

    def forward(self, src: torch.Tensor) -> torch.Tensor:
        # Match nn.TransformerEncoderLayer default behavior: norm_first=False.
        x = src
        x = self.norm1(x + self.dropout1(self.self_attn(x)))
        x = self.norm2(x + self.dropout2(self.linear2(self.dropout(self.activation(self.linear1(x))))))
        return x


class TraceableTransformerEncoder(nn.Module):
    """Drop-in replacement for nn.TransformerEncoder (CoreML-friendly)."""

    def __init__(self, encoder_layer: nn.Module, num_layers: int):
        super().__init__()
        self.layers = nn.ModuleList([copy.deepcopy(encoder_layer) for _ in range(num_layers)])

    def forward(self, src: torch.Tensor) -> torch.Tensor:
        output = src
        for layer in self.layers:
            output = layer(output)
        return output

# ============== TRANSFORMER MODEL ==============

class LayoutTransformer(nn.Module):
    """Character-level Transformer for layout detection"""
    def __init__(self, d_model=128, nhead=8, num_layers=4, dim_feedforward=512, dropout=0.2, traceable: bool = False):
        super().__init__()
        
        self.embedding = nn.Embedding(VOCAB_SIZE, d_model, padding_idx=0)
        self.pos_encoder = PositionalEncoding(d_model, INPUT_LENGTH)
        
        if traceable:
            encoder_layer = TraceableTransformerEncoderLayer(
                d_model=d_model,
                nhead=nhead,
                dim_feedforward=dim_feedforward,
                dropout=dropout,
                activation="gelu",
            )
            self.transformer = TraceableTransformerEncoder(encoder_layer, num_layers=num_layers)
        else:
            encoder_layer = nn.TransformerEncoderLayer(
                d_model=d_model,
                nhead=nhead,
                dim_feedforward=dim_feedforward,
                dropout=dropout,
                activation="gelu",
                batch_first=True,
            )
            self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        
        self.pool = nn.AdaptiveAvgPool1d(1)
        self.dropout = nn.Dropout(dropout)
        self.fc1 = nn.Linear(d_model, d_model // 2)
        self.fc2 = nn.Linear(d_model // 2, len(CLASSES))
        self.gelu = nn.GELU()
        
    def forward(self, x):
        # x: [Batch, SeqLen]
        x = self.embedding(x)  # [Batch, SeqLen, d_model]
        x = self.pos_encoder(x)
        x = self.transformer(x)  # [Batch, SeqLen, d_model]
        
        # Pool over sequence
        x = x.permute(0, 2, 1)  # [Batch, d_model, SeqLen]
        x = self.pool(x).squeeze(2)  # [Batch, d_model]
        
        x = self.dropout(x)
        x = self.gelu(self.fc1(x))
        x = self.fc2(x)
        return x

# ============== CNN MODEL V2 ==============

class LayoutClassifierV2(nn.Module):
    """Enhanced multi-scale CNN for maximum accuracy"""
    def __init__(self, embedding_dim=128, hidden_dim=384):
        super(LayoutClassifierV2, self).__init__()
        
        self.embedding = nn.Embedding(VOCAB_SIZE, embedding_dim, padding_idx=0)
        
        # Multi-scale: 2, 3, 4, 5 character patterns
        self.conv2 = nn.Conv1d(embedding_dim, hidden_dim // 4, kernel_size=2, padding=1)
        self.conv3 = nn.Conv1d(embedding_dim, hidden_dim // 4, kernel_size=3, padding=1)
        self.conv4 = nn.Conv1d(embedding_dim, hidden_dim // 4, kernel_size=4, padding=2)
        self.conv5 = nn.Conv1d(embedding_dim, hidden_dim // 4, kernel_size=5, padding=2)
        
        self.bn1 = nn.BatchNorm1d(hidden_dim)
        
        self.conv2_a = nn.Conv1d(hidden_dim, hidden_dim, kernel_size=3, padding=1)
        self.conv2_b = nn.Conv1d(hidden_dim, hidden_dim, kernel_size=5, padding=2)
        self.bn2 = nn.BatchNorm1d(hidden_dim * 2)
        
        self.conv3_deep = nn.Conv1d(hidden_dim * 2, hidden_dim, kernel_size=3, padding=1)
        self.bn3 = nn.BatchNorm1d(hidden_dim)
        
        self.global_max_pool = nn.AdaptiveMaxPool1d(1)
        self.global_avg_pool = nn.AdaptiveAvgPool1d(1)
        
        self.dropout = nn.Dropout(0.4)
        self.fc1 = nn.Linear(hidden_dim * 2, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, hidden_dim // 2)
        self.fc3 = nn.Linear(hidden_dim // 2, len(CLASSES))
        
        self.gelu = nn.GELU()

    def forward(self, x):
        x = self.embedding(x)
        x = x.permute(0, 2, 1)
        
        c2 = self.gelu(self.conv2(x))
        c3 = self.gelu(self.conv3(x))
        c4 = self.gelu(self.conv4(x))
        c5 = self.gelu(self.conv5(x))
        
        # Torch tracing does not like dynamic Python control flow based on tensor shapes.
        # INPUT_LENGTH is fixed end-to-end (training + CoreML export + Swift inference),
        # so we crop to a constant length instead of computing `min_len` at runtime.
        target_len = INPUT_LENGTH
        c2 = c2[:, :, :target_len]
        c3 = c3[:, :, :target_len]
        c4 = c4[:, :, :target_len]
        c5 = c5[:, :, :target_len]
        x = torch.cat([c2, c3, c4, c5], dim=1)
        x = self.bn1(x)
        
        x_a = self.gelu(self.conv2_a(x))
        x_b = self.gelu(self.conv2_b(x))
        x = torch.cat([x_a, x_b], dim=1)
        x = self.bn2(x)
        
        x = self.gelu(self.conv3_deep(x))
        x = self.bn3(x)
        
        x_max = self.global_max_pool(x).squeeze(2)
        x_avg = self.global_avg_pool(x).squeeze(2)
        x = torch.cat([x_max, x_avg], dim=1)
        
        x = self.dropout(x)
        x = self.gelu(self.fc1(x))
        x = self.dropout(x)
        x = self.gelu(self.fc2(x))
        x = self.fc3(x)
        
        return x

# ============== BASIC CNN (backward compat) ==============

class LayoutClassifier(nn.Module):
    def __init__(self):
        super(LayoutClassifier, self).__init__()
        self.embedding = nn.Embedding(VOCAB_SIZE, 32, padding_idx=0)
        self.conv1 = nn.Conv1d(32, 64, kernel_size=3, padding=1)
        self.relu = nn.ReLU()
        self.pool = nn.MaxPool1d(2)
        self.conv2 = nn.Conv1d(64, 128, kernel_size=3, padding=1)
        self.global_pool = nn.AdaptiveAvgPool1d(1)
        self.fc = nn.Linear(128, len(CLASSES))
        self.dropout = nn.Dropout(0.2)

    def forward(self, x):
        x = self.embedding(x)
        x = x.permute(0, 2, 1)
        x = self.conv1(x)
        x = self.relu(x)
        x = self.pool(x)
        x = self.conv2(x)
        x = self.relu(x)
        x = self.global_pool(x)
        x = x.squeeze(2)
        x = self.dropout(x)
        x = self.fc(x)
        return x

# ============== ENSEMBLE ==============

class EnsembleModel(nn.Module):
    """Ensemble of CNN and Transformer"""
    def __init__(self, traceable_transformer: bool = False):
        super().__init__()
        self.cnn = LayoutClassifierV2()
        self.transformer = LayoutTransformer(traceable=traceable_transformer)
        self.weight_cnn = nn.Parameter(torch.tensor(0.6))
        self.weight_transformer = nn.Parameter(torch.tensor(0.4))
        
    def forward(self, x):
        out_cnn = self.cnn(x)
        out_transformer = self.transformer(x)
        
        # Learnable weighted average
        w_cnn = torch.sigmoid(self.weight_cnn)
        w_transformer = torch.sigmoid(self.weight_transformer)
        total = w_cnn + w_transformer
        
        return (w_cnn * out_cnn + w_transformer * out_transformer) / total

# ============== TRAINING ==============

def train(args):
    device = torch.device("mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")
    
    num_workers = min(os.cpu_count() or 4, 8)
    pin_memory = device.type != "mps"
    persistent_workers = num_workers > 0
    
    # Dataset with augmentation for training
    full_dataset = LayoutDataset(args.data, augment=False)  # Load without aug first for split
    
    train_size = int(0.9 * len(full_dataset))
    val_size = len(full_dataset) - train_size
    train_indices, val_indices = torch.utils.data.random_split(
        range(len(full_dataset)), [train_size, val_size]
    )
    
    # Create augmented training dataset
    train_dataset = LayoutDataset(args.data, augment=args.augment)
    train_dataset.data = full_dataset.data.iloc[train_indices.indices].reset_index(drop=True)
    
    val_dataset = LayoutDataset(args.data, augment=False)
    val_dataset.data = full_dataset.data.iloc[val_indices.indices].reset_index(drop=True)
    
    train_loader = DataLoader(
        train_dataset, 
        batch_size=args.batch_size, 
        shuffle=True,
        num_workers=num_workers,
        pin_memory=pin_memory,
        persistent_workers=persistent_workers
    )
    
    val_loader = DataLoader(
        val_dataset,
        batch_size=args.batch_size * 2,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=pin_memory,
        persistent_workers=persistent_workers
    )
    
    # Model selection
    if args.ensemble:
        model = EnsembleModel().to(device)
        print("Using Ensemble (CNN + Transformer)")
    elif args.transformer:
        model = LayoutTransformer().to(device)
        print("Using LayoutTransformer")
    elif args.model_v2:
        model = LayoutClassifierV2().to(device)
        print("Using LayoutClassifierV2 (enhanced CNN)")
    else:
        model = LayoutClassifier().to(device)
        print("Using LayoutClassifier (basic)")

    # Fine-tune from an existing checkpoint
    if args.finetune:
        if not args.model_in:
            raise ValueError("--model_in is required when using --finetune")
        print(f"Fine-tuning from: {args.model_in}")
        try:
            state = torch.load(args.model_in, map_location="cpu", weights_only=True)
        except TypeError:
            state = torch.load(args.model_in, map_location="cpu")
        model.load_state_dict(state)
    
    # Count parameters
    total_params = sum(p.numel() for p in model.parameters())
    print(f"Total parameters: {total_params:,}")
    
    criterion = nn.CrossEntropyLoss(label_smoothing=0.1)
    optimizer = optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    scheduler = None if args.finetune else optim.lr_scheduler.CosineAnnealingWarmRestarts(optimizer, T_0=10, T_mult=2)
    
    print(f"Training on {len(train_dataset)} samples, validating on {len(val_dataset)}")
    print(f"Batch: {args.batch_size}, Epochs: {args.epochs}, LR: {args.lr}")
    print(f"Augmentation: {args.augment}, Mixup: {args.mixup}")
    
    best_val_acc = 0.0
    patience_counter = 0
    
    for epoch in range(args.epochs):
        model.train()
        total_loss = 0
        correct = 0
        total = 0
        
        for inputs, labels in train_loader:
            inputs, labels = inputs.to(device), labels.to(device)
            
            # Mixup (applied on logits level for ensemble compatibility)
            if args.mixup and random.random() < 0.5:
                # Get outputs first
                outputs = model(inputs)
                # Create mixed labels
                lam = np.random.beta(0.2, 0.2)
                batch_size = inputs.size(0)
                index = torch.randperm(batch_size).to(device)
                y_a, y_b = labels, labels[index]
                loss = lam * criterion(outputs, y_a) + (1 - lam) * criterion(outputs, y_b)
            else:
                outputs = model(inputs)
                loss = criterion(outputs, labels)
            
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            
            total_loss += loss.item()
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
        
        train_acc = 100 * correct / total
        
        # Validation
        model.eval()
        val_correct = 0
        val_total = 0
        with torch.no_grad():
            for inputs, labels in val_loader:
                inputs, labels = inputs.to(device), labels.to(device)
                outputs = model(inputs)
                _, predicted = torch.max(outputs.data, 1)
                val_total += labels.size(0)
                val_correct += (predicted == labels).sum().item()
        
        val_acc = 100 * val_correct / val_total
        if scheduler is not None:
            scheduler.step()
        
        print(f"Epoch {epoch+1}/{args.epochs} | Loss: {total_loss/len(train_loader):.4f} | Train: {train_acc:.2f}% | Val: {val_acc:.2f}%")
        
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            patience_counter = 0
            model.to("cpu")
            torch.save(model.state_dict(), args.model_out)
            model.to(device)
            print(f"  → Best model saved! (Val: {val_acc:.2f}%)")
        else:
            patience_counter += 1
            min_epochs_before_stop = 3 if args.finetune else 20
            if patience_counter >= args.patience and epoch >= min_epochs_before_stop:
                print(f"Early stopping at epoch {epoch+1}")
                break
    
    print(f"\nBest validation accuracy: {best_val_acc:.2f}%")
    print(f"Model saved to {args.model_out}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', default='training_data.csv')
    parser.add_argument('--epochs', type=int, default=50)
    parser.add_argument('--batch_size', type=int, default=512)
    parser.add_argument('--lr', type=float, default=0.001)
    parser.add_argument('--patience', type=int, default=10)
    parser.add_argument('--finetune', action='store_true', help="Fine-tune from an existing checkpoint")
    parser.add_argument('--model_in', default=None, help="Input checkpoint for --finetune (state_dict)")
    parser.add_argument('--model_out', default='model.pth')
    parser.add_argument('--model_v2', action='store_true', help="Use enhanced CNN")
    parser.add_argument('--transformer', action='store_true', help="Use Transformer")
    parser.add_argument('--ensemble', action='store_true', help="Use CNN+Transformer ensemble")
    parser.add_argument('--augment', action='store_true', help="Enable data augmentation")
    parser.add_argument('--mixup', action='store_true', help="Enable mixup training")
    args = parser.parse_args()
    train(args)
