# Локальные модели: от ноутбука до арендованной GPU

Материалы воркшопа: команды, скрипты и замеры. Всё ниже воспроизводимо. Движок — [llama.cpp](https://github.com/ggml-org/llama.cpp) (сборка b12317), агент — [Pi](https://github.com/earendil-works/pi) (coding agent).

| Что | Где |
|---|---|
| Модель «плотная» | Qwen3.8-27B, Q4_K_M, 19,0 ГБ ([ggml-org/Qwen3.8-27B-GGUF](https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF)) |
| Модель MoE | Qwen3.8-Flash-Next, UD-IQ4_XS, 93,7 ГБ в 4 файлах ([unsloth/Qwen3.8-Flash-Next-GGUF](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF)) |
| Ноутбук | MacBook Pro M3 Max, 128 ГБ |
| Облако | [Vast.ai](https://vast.ai), RTX PRO 6000 Blackwell 96 ГБ, около $1,3–2,5 в час |

## 1. Модель на Маке

```bash
# движок: готовая сборка (или brew install llama.cpp)
mkdir -p ~/workshop/bin ~/workshop/models
curl -fL https://github.com/ggml-org/llama.cpp/releases/download/b12317/llama-b12317-bin-macos-arm64.tar.gz | tar xz -C ~/workshop/bin
xattr -dr com.apple.quarantine ~/workshop/bin

# модель
curl -fL -C - -o ~/workshop/models/Qwen3.8-27B-Q4_K_M.gguf \
  https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-Q4_K_M.gguf

# сервер с OpenAI-совместимым API на :8080
~/workshop/bin/llama-b12317/llama-server -m ~/workshop/models/Qwen3.8-27B-Q4_K_M.gguf \
  -c 262144 -np 1 -ngl 999 -fa on -ctk q8_0 -ctv q8_0 --jinja \
  --host 127.0.0.1 --port 8080 --slot-save-path ~/workshop/slots --metrics
```

Флаги:
- `-c` — размер контекста;
- `-np` — число параллельных слотов, контекст делится между ними;
- `-ngl 999` — все слои на GPU;
- `-fa on` — flash attention;
- `-ctk/-ctv q8_0` — KV-кэш в 8 битах, вдвое меньше памяти;
- `--jinja` — шаблон чата из модели, нужен для инструментов;
- `--slot-save-path` — каталог для сохранения контекста на диск.

Pi подключается через `~/.pi/agent/models.json`. Готовый файл с четырьмя провайдерами лежит в [`config/pi-models.json`](config/pi-models.json):

```json
{ "providers": { "ws-mac": {
  "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions", "apiKey": "none",
  "compat": { "supportsDeveloperRole": false, "supportsReasoningEffort": false },
  "models": [ { "id": "qwen27b", "reasoning": true, "contextWindow": 262144, "maxTokens": 32768 } ] } } }
```

```bash
pi --provider ws-mac --model qwen27b
```

**Подвох macOS:** сервер, запущенный фоновым процессом (launchd, агентом, `taskpolicy -b`), получает приоритет 4 вместо 31 и работает до двух раз медленнее. Запускайте из обычного терминала или tmux и проверяйте: `ps -o pri= -p $(pgrep -n llama-server)` должно показать 31.

## 2. Длинный контекст и прогретые сессии

На M3 Max модель читает 200 тыс. токенов около 51 минуты. Но состояние модели — это просто файл. Его можно посчитать на GPU за пару минут, скачать и поднять на ноутбуке за секунды:

```bash
curl -X POST 'localhost:8080/slots/0?action=save'    -d '{"filename":"s200k.bin"}'   # на GPU
curl -X POST 'localhost:8080/slots/0?action=restore' -d '{"filename":"s200k.bin"}'   # на Маке
```

Чтобы восстановленный слот совпал со следующим запросом агента токен в токен, есть [`scripts/ws.py`](scripts/ws.py):
- `capture` перехватывает точный запрос Pi;
- `warm` считает ровно его префикс и сохраняет слот;
- `ask` проверяет: после восстановления сервер должен прочитать только новый вопрос.

Весь цикл — [`scripts/build-session.sh`](scripts/build-session.sh).

Что ломает совпадение:
- всё, что меняется в начале промпта: дата, рабочий каталог (Pi пишет его в системный промпт), версия агента, набор инструментов;
- автокомпакция: выключается в `.pi/settings.json`, `{"compaction": {"enabled": false}}`;
- другая сборка llama.cpp, другой файл модели или тип KV;
- у гибридных моделей (Qwen3.8 с Gated DeltaNet) рекуррентное состояние нельзя откатить на токен назад: любое расхождение — и весь контекст перечитывается заново.

## 3. MoE: Qwen3.8-Flash-Next

Параметров 125 млрд плюс таблица n-грамм на 51 млрд; на токен активны 6,7 млрд. Внимание разреженное (QSA, 2048 позиций), родной контекст 262 144 токена.
- На GPU уходят файлы 1–3, ~65 ГБ. Файл 4 — таблица n-грамм, 28,8 ГБ; llama.cpp держит её в обычной RAM.
- Контекст стоит ~18 КБ на токен: 200 тыс. — 3,6 ГБ.
- В 96 ГБ модель помещается целиком, и ещё остаётся место на несколько длинных сессий.

```bash
llama-server -m Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf -c 262144 -np 1 -ngl 999 -fa on -ctk q8_0 -ctv q8_0 --jinja --port 8080
```

## 4. Облако: Vast.ai

1. Регистрация на vast.ai, пополнение картой или криптой, SSH-ключ в Account → Keys.
2. Поиск: RTX PRO 6000, `on-demand` (не interruptible), надёжность ≥ 0,98, диск ≥ 260 ГБ, канал ≥ 1 Гбит/с. Образ — `vastai/base-image` с CUDA 12.8.
3. На машине:
   ```bash
   # скопировать scripts/ на машину, затем
   bash scripts/node-setup.sh                 # готовая сборка llama.cpp + модели, ~5-10 минут
   bash scripts/node-serve.sh flashnext-par 6 # 6 параллельных слотов по 131k
   ```
4. С ноутбука — туннель. Сервер слушает только localhost машины, наружу ничего не открыто:
   ```bash
   ssh -N -L 8081:127.0.0.1:8080 -p <port> root@<ip>
   pi --provider ws-vast --model flashnext
   ```
5. Четыре агента параллельно: `scripts/air-cloud.sh grid` (tmux 2×2), задания в [`prompts/`](prompts/), результаты репетиции в [`examples/`](examples/).

Проверяйте канал узла сами: заявленные на бирже цифры не гарантия. Наш первый узел обещал 1,4 Гбит/с, а отдавал 0,5 МБ/с.

## Замеры

Все цифры — llama.cpp, Q4-кванты, KV q8_0.

| Машина, модель | Короткий контекст: декод | 200k: декод | 200k: заполнить с нуля |
|---|---|---|---|
| M3 Max 128 ГБ, Qwen3.8-27B | 15,0 ток/с | 7,8 ток/с | 50,8 мин |
| M5 Max 64 ГБ, Qwen3.8-27B | 23,3 ток/с | 11,1 ток/с | ~12–15 мин (оценка по замерам) |
| RTX PRO 6000, Qwen3.8-27B | 63,8 ток/с | 37,7 ток/с | ~2 мин |
| RTX PRO 6000, Flash-Next | 111,6 ток/с | 56,5 ток/с | 56 с |

- Flash-Next на RTX PRO 6000 параллельно: 4 потока — 261 ток/с суммарно, 6 потоков — 314.
- M3 Max на 524 тыс. токенов (Qwen3.8-27B, YaRN): декод 3,84 ток/с, вопрос в 690 токенов читается 48 с.
- Восстановить слот на 200k: 8 ГБ за 1,4 с на GPU.

### Прогон 12 ноября 2026 (M3 Max + RTX PRO 6000 в Чехии)

- Сессия Pi на 206 252 токена (исходники llama.cpp) заполнена на GPU за 110 с: 1 886 ток/с. Слот 7,66 ГБ.
- Слот скачан на Мак по 5G (~16 МБ/с) и поднят за 2,0 с.
- Следующий вопрос Pi сервер прочитал за 22 токена, а не за 206 тысяч. Генерация на Маке ~9 ток/с.
- Тот же Мак прочитал бы этот контекст сам примерно за 51 минуту.
- Четыре агента Pi на Flash-Next параллельно написали четыре лендинга за 4–6 минут, ~65 ток/с на поток.

В репозитории нет секретов, имён хостов и IP-адресов.
