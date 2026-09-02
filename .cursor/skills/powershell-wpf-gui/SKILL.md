---
name: powershell-wpf-gui
description: >-
  Builds and debugs Windows PowerShell 5.1 WPF GUIs without PSObject/.NET binder
  crashes. Use when editing zapret-gui.ps1, WPF XAML in PowerShell, ShowDialog,
  Dispatcher, DockPanel.SetDock, or errors like «Типы аргумента не совпадают».
---

# PowerShell 5.1 WPF GUI

## First, diagnose the exception

If the dialog says `ShowDialog` / `Run` / `PushFrame` / `StartMainLoop` «типы аргумента не совпадают» **and the window is already visible**, the failing call is almost certainly **inside the message loop** (Loaded, timer, health UI), not the method named in the dialog.

## Hard rules

1. Do not call `Window.ShowDialog`, `Application.Run`, or `Dispatcher.PushFrame` from PowerShell. Use the C# helper `ZapretUiHost`.
2. Never assign a **void** .NET method to `$null` or `[void]`. PowerShell 5.1 throws «Тип аргумента не может быть System.Void» (`List[T].Add`, `ConcurrentQueue.Enqueue`, `Inlines.Add`, `Blocks.Add`). Call them as statements. Host methods must return `object`, not `void`.
3. Do not pass WPF `Window` / `UIElement` / `DispatcherFrame` from PowerShell into overloaded .NET methods.
4. Never wrap `List[object]` (from `New-Object`) in `@(...)`. See [PowerShell#27558](https://github.com/PowerShell/PowerShell/issues/27558) and [PowerShell#5579](https://github.com/PowerShell/PowerShell/issues/5579).
5. Prefer `[Type]::new()` over `New-Object` for objects given to typed .NET APIs.
6. After loading both WPF and WinForms, use **fully qualified** names: `System.Windows.MessageBox`, `System.Windows.Forms.FolderBrowserDialog`.
7. Set `Window.Owner` only after the owner has been shown ([docs](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.owner)).
8. Avoid attached-property static helpers (`DockPanel.SetDock`, `Grid.SetRow`) from PowerShell; build layout with `StackPanel` or do it in C#.
9. Keep STA. Isolate timer/Loaded work in `try/catch`.

## Window host

`ZapretUiHost` (embedded C# in `zapret-gui.ps1`) stores main/settings windows and exposes parameterless methods: `LoadMain`, `LoadSettings`, `StartMainLoop`, `ShowSettings`, `HideSettings`, `CloseSettings`, `AttachSettingsOwner`. All of them return `object` so PowerShell never sees `System.Void`.

Do not add a PowerShell `Run($window)` wrapper. If a new window operation is needed, add a **parameterless** C# method that uses the stored fields.

## More detail

See [reference.md](reference.md).
