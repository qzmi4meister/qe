# Выпуск QE

Релизы собираются на Apple Silicon с macOS 26 и Command Line Tools с SDK macOS 26 (Swift 6.2+). В `VERSION` хранится версия вида `0.2.1`; тег — `v0.2.1`.

## Проверить и упаковать

1. Обновите `VERSION` и документацию, запустите `./scripts/check.sh`.
2. Зафиксируйте изменения в Git и отправьте `main`. Дождитесь успешного CI.
3. Запустите `./scripts/release.sh` из чистого checkout того коммита, который будет помечен тегом.

Скрипт собирает приложение отдельно от `dist/QE.app`, проверяет ad-hoc подпись и создаёт:

- `dist/QE-<версия>-arm64.zip` — приложение с иконкой и MIT License;
- `dist/SHA256SUMS` — SHA-256 архива.

Существующий ZIP скрипт не перезаписывает. Уже опубликованные архивы менять нельзя: исправления выпускаются с новой версией. Для повторения неопубликованной сборки сначала уберите прежний ZIP из `dist`.

## Опубликовать через GitHub CLI

Подготовьте описание изменений в `.build/release-notes.md`. Затем:

```sh
version=$(cat VERSION)
git tag -a "v$version" -m "QE $version"
git push origin "v$version"
gh release create "v$version" \
  "dist/QE-$version-arm64.zip" dist/SHA256SUMS \
  --verify-tag --draft --title "QE $version" \
  --notes-file .build/release-notes.md
```

Проверьте описание и оба файла в черновике. Опубликуйте:

```sh
gh release edit "v$version" --draft=false --latest
```

У этой сборки нет Developer ID и нотарификации. Указывайте это в описании релиза и сохраняйте инструкцию первого запуска в README. Не отключайте Gatekeeper в установщике.

## Обновить Homebrew

В [qzmi4meister/homebrew-tap](https://github.com/qzmi4meister/homebrew-tap) обновите `version` и `sha256` в `Casks/qe.rb`. Контрольную сумму возьмите из `dist/SHA256SUMS`; URL вычисляется из версии.

Проверка опубликованного обновления:

```sh
brew update
brew audit --cask qzmi4meister/tap/qe
brew fetch --cask qzmi4meister/tap/qe
brew install --cask qzmi4meister/tap/qe
open -a QE
```

Если QE уже установлен, вместо `install` используйте `upgrade`. Проверьте версию через «О QE». Cask требует macOS 26 и Apple Silicon; ZIP должен содержать `QE.app` в корне. Остальные cask-файлы tap при выпуске QE менять не требуется.
