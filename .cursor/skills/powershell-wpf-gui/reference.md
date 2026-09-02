# PowerShell + WPF — sources

## PSObject wrappers

`New-Object` and binary cmdlets emit `[psobject]` wrappers. Expressions and `::new()` usually do not.

- [PowerShell#5579](https://github.com/PowerShell/PowerShell/issues/5579) — objects are situationally `[psobject]`-wrapped
- [PowerShell#27558](https://github.com/PowerShell/PowerShell/issues/27558) — `@($list)` throws `Argument types do not match` for `List[object]` from `New-Object`

Symptom in this app: health check builds `List[object]`, then `foreach ($r in @($script:HealthResults))` throws. PowerShell reports the exception on `StartMainLoop()` because that call is pumping the dispatcher.

## WPF vs WinForms collision

Loading `PresentationFramework` and `System.Windows.Forms` together makes `Windows.Application`, `Windows.MessageBox`, and `ShowDialog` ambiguous.

- [MessageBox WPF vs WinForms](https://stackoverflow.com/questions/4660587/system-windows-messagebox-vs-system-windows-forms-messagebox)
- [Avoiding MessageBox ambiguity](https://stackoverflow.com/questions/15209886/avoiding-ambiguity-with-messagebox-in-wpf)
- Prefer `Microsoft.Win32` dialogs when possible instead of pulling WinForms ([same SO thread](https://stackoverflow.com/questions/15209886/avoiding-ambiguity-with-messagebox-in-wpf))

Folder picker still uses `System.Windows.Forms.FolderBrowserDialog`; keep every other type fully qualified.

## Window.Owner

[Window.Owner](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.owner) throws if the owner has not been shown. Parse both windows first; call `AttachSettingsOwner` from `Loaded` or when opening settings.

## Attached properties

[DockPanel.SetDock](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.dockpanel.setdock) needs a real `UIElement`, not a PSObject. Prefer `StackPanel` in PowerShell.

## Void methods

PowerShell 5.1 cannot assign or `[void]`-cast a .NET method that returns `void`. That throws `Argument type cannot be System.Void` and is often reported on `StartMainLoop` because that call is pumping the dispatcher.

Do not write `$null = $list.Add(...)`, `[void]$queue.Enqueue(...)`, or `[void]$inlines.Add(...)`. Call them as statements. C# host methods must return `object`.

## STA

WPF requires STA. Relaunch with `-STA` if `ApartmentState` is not STA before creating windows.
