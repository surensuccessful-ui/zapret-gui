# Changelog

Версии **всего репозитория** (исходники, GUI, документация) хранятся git-тегами `vX.Y.Z`. Это не только EXE: по тегу можно вернуть проект целиком.

## Как вернуться к версии

```powershell
git fetch --tags
git checkout v1.0.20
```

Снова на последнюю:

```powershell
git checkout main
```

Список снимков: `git tag`. Архив исходников тега на GitHub: `https://github.com/surensuccessful-ui/zapret-gui/archive/refs/tags/v1.0.20.zip`

Номер оболочки в файле `VERSION` должен совпадать с тегом.

---

## 1.0.23

- Кнопка «О программе» под настройками: версия оболочки, дата выпуска, разработчик
- Раз в сутки GUI проверяет свой релиз на GitHub и предлагает скачать обновление с прогрессом

## 1.0.22

- Окно «Тест сайтов»: свои URL проверяются всеми стратегиями
- После добавления сайта открывается это окно с уже подставленным доменом
- Служба zapret на время теста останавливается и потом возвращается

## 1.0.20

Первый публичный снимок проекта и релиз `ZapretGUI.exe`. Тег: **v1.0.20**.

- Оболочка для Flowseal zapret-discord-youtube
- Служба, трей, автозапуск, живые проверки Discord/YouTube
- Пользовательские списки сайтов
- [Dr.Web](https://online620.drweb.com/cache/?i=c64a838b7e8e177de6f4f68301d567cf) / [VirusTotal](https://www.virustotal.com/gui/file/a8046c2ef24cc9b91bec7d1df2425d70872f7376bb31432f00ac4d8a2bc65e09) для EXE релиза

Последующие коммиты на `main` до 1.0.22 меняли README, лицензию и скриншоты, не номер GUI.

---

# English

Tags `vX.Y.Z` snapshot the **whole repo**, not only the packaged EXE. Restore with `git checkout v1.0.20`. The wrapper number in `VERSION` must match the tag.

## 1.0.23

- About button under Settings: wrapper version, release date, developer
- Daily self-update check against the GitHub GUI release, with download progress
