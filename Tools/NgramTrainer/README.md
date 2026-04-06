# N-gram Training Tool

Offline tooling for generating trigram language models for RightLayout's layout-aware detection.

## Overview

This tool processes text corpora and generates trigram frequency models with add-k smoothing, exported as JSON files that can be loaded by the Swift application.

## Usage

### Training a Model

```bash
python train_ngrams.py --lang {ru|en|he} --input corpus.txt --output model.json
```

**Arguments:**
- `--lang`: Language code (`ru` for Russian, `en` for English, `he` for Hebrew)
- `--input`: Path to input corpus file (UTF-8 text, one phrase per line)
- `--output`: Path for output JSON model file
- `--smoothing-k`: Optional smoothing parameter (default: 1.0)

### Example

```bash
# Train Russian model
python train_ngrams.py --lang ru --input corpora/ru_sample.txt --output ../../RightLayout/Resources/LanguageModels/ru_trigrams.json

# Train English model
python train_ngrams.py --lang en --input corpora/en_sample.txt --output ../../RightLayout/Resources/LanguageModels/en_trigrams.json

# Train Hebrew model
python train_ngrams.py --lang he --input corpora/he_sample.txt --output ../../RightLayout/Resources/LanguageModels/he_trigrams.json
```

## Corpus Format

Input corpora should be UTF-8 text files with one phrase per line:

```
привет мир
доброе утро
спасибо большое
...
```

## Output Format

The tool generates JSON files with the following structure:

```json
{
  "lang": "ru",
  "n": 3,
  "version": 1,
  "smoothing_k": 1.0,
  "total_count": 12345,
  "unique_trigrams": 5678,
  "trigrams": {
    "три": -2.54,
    "риг": -3.12,
    ...
  }
}
```

## Corpus Sources

Current sample corpora (`corpora/` directory) contain common words and phrases:

- **Russian**: 200+ common words, greetings, everyday phrases
- **English**: 250+ common words, conversational phrases
- **Hebrew**: 200+ common words, greetings, everyday phrases

### For Production Models

To create larger, more comprehensive models:

1. **Wikipedia dumps** (permissive license):
   - Download language-specific Wikipedia XML dumps
   - Extract plain text using tools like WikiExtractor
   
2. **Open subtitle corpora**:
   - OPUS open subtitles: https://opus.nlpl.eu/OpenSubtitles.php
   
3. **Common Crawl** (for English):
   - Filtered web text: https://commoncrawl.org/

4. **Frequency word lists**:
   - Hermit Dave frequency lists: https://github.com/hermitdave/FrequencyWords

### Licensing Note

Ensure all corpus sources have permissive licenses compatible with RightLayout's distribution. Current sample corpora use public domain common phrases.

## Regenerating Models

To update the models in the main app:

```bash
cd Tools/NgramTrainer

# Train all three languages
python train_ngrams.py --lang ru --input corpora/ru_sample.txt --output ../../RightLayout/Resources/LanguageModels/ru_trigrams.json
python train_ngrams.py --lang en --input corpora/en_sample.txt --output ../../RightLayout/Resources/LanguageModels/en_trigrams.json  
python train_ngrams.py --lang he --input corpora/he_sample.txt --output ../../RightLayout/Resources/LanguageModels/he_trigrams.json

# Rebuild app
cd ../..
swift build
```

## Technical Details

### Normalization

Text is normalized before processing:
- Converted to lowercase
- Filtered to language-specific letter ranges only
  - Russian: Cyrillic (U+0410-044F, ё)
  - English: Latin (a-z)
  - Hebrew: Hebrew alphabet (U+0590-05FF)

### Frequency Calculation

Trigrams are extracted using a sliding window over normalized text. Frequencies are computed with add-k smoothing:

```
P(trigram) = (count + k) / (total_trigrams + k × vocab_size)
log_P = log(P)
```

Default: k = 1.0

### Model Size

Expected model sizes:
- Sample corpora: 50-100 KB per language
- Production corpora (30-40K trigrams): 300KB - 1MB per language
- Total for all three languages: ~1-3 MB

## Requirements

- Python 3.8+
- No external dependencies (uses standard library only)
