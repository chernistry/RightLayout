import bz2
import xml.etree.ElementTree as ET
import argparse
import os
import re

def clean_text(text):
    if not text:
        return ""
    # Remove Wiki markup (simplified)
    # 1. Remove recursive braces {{...}} (templates) - heuristic
    text = re.sub(r'\{\{.*?\}\}', '', text, flags=re.DOTALL)
    # 2. Remove links [[...]]
    text = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]', r'\1', text)
    # 3. Remove headings ==...==
    text = re.sub(r'={2,}.*?={2,}', '', text)
    # 4. Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)
    # 5. Collapse whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def extract_dump(input_file, output_file, limit=None):
    print(f"Extracting from {input_file} to {output_file}...")
    
    count = 0
    with open(output_file, 'w', encoding='utf-8') as out_f:
        # Use bz2 to open the compressed file
        with bz2.open(input_file, 'rt', encoding='utf-8') as bz2_f:
            # We use a streaming XML parser because dumps are huge
            context = ET.iterparse(bz2_f, events=('end',))
            
            for event, elem in context:
                if elem.tag.endswith('page'):
                    # Found a page
                    ns_elem = elem.find(elem.tag.replace('page', 'ns'))
                    # ns=0 is main article namespace
                    if ns_elem is not None and ns_elem.text == '0':
                        res_elem = elem.find(elem.tag.replace('page', 'revision'))
                        if res_elem:
                            text_elem = res_elem.find(res_elem.tag.replace('revision', 'text'))
                            if text_elem is not None and text_elem.text:
                                plain = clean_text(text_elem.text)
                                if len(plain) > 100: # Skip very short articles
                                    # Write sentences or paragraphs?
                                    # For N-grams/DeepPath, phrases are good.
                                    # Let's write one "article" per line or just raw text.
                                    # N-gram trainer expects "one phrase per line".
                                    # Let's strict to sentences approx.
                                    # Splitting by . is crude but okay for MVP.
                                    for sentence in plain.split('. '):
                                        if len(sentence) > 10:
                                            out_f.write(sentence.strip() + '\n')
                                    
                                    count += 1
                                    if count % 1000 == 0:
                                        print(f"  Processed {count} articles...", end='\r')
                                    
                                    if limit and count >= limit:
                                        break
                    
                    # Clear element to free memory
                    elem.clear()
                    
    print(f"\nDone. Processed {count} articles.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--limit', type=int, default=None, help="Max articles to extract")
    args = parser.parse_args()
    
    extract_dump(args.input, args.output, args.limit)
