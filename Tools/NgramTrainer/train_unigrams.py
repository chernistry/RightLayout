#!/usr/bin/env python3
"""
Unigram (word frequency) training for OMFK.

Generates a compact top-N word frequency list from a corpus:
  word<TAB>count

Used to:
  - disambiguate ambiguous layout conversions (Hebrew QWERTY duplicates)
  - provide deterministic word-validation fallback when NSSpellChecker lacks a dictionary
"""

import argparse
import sys
from collections import Counter


def valid_chars_for(lang: str) -> set[str]:
    if lang == "ru":
        chars = set(chr(i) for i in range(0x0410, 0x044F + 1))
        chars.add("ё")
        chars.add("Ё".lower())
        return chars
    if lang == "en":
        return set("abcdefghijklmnopqrstuvwxyz")
    if lang == "he":
        # Hebrew block incl. niqqud; keep full range like trigram trainer.
        return set(chr(i) for i in range(0x0590, 0x05FF + 1))
    raise ValueError(f"Unsupported language: {lang}")


def iter_words(line: str, valid: set[str]):
    buf: list[str] = []
    for ch in line.lower():
        if ch in valid:
            buf.append(ch)
        else:
            if buf:
                yield "".join(buf)
                buf.clear()
    if buf:
        yield "".join(buf)


def train_unigrams(
    input_file: str,
    lang: str,
    top_n: int,
    min_len: int,
    prune_max_vocab: int,
    prune_keep: int,
) -> Counter:
    valid = valid_chars_for(lang)
    counts: Counter = Counter()

    lines = 0
    tokens = 0

    try:
        with open(input_file, "r", encoding="utf-8") as f:
            for line in f:
                lines += 1
                for w in iter_words(line, valid):
                    if len(w) < min_len:
                        continue
                    counts[w] += 1
                    tokens += 1

                # Periodic pruning to keep memory bounded on huge corpora.
                if len(counts) > prune_max_vocab:
                    counts = Counter(dict(counts.most_common(prune_keep)))
    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    except UnicodeDecodeError:
        print("Error: Input file must be UTF-8 encoded", file=sys.stderr)
        sys.exit(1)

    if not counts:
        print("Error: No tokens extracted from corpus", file=sys.stderr)
        sys.exit(1)

    print(f"  Processed {lines} lines")
    print(f"  Tokens: {tokens}")
    print(f"  Unique tokens (post-prune): {len(counts)}")
    print(f"  Top-N: {top_n}")

    return Counter(dict(counts.most_common(top_n)))


def save_tsv(counter: Counter, output_file: str):
    try:
        with open(output_file, "w", encoding="utf-8") as f:
            for w, c in counter.most_common():
                f.write(f"{w}\t{c}\n")
    except IOError as e:
        print(f"Error: Could not write to '{output_file}': {e}", file=sys.stderr)
        sys.exit(1)


def main():
    p = argparse.ArgumentParser(description="Train unigram word frequency list for OMFK")
    p.add_argument("--lang", required=True, choices=["ru", "en", "he"])
    p.add_argument("--input", required=True, help="Input corpus file (UTF-8)")
    p.add_argument("--output", required=True, help="Output TSV (word\\tcount)")
    p.add_argument("--top", type=int, default=200000, help="Keep top-N words (default: 200000)")
    p.add_argument("--min-len", type=int, default=2, help="Minimum token length (default: 2)")
    p.add_argument("--prune-max-vocab", type=int, default=1500000, help="Prune when vocab exceeds this (default: 1500000)")
    p.add_argument("--prune-keep", type=int, default=600000, help="Keep this many after prune (default: 600000)")
    args = p.parse_args()

    print(f"Training {args.lang} unigrams from {args.input}...")
    counter = train_unigrams(
        input_file=args.input,
        lang=args.lang,
        top_n=args.top,
        min_len=args.min_len,
        prune_max_vocab=args.prune_max_vocab,
        prune_keep=max(args.prune_keep, args.top),
    )
    print(f"Saving to {args.output} ...")
    save_tsv(counter, args.output)
    print("✅ Unigrams complete!")


if __name__ == "__main__":
    main()

