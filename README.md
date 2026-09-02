# ZAPRET GUI

**EN:** A fork of original [zapret](https://github.com/bol-van/zapret) with a Windows 10/11 GUI. The runtime pack is [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube). This GUI does not patch official strategies: it connects a zapret folder, installs the chosen strategy as a Windows service, and checks Discord and YouTube.

**RU:** Форк оригинального [zapret](https://github.com/bol-van/zapret) с графической оболочкой для Windows 10/11. В качестве сборки используется [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube). Сама программа не меняет стратегии zapret: она подключает папку zapret, ставит выбранную стратегию как службу Windows и помогает проверить Discord и YouTube.

Python is not required. / Python не нужен.

---

## Download / Скачать

Latest Windows build (Win10/Win11): see **[Releases](https://github.com/surensuccessful-ui/zapret-gui/releases/latest)**.

Friends only need `ZapretGUI.exe`. Zapret itself is downloaded or selected on first run.

Друзьям достаточно `ZapretGUI.exe`. Папку zapret программа найдёт, скачает или предложит указать самой.

Windows SmartScreen may warn because the file is unsigned. Choose **More info → Run anyway**.

Windows SmartScreen может показать предупреждение: файл не подписан. Выберите **«Подробнее» → «Выполнить в любом случае»**.

---

## English

### What this is

ZAPRET GUI is a **fork of original [zapret](https://github.com/bol-van/zapret)** (by bol-van). On Windows it uses the [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) package as the engine.

The GUI itself is a wrapper only. It never edits `general*.bat`, `service.bat`, or other files inside the zapret package (GitHub updates overwrite those). Extra sites go into zapret **user lists** (`lists\list-general-user.txt` and other `*user*.txt` files).

### Requirements

- Windows 10 or 11
- Administrator rights (UAC). The GUI needs them to install and control the `zapret` service.

### Run

1. Start `ZapretGUI.exe` and accept UAC.
2. Only one copy can run. A second launch shows that the program is already open.
3. On launch the GUI enables Windows startup: **ZAPRET GUI** in Task Manager → Startup, plus scheduled task `ZapretGUI` with highest privileges so logon does not show UAC again. After sign-in the GUI opens in the tray. Bypass still comes from the `zapret` service.
4. Prompts (download zapret, run tests, errors) use dark Discord-style dialogs.
5. The close button hides the window to the tray. Bypass keeps running. Use **Exit** in the tray menu to quit the GUI.

Closing the GUI **does not** stop the zapret service.

### First run

The program checks saved settings and whether a zapret folder is next to the EXE or at the saved path.

If zapret is missing:

- **Yes** — download the latest official Flowseal build from GitHub
- **No** — pick an existing folder
- **Cancel** — open the GUI without zapret and set it up later

After a folder is connected, the GUI can test all strategies, pick the best one (at least one successful target check), and install it as a Windows service with automatic start. You can skip this and do it later with **Auto-test best → service**.

### Zapret updates

While the GUI is running (including in the tray), it checks GitHub once a day. If a new zapret build exists, Windows shows a balloon once, then the GUI downloads it and reinstalls the same strategy. If that strategy fails on the new build, it offers a full test.

### Main window

| Control | Action |
| --- | --- |
| Gear | Opens settings |
| Status | Green — zapret is running, red — not running, grey — no zapret folder |
| **Start / Start service / Restart service / Install and start** | Controls the zapret service |
| **Stop** | Stops the zapret service and this install’s `winws.exe` |
| **DISCORD** / **YOUTUBE** cards | Live reachability. Click a card to check now |
| Site field + **Add site** | Adds a domain to the current user list |
| Update banner | Newer zapret on GitHub. **Release** opens the Flowseal releases page |

### Settings

Strategy, service install/remove, strategy tests, user lists, health-check interval (1–1440 minutes), and the log live in the second window. The log stays at the bottom. The official zapret package is not rewritten.

A saved `ZapretPath` wins over nearby-folder discovery.

### What is stored

`zapret-gui.settings.json` next to the EXE (or `%APPDATA%\ZapretGUI\settings.json`): zapret path, last strategy, last list, restart-after-edit, health interval, first-run flag. Site lists stay in the zapret `lists` folder.

---

## Русский

### Что это

Это **форк оригинального [zapret](https://github.com/bol-van/zapret)** (автор bol-van). На Windows в качестве движка берётся сборка [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube).

Сама GUI — только оболочка. Она не правит `general*.bat`, `service.bat` и другие файлы пакета zapret (обновления с GitHub их затрут). Сайты добавляются только в **пользовательские списки** zapret (`lists\list-general-user.txt` и другие `*user*.txt`).

### Требования

- Windows 10 или 11
- Права администратора (UAC), иначе службу zapret поставить нельзя

### Запуск

1. Запустите `ZapretGUI.exe` и подтвердите UAC.
2. Одновременно можно открыть только одну копию. Если программа уже запущена, появится сообщение, и вторая копия не откроется.
3. При запуске программа сама включает автозагрузку Windows: запись **ZAPRET GUI** в диспетчере задач → «Автозагрузка» и задачу Планировщика `ZapretGUI` с правами администратора, чтобы не показывать UAC при входе. После входа оболочка поднимается в трей. Обход по-прежнему даёт служба zapret.
4. Вопросы программы показаны в тёмных окнах в стиле Discord.
5. Кнопка закрытия сворачивает программу в трей. Обход не останавливается. Чтобы выйти полностью, выберите **Выход** в меню иконки в трее.

Закрытие окна GUI **не останавливает** службу zapret. Обход продолжает работать в фоне.

### Первый запуск

Программа проверяет сохранённые настройки и ищет папку zapret рядом с EXE или по сохранённому пути.

Если zapret не найден:

- **Да** — скачать последнюю официальную сборку Flowseal с GitHub
- **Нет** — указать уже установленную папку
- **Отмена** — открыть программу без zapret и настроить позже

После подключения папки можно прогнать все стратегии, выбрать лучшую (нужна хотя бы одна успешная проверка) и установить её как службу с автозапуском Windows. Это можно пропустить и сделать позже кнопкой **Автотест лучшей → служба**.

Настройки сохраняются сразу: путь к zapret, стратегия, список сайтов, интервал проверки и флаг первого запуска.

### Обновления zapret

Пока программа запущена (в том числе в трее), раз в сутки она проверяет GitHub. Если вышла новая сборка zapret, Windows покажет уведомление один раз, затем программа сама скачает её и перезапустит службу с прежней стратегией. Если эта стратегия на новой сборке не работает, появится вопрос, запустить ли полный тест.

### Главное окно

| Элемент | Что делает |
| --- | --- |
| Значок шестерёнки | Открывает окно настроек |
| Индикатор статуса | Зелёный — zapret работает, красный — не запущен, серый — папка zapret не подключена |
| **Запустить / Запустить службу / Перезапустить службу / Установить и запустить** | Управляет службой zapret |
| **Стоп** | Останавливает службу zapret и связанный `winws.exe` этой сборки |
| Карточки **DISCORD** и **YOUTUBE** | Доступность серверов. Нажмите, чтобы проверить сразу |
| Поле сайта и **Добавить сайт** | Добавляет домен в текущий пользовательский список |
| Баннер обновления | Более новая сборка zapret на GitHub. Кнопка **Релиз** открывает страницу релизов |

После запуска или перезапуска службы карточки Discord/YouTube обновляются сразу. Дальше проверка идёт по интервалу из настроек.

### Окно настроек

В нём — путь к zapret, стратегии, служба, тесты, пользовательские списки, интервал автопроверки (1–1440 минут) и лог внизу окна. Официальные стратегии и `list-general.txt` программа не переписывает.

Сохранённый путь важнее автоматического поиска рядом с программой.

### Стратегия и служба

| Элемент | Что делает |
| --- | --- |
| Список **СТРАТЕГИЯ** | Выбирает файл стратегии из папки zapret |
| **Перезапустить** | Перезапускает службу zapret или, если службы нет, запускает выбранную стратегию |
| **В службу** | Ставит выбранную стратегию как службу `zapret` с автозапуском Windows |
| **Снять службу** | Удаляет службу `zapret` и останавливает обход |

### Тесты стратегий

| Элемент | Что делает |
| --- | --- |
| **Автотест лучшей → служба** | Проверяет все стратегии, выбирает лучшую по успешным проверкам и ставит её службой |
| **Тест текущей** | Проверяет только выбранную стратегию |
| **Тест всех** | Прогоняет все стратегии и пишет отчёт, службу не ставит |
| **Стоп теста** | Прерывает текущий прогон |
| **Консольный тест zapret** | Запускает штатный тест из папки zapret, если он есть |

Во время теста интернет может кратко переключаться. Стратегия без успешных проверок лучшей не считается.

### Списки сайтов

Сайты нужно добавлять только в пользовательские файлы (`*user*.txt`). Если выбранный файл не подключён текущей стратегией, в подсказке будет предупреждение. Для обычного обхода нужен `list-general-user.txt`.

### Что сохраняется

Файл `zapret-gui.settings.json` рядом с EXE (если туда нельзя писать — в `%APPDATA%\ZapretGUI\settings.json`):

- путь к zapret;
- последняя стратегия;
- последний открытый список;
- перезапуск после правки списков;
- интервал автопроверки;
- отметка, что первый запуск уже пройден.

Списки сайтов хранятся в папке zapret: `lists\list-general-user.txt` и другие `*user*.txt`.
