#!/usr/bin/env bash
# ВЫУЧИТЬ ПЕСНЮ В ФОНД ДОМА — приказ владельца 2026-11-16: контент (песни/видео) живёт ТОЛЬКО в репозитории.
# Использование: vyuchit_pesnyu.sh <id> <файл.mp3|m4a|opus|webm> [тег_релиза]
#   пример: vyuchit_pesnyu.sh 4j1GG_X7zHw eto-ne-sekret.m4a
# Что делает:
#   1) ffprobe — честная проверка исходника (частота, каналы, битрейт)
#   2) транскод по закону RUM23-7: MP3 CBR 128 кбит/с 48 кГц стерео, без фейковых 320
#   3) SHA256 → релиз-ассет GOLOS-FOND-2026-11-15 (дверь-0 дома: minus/голос/)
#   4) __SHA256SUMS.txt: строка добавлена/заменена, манифест перезалит
#   5) dispatch pages.yml — пересборка выкладки (материализация minus/голос/ + деплой)
# Нужны: ffmpeg, ffprobe, curl, jq; TOKEN с repo-скоупом (env GH_TOKEN)
set -euo pipefail
ID="${1:?нет id песни}"; SRC="${2:?нет файла}"; TAG="${3:-GOLOS-FOND-2026-11-15}"
REPO="rtynbirf/singulyar"
T="${GH_TOKEN:?нет GH_TOKEN}"
H="Authorization: token $T"

command -v ffmpeg >/dev/null || { echo "нет ffmpeg"; exit 1; }
[ -f "$SRC" ] || { echo "нет файла $SRC"; exit 1; }

echo "── 1) ffprobe исходника"
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels,bit_rate -of default=nw=1 "$SRC"

echo "── 2) транскод RUM23-7 (MP3 CBR 128k, 48 кГц, стерео)"
OUT="${ID}.mp3"
ffmpeg -y -v error -i "$SRC" -ar 48000 -ac 2 -c:a libmp3lame -b:a 128k "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1 "$OUT"

echo "── 3) SHA256 и загрузка релиз-ассета"
SUM=$(sha256sum "$OUT" | cut -d' ' -f1)
REL=$(curl -sS -H "$H" "https://api.github.com/repos/$REPO/releases/tags/$TAG")
REL_ID=$(echo "$REL" | jq -r '.id'); [ "$REL_ID" != "null" ] || { echo "релиз $TAG не найден"; exit 1; }
UP=$(curl -sS -H "$H" -H "Content-Type: audio/mpeg" --data-binary @"$OUT" \
  "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$OUT")
A_URL=$(echo "$UP" | jq -r '.browser_download_url')
echo "   ассет: $A_URL"

echo "── 4) манифест __SHA256SUMS.txt"
curl -sSL -H "$H" -o /tmp/sums.txt "https://github.com/$REPO/releases/download/$TAG/__SHA256SUMS.txt"
grep -v " $OUT\$" /tmp/sums.txt > /tmp/sums_new.txt || true
echo "$SUM  $OUT" >> /tmp/sums_new.txt
OLD_ID=$(echo "$REL" | jq -r '.assets[] | select(.name=="__SHA256SUMS.txt") | .id')
[ "$OLD_ID" != "null" ] && curl -sS -X DELETE -H "$H" "https://api.github.com/repos/$REPO/releases/assets/$OLD_ID" -o /dev/null
curl -sS -H "$H" -H "Content-Type: text/plain" --data-binary @/tmp/sums_new.txt \
  "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=__SHA256SUMS.txt" | jq -r '.name'

echo "── 5) dispatch pages.yml (пересборка двери-0)"
curl -sS -X POST -H "$H" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/actions/workflows/pages.yml/dispatches" \
  -d '{"ref":"rumu"}' -o /dev/null -w "   HTTP %{http_code} (204 = запущена)\n"
echo "ГОТОВО: песня $ID выучена в фонд; через ~2 минуты дверь-0 same-origin ответит."
echo "Проверка: curl -I https://rtynbirf.github.io/singulyar/minus/%D0%B3%D0%BE%D0%BB%D0%BE%D1%81/$ID.mp3"
