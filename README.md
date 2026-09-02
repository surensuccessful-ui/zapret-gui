## [Русский](#русский) | [English](#english)

# ZAPRET GUI

[![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?logo=windows&logoColor=white)](https://github.com/surensuccessful-ui/zapret-gui/releases/latest)
[![Release](https://img.shields.io/github/v/release/surensuccessful-ui/zapret-gui?label=release)](https://github.com/surensuccessful-ui/zapret-gui/releases/latest)
[![Made with Cursor](https://img.shields.io/badge/Made%20with-Cursor-000000?logo=cursor&logoColor=white)](https://cursor.com)

**Форк оригинального [zapret](https://github.com/bol-van/zapret)** с графической оболочкой для Windows. Движок — сборка [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube).

Проект сделан в [Cursor](https://cursor.com). Python не нужен.

**[Скачать ZapretGUI.exe](https://github.com/surensuccessful-ui/zapret-gui/releases/latest)**

<p>
  <img src="docs/screenshots/main.png" alt="Главное окно ZAPRET GUI" width="820">
</p>
<p>
  <img src="docs/screenshots/settings.png" alt="Окно настроек ZAPRET GUI" width="820">
</p>

---

## Русский

Графическая оболочка для zapret: подключает папку сборки Flowseal, ставит выбранную стратегию службой Windows и показывает, открываются ли Discord и YouTube. Официальные `general*.bat` и `service.bat` программа не меняет.

По умолчанию программа **прописывается в автозапуск Windows**. Кнопка закрытия **сворачивает окно в трей**, обход при этом не останавливается.

### Возможности

- Запуск, стоп и перезапуск службы zapret в один клик
- Живые карточки Discord и YouTube с задержкой
- Автоподбор лучшей стратегии и установка её службой
- Добавление сайтов только в пользовательские списки (`*user*.txt`)
- Сворачивание в трей (закрытие окна не выключает обход)
- Автозапуск Windows по умолчанию: запись в «Автозагрузке» и задача Планировщика без повторного UAC
- Автопроверка новой сборки zapret на GitHub, пока GUI запущен
- Одна копия программы: вторая не откроется

### Установка

Установка не нужна.

1. Скачайте `ZapretGUI.exe` со страницы [Releases](https://github.com/surensuccessful-ui/zapret-gui/releases/latest).
2. Запустите файл и подтвердите UAC. Без прав администратора службу zapret поставить нельзя.
3. Если Windows покажет SmartScreen: **Подробнее → Выполнить в любом случае**.

Папку zapret программа скачает с GitHub или предложит указать самой. Рядом с EXE ничего класть не обязательно.

### Как пользоваться

1. После первого запуска согласитесь скачать официальную сборку Flowseal или выберите уже установленную папку.
2. При желании прогоните **Автотест лучшей → служба**: программа проверит стратегии и поставит лучшую в автозапуск Windows.
3. На главном окне смотрите статус службы и карточки Discord / YouTube. Сайт, который не открывается, можно добавить в список.
4. Крестик сворачивает GUI в трей. Обход продолжает работать. Полный выход — пункт **Выход** в меню иконки в трее.
5. Автозапуск GUI включается сам при первом запуске (диспетчер задач → Автозагрузка → **ZAPRET GUI**).

Закрытие окна **не останавливает** службу zapret.

### Оригинальные репозитории

1. [bol-van/zapret](https://github.com/bol-van/zapret) — оригинальный zapret  
2. [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — Windows-сборка и стратегии  

Поддержать автора zapret можно [на странице оригинального проекта](https://github.com/bol-van/zapret?tab=readme-ov-file#%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%B0%D1%82%D1%8C-%D1%80%D0%B0%D0%B7%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D1%87%D0%B8%D0%BA%D0%B0).

---

## English

A **fork of original [zapret](https://github.com/bol-van/zapret)** with a Windows GUI. The engine is [Flowseal zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube).

Built with [Cursor](https://cursor.com). Python is not required.

The GUI connects a zapret folder, installs the chosen strategy as a Windows service, and checks Discord and YouTube. It does not patch official strategy files.

By default the app **registers itself in Windows Startup**. The close button **hides the window to the tray**; bypass keeps running.

### Features

- Start, stop, and restart the zapret service in one click
- Live Discord and YouTube cards with latency
- Auto-test strategies and install the best one as a service
- Add sites only to user lists (`*user*.txt`)
- Minimize to tray (closing the window does not stop bypass)
- Windows Startup enabled by default (Task Manager Startup entry plus an elevated scheduled task, no extra UAC at logon)
- Daily GitHub check for a newer zapret build while the GUI is running
- Single instance: a second copy will not open

### Install

No installer.

1. Download `ZapretGUI.exe` from [Releases](https://github.com/surensuccessful-ui/zapret-gui/releases/latest).
2. Run it and accept UAC. Administrator rights are required to install the zapret service.
3. If SmartScreen appears: **More info → Run anyway**.

The program downloads zapret from GitHub or asks you to pick an existing folder.

### How to use

1. On first run, download the official Flowseal pack or select a folder you already have.
2. Optionally run **Auto-test best → service** to pick a working strategy and install it.
3. Use the main window for service status and Discord / YouTube checks. Add a site if it does not open.
4. The close button hides the GUI to the tray. Use **Exit** in the tray menu to quit.
5. Autostart is enabled on first launch (Task Manager → Startup → **ZAPRET GUI**).

Closing the window **does not** stop the zapret service.

### Original repositories

1. [bol-van/zapret](https://github.com/bol-van/zapret) — original zapret  
2. [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — Windows pack and strategies  

You can support the original zapret author [here](https://github.com/bol-van/zapret?tab=readme-ov-file#%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%B0%D1%82%D1%8C-%D1%80%D0%B0%D0%B7%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D1%87%D0%B8%D0%BA%D0%B0).
