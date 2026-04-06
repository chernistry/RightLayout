#!/usr/bin/env python3
"""
Download OpenSubtitles corpus from OPUS for OMFK training.
Focus: Hebrew <-> English, Hebrew <-> Russian pairs.
"""

import os
import sys
import gzip
import zipfile
import tempfile
import argparse
from urllib.request import urlretrieve
from urllib.error import URLError
import shutil

# OpenSubtitles v2018 URLs from OPUS
DATASETS = {
    # Monolingual (subtitles in single language - conversational text)
    "he_mono": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmono%2FOpenSubtitles.he.gz",
        "type": "mono",
        "lang": "he",
        "desc": "Hebrew subtitles (tokenized)"
    },
    "he_raw": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmono%2FOpenSubtitles.raw.he.gz",
        "type": "mono",
        "lang": "he",
        "desc": "Hebrew subtitles (raw, less normalized)"
    },
    "ru_mono": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmono%2FOpenSubtitles.ru.gz",
        "type": "mono",
        "lang": "ru",
        "desc": "Russian subtitles (tokenized)"
    },
    "en_mono": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmono%2FOpenSubtitles.en.gz",
        "type": "mono",
        "lang": "en",
        "desc": "English subtitles (tokenized)"
    },
    # Parallel (aligned sentence pairs - useful for verification)
    "en_he_parallel": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmoses%2Fen-he.txt.zip",
        "type": "parallel",
        "langs": ["en", "he"],
        "desc": "English-Hebrew parallel subtitles"
    },
    "he_ru_parallel": {
        "url": "https://opus.nlpl.eu/legacy/download.php?f=OpenSubtitles%2Fv2018%2Fmoses%2Fhe-ru.txt.zip",
        "type": "parallel",
        "langs": ["he", "ru"],
        "desc": "Hebrew-Russian parallel subtitles"
    },
}

def download_file(url, dest_path, desc=""):
    """Download file with progress indicator."""
    print(f"  Downloading: {desc or url}")
    try:
        def reporthook(block_num, block_size, total_size):
            downloaded = block_num * block_size
            if total_size > 0:
                percent = min(100, downloaded * 100 / total_size)
                mb_down = downloaded / (1024 * 1024)
                mb_total = total_size / (1024 * 1024)
                sys.stdout.write(f"\r    {percent:.1f}% ({mb_down:.1f}/{mb_total:.1f} MB)")
                sys.stdout.flush()
        
        urlretrieve(url, dest_path, reporthook)
        print()  # newline after progress
        return True
    except URLError as e:
        print(f"\n  ERROR downloading: {e}")
        return False
    except Exception as e:
        print(f"\n  ERROR: {e}")
        return False

def extract_gz(gz_path, output_path, limit_lines=None):
    """Extract .gz file and optionally limit lines."""
    print(f"  Extracting {os.path.basename(gz_path)}...")
    count = 0
    with gzip.open(gz_path, 'rt', encoding='utf-8', errors='ignore') as f_in:
        with open(output_path, 'w', encoding='utf-8') as f_out:
            for line in f_in:
                line = line.strip()
                if line and len(line) > 2:
                    f_out.write(line + '\n')
                    count += 1
                    if limit_lines and count >= limit_lines:
                        break
                if count % 500000 == 0:
                    print(f"    Processed {count} lines...")
    print(f"  Extracted {count} lines to {os.path.basename(output_path)}")
    return count

def extract_zip_parallel(zip_path, output_dir, limit_lines=None):
    """Extract parallel corpus from Moses-format zip."""
    print(f"  Extracting parallel corpus from {os.path.basename(zip_path)}...")
    
    with zipfile.ZipFile(zip_path, 'r') as zf:
        names = zf.namelist()
        print(f"    Found files: {names}")
        
        for name in names:
            # Moses format: OpenSubtitles.en-he.en, OpenSubtitles.en-he.he
            if name.endswith('.en'):
                lang = 'en'
            elif name.endswith('.he'):
                lang = 'he'
            elif name.endswith('.ru'):
                lang = 'ru'
            else:
                continue
            
            output_path = os.path.join(output_dir, f"subtitles_parallel_{lang}.txt")
            
            with zf.open(name) as f_in:
                count = 0
                with open(output_path, 'w', encoding='utf-8') as f_out:
                    for line in f_in:
                        try:
                            decoded = line.decode('utf-8').strip()
                            if decoded and len(decoded) > 2:
                                f_out.write(decoded + '\n')
                                count += 1
                                if limit_lines and count >= limit_lines:
                                    break
                        except:
                            pass
                print(f"    {lang}: {count} lines")

def process_mono_dataset(key, dataset, raw_dir, processed_dir, limit_lines):
    """Download and process monolingual dataset."""
    lang = dataset["lang"]
    url = dataset["url"]
    desc = dataset["desc"]
    
    print(f"\n[{key}] {desc}")
    
    # Download
    gz_path = os.path.join(raw_dir, f"subtitles_{key}.gz")
    if not os.path.exists(gz_path):
        if not download_file(url, gz_path, desc):
            return False
    else:
        print(f"  Already downloaded: {gz_path}")
    
    # Extract to processed
    output_path = os.path.join(processed_dir, f"subtitles_{lang}.txt")
    
    # Append to existing or create new
    mode = 'a' if os.path.exists(output_path) else 'w'
    
    count = 0
    with gzip.open(gz_path, 'rt', encoding='utf-8', errors='ignore') as f_in:
        with open(output_path, mode, encoding='utf-8') as f_out:
            for line in f_in:
                line = line.strip()
                if line and 3 < len(line) < 200:  # Filter short/long
                    f_out.write(line + '\n')
                    count += 1
                    if limit_lines and count >= limit_lines:
                        break
                if count % 500000 == 0:
                    print(f"    Processed {count} lines...")
    
    print(f"  -> {count} lines added to subtitles_{lang}.txt")
    return True

def main():
    parser = argparse.ArgumentParser(description="Download OpenSubtitles corpus for OMFK")
    parser.add_argument("--raw-dir", default="../../data/raw/subtitles", help="Raw downloads directory")
    parser.add_argument("--processed-dir", default="../../data/processed", help="Processed output directory")
    parser.add_argument("--limit", type=int, default=2000000, help="Max lines per language")
    parser.add_argument("--skip-parallel", action="store_true", help="Skip parallel corpora")
    parser.add_argument("--only", nargs="+", help="Only download specific datasets (e.g., he_mono ru_mono)")
    args = parser.parse_args()
    
    # Resolve paths relative to script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    raw_dir = os.path.join(script_dir, args.raw_dir)
    processed_dir = os.path.join(script_dir, args.processed_dir)
    
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(processed_dir, exist_ok=True)
    
    print("=" * 60)
    print("  OpenSubtitles Download for OMFK")
    print("=" * 60)
    print(f"Raw downloads: {raw_dir}")
    print(f"Processed output: {processed_dir}")
    print(f"Limit per language: {args.limit} lines")
    
    # Determine which datasets to download
    if args.only:
        datasets_to_download = {k: v for k, v in DATASETS.items() if k in args.only}
    else:
        datasets_to_download = {k: v for k, v in DATASETS.items() 
                               if v["type"] == "mono" or not args.skip_parallel}
    
    # Focus on monolingual first
    mono_datasets = {k: v for k, v in datasets_to_download.items() if v["type"] == "mono"}
    parallel_datasets = {k: v for k, v in datasets_to_download.items() if v["type"] == "parallel"}
    
    # Process monolingual
    for key, dataset in mono_datasets.items():
        process_mono_dataset(key, dataset, raw_dir, processed_dir, args.limit)
    
    # Process parallel if requested
    if parallel_datasets and not args.skip_parallel:
        print("\n" + "=" * 40)
        print("  Parallel Corpora (for verification)")
        print("=" * 40)
        for key, dataset in parallel_datasets.items():
            print(f"\n[{key}] {dataset['desc']}")
            zip_path = os.path.join(raw_dir, f"{key}.zip")
            if not os.path.exists(zip_path):
                download_file(dataset["url"], zip_path, dataset["desc"])
            extract_zip_parallel(zip_path, processed_dir, args.limit // 2)
    
    print("\n" + "=" * 60)
    print("  DONE!")
    print("=" * 60)
    
    # Show what we got
    print("\nProcessed files:")
    for f in os.listdir(processed_dir):
        if f.startswith("subtitles_"):
            path = os.path.join(processed_dir, f)
            lines = sum(1 for _ in open(path, encoding='utf-8'))
            size_mb = os.path.getsize(path) / (1024 * 1024)
            print(f"  {f}: {lines:,} lines ({size_mb:.1f} MB)")
    
    print("\nNext steps:")
    print("  1. Merge subtitles into main corpus:")
    print("     cat data/processed/subtitles_he.txt >> data/processed/he.txt")
    print("     cat data/processed/subtitles_ru.txt >> data/processed/ru.txt")
    print("     cat data/processed/subtitles_en.txt >> data/processed/en.txt")
    print("  2. Run ./train_master.sh to retrain models")

if __name__ == "__main__":
    main()
