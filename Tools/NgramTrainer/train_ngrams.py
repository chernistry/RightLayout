#!/usr/bin/env python3
"""
N-gram Training Script for OMFK

Generates trigram frequency models from text corpora for language detection.
Usage: python train_ngrams.py --lang {ru|en|he} --input corpus.txt --output model.json
"""

import argparse
import json
import math
import sys
from collections import Counter
from typing import Dict, List


def normalize_text(text: str, lang: str) -> str:
    """Normalize text to lowercase letters only."""
    # Lowercase and filter to letters only
    normalized = text.lower()
    
    # Define valid character ranges for each language
    if lang == 'ru':
        # Cyrillic letters
        valid_chars = set(chr(i) for i in range(0x0410, 0x044F + 1))
        valid_chars.add('ё')
        valid_chars.add('Ё'.lower())
    elif lang == 'en':
        # Latin letters
        valid_chars = set('abcdefghijklmnopqrstuvwxyz')
    elif lang == 'he':
        # Hebrew letters
        valid_chars = set(chr(i) for i in range(0x0590, 0x05FF + 1))
    else:
        raise ValueError(f"Unsupported language: {lang}")
    
    # Filter to valid characters
    result = ''.join(c for c in normalized if c in valid_chars)
    return result


def extract_trigrams(text: str) -> List[str]:
    """Extract all trigrams from normalized text."""
    trigrams = []
    for i in range(len(text) - 2):
        trigram = text[i:i+3]
        if len(trigram) == 3:  # Ensure it's a valid trigram
            trigrams.append(trigram)
    return trigrams


def train_model(input_file: str, lang: str, smoothing_k: float = 1.0) -> Dict:
    """Train a trigram model from a corpus file."""
    print(f"Training {lang} model from {input_file}...")
    
    # Read and normalize corpus
    trigram_counts = Counter()
    total_phrases = 0
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                
                total_phrases += 1
                normalized = normalize_text(line, lang)
                
                if len(normalized) < 3:
                    continue
                
                trigrams = extract_trigrams(normalized)
                trigram_counts.update(trigrams)
    
    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError:
        print(f"Error: Input file must be UTF-8 encoded", file=sys.stderr)
        sys.exit(1)
    
    if not trigram_counts:
        print(f"Error: No trigrams extracted from corpus", file=sys.stderr)
        sys.exit(1)
    
    print(f"  Processed {total_phrases} phrases")
    print(f"  Found {len(trigram_counts)} unique trigrams")
    print(f"  Total trigram occurrences: {sum(trigram_counts.values())}")
    
    # Calculate log-probabilities with add-k smoothing
    total_count = sum(trigram_counts.values())
    vocab_size = len(trigram_counts)
    
    trigram_logprobs = {}
    for trigram, count in trigram_counts.items():
        # Add-k smoothing: P(trigram) = (count + k) / (total + k * vocab_size)
        prob = (count + smoothing_k) / (total_count + smoothing_k * vocab_size)
        log_prob = math.log(prob)
        
        # Round to 2 decimal places to reduce JSON size
        trigram_logprobs[trigram] = round(log_prob, 2)
    
    # Create model structure
    model = {
        "lang": lang,
        "n": 3,
        "version": 1,
        "smoothing_k": smoothing_k,
        "total_count": total_count,
        "unique_trigrams": vocab_size,
        "trigrams": trigram_logprobs
    }
    
    return model


def save_model(model: Dict, output_file: str):
    """Save model to JSON file."""
    print(f"Saving model to {output_file}...")
    
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(model, f, ensure_ascii=False, indent=2)
        
        # Report file size
        import os
        size_kb = os.path.getsize(output_file) / 1024
        print(f"  Model saved ({size_kb:.1f} KB)")
        
    except IOError as e:
        print(f"Error: Could not write to '{output_file}': {e}", file=sys.stderr)
        sys.exit(1)


def validate_model(model: Dict) -> bool:
    """Validate model structure and values."""
    required_fields = ['lang', 'n', 'version', 'trigrams']
    
    for field in required_fields:
        if field not in model:
            print(f"Error: Missing required field '{field}'", file=sys.stderr)
            return False
    
    if model['n'] != 3:
        print(f"Warning: Expected n=3, got n={model['n']}")
    
    trigrams = model['trigrams']
    if not trigrams:
        print("Error: No trigrams in model", file=sys.stderr)
        return False
    
    # Check value ranges
    log_probs = list(trigrams.values())
    min_log_prob = min(log_probs)
    max_log_prob = max(log_probs)
    
    print(f"  Log-probability range: [{min_log_prob:.2f}, {max_log_prob:.2f}]")
    
    if max_log_prob > 0:
        print("Warning: Some log-probabilities are positive (should be negative)", file=sys.stderr)
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Train n-gram language models for OMFK'
    )
    parser.add_argument(
        '--lang',
        required=True,
        choices=['ru', 'en', 'he'],
        help='Language code (ru, en, or he)'
    )
    parser.add_argument(
        '--input',
        required=True,
        help='Input corpus file (UTF-8 text, one phrase per line)'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Output JSON model file'
    )
    parser.add_argument(
        '--smoothing-k',
        type=float,
        default=1.0,
        help='Add-k smoothing parameter (default: 1.0)'
    )
    
    args = parser.parse_args()
    
    # Train model
    model = train_model(args.input, args.lang, args.smoothing_k)
    
    # Validate model
    if not validate_model(model):
        sys.exit(1)
    
    # Save model
    save_model(model, args.output)
    
    print("✅ Training complete!")


if __name__ == '__main__':
    main()
