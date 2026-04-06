import os
import subprocess
import argparse

# Direct links to the first partition (most important articles) or reasonably sized dumps
# These are much smaller than the full 23GB+ dumps.
URLS = {
    # ~390 MB (contains p1 to p224167)
    "ru": "https://dumps.wikimedia.org/ruwiki/latest/ruwiki-latest-pages-articles-multistream1.xml-p1p224167.bz2",
    # ~293 MB (contains p1 to p41242)
    "en": "https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles-multistream1.xml-p1p41242.bz2",
    # ~1.1 GB (Hebrew is small enough to not be always split, or this is the main file)
    "he": "https://dumps.wikimedia.org/hewiki/latest/hewiki-latest-pages-articles-multistream.xml.bz2"
}

def download_file(url, output_dir):
    filename = url.split("/")[-1]
    output_path = os.path.join(output_dir, filename)
    
    print(f"Downloading {filename}...")
    # Using curl for speed and progress bar
    try:
        subprocess.run(["curl", "-O", url], cwd=output_dir, check=True)
        print(f"Saved to {output_path}")
    except subprocess.CalledProcessError:
        print(f"Failed to download {url}")

def main():
    parser = argparse.ArgumentParser(description="Download specific smaller Wikipedia chunks")
    parser.add_argument("--output", default="data/raw", help="Output directory")
    args = parser.parse_args()
    
    os.makedirs(args.output, exist_ok=True)
    
    for lang, url in URLS.items():
        print(f"\n[{lang.upper()}] Processing...")
        download_file(url, args.output)

if __name__ == "__main__":
    main()
