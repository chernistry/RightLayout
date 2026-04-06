# CoreML Classifier Training Pipeline

Этот пайплайн обучает нейросеть для определения языка и раскладки клавиатуры.

## 🎯 Что делает эта модель?

Модель определяет, на каком языке и какой раскладке был набран текст. Например:
- `"hello"` → английский (правильная раскладка)
- `"руддщ"` → английский, набранный на русской раскладке (должно быть "hello")
- `"ghbdtn"` → русский, набранный на английской раскладке (должно быть "привет")

## 📋 Быстрый старт (для MVP)

Если вам нужна **базовая модель прямо сейчас**:

```bash
cd Tools/CoreMLTrainer
./train_quick.sh
```

Это создаст модель на синтетических данных (~5 минут).

## 🚀 Полный пайплайн (для production)

Для **качественной модели** на реальных данных:

```bash
cd Tools/CoreMLTrainer
./train_full.sh
```

Это займет ~30-60 минут и включает:
1. Скачивание Wikipedia корпусов (RU/EN/HE)
2. Генерацию большого датасета
3. Обучение модели
4. Экспорт в CoreML

## 📁 Что внутри?

### Скрипты:
- `generate_data.py` — генерирует тренировочные данные
- `train.py` — обучает PyTorch модель
- `export.py` — конвертирует в CoreML
- `download_corpus.py` — скачивает Wikipedia (TODO)

### Результаты:
- `training_data.csv` — датасет для обучения
- `model.pth` — обученная PyTorch модель
- `LayoutClassifier.mlmodel` — финальная CoreML модель

## 🔧 Ручной запуск (шаг за шагом)

### 1. Установка зависимостей
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Генерация данных
```bash
# Быстрый вариант (10K примеров, синтетика)
python3 generate_data.py --count 10000 --output training_data.csv

# Полный вариант (100K примеров, нужен корпус)
# python3 download_corpus.py  # TODO: не реализовано
python3 generate_data.py --count 100000 --output training_data.csv
```

### 3. Обучение модели
```bash
# 5 эпох (быстро, для теста)
python3 train.py --epochs 5 --data training_data.csv --model_out model.pth

# 20 эпох (лучше качество)
python3 train.py --epochs 20 --data training_data.csv --model_out model.pth
```

### 4. Экспорт в CoreML
```bash
python3 export.py --model_in model.pth --output LayoutClassifier.mlmodel
```

### 5. Копирование в проект
```bash
cp LayoutClassifier.mlmodel ../../RightLayout/Sources/Resources/
```

## ✅ Проверка

После обучения запустите тесты:
```bash
cd ../..
swift test --filter CoreMLLayoutClassifierTests
```

Вы должны увидеть:
```
✔ Test run with 3 tests passed
Prediction for 'test': en conf: 0.999...
```

## 📊 Текущее состояние

**Сейчас используется**: Синтетическая модель на 10K примеров (~50 слов/язык).

**Для production нужно**:
1. Реализовать `download_corpus.py` для скачивания Wikipedia
2. Увеличить датасет до 100K+ примеров
3. Переобучить с 20+ эпохами

## 🐛 Troubleshooting

**Ошибка: "Model not found"**
→ Убедитесь, что `LayoutClassifier.mlmodel` скопирован в `RightLayout/Sources/Resources/`

**Ошибка: "Module not found"**
→ Активируйте venv: `source venv/bin/activate`

**Низкая точность**
→ Увеличьте `--count` и `--epochs`, используйте реальные корпуса
