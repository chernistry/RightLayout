import os
import argparse
import json
import concurrent.futures
from datasets import load_dataset
import time

# Enable HF Transfer for faster downloads if installed
try:
    import hf_transfer
    os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
except ImportError:
    pass

# Use the maintained "wikimedia/wikipedia" dataset instead of the old "wikipedia"
# Date: 20231101 is a widely available dump date for this dataset
DATASET_NAME = "wikimedia/wikipedia"
DATASET_DATE = "20231101" 

# Limit articles per language
LIMIT = 300_000 

def download_lang(lang_code, output_dir):
    start_time = time.time()
    print(f"[{lang_code}] Starting download...")
    
    # Config format: "20231101.ru"
    config_name = f"{DATASET_DATE}.{lang_code}"
    output_file = os.path.join(output_dir, f"{lang_code}_wiki.jsonl")
    
    try:
        # Load in streaming mode
        print(f"[{lang_code}] Load dataset: {DATASET_NAME} / {config_name}")
        ds = load_dataset(DATASET_NAME, config_name, split="train", streaming=True, trust_remote_code=True)
        
        count = 0
        batch_size = 2000 # Increased batch size
        buffer = []
        
        # 4MB buffer for writing
        with open(output_file, 'w', encoding='utf-8', buffering=4*1024*1024) as f: 
            for example in ds:
                # Structure of wikimedia/wikipedia: {'id':..., 'url':..., 'title':..., 'text':...}
                json_line = json.dumps({"text": example['text']}, ensure_ascii=False)
                buffer.append(json_line)
                count += 1
                
                if len(buffer) >= batch_size:
                    f.write('\n'.join(buffer) + '\n')
                    buffer = []
                    if count % 20000 == 0:
                        elapsed = time.time() - start_time
                        rate = count / elapsed if elapsed > 0 else 0
                        print(f"[{lang_code}] Saved {count} articles... ({rate:.1f} arts/s)")
                
                if count >= LIMIT:
                    break
            
            if buffer:
                f.write('\n'.join(buffer) + '\n')
                
        duration = time.time() - start_time
        print(f"[{lang_code}] FINISHED. Saved {count} articles in {duration:.1f}s.")
        
    except Exception as e:
        print(f"[{lang_code}] ERROR: {e}")
        # Fallback suggestion if specific date fails
        print(f"[{lang_code}] Tip: If 404, try a different date or check HuggingFace 'wikimedia/wikipedia' avail configs.")

def main():
    parser = argparse.ArgumentParser(description="Download Wikipedia datasets for OMFK training")
    parser.add_argument("--output", default="data/raw", help="Output directory")
    args = parser.parse_args()
    
    os.makedirs(args.output, exist_ok=True)
    
    languages = ["ru", "he", "en"]
    
    print(f"Downloading {languages} in parallel to {args.output}...")
    print(f"Dataset: {DATASET_NAME} (Date: {DATASET_DATE})")
    print("Using ThreadPoolExecutor for concurrency.")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(languages)) as executor:
        futures = [executor.submit(download_lang, lang, args.output) for lang in languages]
        
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as exc:
                print(f"Generated an exception: {exc}")

if __name__ == "__main__":
    main()
