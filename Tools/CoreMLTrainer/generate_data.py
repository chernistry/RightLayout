import json
import random
import os
import argparse

# Seed lexicons for MVP (Top ~50 words per language to capture reasonable N-grams)
# In a real production run, download_corpus.py would populate these.
# UPDATED: Added common conversational/slang/profanity words that might be missing from formal Wikipedia data.
COMMON_SEEDS = {
    "en": "hello hi lol ok wow thanks yes no maybe please sorry bro dude wtf omg idc idk u r ur".split(),
    "ru": "привет пока да нет ок спс пж лол кек сука блять нахуй пиздец говно залупа мудак педрило ебок привет как дела че кого хах".split(),
    "he": "שלום היי ביי טוב לא כן תודה בבקשה סבבה יאללה אח שלי חיים כפרה זין מניאק שרמוטה בן זונה".split()
}

SEEDS = {
    "en": "the be to of and a in that have I it for not on with he as you do at this but his by from they we say her she or an will my one all would there their what so up out if about who get which go me when make can like time no just him know take people into year your good some could them see other than then now look only come its over think also back after use two how our work first well way even new want because any these give day most us".split() + COMMON_SEEDS["en"],
    "ru": "и в не на я быть с он что а этот к это по ты они мы она который то из но все у за свой же весь год вы мочь человек о один такой какой только себя ее тот как сказать дело сам для когда очень время вот чтобы до место иметь раз если жизнь уж под где ни слово быть даже идти там мочь сейчас лицо друг глаз теперь тоже здесь кто потом стать ли ничто работа дом надо голова стоять первый".split() + COMMON_SEEDS["ru"],
    "he": "את ב של לא ה ל זה כי גם היה עם על אני מה כן אם הוא כל אבל יש לא רק או מי זה אתה איך מתי איפה שם כאן למה מי היה כדי פעם תמיד טוב יום בית איש דבר עולם חיים משפחה אהבה זמן עכשיו יותר מאוד רוצה צריך יכול עושה רואה יודע חושב אומר בא דרך מים לחם שמש ירח ארץ עיר ספר ילד".split() + COMMON_SEEDS["he"]
}

CLASSES = [
    'ru', 'en', 'he',
    'ru_from_en', 'he_from_en',
    'en_from_ru', 'en_from_he',
    'he_from_ru', 'ru_from_he'
]

def load_layout_map(json_path, focus_layout=None):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # We need to build char->char maps for layout conversion.
    # Map key: (source_layout, target_layout) -> {source_char: target_char}
    
    # Primary layouts to use
    # Primary layouts to use (Lists to support multiple variants)
    layouts = {
        'en': ['en_us'],
        'ru': ['ru_pc', 'ru_phonetic_yasherty'],
        'he': ['he_standard', 'he_qwerty', 'he_pc'] # Support ALL common Hebrew layouts
    }

    if focus_layout:
        focus_lang = focus_layout.split('_', 1)[0] if '_' in focus_layout else focus_layout
        if focus_lang in layouts and focus_layout in layouts[focus_lang]:
            layouts[focus_lang] = [focus_layout]
        else:
            print(f"Warning: focus layout '{focus_layout}' not found in presets, ignoring")
    
    maps = {}
    
    key_map = data['map']
    
    def get_char(k, l_id, mod='n'):
        val = key_map.get(k, {}).get(l_id, {})
        if val:
            return val.get(mod)
        return None

    # Build maps between all pairs
    # Since we have lists of layouts, we generate a map for each specific layout pair
    # and store them in a list under the language pair key.
    
    for src_lang, src_layout_list in layouts.items():
        for tgt_lang, tgt_layout_list in layouts.items():
            if src_lang == tgt_lang: continue
            
            # We want to support: User intends src_lang, but is typing on tgt_layout.
            # Wait, the class naming is "tgt_from_src" (e.g., "ru_from_en").
            # This means: "Detected as RU, but coming from EN layout input".
            # My logic in generate_sample:
            # intended_lang = ru
            # typed_layout_lang = en
            # We need map: RU -> EN.
            # i.e., what keys does user press to type RU word?
            # And what characters do those keys produce on EN layout?
            
            # The user presses a physical key.
            # If user intends RU (e.g. "привет"), they press keys G, H, ...
            # Wait. "привет" is typed on `ru_pc`.
            # Keys: G (п), H (р), B (и), ...
            # Make sure we use the CORRECT RU layout they utilize.
            # If they use `ru_pc`, they press `KeyG`.
            # If they are on `en_us` layout, `KeyG` produces `g`.
            
            # So, for each possible intended layout (e.g. `ru_pc`):
            # And each possible actual layout (e.g. `en_us`):
            # We create a map.
            
            pair_key = f"{tgt_lang}_from_{src_lang}" # e.g. en_from_ru (EN chars from RU intention)
            
            if pair_key not in maps:
                maps[pair_key] = []
            
            for s_layout in src_layout_list:
                for t_layout in tgt_layout_list:
                    
                    mapping = {}
                    for key_code in key_map:
                        # Character produced by key in INTENDED layout (s_layout)
                        # This works backwards:
                        # We have intended char (e.g. 'п').
                        # We find key code that produces it in s_layout (KeyG).
                        # We find char produced by that key code in t_layout ('g').
                        
                        # Optimization: Layouts.json map is Key -> Layout -> Char.
                        # So for each KEY, we map s_char -> t_char
                        
                        # Normal
                        s_char = get_char(key_code, s_layout, 'n')
                        t_char = get_char(key_code, t_layout, 'n')
                        if s_char and t_char:
                            mapping[s_char] = t_char
                        
                        # Shift
                        s_char_s = get_char(key_code, s_layout, 's')
                        t_char_s = get_char(key_code, t_layout, 's')
                        if s_char_s and t_char_s:
                            mapping[s_char_s] = t_char_s
                    
                    maps[pair_key].append(mapping)
            
    return maps

def convert_text(text, mapping):
    return "".join(mapping.get(c, c) for c in text)

def generate_sample(class_name, maps, max_phrase_len=3):
    # Determine source language and transformation
    if class_name in ['ru', 'en', 'he']:
        src_lang = class_name
        num_words = random.randint(1, max_phrase_len)
        words = [random.choice(SEEDS[src_lang]) for _ in range(num_words)]
        return " ".join(words), class_name
    
    parts = class_name.split('_from_')
    intended_lang, typed_layout_lang = parts[0], parts[1]
    map_key = f"{typed_layout_lang}_from_{intended_lang}"
    available_maps = maps.get(map_key, [])
    
    if not available_maps:
        return "x", class_name
        
    mapping = random.choice(available_maps)
    num_words = random.randint(1, max_phrase_len)
    words = [random.choice(SEEDS[intended_lang]) for _ in range(num_words)]
    text = " ".join(words)
    converted = convert_text(text, mapping)
    return converted, class_name

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='training_data.csv')
    parser.add_argument('--count', type=int, default=1000000)
    parser.add_argument('--layouts', default='../../.sdd/layouts.json')
    parser.add_argument('--corpus_dir', default=None, help="Directory with {lang}.txt corpus files")
    parser.add_argument(
        '--max-corpus-words',
        type=int,
        default=500_000,
        help="Max words to load per language from corpus files (keeps RAM bounded). Set 0 to load all (slow, high memory).",
    )
    parser.add_argument(
        '--corpus-sample-mode',
        choices=['head', 'reservoir'],
        default='reservoir',
        help="How to sample words from large corpora when --max-corpus-words > 0. "
             "'head' reads the first N words (fast, biased). "
             "'reservoir' does one pass and keeps a uniform random sample (slower, higher quality).",
    )
    parser.add_argument('--balance', type=float, default=0.5, help="Ratio of pure language samples (vs _from_ samples)")
    parser.add_argument('--max-phrase-len', type=int, default=3, help="Max words per sample")
    parser.add_argument(
        '--focus-layout',
        default=None,
        help="Focus generation on a specific layout variant (e.g. he_qwerty). When set, only classes involving that language are generated.",
    )
    args = parser.parse_args()
    
    maps = load_layout_map(args.layouts, focus_layout=args.focus_layout)
    
    # Load corpus words if provided
    if args.corpus_dir:
        print(f"Loading corpus from {args.corpus_dir}...")
        for lang in ['ru', 'en', 'he']:
            path = os.path.join(args.corpus_dir, f"{lang}.txt")
            if os.path.exists(path):
                print(f"  Loading {lang}.txt...", end='', flush=True)
                with open(path, 'r', encoding='utf-8') as f:
                    words = []
                    max_words = args.max_corpus_words or 0
                    if max_words and args.corpus_sample_mode == 'reservoir':
                        seen = 0
                        for line in f:
                            for p in line.strip().split():
                                # Include 2-letter words; they're important for HE (e.g. מה, לא) and short EN/RU tokens.
                                if 2 <= len(p) < 20:
                                    seen += 1
                                    if len(words) < max_words:
                                        words.append(p)
                                    else:
                                        j = random.randint(0, seen - 1)
                                        if j < max_words:
                                            words[j] = p
                    else:
                        # Fast path: take the first N acceptable words.
                        for line in f:
                            for p in line.strip().split():
                                if 2 <= len(p) < 20:
                                    words.append(p)
                                    if max_words and len(words) >= max_words:
                                        break
                            if max_words and len(words) >= max_words:
                                break
                    if words:
                        SEEDS[lang] = words
                        if args.max_corpus_words and len(words) >= args.max_corpus_words:
                            note = "sampled" if args.corpus_sample_mode == 'reservoir' else "capped"
                            print(f" {len(words)} words loaded ({note}).")
                        else:
                            print(f" {len(words)} words loaded.")
                    else:
                        print(" Empty or error.")
            else:
                print(f"  Warning: {path} not found. Using default seeds.")
    
    # Balanced class selection
    pure_classes = ['ru', 'en', 'he']
    from_classes = [c for c in CLASSES if '_from_' in c]

    if args.focus_layout:
        focus = args.focus_layout
        # Currently only language-specific focus is supported via layout prefix.
        # Example: he_qwerty -> focus on Hebrew-related classes.
        focus_lang = focus.split('_', 1)[0] if '_' in focus else focus
        if focus_lang in ['ru', 'en', 'he']:
            pure_classes = [focus_lang]
            focused_from = []
            for c in from_classes:
                intended, typed = c.split('_from_')
                if intended == focus_lang or typed == focus_lang:
                    focused_from.append(c)
            from_classes = focused_from
            print(f"Focus mode: {focus} -> classes: pure={pure_classes} from={len(from_classes)}")
        else:
            print(f"Warning: unknown focus layout '{focus}', ignoring focus mode")
    
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write("text,label\n")
        for i in range(args.count):
            # Balance: args.balance chance of pure, (1-args.balance) chance of _from_
            if random.random() < args.balance:
                cls = random.choice(pure_classes)
            else:
                cls = random.choice(from_classes)
            
            text, label = generate_sample(cls, maps, args.max_phrase_len)
            if ',' in text or '"' in text:
                text = f'"{text.replace(chr(34), chr(34)+chr(34))}"'
            f.write(f"{text},{label}\n")
            
            if (i + 1) % 100000 == 0:
                print(f"  Generated {i+1}/{args.count}...")
            
    print(f"Generated {args.count} samples to {args.output}")

if __name__ == "__main__":
    main()
