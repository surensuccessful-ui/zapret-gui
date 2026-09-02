#Requires -Version 5.1
# ZAPRET GUI — универсальная оболочка для любой сборки zapret-discord-youtube.
$ErrorActionPreference = 'Stop'
$script:GithubVersionUrl = 'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt'
$script:GithubReleasesUrl = 'https://github.com/Flowseal/zapret-discord-youtube/releases/latest'

function Get-OwnPath {
    try {
        $proc = [Diagnostics.Process]::GetCurrentProcess()
        $file = $proc.MainModule.FileName
        $name = [IO.Path]::GetFileNameWithoutExtension([string]$file)
        if ($file -and $name -notmatch '^(powershell|pwsh)$') { return $file }
    } catch { }
    if ($PSCommandPath) { return $PSCommandPath }
    if ($MyInvocation.MyCommand.Path) { return $MyInvocation.MyCommand.Path }
    return $null
}

function Get-AppDirectory {
    $own = Get-OwnPath
    if ($own) { return [IO.Path]::GetDirectoryName($own) }
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Get-Location).Path
}

$script:OwnPath = Get-OwnPath
$script:IsPackaged = [bool]($script:OwnPath -and $script:OwnPath.ToLower().EndsWith('.exe'))
$script:LaunchArgs = @($args | ForEach-Object { [string]$_ })
$script:StartInTray = $false
$script:GuiAutostartTaskName = 'ZapretGUI'
$script:GuiAutostartRunName = 'ZAPRET GUI'
foreach ($launchArg in $script:LaunchArgs) {
    if ($launchArg -eq '-tray' -or $launchArg -eq '/tray' -or $launchArg -eq '--tray') {
        $script:StartInTray = $true
    }
}

function Get-QuotedArgumentString {
    param([string[]]$Items)
    $parts = foreach ($item in @($Items)) {
        if ([string]::IsNullOrEmpty($item)) { continue }
        if ($item -match '[\s"]') {
            '"' + ($item -replace '"', '\"') + '"'
        } else {
            $item
        }
    }
    return [string]($parts -join ' ')
}

function Get-SelfProcessArguments {
    if ($script:IsPackaged) {
        return (Get-QuotedArgumentString $script:LaunchArgs)
    }
    $text = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script:OwnPath)`""
    $extra = Get-QuotedArgumentString $script:LaunchArgs
    if ($extra) { return "$text $extra" }
    return $text
}

function Invoke-Schtasks {
    param([string[]]$ArgumentList)
    $schtasks = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    if (-not (Test-Path -LiteralPath $schtasks)) { return 1 }
    $p = Start-Process -FilePath $schtasks -ArgumentList $ArgumentList -WindowStyle Hidden -Wait -PassThru
    if ($p) { return [int]$p.ExitCode }
    return 1
}

function Start-GuiViaScheduledTask {
    $query = Invoke-Schtasks -ArgumentList @('/Query', '/TN', $script:GuiAutostartTaskName)
    if ($query -ne 0) { return $false }
    $run = Invoke-Schtasks -ArgumentList @('/Run', '/TN', $script:GuiAutostartTaskName)
    return ($run -eq 0)
}

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    if ($script:IsPackaged) {
        if ($script:LaunchArgs.Count -gt 0) {
            Start-Process -FilePath $script:OwnPath -ArgumentList $script:LaunchArgs
        } else {
            Start-Process -FilePath $script:OwnPath
        }
    } elseif ($script:OwnPath) {
        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', $script:OwnPath) + @($script:LaunchArgs)
        Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs
    }
    exit
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (Start-GuiViaScheduledTask) { exit }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true
    if ($script:IsPackaged) {
        $psi.FileName = $script:OwnPath
        $psi.Arguments = Get-QuotedArgumentString $script:LaunchArgs
    } else {
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = Get-SelfProcessArguments
    }
    try { $elevatedProcess = [Diagnostics.Process]::Start($psi) } catch { }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

if (-not ('ZapretUiHost' -as [type])) {
    try { Add-Type -AssemblyName System.Xaml } catch { }
    $wpfRefs = @(
        ([System.Windows.Window].Assembly.Location)
        ([System.Windows.Threading.Dispatcher].Assembly.Location)
        ([System.Windows.Media.Visual].Assembly.Location)
        ([System.Windows.Interop.WindowInteropHelper].Assembly.Location)
    )
    if ('System.Xaml.XamlObjectWriter' -as [type]) {
        $wpfRefs += [System.Xaml.XamlObjectWriter].Assembly.Location
    }
    $wpfRefs = @($wpfRefs | Select-Object -Unique)
    Add-Type -ReferencedAssemblies $wpfRefs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;

public static class ZapretUiHost {
    static Window _main;
    static Window _settings;
    static string _dialogResult = "Cancel";

    static object Ok() { return true; }

    static Brush HexBrush(string hex) {
        return (Brush)(new BrushConverter().ConvertFrom(hex));
    }

    static Button MakeAskButton(string text, string result, string bgHex, string fgHex, Window dlg) {
        Button btn = new Button();
        btn.Content = text;
        btn.MinWidth = 108;
        btn.Height = 38;
        btn.Margin = new Thickness(8, 0, 0, 0);
        btn.Padding = new Thickness(16, 0, 16, 0);
        btn.FontSize = 14;
        btn.FontWeight = FontWeights.SemiBold;
        btn.Cursor = Cursors.Hand;
        btn.Foreground = HexBrush(fgHex);
        btn.Background = HexBrush(bgHex);
        btn.BorderThickness = new Thickness(0);
        ControlTemplate tpl = new ControlTemplate(typeof(Button));
        FrameworkElementFactory border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(4));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Button.BackgroundProperty));
        border.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Button.PaddingProperty));
        FrameworkElementFactory presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(presenter);
        tpl.VisualTree = border;
        btn.Template = tpl;
        btn.Click += delegate(object s, RoutedEventArgs e) {
            _dialogResult = result;
            dlg.Close();
        };
        return btn;
    }

    static Window CreateAskWindow(string title, string body, string buttons) {
        Window dlg = new Window();
        dlg.WindowStyle = WindowStyle.None;
        dlg.AllowsTransparency = true;
        dlg.ResizeMode = ResizeMode.NoResize;
        dlg.ShowInTaskbar = false;
        dlg.Width = 460;
        dlg.SizeToContent = SizeToContent.Height;
        dlg.Background = Brushes.Transparent;
        dlg.FontFamily = new FontFamily("Segoe UI");

        Border chrome = new Border();
        chrome.Background = HexBrush("#2B2D31");
        chrome.BorderBrush = HexBrush("#1E1F22");
        chrome.BorderThickness = new Thickness(1);
        chrome.CornerRadius = new CornerRadius(8);
        chrome.Padding = new Thickness(20);

        StackPanel root = new StackPanel();
        TextBlock titleBlock = new TextBlock();
        titleBlock.Text = title;
        titleBlock.FontSize = 16;
        titleBlock.FontWeight = FontWeights.Bold;
        titleBlock.Foreground = HexBrush("#F2F3F5");
        titleBlock.TextWrapping = TextWrapping.Wrap;
        root.Children.Add(titleBlock);

        TextBlock bodyBlock = new TextBlock();
        bodyBlock.Text = body;
        bodyBlock.FontSize = 14;
        bodyBlock.Foreground = HexBrush("#B5BAC1");
        bodyBlock.TextWrapping = TextWrapping.Wrap;
        bodyBlock.Margin = new Thickness(0, 12, 0, 20);
        root.Children.Add(bodyBlock);

        StackPanel row = new StackPanel();
        row.Orientation = Orientation.Horizontal;
        row.HorizontalAlignment = HorizontalAlignment.Right;
        string mode = (buttons == null || buttons.Length == 0) ? "OK" : buttons;
        if (mode == "YesNoCancel") {
            row.Children.Add(MakeAskButton("Отмена", "Cancel", "#4E5058", "#DBDEE1", dlg));
            row.Children.Add(MakeAskButton("Нет", "No", "#4E5058", "#DBDEE1", dlg));
            row.Children.Add(MakeAskButton("Да", "Yes", "#5865F2", "#FFFFFF", dlg));
        } else if (mode == "YesNo") {
            row.Children.Add(MakeAskButton("Нет", "No", "#4E5058", "#DBDEE1", dlg));
            row.Children.Add(MakeAskButton("Да", "Yes", "#5865F2", "#FFFFFF", dlg));
        } else {
            row.Children.Add(MakeAskButton("Понятно", "OK", "#5865F2", "#FFFFFF", dlg));
        }
        root.Children.Add(row);
        chrome.Child = root;
        dlg.Content = chrome;
        dlg.KeyDown += delegate(object s, KeyEventArgs e) {
            if (e.Key == Key.Escape) {
                _dialogResult = (mode == "OK") ? "OK" : "Cancel";
                if (mode == "YesNo") _dialogResult = "No";
                dlg.Close();
            }
        };
        return dlg;
    }

    public static object Ask(string title, string body, string buttons) {
        _dialogResult = "Cancel";
        if (Application.Current == null) {
            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        }
        Window dlg = CreateAskWindow(title, body == null ? "" : body, buttons);
        if (_main != null && _main.IsVisible) {
            dlg.Owner = _main;
            dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        } else {
            dlg.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }
        DispatcherFrame frame = new DispatcherFrame();
        EventHandler onClosed = null;
        onClosed = delegate(object s, EventArgs e) {
            dlg.Closed -= onClosed;
            frame.Continue = false;
        };
        dlg.Closed += onClosed;
        dlg.Show();
        dlg.Activate();
        Dispatcher.PushFrame(frame);
        return _dialogResult;
    }

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    static void DisableRoundedCorners(Window win) {
        if (win == null) return;
        try {
            IntPtr hwnd = new WindowInteropHelper(win).EnsureHandle();
            if (hwnd == IntPtr.Zero) return;
            int preference = 1;
            DwmSetWindowAttribute(hwnd, 33, ref preference, 4);
        } catch { }
    }

    static void ApplyChrome(Window win) {
        if (win == null) return;
        win.AllowsTransparency = false;
        WindowChrome chrome = new WindowChrome();
        chrome.CaptionHeight = 0;
        chrome.ResizeBorderThickness = new Thickness(6);
        chrome.GlassFrameThickness = new Thickness(0);
        chrome.CornerRadius = new CornerRadius(0);
        chrome.UseAeroCaptionButtons = false;
        WindowChrome.SetWindowChrome(win, chrome);
        win.BorderThickness = new Thickness(0);
        win.SourceInitialized += delegate(object s, EventArgs e) {
            DisableRoundedCorners(win);
        };
        DisableRoundedCorners(win);
    }

    public static Window LoadMain(string xaml) {
        _main = (Window)XamlReader.Parse(xaml);
        ApplyChrome(_main);
        return _main;
    }
    public static Window LoadSettings(string xaml) {
        _settings = (Window)XamlReader.Parse(xaml);
        ApplyChrome(_settings);
        return _settings;
    }
    public static object AttachSettingsOwner() {
        if (_settings == null || _main == null || !_main.IsVisible) return Ok();
        _settings.Owner = _main;
        return Ok();
    }
    public static object ShowSettings() {
        if (_settings == null) return Ok();
        AttachSettingsOwner();
        if (!_settings.IsVisible) _settings.Show();
        if (_settings.WindowState == WindowState.Minimized) _settings.WindowState = WindowState.Normal;
        _settings.Activate();
        return Ok();
    }
    public static object HideSettings() {
        if (_settings != null) _settings.Hide();
        return Ok();
    }
    public static object CloseSettings() {
        if (_settings != null) _settings.Close();
        return Ok();
    }
    public static object MinimizeMain() {
        if (_main != null) _main.WindowState = WindowState.Minimized;
        return Ok();
    }
    public static object CloseMain() {
        if (_main != null) _main.Close();
        return Ok();
    }
    public static object HideMain() {
        if (_main != null) {
            _main.ShowInTaskbar = false;
            _main.Hide();
        }
        return Ok();
    }
    public static object ShowMain() {
        if (_main == null) return Ok();
        _main.ShowInTaskbar = true;
        if (!_main.IsVisible) _main.Show();
        if (_main.WindowState == WindowState.Minimized) _main.WindowState = WindowState.Normal;
        _main.Activate();
        return Ok();
    }
    public static object DragMain() {
        if (_main != null) _main.DragMove();
        return Ok();
    }
    public static object MinimizeSettings() {
        if (_settings != null) _settings.WindowState = WindowState.Minimized;
        return Ok();
    }
    public static object DragSettings() {
        if (_settings != null) _settings.DragMove();
        return Ok();
    }
    public static object StartMainLoop() {
        if (_main == null) throw new InvalidOperationException("Main window is not loaded.");
        DispatcherFrame frame = new DispatcherFrame();
        EventHandler onClosed = null;
        onClosed = delegate(object s, EventArgs e) {
            _main.Closed -= onClosed;
            frame.Continue = false;
        };
        _main.Closed += onClosed;
        _main.Show();
        Dispatcher.PushFrame(frame);
        return Ok();
    }
}

public static class ZapretSingleInstance {
    const string MutexName = @"Local\ZapretGUI.SingleInstance";
    static Mutex _mutex;

    public static object TryAcquire() {
        bool createdNew;
        Mutex mutex = new Mutex(true, MutexName, out createdNew);
        if (!createdNew) {
            mutex.Dispose();
            return false;
        }
        _mutex = mutex;
        return true;
    }

    public static object Release() {
        if (_mutex == null) return true;
        try { _mutex.ReleaseMutex(); } catch { }
        try { _mutex.Dispose(); } catch { }
        _mutex = null;
        return true;
    }
}
'@
}

$singleInstanceOk = [ZapretSingleInstance]::TryAcquire()
if (-not $singleInstanceOk) {
    if (-not $script:StartInTray) {
        $dupMsg = [ZapretUiHost]::Ask('ZAPRET GUI', "ZAPRET GUI уже запущена.`nВторая копия не будет открыта.", 'OK')
    }
    exit
}

$script:GithubApiUrl = 'https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest'

$script:AppDir = Get-AppDirectory
$script:SettingsPath = Join-Path $script:AppDir 'zapret-gui.settings.json'
$appDataSettings = Join-Path $env:APPDATA 'ZapretGUI\settings.json'
if (-not (Test-Path -LiteralPath $script:SettingsPath) -and (Test-Path -LiteralPath $appDataSettings)) {
    $script:SettingsPath = $appDataSettings
}
$script:SettingsExistedAtStartup = Test-Path -LiteralPath $script:SettingsPath
$script:DummyHost = 'domain.example.abc'
$script:DummyIp = '203.0.113.113/32'
$script:Root = ''
$script:Lists = ''
$script:Bin = ''
$script:Utils = ''
$script:Version = ''
$script:GuiVersion = '1.0.0'
$script:LastRunning = $null
$script:Restarting = $false
$script:TestBusy = $false
$script:TestCancel = $false
$script:Watcher = $null
$script:WatchTimer = $null
$script:HealthIntervalMinutes = 1
$script:NextHealthCheckAt = [datetime]::MinValue
$script:HealthCheckPending = $false
$script:FirstRunCompleted = $script:SettingsExistedAtStartup
$script:FirstRunPromptActive = $false
$script:AllowMainClose = $false
$script:SetupIsUpdate = $false
$script:PendingUpdateStrategy = ''
$script:UpdateFromRoot = ''
$script:OverlayRetryUpdate = $false
$script:NotifiedZapretVersion = ''
$script:LastZapretUpdateCheck = ''
$script:NextGithubCheckAt = [datetime]::MinValue
$script:TrayIcon = $null
$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:BrushConv = [Windows.Media.BrushConverter]::new()

function ConvertTo-Brush {
    param([string]$Hex)
    try { return $script:BrushConv.ConvertFromString($Hex) } catch { return [Windows.Media.Brushes]::LightGray }
}

function Show-ZapretDialog {
    param(
        [string]$Message,
        [string]$Title = 'ZAPRET GUI',
        [string]$Buttons = 'OK'
    )
    return [string][ZapretUiHost]::Ask($Title, $Message, $Buttons)
}

function Get-GuiVersion {
    $candidates = @(
        (Join-Path $script:AppDir 'VERSION')
        (Join-Path $script:AppDir 'zapret-gui.version')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            $text = ([IO.File]::ReadAllText($p)).Trim()
            if ($text -match '^[0-9][0-9A-Za-z.\-+]*$') { return $text }
        }
    }
    return '1.0.0'
}
$script:GuiVersion = Get-GuiVersion
$script:EmbeddedSettingsGearPngBase64 = [string]::Empty

function Save-Settings {
    $currentList = Get-CurrentListInfo
    $data = @{
        ZapretPath       = [string]$script:Root
        LastStrategy     = if ($script:CmbStrategy) { [string]$script:CmbStrategy.SelectedItem } else { '' }
        LastList         = if ($currentList) { [string]$currentList.Name } else { '' }
        RestartAfterEdit = if ($script:ChkRestart) { [bool]$script:ChkRestart.IsChecked } else { $true }
        HealthIntervalMinutes = [int]$script:HealthIntervalMinutes
        FirstRunCompleted = [bool]$script:FirstRunCompleted
        LastZapretUpdateCheck = [string]$script:LastZapretUpdateCheck
        NotifiedZapretVersion = [string]$script:NotifiedZapretVersion
    }
    $json = $data | ConvertTo-Json
    $enc = [System.Text.UTF8Encoding]::new($false)
    $settingsDir = Split-Path -Parent $script:SettingsPath
    if ($settingsDir -and -not (Test-Path -LiteralPath $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    $tempPath = "$($script:SettingsPath).tmp"
    [IO.File]::WriteAllText($tempPath, $json, $enc)
    if (Test-Path -LiteralPath $script:SettingsPath) {
        $backupPath = "$($script:SettingsPath).bak"
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Force
        }
        [IO.File]::Replace($tempPath, $script:SettingsPath, $backupPath)
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    } else {
        [IO.File]::Move($tempPath, $script:SettingsPath)
    }
}

function Get-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) { return $null }
    try { return Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Write-Utf8Lines {
    param([string]$Path, [string[]]$Lines)
    $enc = [System.Text.UTF8Encoding]::new($false)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Add-Log {
    param(
        [string]$Message,
        [string]$Color = '#B5BAC1'
    )
    $script:LogQueue.Enqueue([pscustomobject]@{ Message = $Message; Color = $Color; Time = (Get-Date) })
}

function Get-GuiAutostartCommand {
    if ($script:IsPackaged) {
        return @{
            Path = [string]$script:OwnPath
            Arguments = '-tray'
            WorkingDirectory = [string]$script:AppDir
        }
    }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return @{
        Path = $psExe
        Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$($script:OwnPath)`" -tray"
        WorkingDirectory = [string]$script:AppDir
    }
}

function Get-GuiAutostartRunCommand {
    $cmd = Get-GuiAutostartCommand
    if ($cmd.Arguments) {
        return ('"{0}" {1}' -f $cmd.Path, $cmd.Arguments)
    }
    return ('"{0}"' -f $cmd.Path)
}

function Register-GuiStartupApproved {
    param([string]$Name)
    $approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    if (-not (Test-Path -LiteralPath $approved)) {
        New-Item -Path $approved -Force | Out-Null
    }
    $enabled = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    New-ItemProperty -Path $approved -Name $Name -PropertyType Binary -Value $enabled -Force | Out-Null
}

function Register-GuiTaskManagerStartup {
    param([string]$Command)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey -Force | Out-Null
    }
    Set-ItemProperty -Path $runKey -Name $script:GuiAutostartRunName -Value $Command -Type String
    Register-GuiStartupApproved -Name $script:GuiAutostartRunName
}

function Register-GuiScheduledTask {
    param($Command)
    $userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskName = $script:GuiAutostartTaskName
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = $service.GetFolder('\')
    $task = $service.NewTask(0)
    $task.RegistrationInfo.Description = 'Автозапуск ZAPRET GUI при входе в Windows'
    $task.Principal.UserId = $userId
    $task.Principal.LogonType = 3
    $task.Principal.RunLevel = 1
    $task.Settings.Enabled = $true
    $task.Settings.AllowDemandStart = $true
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.MultipleInstances = 2
    $trigger = $task.Triggers.Create(9)
    $trigger.Enabled = $true
    $trigger.UserId = $userId
    $trigger.Delay = 'PT20S'
    $action = $task.Actions.Create(0)
    $action.Path = $Command.Path
    $action.Arguments = $Command.Arguments
    $action.WorkingDirectory = $Command.WorkingDirectory
    $registered = $folder.RegisterTaskDefinition($taskName, $task, 6, $userId, $null, 3)
}

function Register-GuiScheduledTaskFallback {
    param($Command)
    $tr = Get-GuiAutostartRunCommand
    $code = Invoke-Schtasks -ArgumentList @(
        '/Create',
        '/TN', $script:GuiAutostartTaskName,
        '/TR', $tr,
        '/SC', 'ONLOGON',
        '/RL', 'HIGHEST',
        '/F',
        '/IT'
    )
    if ($code -ne 0) { throw "schtasks /Create завершился с кодом $code" }
}

function Register-GuiWindowsAutostart {
    if (-not $script:OwnPath -or -not (Test-Path -LiteralPath $script:OwnPath)) { return }
    $cmd = Get-GuiAutostartCommand
    if (-not $cmd.Path -or -not (Test-Path -LiteralPath $cmd.Path)) { return }
    $runOk = $false
    $taskOk = $false
    try {
        Register-GuiTaskManagerStartup -Command (Get-GuiAutostartRunCommand)
        $runOk = $true
    } catch {
        Add-Log "Автозагрузка (диспетчер задач): $($_.Exception.Message)" '#E8C36A'
    }
    try {
        Register-GuiScheduledTask -Command $cmd
        $taskOk = $true
    } catch {
        try {
            Register-GuiScheduledTaskFallback -Command $cmd
            $taskOk = $true
        } catch {
            Add-Log "Задача автозапуска: $($_.Exception.Message)" '#E8C36A'
        }
    }
    if ($runOk -and $taskOk) {
        Add-Log 'Автозапуск Windows для GUI включён' '#8B9BB4'
    } elseif ($runOk) {
        Add-Log 'Автозагрузка добавлена в Windows. Задача Планировщика не создана.' '#E8C36A'
    } elseif ($taskOk) {
        Add-Log 'Задача автозапуска создана. В диспетчере задач запись может не появиться.' '#E8C36A'
    }
}

function Flush-LogQueue {
    if (-not $script:LogBox) { return }
    $item = $null
    $n = 0
    while ($script:LogQueue.TryDequeue([ref]$item)) {
        $run = [Windows.Documents.Run]::new()
        $run.Text = '{0}  {1}' -f $item.Time.ToString('HH:mm:ss'), $item.Message
        $run.Foreground = ConvertTo-Brush $item.Color
        $p = [Windows.Documents.Paragraph]::new()
        $p.Margin = [Windows.Thickness]::new(0)
        $p.Inlines.Add($run)
        $script:LogBox.Document.Blocks.Add($p)
        $n++
    }
    if ($n -gt 0) {
        while ($script:LogBox.Document.Blocks.Count -gt 400) {
            $script:LogBox.Document.Blocks.Remove($script:LogBox.Document.Blocks.FirstBlock)
        }
        $script:LogBox.ScrollToEnd()
    }
}

function Get-StrategyBats {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return @() }
    Get-ChildItem -LiteralPath $Root -File -Filter '*.bat' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notmatch '^(service|zapret-gui)' -and
            (Select-String -LiteralPath $_.FullName -Pattern 'winws\.exe' -Quiet -ErrorAction SilentlyContinue)
        } |
        Sort-Object { [regex]::Replace($_.Name, '(\d+)', { param($m) $m.Value.PadLeft(8, '0') }) }
}

function Test-ZapretRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Path 'service.bat')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'bin\winws.exe')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'winws.exe')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'lists')) { return $true }
    return @((Get-StrategyBats $Path)).Count -gt 0
}

function Find-ZapretNear {
    param([string]$Base)
    $found = [System.Collections.Generic.List[string]]::new()
    if (-not $Base -or -not (Test-Path -LiteralPath $Base)) { return @() }
    if (Test-ZapretRoot $Base) { $found.Add((Get-Item -LiteralPath $Base).FullName) }
    Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        $looksLike = $name -match 'zapret|discord.?youtube|winws|flowseal'
        if ($looksLike -or (Test-Path -LiteralPath (Join-Path $_.FullName 'service.bat')) -or (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\winws.exe'))) {
            if (Test-ZapretRoot $_.FullName) { $found.Add($_.FullName) }
        }
    }
    $uniq = @($found | Select-Object -Unique)
    return @(
        $uniq | ForEach-Object {
            $ver = Get-ZapretVersion $_
            $n = @((Get-StrategyBats $_)).Count
            [pscustomobject]@{ Path = $_; Version = $ver; Strategies = $n }
        } | Sort-Object @{Expression = {
            try { [version](($_.Version -replace '[^0-9.].*$', '')) } catch { [version]'0.0' }
        }; Descending = $true }, @{Expression = 'Strategies'; Descending = $true }
    )
}

function Compare-ZapretVersion {
    param([string]$A, [string]$B)
    $na = ($A -replace '[^0-9.].*$', '')
    $nb = ($B -replace '[^0-9.].*$', '')
    try { return ([version]$na).CompareTo([version]$nb) } catch { return [string]::CompareOrdinal($A, $B) }
}

function Start-GithubCheck {
    if ($script:GithubSync -and -not $script:GithubSync.Done) { return }
    $sync = [hashtable]::Synchronized(@{ Done = $false; Version = ''; Error = '' })
    $script:GithubSync = $sync
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $githubPipeline = $ps.AddScript({
        param($Url, $Sync)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object Net.WebClient
            $wc.Headers['User-Agent'] = 'ZapretGUI'
            $wc.Headers['Cache-Control'] = 'no-cache'
            $Sync.Version = ([string]$wc.DownloadString($Url)).Trim()
            $wc.Dispose()
        } catch {
            $Sync.Error = $_.Exception.Message
        }
        $Sync.Done = $true
    }).AddArgument($script:GithubVersionUrl).AddArgument($sync)
    $script:GithubPs = $ps
    $script:GithubRs = $rs
    $script:GithubHandle = $ps.BeginInvoke()
}

function Show-WindowsNotify {
    param([string]$Title, [string]$Text)
    if (-not $script:TrayIcon) { return }
    try {
        $script:TrayIcon.BalloonTipTitle = $Title
        $script:TrayIcon.BalloonTipText = $Text
        $script:TrayIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $script:TrayIcon.ShowBalloonTip(8000)
    } catch { }
}

function Initialize-TrayIcon {
    if ($script:TrayIcon) { return }
    $ni = [System.Windows.Forms.NotifyIcon]::new()
    $ni.Text = 'ZAPRET GUI'
    $ni.Visible = $true
    try {
        if ($script:OwnPath -and (Test-Path -LiteralPath $script:OwnPath)) {
            $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:OwnPath)
        }
    } catch { }
    if (-not $ni.Icon) { $ni.Icon = [System.Drawing.SystemIcons]::Application }
    $menu = [System.Windows.Forms.ContextMenuStrip]::new()
    $openItem = [System.Windows.Forms.ToolStripMenuItem]::new('Открыть')
    $openItem.Add_Click({ $shown = [ZapretUiHost]::ShowMain() })
    $exitItem = [System.Windows.Forms.ToolStripMenuItem]::new('Выход')
    $exitItem.Add_Click({ Exit-ZapretGui })
    $addedOpen = $menu.Items.Add($openItem)
    $addedExit = $menu.Items.Add($exitItem)
    $ni.ContextMenuStrip = $menu
    $ni.Add_DoubleClick({ $shown = [ZapretUiHost]::ShowMain() })
    $script:TrayIcon = $ni
}

function Hide-MainToTray {
    if ($script:SettingsWindow) { $hiddenSettings = [ZapretUiHost]::HideSettings() }
    $hidden = [ZapretUiHost]::HideMain()
    Show-WindowsNotify 'ZAPRET GUI' 'Программа свёрнута в трей. Обход продолжает работать.'
}

function Exit-ZapretGui {
    if ($script:TestBusy) {
        $answer = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'YesNo' -Message "Сейчас выполняется тест стратегий.`nЗавершить тест и закрыть программу?"
        if ($answer -ne 'Yes') { return }
        if ($script:TestSync) { $script:TestSync.Cancel = $true }
        Add-Log 'Тест остановлен при выходе из программы' '#E8C36A'
    }
    $script:AllowMainClose = $true
    $closed = [ZapretUiHost]::CloseMain()
}

function Dispose-TrayIcon {
    if (-not $script:TrayIcon) { return }
    $script:TrayIcon.Visible = $false
    $script:TrayIcon.Dispose()
    $script:TrayIcon = $null
}

function Get-PreferredStrategyName {
    $installed = Get-InstalledStrategy
    if ($script:CmbStrategy) {
        if ($installed) {
            foreach ($it in $script:CmbStrategy.Items) {
                $name = [string]$it
                $base = [IO.Path]::GetFileNameWithoutExtension($name)
                if ($base -eq $installed -or $name -eq $installed) { return $name }
            }
        }
        $sel = [string]$script:CmbStrategy.SelectedItem
        if ($sel) { return $sel }
    }
    $cfg = Get-Settings
    if ($cfg -and $cfg.LastStrategy) { return [string]$cfg.LastStrategy }
    return [string]$installed
}

function Copy-ZapretUserLists {
    param([string]$FromRoot, [string]$ToRoot)
    if (-not $FromRoot -or -not $ToRoot) { return }
    $src = Join-Path $FromRoot 'lists'
    $dst = Join-Path $ToRoot 'lists'
    if (-not (Test-Path -LiteralPath $src) -or -not (Test-Path -LiteralPath $dst)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $src -File -Filter '*user*.txt' -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dst $file.Name) -Force
        Add-Log "Перенёс пользовательский список: $($file.Name)" '#8B9BB4'
    }
}

function Test-BypassLooksWorking {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $true }
    $urls = @('https://discord.com', 'https://www.youtube.com')
    $ok = 0
    foreach ($url in $urls) {
        $tok = Test-OneUrl -Url $url -TimeoutSec 3
        if ($tok -notmatch 'ERROR') { $ok++ }
    }
    return ($ok -gt 0)
}

function Offer-FullStrategyTest {
    param([string]$Reason)
    Add-Log $Reason '#E8C36A'
    $shown = [ZapretUiHost]::ShowMain()
    $names = @()
    if ($script:CmbStrategy) {
        $names = @($script:CmbStrategy.Items | ForEach-Object { [string]$_ })
    }
    if ($names.Count -eq 0) {
        $offer = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message "$Reason`nВ новой сборке нет стратегий для теста."
        return
    }
    $answer = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'YesNo' -Message "$Reason`n`nЗапустить полный тест всех стратегий и поставить лучшую службой?"
    if ($answer -eq 'Yes') {
        Start-StrategyTestsSafe $names -AutoInstallBest
    }
}

function Complete-ZapretUpdate {
    param([string]$NewPath, [string]$StrategyName)
    $oldRoot = [string]$script:UpdateFromRoot
    Copy-ZapretUserLists -FromRoot $oldRoot -ToRoot $NewPath
    Set-ZapretRoot $NewPath
    Hide-BusyOverlay
    Show-WindowsNotify 'ZAPRET GUI' "Zapret обновлён до $($script:Version)."
    if ([string]::IsNullOrWhiteSpace($StrategyName)) {
        Offer-FullStrategyTest 'Новая сборка zapret установлена, но предыдущая стратегия неизвестна.'
        return
    }
    if (-not (Test-ComboHasItem $script:CmbStrategy $StrategyName)) {
        Offer-FullStrategyTest "Стратегия $StrategyName отсутствует в новой сборке zapret."
        return
    }
    $script:CmbStrategy.SelectedItem = $StrategyName
    try {
        Show-BusyOverlay 'Перезапуск службы' $StrategyName -1
        Install-ZapretService -StrategyName $StrategyName
        Hide-BusyOverlay
        Start-Sleep -Milliseconds 800
        if (Test-BypassLooksWorking) {
            Add-Log "Служба перезапущена со стратегией $StrategyName" '#23A559'
            Start-LiveHealthCheck -Force
        } else {
            Offer-FullStrategyTest "Стратегия $StrategyName не проходит проверку Discord/YouTube на новой сборке."
        }
    } catch {
        Hide-BusyOverlay
        Offer-FullStrategyTest "Не удалось запустить $StrategyName на новой сборке: $($_.Exception.Message)"
    }
}

function Complete-GithubCheck {
    if (-not $script:GithubSync -or -not $script:GithubSync.Done) { return }
    $sync = $script:GithubSync
    $script:GithubSync = $null
    try { $githubOutput = $script:GithubPs.EndInvoke($script:GithubHandle) } catch { }
    try { $script:GithubPs.Dispose() } catch { }
    try { $script:GithubRs.Close(); $script:GithubRs.Dispose() } catch { }
    $script:LastZapretUpdateCheck = (Get-Date).ToString('yyyy-MM-dd')
    $script:NextGithubCheckAt = (Get-Date).Date.AddDays(1)
    Save-SettingsSafe
    if ($sync.Error) {
        Add-Log "GitHub недоступен: $($sync.Error)" '#8B9BB4'
        $script:NextGithubCheckAt = (Get-Date).AddHours(6)
        return
    }
    $remote = [string]$sync.Version
    if ([string]::IsNullOrWhiteSpace($remote)) { return }
    $local = [string]$script:Version
    if ($local -and (Compare-ZapretVersion $remote $local) -gt 0) {
        if ($script:PnlUpdate) { $script:PnlUpdate.Visibility = 'Visible' }
        if ($script:LblUpdate) { $script:LblUpdate.Text = "На GitHub новая версия $remote (у вас $local). Программа скачает её автоматически." }
        Add-Log "Доступно обновление zapret $remote (сейчас $local)" '#E8C36A'
        if ($script:NotifiedZapretVersion -ne $remote) {
            Show-WindowsNotify 'ZAPRET GUI' "Доступна новая версия zapret $remote. Начинаю загрузку."
            $script:NotifiedZapretVersion = $remote
            Save-SettingsSafe
        }
        if ($script:Root -and -not $script:TestBusy -and -not ($script:SetupSync -and -not $script:SetupSync.Done)) {
            Start-ZapretAutoSetup -Update
        } elseif ($script:TestBusy) {
            $script:NextGithubCheckAt = (Get-Date).AddMinutes(15)
        }
    } elseif ($local -and ((Compare-ZapretVersion $remote $local) -eq 0)) {
        Add-Log "Сборка zapret актуальна ($local)" '#3DDC97'
        if ($script:PnlUpdate) { $script:PnlUpdate.Visibility = 'Collapsed' }
    } else {
        Add-Log "Последний релиз на GitHub: $remote" '#8B9BB4'
        if (-not $local -and $script:PnlUpdate) {
            $script:PnlUpdate.Visibility = 'Visible'
            if ($script:LblUpdate) { $script:LblUpdate.Text = "Последний релиз Flowseal: $remote. Укажите папку своей сборки zapret." }
        }
    }
}

function Resolve-ZapretPath {
    $cfg = Get-Settings
    if ($cfg -and $cfg.ZapretPath -and (Test-ZapretRoot $cfg.ZapretPath)) {
        Add-Log "Взял сохранённый путь: $($cfg.ZapretPath)" '#8B9BB4'
        return [string]$cfg.ZapretPath
    }
    $near = @(Find-ZapretNear $script:AppDir)
    if ($near.Count -gt 0) {
        if ($near.Count -gt 1) {
            Add-Log ('Рядом найдено несколько сборок: ' + (($near | ForEach-Object { $_.Path }) -join ' | ')) '#E8C36A'
        }
        return $near[0].Path
    }
    return $null
}

function Show-BusyOverlay {
    param([string]$Title, [string]$Sub = '', [int]$Percent = -1)
    if (-not $script:PnlOverlay) { return }
    $script:PnlOverlay.Visibility = 'Visible'
    if ($script:BtnOverlayRetry) { $script:BtnOverlayRetry.Visibility = 'Collapsed' }
    if ($script:LblOverlayTitle) { $script:LblOverlayTitle.Text = $Title }
    if ($script:LblOverlaySub) { $script:LblOverlaySub.Text = $Sub }
    if ($script:PrgOverlay) {
        if ($Percent -lt 0) {
            $script:PrgOverlay.IsIndeterminate = $true
        } else {
            $script:PrgOverlay.IsIndeterminate = $false
            $script:PrgOverlay.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
        }
    }
    if ($script:LblOverlayPct) {
        $script:LblOverlayPct.Text = if ($Percent -ge 0) { "$Percent%" } else { '' }
    }
}

function Hide-BusyOverlay {
    if ($script:PnlOverlay) { $script:PnlOverlay.Visibility = 'Collapsed' }
    if ($script:PrgOverlay) { $script:PrgOverlay.IsIndeterminate = $false }
}

function Find-ZapretInTree {
    param([string]$Root, [int]$Depth = 3)
    if (Test-ZapretRoot $Root) { return $Root }
    if ($Depth -le 0) { return $null }
    foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        $hit = Find-ZapretInTree -Root $dir.FullName -Depth ($Depth - 1)
        if ($hit) { return $hit }
    }
    return $null
}

function Start-ZapretAutoSetup {
    param([switch]$Update)
    if ($script:SetupSync -and -not $script:SetupSync.Done) { return }
    if ($Update) {
        $script:SetupIsUpdate = $true
        $script:PendingUpdateStrategy = Get-PreferredStrategyName
        $script:UpdateFromRoot = [string]$script:Root
        Show-BusyOverlay 'Обновляю zapret' 'Запрос к GitHub Flowseal...' -1
        Add-Log 'Найдена новая версия zapret — скачиваю официальную сборку' '#5865F2'
    } else {
        $script:SetupIsUpdate = $false
        Show-BusyOverlay 'Скачиваю zapret' 'Запрос к GitHub Flowseal...' -1
        Add-Log 'zapret рядом не найден — скачиваю официальную сборку с GitHub' '#5865F2'
    }
    $sync = [hashtable]::Synchronized(@{
        Done = $false; Error = ''; Path = ''; Percent = 0; Status = 'Подключение к GitHub...'; Stage = 'info'; Version = ''
    })
    $script:SetupSync = $sync
    $destRoot = $script:AppDir
    $api = $script:GithubApiUrl
    $versionUrl = $script:GithubVersionUrl
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $setupPipeline = $ps.AddScript({
        param($DestRoot, $ApiUrl, $VersionUrl, $Sync)
        function Fail($msg) { $Sync.Error = $msg; $Sync.Stage = 'error'; $Sync.Done = $true }
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object Net.WebClient
            $wc.Headers['User-Agent'] = 'ZapretGUI'
            $wc.Headers['Accept'] = 'application/vnd.github+json'
            $zipUrl = $null
            $version = ''
            try {
                $json = $wc.DownloadString($ApiUrl)
                $rel = $json | ConvertFrom-Json
                $version = [string]$rel.tag_name
                $asset = @($rel.assets) | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
                if ($asset) { $zipUrl = [string]$asset.browser_download_url }
            } catch { }
            if (-not $zipUrl) {
                $version = ([string]$wc.DownloadString($VersionUrl)).Trim()
                $zipUrl = "https://github.com/Flowseal/zapret-discord-youtube/releases/download/$version/zapret-discord-youtube-$version.zip"
            }
            $zipUri = [Uri]$zipUrl
            if ($zipUri.Scheme -ne 'https' -or $zipUri.Host -ne 'github.com') {
                throw "GitHub вернул недопустимый адрес архива: $zipUrl"
            }
            $Sync.Version = $version
            $Sync.Status = "Скачиваю zapret $version"
            $Sync.Stage = 'download'
            $tmpDir = Join-Path $env:TEMP ("zapret-gui-dl-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            $zipPath = Join-Path $tmpDir "zapret.zip"
            $req = [Net.HttpWebRequest]::Create($zipUrl)
            $req.UserAgent = 'ZapretGUI'
            $req.AllowAutoRedirect = $true
            $req.Timeout = 60000
            $resp = $req.GetResponse()
            $total = $resp.ContentLength
            if ($total -gt 500MB) { throw 'Архив zapret имеет недопустимо большой размер.' }
            $input = $resp.GetResponseStream()
            $output = [IO.File]::Create($zipPath)
            $buf = New-Object byte[] 65536
            $readTotal = [int64]0
            while (($n = $input.Read($buf, 0, $buf.Length)) -gt 0) {
                $output.Write($buf, 0, $n)
                $readTotal += $n
                if ($total -gt 0) { $Sync.Percent = [int][Math]::Min(100, (100.0 * $readTotal / $total)) }
                $Sync.Status = ('Скачиваю zapret {0}  ({1:N1} МБ)' -f $version, ($readTotal / 1MB))
            }
            $output.Close(); $input.Close(); $resp.Close()
            $zipStream = [IO.File]::OpenRead($zipPath)
            try {
                $firstByte = $zipStream.ReadByte()
                $secondByte = $zipStream.ReadByte()
            } finally {
                $zipStream.Dispose()
            }
            if ($firstByte -ne 0x50 -or $secondByte -ne 0x4B) {
                throw 'Загруженный файл не является ZIP-архивом.'
            }
            $Sync.Percent = 100
            $Sync.Stage = 'extract'
            $Sync.Status = 'Распаковываю архив...'
            $extract = Join-Path $tmpDir 'extract'
            New-Item -ItemType Directory -Path $extract -Force | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extract)
            function FindTree($root, $depth) {
                if (Test-Path (Join-Path $root 'service.bat')) { return $root }
                if (Test-Path (Join-Path $root 'bin\winws.exe')) { return $root }
                if ($depth -le 0) { return $null }
                foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                    $h = FindTree $d.FullName ($depth - 1)
                    if ($h) { return $h }
                }
                return $null
            }
            $found = FindTree $extract 4
            if (-not $found) { Fail 'В архиве не найдена сборка zapret (service.bat / winws.exe).'; return }
            $leaf = Split-Path -Leaf $found
            if ($leaf -eq 'extract' -or $leaf -eq 'bin') { $leaf = "zapret-discord-youtube-$version" }
            $dest = Join-Path $DestRoot $leaf
            if (Test-Path -LiteralPath $dest) {
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $dest = Join-Path $DestRoot ("$leaf-$stamp")
            }
            Move-Item -LiteralPath $found -Destination $dest
            try { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
            $Sync.Path = $dest
            $Sync.Status = "Готово: $dest"
            $Sync.Stage = 'done'
            $Sync.Done = $true
        } catch {
            Fail $_.Exception.Message
        }
    }).AddArgument($destRoot).AddArgument($api).AddArgument($versionUrl).AddArgument($sync)
    $script:SetupPs = $ps
    $script:SetupRs = $rs
    $script:SetupHandle = $ps.BeginInvoke()
}

function Complete-ZapretAutoSetup {
    if (-not $script:SetupSync -or -not $script:SetupSync.Done) { return }
    $sync = $script:SetupSync
    $script:SetupSync = $null
    try { $setupOutput = $script:SetupPs.EndInvoke($script:SetupHandle) } catch { }
    try { $script:SetupPs.Dispose() } catch { }
    try { $script:SetupRs.Close(); $script:SetupRs.Dispose() } catch { }
    if ($sync.Error) {
        Add-Log "Не удалось скачать zapret: $($sync.Error)" '#F23F42'
        Show-BusyOverlay 'Не удалось скачать zapret' $sync.Error -1
        if ($script:BtnOverlayRetry) { $script:BtnOverlayRetry.Visibility = 'Visible' }
        $script:OverlayRetryUpdate = [bool]$script:SetupIsUpdate
        return
    }
    $isUpdate = [bool]$script:SetupIsUpdate
    $keepStrategy = [string]$script:PendingUpdateStrategy
    $script:SetupIsUpdate = $false
    try {
        if ($isUpdate) {
            Complete-ZapretUpdate -NewPath $sync.Path -StrategyName $keepStrategy
            return
        }
        Set-ZapretRoot $sync.Path
        Add-Log "Скачано и подключено: $($sync.Path)" '#23A559'
        Hide-BusyOverlay
        Start-GithubCheck
        if (-not $script:FirstRunCompleted) {
            Show-FirstRunStrategyOffer
        }
    } catch {
        Add-Log $_.Exception.Message '#F23F42'
        Show-BusyOverlay 'Ошибка подключения' $_.Exception.Message -1
        if ($script:BtnOverlayRetry) { $script:BtnOverlayRetry.Visibility = 'Visible' }
        $script:OverlayRetryUpdate = $isUpdate
    }
}

function Complete-FirstRun {
    $script:FirstRunCompleted = $true
    Save-SettingsSafe
}

function Show-FirstRunStrategyOffer {
    if ($script:FirstRunCompleted -or $script:FirstRunPromptActive -or -not $script:Root) { return }
    $script:FirstRunPromptActive = $true
    try {
        $state = Get-ZapretState
        if ($state.ServiceInstalled) {
            Complete-FirstRun
            Add-Log 'Первичная настройка завершена: служба zapret уже установлена.' '#23A559'
            return
        }
        $names = @($script:CmbStrategy.Items | ForEach-Object { [string]$_ })
        if ($names.Count -eq 0) {
            $noStrategies = Show-ZapretDialog -Title 'Первый запуск' -Buttons 'OK' -Message 'В подключённой папке не найдено стратегий для проверки.'
            return
        }
        $answer = Show-ZapretDialog -Title 'Первый запуск · подбор стратегии' -Buttons 'YesNo' -Message "Zapret подключён. Проверить все $($names.Count) стратегий, выбрать лучшую и установить её как службу с автозапуском Windows?`n`nВо время проверки интернет может кратковременно переключаться."
        Complete-FirstRun
        if ($answer -eq 'Yes') {
            Add-Log 'Первый запуск: начинаю подбор лучшей стратегии.' '#5865F2'
            Start-StrategyTestsSafe $names -AutoInstallBest
        } else {
            Add-Log 'Первый запуск: автоматический подбор стратегии пропущен пользователем.' '#E8C36A'
        }
    } finally {
        $script:FirstRunPromptActive = $false
    }
}

function Show-ZapretSetupOffer {
    if ($script:FirstRunPromptActive -or $script:Root) { return }
    $script:FirstRunPromptActive = $true
    try {
        $answer = Show-ZapretDialog -Title 'Настройка zapret' -Buttons 'YesNoCancel' -Message "Zapret рядом с программой и в сохранённых настройках не найден.`n`nДа — скачать последнюю официальную версию Flowseal с GitHub.`nНет — выбрать уже установленную папку.`nОтмена — продолжить без настройки."
        if ($answer -eq 'Yes') {
            Add-Log 'Загрузка подтверждена пользователем.' '#5865F2'
            Start-ZapretAutoSetup
        } elseif ($answer -eq 'No') {
            Invoke-Browse
        } else {
            Add-Log 'Настройка zapret отложена.' '#E8C36A'
        }
    } finally {
        $script:FirstRunPromptActive = $false
    }
    if ($script:Root -and -not $script:FirstRunCompleted) {
        Show-FirstRunStrategyOffer
    }
}

function Update-BusyOverlayFromState {
    if ($script:SetupSync -and -not $script:SetupSync.Done) {
        $st = [string]$script:SetupSync.Status
        $pct = [int]$script:SetupSync.Percent
        $stage = [string]$script:SetupSync.Stage
        $title = if ($stage -eq 'extract') { 'Распаковка' } else { 'Скачиваю zapret' }
        Show-BusyOverlay $title $st $(if ($stage -eq 'extract') { -1 } else { $pct })
        return
    }
    if ($script:TestBusy -and $script:TestSync) {
        $i = [int]$script:TestSync.Index
        $n = [int]$script:TestSync.Total
        $name = [string]$script:TestSync.Name
        if ($n -gt 0 -and $i -gt 0) {
            $pct = [int][Math]::Floor(100.0 * ($i - 1) / $n)
            Show-BusyOverlay 'Проверка стратегий' ("[$i / $n]  $name") $pct
        } else {
            Show-BusyOverlay 'Проверка стратегий' 'Запуск тестов...' -1
        }
    }
}

function Save-SettingsSafe {
    try {
        Save-Settings
    } catch {
        $dir = Join-Path $env:APPDATA 'ZapretGUI'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $script:SettingsPath = Join-Path $dir 'settings.json'
        Save-Settings
    }
}

function Set-HealthIntervalMinutes {
    param(
        $Value,
        [switch]$Save
    )
    try { $minutes = [int]$Value } catch { $minutes = 1 }
    $minutes = [Math]::Max(1, [Math]::Min(1440, $minutes))
    $script:HealthIntervalMinutes = $minutes
    $script:NextHealthCheckAt = (Get-Date).AddMinutes($minutes)
    if ($script:TxtHealthInterval -and $script:TxtHealthInterval.Text -ne [string]$minutes) {
        $script:TxtHealthInterval.Text = [string]$minutes
    }
    if ($Save) {
        Save-SettingsSafe
        Add-Log "Автопроверка серверов: каждые $minutes мин." '#8B9BB4'
    }
}

function Get-ZapretVersion {
    param([string]$Root)
    $service = Join-Path $Root 'service.bat'
    if (Test-Path -LiteralPath $service) {
        foreach ($line in [IO.File]::ReadAllLines($service)) {
            if ($line -match 'LOCAL_VERSION=([0-9.]+)') { return $Matches[1] }
        }
    }
    $name = Split-Path -Leaf $Root
    if ($name -match '(\d+\.\d+[\.\d]*)') { return $Matches[1] }
    return ''
}

function Get-ReferencedListPaths {
    param([string]$BatPath)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $BatPath)) { return @() }
    $text = [IO.File]::ReadAllText($BatPath)
    foreach ($m in [regex]::Matches($text, '--(?:hostlist|hostlist-exclude|ipset|ipset-exclude)="([^"]+)"')) {
        $raw = $m.Groups[1].Value
        $raw = $raw -replace '%LISTS%', (Join-Path $script:Root 'lists\')
        $raw = $raw -replace '%~dp0lists\\', (Join-Path $script:Root 'lists\')
        $raw = $raw -replace '%~dp0', ($script:Root.TrimEnd('\') + '\')
        $pathAdded = $set.Add([IO.Path]::GetFullPath($raw))
    }
    $paths = [string[]]::new($set.Count)
    $set.CopyTo($paths)
    return $paths
}

function Get-UserListInfos {
    $result = [System.Collections.Generic.List[object]]::new()
    if (-not $script:Lists -or -not (Test-Path -LiteralPath $script:Lists)) { return @() }

    $selectedBat = $null
    if ($script:CmbStrategy -and $script:CmbStrategy.SelectedItem) {
        $selectedBat = Join-Path $script:Root ([string]$script:CmbStrategy.SelectedItem)
    }
    $wired = @()
    if ($selectedBat) { $wired = Get-ReferencedListPaths $selectedBat }

    $files = @(Get-ChildItem -LiteralPath $script:Lists -File -Filter '*.txt' -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $isUser = $file.Name -match 'user'
        $isDummyOnly = $file.Name -match 'example'
        if (-not $isUser) { continue }
        $kind = 'host'
        if ($file.Name -match 'ipset') { $kind = 'ip' }
        $role = 'bypass'
        if ($file.Name -match 'exclude') { $role = 'exclude' }
        $full = $file.FullName
        $isWired = $false
        foreach ($w in $wired) {
            if ([string]::Equals($w, $full, 'OrdinalIgnoreCase')) { $isWired = $true; break }
        }
        $result.Add([pscustomobject]@{
            Name    = $file.Name
            Path    = $full
            Kind    = $kind
            Role    = $role
            Wired   = $isWired
            Display = if ($isWired) { $file.Name } else { "$($file.Name)  (не в этой стратегии)" }
        })
    }
    return @($result | Sort-Object { if ($_.Wired) { 0 } else { 1 } }, Name)
}

function Read-ListEntries {
    param([string]$Path, [string]$Dummy)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        if ($line -eq $Dummy) { continue }
        $items.Add($line)
    }
    return $items.ToArray()
}

function Save-ListEntries {
    param([string]$Path, [string[]]$Entries, [string]$Dummy, [switch]$KeepComment)
    $unique = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($item in $Entries) {
        $key = $item.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key) -or $seen.ContainsKey($key) -or $key -eq $Dummy) { continue }
        $seen[$key] = $true
        $unique.Add($item.Trim())
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($KeepComment) { $lines.Add('# Never leave this file empty') }
    if ($unique.Count -eq 0) { $lines.Add($Dummy) } else { foreach ($u in $unique) { $lines.Add($u) } }
    Write-Utf8Lines $Path $lines.ToArray()
}

function ConvertTo-HostName {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $value = $Raw.Trim()
    $value = $value -replace '^\^', ''
    $value = $value -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
    $value = $value -replace '^[^@/]+@', ''
    $value = ($value -split '[/?#]', 2)[0]
    $value = $value.Trim().TrimEnd('.')
    if ($value -match '^\[.+' ) { return $null }
    if ($value -match '^([^:]+):\d+$') { $value = $Matches[1] }
    $value = $value.Trim().ToLowerInvariant()
    if ($value.StartsWith('www.')) { $value = $value.Substring(4) }
    if ($value -match '^\d{1,3}(\.\d{1,3}){3}$') { return $null }
    try {
        $idn = New-Object System.Globalization.IdnMapping
        $value = $idn.GetAscii($value)
    } catch { return $null }
    if ($value -notmatch '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$') {
        return $null
    }
    return $value
}

function Test-HostInFiles {
    param([string]$HostName, [string[]]$Files)
    $needle = $HostName.ToLowerInvariant()
    foreach ($file in $Files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($raw in [IO.File]::ReadAllLines($file)) {
            $line = $raw.Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            $plain = $line.TrimStart('^')
            if ($plain -eq $needle) { return $true }
            if (-not $line.StartsWith('^') -and $needle.EndsWith('.' + $plain)) { return $true }
        }
    }
    return $false
}

function Get-InstalledStrategy {
    try {
        $val = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop
        return [string]$val.'zapret-discord-youtube'
    } catch { return $null }
}

function Get-ZapretState {
    $svc = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    $winws = @(Get-Process -Name 'winws' -ErrorAction SilentlyContinue)
    $svcRunning = [bool]($svc -and $svc.Status -eq 'Running')
    $ours = $false
    $other = $false
    $bin = [string]$script:Bin
    $root = [string]$script:Root
    foreach ($proc in $winws) {
        $path = ''
        try { $path = [string]$proc.Path } catch { $path = '' }
        if (-not $path) {
            try { $path = [string]$proc.MainModule.FileName } catch { $path = '' }
        }
        if ($path -and (
            ($bin -and $path.StartsWith($bin, [StringComparison]::OrdinalIgnoreCase)) -or
            ($root -and $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase))
        )) {
            $ours = $true
        } else {
            $other = $true
        }
    }
    $running = $svcRunning -or ($winws.Count -gt 0)
    $mode = 'нет'
    if ($svcRunning) { $mode = 'служба' }
    elseif ($ours) { $mode = 'winws' }
    elseif ($winws.Count -gt 0) { $mode = 'чужой winws' }
    [pscustomobject]@{
        ServiceInstalled = [bool]$svc
        ServiceRunning   = $svcRunning
        WinwsRunning     = $winws.Count -gt 0
        ThisBuildRunning = $svcRunning -or $ours
        OtherWinws       = $other -and -not $ours -and -not $svcRunning
        Running          = $running
        Mode             = $mode
        WinwsCount       = $winws.Count
        Strategy         = Get-InstalledStrategy
    }
}

function Enable-TcpTimestamps {
    try {
        $show = netsh interface tcp show global
        if ($show -notmatch 'timestamps\s+enabled') {
            netsh interface tcp set global timestamps=enabled | Out-Null
        }
    } catch { }
}

function Stop-Zapret {
    param([switch]$Quiet)
    $svc = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name 'zapret' -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) { Add-Log 'Служба zapret остановлена' '#E8C36A' }
    }
    Get-Process -Name 'winws' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 350
}

function Start-StrategyFile {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Выберите стратегию.' }
    $bat = Join-Path $script:Root $Name
    if (-not (Test-Path -LiteralPath $bat)) { throw "Стратегия не найдена: $Name" }
    $state = Get-ZapretState
    if ($state.ServiceInstalled) {
        throw 'Установлена служба zapret. Снимите её, чтобы запускать стратегии из GUI.'
    }
    Enable-TcpTimestamps
    Invoke-LoadUserLists
    Save-SettingsSafe
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $bat
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $true
    $psi.WindowStyle = 'Hidden'
    $strategyProcess = [Diagnostics.Process]::Start($psi)
    Add-Log "Запуск $Name" '#3DDC97'
}

function Start-ZapretFromMain {
    $state = Get-ZapretState
    if ($state.ServiceInstalled) {
        Invoke-LoadUserLists
        if ($state.ServiceRunning) {
            Stop-Service -Name 'zapret' -Force -ErrorAction Stop
            Add-Log 'Служба zapret остановлена для перезапуска' '#E8C36A'
        }
        Start-Service -Name 'zapret' -ErrorAction Stop
        $strategy = if ($state.Strategy) { " ($($state.Strategy))" } else { '' }
        Add-Log "Служба zapret запущена$strategy" '#3DDC97'
        Start-LiveHealthCheck -Force
        return
    }
    $name = if ($script:CmbStrategy) { [string]$script:CmbStrategy.SelectedItem } else { '' }
    if (-not $name) {
        throw 'Выберите стратегию в настройках.'
    }
    Add-Log "Служба не установлена — устанавливаю выбранную стратегию: $name" '#6EC6FF'
    Install-ZapretService -StrategyName $name
}

function Start-InstalledZapretService {
    $state = Get-ZapretState
    if (-not $state.ServiceInstalled -or $state.ServiceRunning) { return }
    Invoke-LoadUserLists
    Start-Service -Name 'zapret' -ErrorAction Stop
    $strategy = if ($state.Strategy) { " ($($state.Strategy))" } else { '' }
    Add-Log "Установленная служба zapret запущена автоматически$strategy" '#3DDC97'
    Refresh-Status
    Start-LiveHealthCheck -Force
}

function Wait-Winws {
    param([int]$TimeoutMs = 8000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        if (Get-Process -Name 'winws' -ErrorAction SilentlyContinue) {
            Start-Sleep -Milliseconds 400
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Invoke-LoadUserLists {
    $service = Join-Path $script:Root 'service.bat'
    if (Test-Path -LiteralPath $service) {
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$service`" load_user_lists" -WorkingDirectory $script:Root -WindowStyle Hidden -Wait | Out-Null
    }
}

function Get-CurrentListInfo {
    if (-not $script:CmbList) { return $null }
    if ($script:CmbList.SelectedItem) {
        $item = $script:CmbList.SelectedItem
        if ($item -is [Windows.Controls.ComboBoxItem]) { return $item.Tag }
        return $item
    }
    foreach ($it in @($script:CmbList.Items)) {
        $tag = if ($it -is [Windows.Controls.ComboBoxItem]) { $it.Tag } else { $it }
        if ($tag -and $tag.Name -eq 'list-general-user.txt') { return $tag }
    }
    if ($script:CmbList.Items.Count -gt 0) {
        $first = $script:CmbList.Items[0]
        if ($first -is [Windows.Controls.ComboBoxItem]) { return $first.Tag }
        return $first
    }
    return $null
}

function Restart-ZapretIfNeeded {
    if ($script:ChkRestart -and -not $script:ChkRestart.IsChecked) { return }
    $state = Get-ZapretState
    if (-not $state.Running -and -not $state.ServiceInstalled) { return }
    $script:Restarting = $true
    try {
        if ($state.ServiceInstalled) {
            Restart-Service -Name 'zapret' -Force -ErrorAction Stop
            Add-Log 'Служба перезапущена, список применён' '#3DDC97'
            return
        }
        $name = [string]$script:CmbStrategy.SelectedItem
        Stop-Zapret -Quiet
        Start-Sleep -Milliseconds 400
        if ($name) { Start-StrategyFile $name }
    } catch {
        Add-Log "Перезапуск не удался: $($_.Exception.Message)" '#FF8A8A'
    } finally {
        $script:Restarting = $false
    }
}

function Get-DefaultTargets {
    $file = Join-Path $script:Utils 'targets.txt'
    $map = [System.Collections.Specialized.OrderedDictionary]::new()
    if (Test-Path -LiteralPath $file) {
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line -match '^\s*(\w+)\s*=\s*"(.+)"\s*$') {
                if ($map.Contains($Matches[1])) { $map[$Matches[1]] = $Matches[2] } else { $map.Add($Matches[1], $Matches[2]) }
            }
        }
    }
    if ($map.Count -eq 0) {
        $map.Add('DiscordMain', 'https://discord.com')
        $map.Add('YouTubeWeb', 'https://www.youtube.com')
        $map.Add('GoogleMain', 'https://www.google.com')
        $map.Add('CloudflareWeb', 'https://www.cloudflare.com')
    }
    $list = @()
    foreach ($key in $map.Keys) {
        $val = [string]$map[$key]
        if ($val -like 'PING:*') {
            $list += [pscustomobject]@{ Name = $key; Url = $null; Ping = ($val -replace '^PING:\s*', '') }
        } else {
            $hostName = ($val -replace '^https?://', '' -replace '/.*$', '')
            $list += [pscustomobject]@{ Name = $key; Url = $val; Ping = $hostName }
        }
    }
    return $list
}

function Get-LiveCheckTargets {
    $all = @(Get-DefaultTargets | Where-Object { $_.Url })
    $discord = @($all | Where-Object { $_.Name -match 'Discord' })
    $youtube = @($all | Where-Object { $_.Name -match 'YouTube' })
    if ($discord.Count -eq 0) {
        $discord = @(
            [pscustomobject]@{ Name = 'DiscordMain'; Url = 'https://discord.com'; Ping = 'discord.com' }
            [pscustomobject]@{ Name = 'DiscordGateway'; Url = 'https://gateway.discord.gg'; Ping = 'gateway.discord.gg' }
            [pscustomobject]@{ Name = 'DiscordCDN'; Url = 'https://cdn.discordapp.com'; Ping = 'cdn.discordapp.com' }
            [pscustomobject]@{ Name = 'DiscordUpdates'; Url = 'https://updates.discord.com'; Ping = 'updates.discord.com' }
        )
    }
    if ($youtube.Count -eq 0) {
        $youtube = @(
            [pscustomobject]@{ Name = 'YouTubeWeb'; Url = 'https://www.youtube.com'; Ping = 'www.youtube.com' }
            [pscustomobject]@{ Name = 'YouTubeShort'; Url = 'https://youtu.be'; Ping = 'youtu.be' }
            [pscustomobject]@{ Name = 'YouTubeImage'; Url = 'https://i.ytimg.com'; Ping = 'i.ytimg.com' }
            [pscustomobject]@{ Name = 'YouTubeVideoRedirect'; Url = 'https://redirector.googlevideo.com'; Ping = 'redirector.googlevideo.com' }
        )
    }
    return @{ Discord = $discord; Youtube = $youtube }
}

function Get-TargetLabel {
    param([string]$Name, [string]$HostName)
    switch -Regex ($Name) {
        'DiscordMain' { return 'Discord' }
        'Gateway' { return 'Gateway' }
        'CDN' { return 'CDN' }
        'Updates' { return 'Updates' }
        'YouTubeWeb' { return 'YouTube' }
        'YouTubeShort' { return 'youtu.be' }
        'Image' { return 'Превью' }
        'Video|googlevideo' { return 'Видео' }
        default { return $HostName }
    }
}

function New-HealthRow {
    param($Item)
    $row = [Windows.Controls.StackPanel]::new()
    $row.Orientation = [Windows.Controls.Orientation]::Horizontal
    $row.Margin = [Windows.Thickness]::new(0, 0, 0, 6)

    $dot = [Windows.Shapes.Ellipse]::new()
    $dot.Width = 10
    $dot.Height = 10
    $dot.Margin = [Windows.Thickness]::new(0, 4, 10, 0)
    $dot.Fill = ConvertTo-Brush $Item.Color
    $dot.VerticalAlignment = [Windows.VerticalAlignment]::Top

    $col = [Windows.Controls.StackPanel]::new()
    $t1 = [Windows.Controls.TextBlock]::new()
    $t1.Text = [string]$Item.Label
    $t1.FontWeight = [Windows.FontWeights]::SemiBold
    $t1.Foreground = ConvertTo-Brush '#F2F3F5'
    $t2 = [Windows.Controls.TextBlock]::new()
    $t2.Text = [string]$Item.Host
    $t2.FontSize = 11
    $t2.Foreground = ConvertTo-Brush '#949BA4'
    $col.Children.Insert($col.Children.Count, $t1)
    $col.Children.Insert($col.Children.Count, $t2)

    $st = [Windows.Controls.TextBlock]::new()
    $st.Text = [string]$Item.Status
    $st.Foreground = ConvertTo-Brush $Item.Color
    $st.FontSize = 12
    $st.Margin = [Windows.Thickness]::new(12, 4, 0, 0)
    $st.VerticalAlignment = [Windows.VerticalAlignment]::Center

    $row.Children.Insert($row.Children.Count, $dot)
    $row.Children.Insert($row.Children.Count, $col)
    $row.Children.Insert($row.Children.Count, $st)
    return $row
}

function Show-HealthPlaceholders {
    $targets = Get-LiveCheckTargets
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $targets.Discord) {
        $rows.Add([pscustomobject]@{
            Group = 'Discord'; Name = $t.Name; Host = $t.Ping; Label = (Get-TargetLabel $t.Name $t.Ping)
            Ok = $false; Status = 'проверка...'; Color = '#80848E'
        })
    }
    foreach ($t in $targets.Youtube) {
        $rows.Add([pscustomobject]@{
            Group = 'Youtube'; Name = $t.Name; Host = $t.Ping; Label = (Get-TargetLabel $t.Name $t.Ping)
            Ok = $false; Status = 'проверка...'; Color = '#80848E'
        })
    }
    $script:HealthResults = $rows
    Update-HealthPanels $rows
}

function Update-HealthPanels {
    param($Results)
    if (-not $script:PnlDiscord) { return }
    $script:PnlDiscord.Children.Clear()
    $script:PnlYoutube.Children.Clear()
    $dOk = 0; $dN = 0; $yOk = 0; $yN = 0
    foreach ($item in $Results) {
        try {
            $row = New-HealthRow $item
            if ($item.Group -eq 'Discord') {
                $script:PnlDiscord.Children.Insert($script:PnlDiscord.Children.Count, $row)
                $dN++; if ($item.Ok) { $dOk++ }
            } else {
                $script:PnlYoutube.Children.Insert($script:PnlYoutube.Children.Count, $row)
                $yN++; if ($item.Ok) { $yOk++ }
            }
        } catch {
            Add-Log "Статус $($item.Host): $($_.Exception.Message)" '#F23F42'
        }
    }
    if ($script:LblDiscordSummary) { $script:LblDiscordSummary.Text = if ($dN) { "$dOk/$dN" } else { '' } }
    if ($script:LblYoutubeSummary) { $script:LblYoutubeSummary.Text = if ($yN) { "$yOk/$yN" } else { '' } }
}

function Start-LiveHealthCheck {
    param([switch]$Force)
    if ($Force) { $script:HealthCheckPending = $true }
    if ($script:HealthBusy) { return }
    if ($script:TestBusy) { return }
    if ($script:SetupSync -and -not $script:SetupSync.Done) { return }
    if (-not $script:Root) { return }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return }
    $script:HealthCheckPending = $false
    $script:NextHealthCheckAt = (Get-Date).AddMinutes($script:HealthIntervalMinutes)
    $targets = Get-LiveCheckTargets
    Show-HealthPlaceholders
    $script:HealthBusy = $true
    $queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $script:HealthQueue = $queue
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $healthPipeline = $ps.AddScript({
        param($Discord, $Youtube, $Queue)
        function CheckOne($t, $group) {
            $ok = $false
            $code = '000'
            $ms = 0
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                $raw = & curl.exe @('-I', '-s', '-m', '4', '--connect-timeout', '2', '-o', 'NUL', '-w', '%{http_code}', '--tlsv1.2', $t.Url) 2>&1 | Out-String
                $code = ($raw -replace '(?s).*?(\d{3})\s*$', '$1').Trim()
                if ($code -notmatch '^\d{3}$') { $code = '000' }
                $ok = ($code -ne '000')
            } catch { $ok = $false }
            $ms = [int]$sw.ElapsedMilliseconds
            $status = if ($ok) { "OK · ${ms} мс" } else { 'Нет ответа' }
            $color = if ($ok) { '#23A559' } else { '#F23F42' }
            $Queue.Enqueue([pscustomobject]@{
                Group = $group; Name = $t.Name; Host = $t.Ping; Ok = $ok; Status = $status; Color = $color; Code = $code
            })
        }
        foreach ($t in @($Discord)) { CheckOne $t 'Discord' }
        foreach ($t in @($Youtube)) { CheckOne $t 'Youtube' }
        $Queue.Enqueue([pscustomobject]@{ Done = $true })
    }).AddArgument(@($targets.Discord)).AddArgument(@($targets.Youtube)).AddArgument($queue)
    $script:HealthPs = $ps
    $script:HealthRs = $rs
    $script:HealthHandle = $ps.BeginInvoke()
}

function Complete-LiveHealthCheck {
    if (-not $script:HealthQueue) { return }
    $item = $null
    while ($script:HealthQueue.TryDequeue([ref]$item)) {
        if ($item.Done) {
            $script:HealthBusy = $false
            try { $script:HealthPs.EndInvoke($script:HealthHandle) } catch { }
            try { $script:HealthPs.Dispose() } catch { }
            try { $script:HealthRs.Close(); $script:HealthRs.Dispose() } catch { }
            $script:HealthQueue = $null
            if ($script:HealthCheckPending) {
                $script:NextHealthCheckAt = [datetime]::MinValue
            }
            return
        }
        $item | Add-Member -NotePropertyName Label -NotePropertyValue (Get-TargetLabel $item.Name $item.Host) -Force
        if (-not $script:HealthResults) { $script:HealthResults = [System.Collections.Generic.List[object]]::new() }
        $existing = $null
        foreach ($r in $script:HealthResults) {
            if ($r.Name -eq $item.Name -and $r.Group -eq $item.Group) { $existing = $r; break }
        }
        if ($existing) { $removed = $script:HealthResults.Remove($existing) }
        $script:HealthResults.Add($item)
        Update-HealthPanels $script:HealthResults
    }
}

function Test-OneUrl {
    param([string]$Url, [int]$TimeoutSec = 5)
    $tests = @(
        @{ Label = 'HTTP'; Args = @('--http1.1') }
        @{ Label = 'TLS1.2'; Args = @('--tlsv1.2', '--tls-max', '1.2') }
        @{ Label = 'TLS1.3'; Args = @('--tlsv1.3', '--tls-max', '1.3') }
    )
    $pieces = @()
    foreach ($t in $tests) {
        $args = @('-I', '-s', '-m', "$TimeoutSec", '--connect-timeout', '3', '-o', 'NUL', '-w', '%{http_code}') + $t.Args + @($Url)
        $output = & curl.exe @args 2>&1 | Out-String
        $code = ($output -replace '(?s).*?(\d{3})\s*$', '$1').Trim()
        $ok = ($LASTEXITCODE -eq 0)
        if ($ok) { $pieces += "$($t.Label):OK" } else { $pieces += "$($t.Label):ERROR" }
    }
    return $pieces
}

function Save-TestReport {
    param([string]$Text)
    if (-not $script:Utils) { return $null }
    $dir = Join-Path $script:Utils 'test results'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir ('gui_test_{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    Write-Utf8Lines $path @($Text -split "`n")
    return $path
}

function Remove-ZapretService {
    param([switch]$Quiet)
    $svc = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name 'zapret' -Force -ErrorAction SilentlyContinue
        sc.exe delete zapret | Out-Null
        if (-not $Quiet) { Add-Log 'Служба zapret снята' '#E8C36A' }
    }
    Stop-Zapret -Quiet
    foreach ($name in @('WinDivert', 'WinDivert14')) {
        sc.exe stop $name 2>$null | Out-Null
        sc.exe delete $name 2>$null | Out-Null
    }
}

function Get-WinwsCommandLine {
    try {
        $proc = Get-CimInstance Win32_Process -Filter "Name = 'winws.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($proc -and $proc.CommandLine) { return [string]$proc.CommandLine }
    } catch { }
    return $null
}

function Install-ZapretService {
    param([string]$StrategyName)
    if ([string]::IsNullOrWhiteSpace($StrategyName)) { throw 'Нет стратегии для установки в службу.' }
    $bat = Join-Path $script:Root $StrategyName
    if (-not (Test-Path -LiteralPath $bat)) { throw "Стратегия не найдена: $StrategyName" }

    $winws = Join-Path $script:Root 'bin\winws.exe'
    if (-not (Test-Path -LiteralPath $winws)) { $winws = Join-Path $script:Root 'winws.exe' }
    if (-not (Test-Path -LiteralPath $winws)) { throw 'winws.exe не найден в этой сборке zapret.' }

    Add-Log "Ставлю службу zapret для $StrategyName (автозапуск с Windows)..." '#6EC6FF'
    Enable-TcpTimestamps
    Invoke-LoadUserLists
    Remove-ZapretService -Quiet
    Start-Sleep -Milliseconds 400

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $bat
    $psi.WorkingDirectory = $script:Root
    $psi.UseShellExecute = $true
    $psi.WindowStyle = 'Hidden'
    $strategyProcess = [Diagnostics.Process]::Start($psi)
    if (-not (Wait-Winws 12000)) { throw 'winws.exe не запустился — службу поставить нельзя.' }

    $cmd = Get-WinwsCommandLine
    if ([string]::IsNullOrWhiteSpace($cmd)) { throw 'Не удалось прочитать командную строку winws.exe.' }
    Add-Log "Командная строка службы получена" '#8B9BB4'

    if ($cmd.StartsWith('"')) {
        $end = $cmd.IndexOf('"', 1)
        $exe = $cmd.Substring(1, $end - 1)
        $winArgs = $cmd.Substring($end + 1).Trim()
    } else {
        $sp = $cmd.IndexOf(' ')
        if ($sp -lt 0) { $exe = $cmd; $winArgs = '' } else {
            $exe = $cmd.Substring(0, $sp)
            $winArgs = $cmd.Substring($sp + 1).Trim()
        }
    }

    Stop-Zapret -Quiet
    Start-Sleep -Milliseconds 400
    sc.exe stop zapret 2>$null | Out-Null
    sc.exe delete zapret 2>$null | Out-Null

    $scBin = '\"{0}\" {1}' -f $exe, $winArgs
    $createOut = cmd.exe /c "sc create zapret binPath= `"$scBin`" DisplayName= `"zapret`" start= auto"
    Add-Log (($createOut | Out-String).Trim()) '#8B9BB4'
    cmd.exe /c 'sc description zapret "Zapret DPI bypass software"' | Out-Null

    $valueName = [IO.Path]::GetFileNameWithoutExtension($StrategyName)
    $regPath = 'HKLM:\System\CurrentControlSet\Services\zapret'
    if (Test-Path -LiteralPath $regPath) {
        New-ItemProperty -Path $regPath -Name 'zapret-discord-youtube' -Value $valueName -PropertyType String -Force | Out-Null
    }

    $startOut = cmd.exe /c 'sc start zapret'
    Add-Log (($startOut | Out-String).Trim()) '#8B9BB4'
    Start-Sleep -Milliseconds 900
    $svc = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') {
        throw 'Служба создана, но не запустилась. Откройте service.bat → Check Status.'
    }
    if (Test-ComboHasItem $script:CmbStrategy $StrategyName) {
        $script:CmbStrategy.SelectedItem = $StrategyName
    }
    Save-SettingsSafe
    Refresh-Status
    Add-Log "Готово: $StrategyName работает как служба и будет стартовать вместе с Windows." '#3DDC97'
    Start-LiveHealthCheck -Force
}

function Start-StrategyTestsSafe {
    param(
        [string[]]$StrategyNames,
        [switch]$AutoInstallBest
    )
    if ($script:TestBusy) { return }
    if (-not $StrategyNames -or $StrategyNames.Count -eq 0) { Add-Log 'Нет стратегий для теста' '#E8C36A'; return }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Add-Log 'curl.exe не найден' '#FF8A8A'; return }
    if ((Get-ZapretState).ServiceInstalled) {
        if ($AutoInstallBest) {
            Add-Log 'Снимаю текущую службу, чтобы прогнать автотест...' '#E8C36A'
            Remove-ZapretService -Quiet
        } else {
            Add-Log 'Снимите службу zapret перед тестом стратегий' '#FF8A8A'
            return
        }
    }

    $script:TestBusy = $true
    $script:TestCancel = $false
    $script:AutoInstallBest = [bool]$AutoInstallBest
    Set-TestUi $true
    Show-BusyOverlay 'Проверка стратегий' 'Запуск тестов...' -1
    $targets = @(Get-DefaultTargets)
    $root = $script:Root
    $queue = $script:LogQueue
    $sync = [hashtable]::Synchronized(@{ Cancel = $false; Report = ''; Done = $false; Best = ''; Cancelled = $false; Index = 0; Total = $StrategyNames.Count; Name = ''; Stage = 'test' })
    $script:TestSync = $sync
    if ($AutoInstallBest) {
        Add-Log ("Автотест лучшей стратегии: {0} шт., затем установка в службу" -f $StrategyNames.Count) '#6EC6FF'
    } else {
        Add-Log ("Старт теста: {0} стратегий, {1} целей" -f $StrategyNames.Count, $targets.Count) '#6EC6FF'
    }

    $script:TestRunspace = [runspacefactory]::CreateRunspace()
    $script:TestRunspace.ApartmentState = 'MTA'
    $script:TestRunspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $script:TestRunspace
    $testPipeline = $ps.AddScript({
        param($Root, $Names, $Targets, $Queue, $Sync)
        function QLog($msg, $color) {
            $Queue.Enqueue([pscustomobject]@{ Message = $msg; Color = $color; Time = Get-Date })
        }
        function Stop-Winws { Get-Process -Name 'winws' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
        $report = [System.Collections.Generic.List[string]]::new()
        $best = $null
        $bestOk = -1
        $i = 0
        try {
        foreach ($name in $Names) {
            $i++
            if ($Sync.Cancel) { QLog 'Тест прерван' '#E8C36A'; break }
            $Sync.Index = $i
            $Sync.Total = $Names.Count
            $Sync.Name = $name
            $bat = Join-Path $Root $name
            QLog ("[{0}/{1}] {2}" -f $i, $Names.Count, $name) '#E8C36A'
            $report.Add("Config: $name")
            Stop-Winws
            Start-Sleep -Milliseconds 300
            try {
                $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$bat`"" -WorkingDirectory $Root -WindowStyle Hidden -PassThru
            } catch {
                QLog "  не удалось запустить: $($_.Exception.Message)" '#FF8A8A'
                continue
            }
            $ready = $false
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 8000) {
                if (Get-Process -Name 'winws' -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 400; $ready = $true; break }
                Start-Sleep -Milliseconds 200
            }
            if (-not $ready) {
                QLog '  winws не стартовал, стратегия пропущена' '#FF8A8A'
                $report.Add('  START FAILED')
                if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
                continue
            }
            $okCount = 0
            $errCount = 0
            foreach ($t in $Targets) {
                if ($Sync.Cancel) { break }
                if ($t.Url) {
                    $tok = @()
                    foreach ($pair in @(
                        @{ L = 'HTTP'; A = @('--http1.1') },
                        @{ L = 'TLS1.2'; A = @('--tlsv1.2', '--tls-max', '1.2') },
                        @{ L = 'TLS1.3'; A = @('--tlsv1.3', '--tls-max', '1.3') }
                    )) {
                        $cargs = @('-I', '-s', '-m', '4', '--connect-timeout', '2', '-o', 'NUL', '-w', '%{http_code}') + $pair.A + @($t.Url)
                        $null = & curl.exe @cargs 2>&1
                        if ($LASTEXITCODE -eq 0) { $tok += "$($pair.L):OK"; $okCount++ } else { $tok += "$($pair.L):ERROR"; $errCount++ }
                    }
                    $line = "  $($t.Name)  $($tok -join '  ')"
                    $color = if ($tok -match 'ERROR') { '#FF8A8A' } else { '#3DDC97' }
                    QLog $line $color
                    $report.Add($line)
                } else {
                    $ms = 'Timeout'
                    try {
                        $ping = New-Object Net.NetworkInformation.Ping
                        $reply = $ping.Send($t.Ping, 1000)
                        if ($reply.Status -eq 'Success') { $ms = '{0:N0} ms' -f $reply.RoundtripTime }
                    } catch { }
                    $line = "  $($t.Name)  Ping: $ms"
                    QLog $line '#8B9BB4'
                    $report.Add($line)
                }
            }
            Stop-Winws
            if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
            $report.Add("  OK=$okCount ERR=$errCount")
            $report.Add('')
            QLog "  итог ${name}: OK=$okCount ERR=$errCount" '#6EC6FF'
            if ($okCount -gt $bestOk) { $bestOk = $okCount; $best = $name }
        }
        } catch {
            QLog "Автотест остановился: $($_.Exception.Message)" '#FF8A8A'
        } finally {
            Stop-Winws
            if ($Sync.Cancel) { $Sync.Cancelled = $true }
            if ($best) {
                QLog "Лучшая стратегия: $best (OK=$bestOk)" '#3DDC97'
                $report.Add("Best strategy: $best")
                $Sync.Best = $best
            }
            $Sync.Report = [string]::Join([Environment]::NewLine, $report)
            $Sync.Done = $true
        }
    }).AddArgument($root).AddArgument($StrategyNames).AddArgument($targets).AddArgument($queue).AddArgument($sync)
    $script:TestPs = $ps
    $script:TestHandle = $ps.BeginInvoke()
}

function Complete-StrategyTests {
    if (-not $script:TestSync -or -not $script:TestSync.Done) { return }
    try {
    $best = [string]$script:TestSync.Best
    $cancelled = [bool]$script:TestSync.Cancelled
    $auto = [bool]$script:AutoInstallBest
    $script:TestBusy = $false
    $script:AutoInstallBest = $false
    Set-TestUi $false
    $text = [string]$script:TestSync.Report
    $saved = Save-TestReport $text
    if ($saved) { Add-Log "Отчёт сохранён: $saved" '#8B9BB4' }
    try { $script:TestPs.EndInvoke($script:TestHandle) } catch { }
    try { $script:TestPs.Dispose() } catch { }
    try { $script:TestRunspace.Close(); $script:TestRunspace.Dispose() } catch { }
    $script:TestSync = $null
    $script:TestPs = $null
    if ($auto -and -not $cancelled -and $best) {
        try {
            $launchDlg = Show-ZapretDialog -Title 'Лучшая стратегия' -Buttons 'OK' -Message "Лучшая стратегия: $best.`nСейчас она будет запущена как служба zapret."
            Show-BusyOverlay 'Установка службы' "Лучшая стратегия: $best" -1
            if (Test-ComboHasItem $script:CmbStrategy $best) {
                $script:CmbStrategy.SelectedItem = $best
            }
            Install-ZapretService -StrategyName $best
            Hide-BusyOverlay
        } catch {
            Hide-BusyOverlay
            Add-Log "Автоустановка службы не удалась: $($_.Exception.Message)" '#FF8A8A'
        }
    } else {
        Hide-BusyOverlay
        if ($auto -and -not $best) {
            Add-Log 'Автотест не нашёл рабочую стратегию — служба не установлена.' '#FF8A8A'
        }
    }
    } catch {
        $script:TestBusy = $false
        $script:TestSync = $null
        Hide-BusyOverlay
        Set-TestUi $false
        Add-Log "Автотест: $($_.Exception.Message)" '#F23F42'
    }
}

function Set-TestUi {
    param([bool]$Busy)
    if (-not $script:BtnTestCurrent) { return }
    $script:BtnTestCurrent.IsEnabled = -not $Busy
    $script:BtnTestAll.IsEnabled = -not $Busy
    if ($script:BtnAutoBest) { $script:BtnAutoBest.IsEnabled = -not $Busy }
    if ($script:BtnInstallService) { $script:BtnInstallService.IsEnabled = -not $Busy }
    $script:BtnCheckSite.IsEnabled = -not $Busy
    $script:BtnCancelTest.IsEnabled = $Busy
    $script:BtnStart.IsEnabled = -not $Busy
    $script:BtnRestart.IsEnabled = -not $Busy
}

function Stop-Watcher {
    if ($script:Watcher) {
        $script:Watcher.EnableRaisingEvents = $false
        $script:Watcher.Dispose()
        $script:Watcher = $null
    }
}

function Start-Watcher {
    Stop-Watcher
    if (-not (Test-Path -LiteralPath $script:Root)) { return }
    $w = [IO.FileSystemWatcher]::new($script:Root, '*.bat')
    $w.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite'
    $w.EnableRaisingEvents = $true
    $handler = {
        if ($script:WatchTimer) { $script:WatchTimer.Stop(); $script:WatchTimer.Start() }
    }
    $null = Register-ObjectEvent -InputObject $w -EventName Created -Action $handler
    $null = Register-ObjectEvent -InputObject $w -EventName Deleted -Action $handler
    $null = Register-ObjectEvent -InputObject $w -EventName Renamed -Action $handler
    $script:Watcher = $w
}

function Set-ZapretRoot {
    param([string]$Path, [switch]$Silent)
    $Path = $Path.Trim().Trim('"')
    if (-not (Test-ZapretRoot $Path)) {
        throw "Это не папка zapret: нет service.bat, winws.exe или стратегий.`n$Path"
    }
    $script:Root = [IO.Path]::GetFullPath($Path)
    $script:Lists = Join-Path $script:Root 'lists'
    $script:Bin = Join-Path $script:Root 'bin'
    $script:Utils = Join-Path $script:Root 'utils'
    $script:Version = Get-ZapretVersion $script:Root
    if ($script:TxtPath) { $script:TxtPath.Text = $script:Root }
    Invoke-LoadUserLists
    Refresh-Strategies
    Refresh-ListCombo
    Refresh-SiteList
    Refresh-Status
    Start-Watcher
    Save-SettingsSafe
    if (-not $Silent) {
        $n = @($script:CmbStrategy.Items).Count
        $ver = if ($script:Version) { "v$($script:Version)" } else { 'версия не определена' }
        Add-Log "Папка zapret: $script:Root ($ver, стратегий: $n)" '#6EC6FF'
    }
    $script:NextHealthCheckAt = [datetime]::MinValue
    Start-LiveHealthCheck -Force
}

function Test-ComboHasItem {
    param($Combo, [string]$Name)
    if (-not $Combo -or [string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($it in $Combo.Items) {
        if ([string]$it -eq $Name) { return $true }
    }
    return $false
}

function Refresh-Strategies {
    if (-not $script:CmbStrategy) { return }
    $prev = [string]$script:CmbStrategy.SelectedItem
    $script:CmbStrategy.Items.Clear()
    $bats = @(Get-StrategyBats $script:Root)
    foreach ($b in $bats) { $script:CmbStrategy.Items.Add($b.Name) | Out-Null }
    if ($prev -and (Test-ComboHasItem $script:CmbStrategy $prev)) {
        $script:CmbStrategy.SelectedItem = $prev
    } elseif ($script:CmbStrategy.Items.Count -gt 0) {
        $cfg = Get-Settings
        if ($cfg -and $cfg.LastStrategy -and (Test-ComboHasItem $script:CmbStrategy $cfg.LastStrategy)) {
            $script:CmbStrategy.SelectedItem = $cfg.LastStrategy
        } else {
            $script:CmbStrategy.SelectedIndex = 0
        }
    }
    if ($script:LblStrategies) {
        $script:LblStrategies.Text = "Стратегии ($($bats.Count))"
    }
}

function Refresh-ListCombo {
    if (-not $script:CmbList) { return }
    $prev = $null
    $cur = Get-CurrentListInfo
    if ($cur) { $prev = $cur.Path }
    $script:CmbList.Items.Clear()
    $infos = @(Get-UserListInfos)
    foreach ($info in $infos) {
        $item = [Windows.Controls.ComboBoxItem]::new()
        $item.Content = $info.Display
        $item.Tag = $info
        $item.Foreground = ConvertTo-Brush '#F2F3F5'
        $item.Background = ConvertTo-Brush '#1E1F22'
        $script:CmbList.Items.Add($item) | Out-Null
        if ($prev -and [string]::Equals($prev, $info.Path, 'OrdinalIgnoreCase')) {
            $script:CmbList.SelectedItem = $item
        }
    }
    if ($script:CmbList.SelectedIndex -lt 0 -and $script:CmbList.Items.Count -gt 0) {
        $prefer = $null
        $cfg = Get-Settings
        if ($cfg -and $cfg.LastList) {
            foreach ($it in $script:CmbList.Items) {
                if ($it.Tag.Name -eq [string]$cfg.LastList) { $prefer = $it; break }
            }
        }
        foreach ($it in $script:CmbList.Items) {
            if (-not $prefer -and $it.Tag.Name -eq 'list-general-user.txt') { $prefer = $it; break }
        }
        $script:CmbList.SelectedItem = $(if ($prefer) { $prefer } else { $script:CmbList.Items[0] })
    }
}

function Refresh-SiteList {
    if (-not $script:LstSites) { return }
    $info = Get-CurrentListInfo
    $script:LstSites.Items.Clear()
    if (-not $info) {
        if ($script:LblCount) { $script:LblCount.Text = 'Нет пользовательских списков' }
        if ($script:LblListHint) { $script:LblListHint.Text = 'В этой сборке нет *-user.txt. Обновите zapret или создайте list-general-user.txt в lists.' }
        return
    }
    $dummy = if ($info.Kind -eq 'ip') { $script:DummyIp } else { $script:DummyHost }
    $items = Read-ListEntries -Path $info.Path -Dummy $dummy
    foreach ($item in $items) { $script:LstSites.Items.Add($item) | Out-Null }
    if ($items.Count -eq 0) {
        $emptyItem = [Windows.Controls.ListBoxItem]::new()
        $emptyItem.Content = 'Добавленных записей пока нет'
        $emptyItem.Foreground = ConvertTo-Brush '#949BA4'
        $emptyItem.IsEnabled = $false
        $script:LstSites.Items.Add($emptyItem) | Out-Null
    }
    if ($script:LblCount) {
        $script:LblCount.Text = if ($items.Count -eq 0) { 'Список пуст' } else { "Записей: $($items.Count)" }
    }
    if ($script:LblListHint) {
        if ($info.Wired) {
            $script:LblListHint.Text = "Читается файл $($info.Path). Текущая стратегия его использует."
        } else {
            $script:LblListHint.Text = "Читается файл $($info.Path), но выбранная стратегия его не подключает. Для обхода обычно нужен list-general-user.txt."
        }
    }
}

function Refresh-Status {
    if (-not $script:LblStatus) { return }
    $state = Get-ZapretState
    if ($script:BtnStart) {
        if ($state.ServiceInstalled) {
            $script:BtnStart.Content = if ($state.ServiceRunning) { 'Перезапустить службу' } else { 'Запустить службу' }
        } else {
            $script:BtnStart.Content = 'Установить и запустить'
        }
    }
    if ($script:LblGuiVersion) {
        $script:LblGuiVersion.Text = "GUI $($script:GuiVersion)"
    }
    if ($script:LblZapretVer) {
        if ($script:Root -and $script:Version) {
            $script:LblZapretVer.Text = "zapret $($script:Version)"
        } elseif ($script:Root) {
            $script:LblZapretVer.Text = 'zapret (версия неизвестна)'
        } else {
            $script:LblZapretVer.Text = 'zapret не подключен'
        }
    }
    if ($state.Running) {
        $script:DotStatus.Fill = ConvertTo-Brush '#23A559'
        $label = switch ($state.Mode) {
            'служба' { 'Запущен · служба' }
            'winws' { 'Запущен · winws' }
            'чужой winws' { 'Запущен · другой winws' }
            default { 'Запущен' }
        }
        if ($state.Strategy -and $state.ServiceRunning) { $label = "$label · $($state.Strategy)" }
        $script:LblStatus.Text = $label
        $script:LblStatus.Foreground = ConvertTo-Brush '#F2F3F5'
    } elseif (-not $script:Root) {
        $script:DotStatus.Fill = ConvertTo-Brush '#80848E'
        $script:LblStatus.Text = 'zapret не найден'
        $script:LblStatus.Foreground = ConvertTo-Brush '#B5BAC1'
    } else {
        $script:DotStatus.Fill = ConvertTo-Brush '#F23F42'
        $script:LblStatus.Text = 'Не запущен'
        $script:LblStatus.Foreground = ConvertTo-Brush '#F2F3F5'
    }
    if ($script:LastRunning -ne $state.Running) {
        if ($null -ne $script:LastRunning) {
            if ($state.Running) { Add-Log "zapret запущен ($($state.Mode))" '#23A559' }
            else { Add-Log 'zapret остановлен' '#E8C36A' }
        } elseif ($state.Running) {
            Add-Log "Скан: zapret уже работает ($($state.Mode))" '#23A559'
        } else {
            Add-Log 'Скан: zapret сейчас не запущен' '#949BA4'
        }
        $script:LastRunning = $state.Running
    }
    if ($script:LblMode) {
        $gui = "Оболочка GUI $($script:GuiVersion)."
        if ($state.ServiceInstalled) {
            $hint = if ($state.Strategy) { $state.Strategy } else { 'неизвестно' }
            $run = if ($state.ServiceRunning) { 'работает' } else { 'установлена, сейчас остановлена' }
            $script:LblMode.Text = "$gui Служба zapret $run ($hint)."
        } else {
            $run = if ($state.Running) { 'winws запущен' } else { 'winws не запущен' }
            $script:LblMode.Text = "$gui Обычный запуск, $run. После обновления zapret нажмите «Сканировать»."
        }
    }
}

function Add-CurrentHost {
    $raw = [string]$script:TxtHost.Text
    $info = Get-CurrentListInfo
    if (-not $info) { throw 'Нет пользовательского списка в этой сборке zapret.' }
    if ($info.Kind -eq 'ip') {
        Add-IpEntry -Raw $raw -Path $info.Path
    } else {
        Add-HostEntry -Raw $raw -Info $info
    }
    $script:TxtHost.Clear()
    Refresh-SiteList
    Restart-ZapretIfNeeded
}

function Add-HostEntry {
    param([string]$Raw, $Info)
    $hostName = ConvertTo-HostName $Raw
    if (-not $hostName) { throw 'Введите домен или ссылку: instagram.com или https://x.com/home' }
    if ($Info.Role -ne 'exclude') {
        $excludeFiles = @(Get-ChildItem -LiteralPath $script:Lists -Filter '*exclude*.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        if (Test-HostInFiles -HostName $hostName -Files $excludeFiles) {
            throw "Домен $hostName в исключениях — обход на него не действует. Уберите его из exclude-списка, если уверены."
        }
    }
    $dummy = $script:DummyHost
    $current = [System.Collections.Generic.List[string]]::new()
    foreach ($item in (Read-ListEntries -Path $Info.Path -Dummy $dummy)) { $current.Add($item) }
    if ($current | Where-Object { $_.ToLowerInvariant() -eq $hostName }) { throw "Уже есть: $hostName" }
    $current.Add($hostName)
    Save-ListEntries -Path $Info.Path -Entries $current.ToArray() -Dummy $dummy -KeepComment:($Info.Role -ne 'exclude')
    Add-Log "Добавлен $hostName → $($Info.Name)" '#3DDC97'
    if (-not $Info.Wired) {
        Add-Log 'Внимание: текущая стратегия этот файл не читает. Выберите list-general-user.txt или другую стратегию.' '#E8C36A'
    }
}

function Add-IpEntry {
    param([string]$Raw, [string]$Path)
    $value = $Raw.Trim()
    $ips = [System.Collections.Generic.List[string]]::new()
    if ($value -match '^(\d{1,3}(?:\.\d{1,3}){3})(?:/\d{1,2})?$') {
        $ips.Add("$($Matches[1])/32")
    } else {
        $hostName = ConvertTo-HostName $value
        if (-not $hostName) { throw 'Для IP-списка нужен домен или IPv4.' }
        $addrs = [Net.Dns]::GetHostAddresses($hostName)
        foreach ($a in $addrs) {
            if ($a.AddressFamily -eq 'InterNetwork') { $ips.Add($a.IPAddressToString + '/32') }
        }
        if ($ips.Count -eq 0) { throw "Нет IPv4 у $hostName" }
    }
    $current = [System.Collections.Generic.List[string]]::new()
    foreach ($item in (Read-ListEntries -Path $Path -Dummy $script:DummyIp)) { $current.Add($item) }
    $added = @()
    foreach ($ip in $ips) {
        if ($ip -eq $script:DummyIp) { continue }
        if ($current -contains $ip) { continue }
        $current.Add($ip)
        $added += $ip
    }
    if ($added.Count -eq 0) { throw 'Эти IP уже в списке.' }
    Save-ListEntries -Path $Path -Entries $current.ToArray() -Dummy $script:DummyIp
    Add-Log ("IP: " + ($added -join ', ')) '#3DDC97'
}

function Remove-SelectedEntry {
    $info = Get-CurrentListInfo
    if (-not $info) { return }
    $selected = @($script:LstSites.SelectedItems)
    if ($selected.Count -eq 0) { return }
    $dummy = if ($info.Kind -eq 'ip') { $script:DummyIp } else { $script:DummyHost }
    $current = @(Read-ListEntries -Path $info.Path -Dummy $dummy)
    $drop = @{}
    foreach ($s in $selected) { $drop[[string]$s] = $true }
    $remain = @($current | Where-Object { -not $drop.ContainsKey($_) })
    Save-ListEntries -Path $info.Path -Entries $remain -Dummy $dummy -KeepComment:($info.Kind -ne 'ip' -and $info.Role -ne 'exclude')
    Add-Log ('Удалено: ' + ($selected -join ', ')) '#E8C36A'
    Refresh-SiteList
    Restart-ZapretIfNeeded
}

function Open-LatestReport {
    $dir = Join-Path $script:Utils 'test results'
    if (-not (Test-Path -LiteralPath $dir)) { Add-Log 'Папка test results ещё не создана' '#E8C36A'; return }
    $file = Get-ChildItem -LiteralPath $dir -File -Filter '*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $file) { Add-Log 'Отчётов пока нет' '#E8C36A'; return }
    Add-Log "Отчёт: $($file.FullName)" '#6EC6FF'
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        $color = '#A9B8C9'
        if ($line -match 'ERROR|FAIL|BLOCKED') { $color = '#FF8A8A' }
        elseif ($line -match 'Best strategy|HTTP:OK' -and $line -notmatch 'ERROR') { $color = '#3DDC97' }
        elseif ($line -match '^Config:') { $color = '#E8C36A' }
        Add-Log $line $color
    }
}

function Find-OfficialTest {
    $candidates = @(
        (Join-Path $script:Utils 'test zapret.ps1')
        (Join-Path $script:Utils 'test.ps1')
        (Join-Path $script:Root 'blockcheck.bat')
        (Join-Path $script:Root 'blockcheck.cmd')
    )
    Get-ChildItem -LiteralPath $script:Utils -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'test' -and $_.Extension -in '.ps1', '.bat', '.cmd' } |
        ForEach-Object { $candidates += $_.FullName }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ZAPRET"
        Width="820" Height="640" MinWidth="760" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize"
        AllowsTransparency="False" BorderThickness="0"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        Background="#1E1F22"
        FontFamily="Segoe UI" FontSize="13"
        Foreground="#DBDEE1">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="BorderBrush" Value="#1E1F22"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,9"/>
      <Setter Property="CaretBrush" Value="#F2F3F5"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#DBDEE1"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
    <Style TargetType="ListBox">
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#DBDEE1"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#B5BAC1"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="8"/>
      <Setter Property="Foreground" Value="#5865F2"/>
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Border Background="#1E1F22" CornerRadius="4" Height="8">
              <Grid>
                <Border x:Name="PART_Track" CornerRadius="4"/>
                <Border x:Name="PART_Indicator" HorizontalAlignment="Left" Background="#5865F2" CornerRadius="4"/>
              </Grid>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#2B2D31"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="16"/>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#949BA4"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Margin" Value="4,14,0,8"/>
    </Style>
    <ControlTemplate x:Key="BtnTpl" TargetType="Button">
      <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter TargetName="bd" Property="Opacity" Value="0.76"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <ControlTemplate x:Key="BtnTplSquare" TargetType="Button">
      <Grid x:Name="root" Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="root" Property="Opacity" Value="0.88"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter TargetName="root" Property="Opacity" Value="0.76"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter TargetName="root" Property="Opacity" Value="0.4"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#DBDEE1"/>
      <Setter Property="Background" Value="#4E5058"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,9"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template" Value="{StaticResource BtnTpl}"/>
    </Style>
    <Style x:Key="BtnAccent" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#248046"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
    <Style x:Key="BtnBlurple" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#5865F2"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
    <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#DA373C"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="34"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="48"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <Border Grid.Row="0" Grid.ColumnSpan="2" Background="#202225" Padding="0" SnapsToDevicePixels="True">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="46"/>
          <ColumnDefinition Width="46"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="DragMain" Background="Transparent" Padding="12,0">
          <TextBlock Text="ZAPRET GUI" Foreground="#DCDDDE" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </Border>
        <Button Grid.Column="1" x:Name="BtnMinimizeMain" Content="—" Style="{StaticResource Btn}" Width="Auto" Height="34" Margin="0" Padding="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#202225" FontSize="16"/>
        <Button Grid.Column="2" x:Name="BtnCloseMain" Content="×" Style="{StaticResource Btn}" Template="{StaticResource BtnTplSquare}" Width="Auto" Height="34" Margin="0" Padding="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#B83A3A" Foreground="White" FontSize="17"/>
      </Grid>
    </Border>
    <Border Grid.Row="1" Grid.Column="0" Background="#1E1F22">
      <StackPanel Margin="0,12,0,0" HorizontalAlignment="Center">
        <Border Width="36" Height="36" CornerRadius="18" Background="#5865F2">
          <TextBlock Text="Z" Foreground="White" FontWeight="Bold" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border Width="32" Height="2" Background="#35373C" Margin="0,10,0,10" CornerRadius="1"/>
        <Button x:Name="BtnSettings" ToolTip="Настройки" Style="{StaticResource Btn}" Width="36" Height="36" Margin="0" Padding="0" Background="#2B2D31">
          <Grid>
            <Image x:Name="ImgSettingsGear" Width="22" Height="22" Stretch="Uniform" Visibility="Collapsed"/>
            <TextBlock x:Name="TxtSettingsGearFallback" Text="⚙" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
        </Button>
      </StackPanel>
    </Border>

    <Grid Grid.Row="1" Grid.Column="1" Background="#313338">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#2B2D31" Padding="16,12">
        <StackPanel>
          <DockPanel>
            <Button x:Name="BtnStart" DockPanel.Dock="Right" Content="Запустить" Style="{StaticResource BtnAccent}" Margin="8,0,0,0" Padding="16,8" Width="Auto"/>
            <Button x:Name="BtnStop" DockPanel.Dock="Right" Content="Стоп" Style="{StaticResource Btn}" Margin="0" Padding="16,8" Width="Auto"/>
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock Text="#" Foreground="#80848E" FontSize="20" FontWeight="Bold" Margin="0,0,6,1"/>
              <TextBlock Text="zapret" FontSize="16" FontWeight="Bold" Foreground="#F2F3F5" VerticalAlignment="Center" Margin="0,0,14,0"/>
              <Ellipse x:Name="DotStatus" Width="10" Height="10" Fill="#80848E" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock x:Name="LblStatus" Text="проверка..." FontWeight="SemiBold" VerticalAlignment="Center"/>
            </StackPanel>
          </DockPanel>
          <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
            <TextBlock x:Name="LblGuiVersion" Text="GUI" Foreground="#DCDDDE" FontSize="12"/>
            <TextBlock Text="  ·  " Foreground="#80848E" FontSize="12"/>
            <TextBlock x:Name="LblZapretVer" Text="zapret —" Foreground="#DCDDDE" FontSize="12"/>
          </StackPanel>
          <DockPanel x:Name="PnlUpdate" Visibility="Collapsed" Margin="0,10,0,0">
            <Button x:Name="BtnRelease" DockPanel.Dock="Right" Content="Релиз" Style="{StaticResource BtnBlurple}" Margin="12,0,0,0" Padding="14,6" Width="Auto"/>
            <Border Background="#3C2A1E" CornerRadius="8" Padding="10,8">
              <TextBlock x:Name="LblUpdate" TextWrapping="Wrap" Foreground="#F0B232" VerticalAlignment="Center"/>
            </Border>
          </DockPanel>
        </StackPanel>
      </Border>

      <Grid Grid.Row="1" Margin="16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="CardDiscord" Grid.Column="0" Background="#2B2D31" CornerRadius="8" Padding="16" Cursor="Hand" ToolTip="Нажмите, чтобы проверить сейчас">
          <DockPanel>
            <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
              <Ellipse Width="8" Height="8" Fill="#5865F2" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Text="DISCORD" FontWeight="Bold" FontSize="12" Foreground="#DCDDDE" VerticalAlignment="Center"/>
              <TextBlock x:Name="LblDiscordSummary" Text="" Foreground="#DCDDDE" FontSize="12" Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel x:Name="PnlDiscord"/>
          </DockPanel>
        </Border>
        <Border x:Name="CardYoutube" Grid.Column="2" Background="#2B2D31" CornerRadius="8" Padding="16" Cursor="Hand" ToolTip="Нажмите, чтобы проверить сейчас">
          <DockPanel>
            <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
              <Ellipse Width="8" Height="8" Fill="#F23F42" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock Text="YOUTUBE" FontWeight="Bold" FontSize="12" Foreground="#DCDDDE" VerticalAlignment="Center"/>
              <TextBlock x:Name="LblYoutubeSummary" Text="" Foreground="#DCDDDE" FontSize="12" Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel x:Name="PnlYoutube"/>
          </DockPanel>
        </Border>
      </Grid>

      <Border Grid.Row="2" Background="#2B2D31" Padding="14,12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="10"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border Background="#1E1F22" CornerRadius="8">
            <Grid>
              <TextBlock x:Name="TxtHostHint" Text="сайт, который не открывается" Foreground="#6D6F78" VerticalAlignment="Center" Margin="12,0,0,0" IsHitTestVisible="False"/>
              <TextBox x:Name="TxtHost" Background="Transparent" VerticalContentAlignment="Center" ToolTip="Домен добавится в пользовательский список zapret"/>
            </Grid>
          </Border>
          <Button x:Name="BtnAdd" Grid.Column="2" Content="Добавить сайт" Style="{StaticResource BtnAccent}" Margin="0" Padding="18,9"/>
        </Grid>
      </Border>
    </Grid>
    <Border x:Name="PnlOverlay" Grid.Row="1" Grid.ColumnSpan="2" Visibility="Collapsed" Background="#E61E1F22" Panel.ZIndex="80">
      <Border Width="440" HorizontalAlignment="Center" VerticalAlignment="Center" Background="#2B2D31" CornerRadius="12" Padding="28,26">
        <StackPanel>
          <Border Width="48" Height="48" CornerRadius="24" Background="#5865F2" HorizontalAlignment="Center" Margin="0,0,0,16">
            <TextBlock Text="Z" Foreground="White" FontWeight="Bold" FontSize="22" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="LblOverlayTitle" Text="Подготовка zapret" FontSize="18" FontWeight="Bold" Foreground="#F2F3F5" HorizontalAlignment="Center" Margin="0,0,0,8"/>
          <TextBlock x:Name="LblOverlaySub" Text="Проверяю файлы..." TextWrapping="Wrap" TextAlignment="Center" Foreground="#B5BAC1" Margin="0,0,0,18"/>
          <ProgressBar x:Name="PrgOverlay" Minimum="0" Maximum="100" Value="0"/>
          <TextBlock x:Name="LblOverlayPct" Text="" Foreground="#949BA4" HorizontalAlignment="Center" FontSize="12" Margin="0,8,0,16"/>
          <Button x:Name="BtnOverlayRetry" Content="Указать папку вручную" Style="{StaticResource Btn}" Visibility="Collapsed" HorizontalAlignment="Center" Width="240" Margin="0"/>
        </StackPanel>
      </Border>
    </Border>
  </Grid>
</Window>
'@

$xamlSettings = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Настройки"
        Width="980" Height="700" MinWidth="880" MinHeight="620"
        WindowStartupLocation="CenterOwner"
        WindowStyle="None" ResizeMode="CanResize"
        AllowsTransparency="False" BorderThickness="0"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        Background="#1E1F22"
        FontFamily="Segoe UI" FontSize="13"
        Foreground="#DBDEE1"
        ShowInTaskbar="False">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="CaretBrush" Value="#F2F3F5"/>
    </Style>
    <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#1E1F22"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#F2F3F5"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#1E1F22"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#F2F3F5"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#5865F2"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.GrayTextBrushKey}" Color="#B5BAC1"/>
    <ControlTemplate x:Key="DarkComboToggle" TargetType="ToggleButton">
      <Border x:Name="Chrome" Background="#1E1F22" CornerRadius="6" MinHeight="28">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="28"/>
          </Grid.ColumnDefinitions>
          <Path Grid.Column="1" Fill="#F2F3F5" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
        </Grid>
      </Border>
    </ControlTemplate>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#5865F2"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#80848E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Margin" Value="0,0,0,6"/>
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Disabled"/>
      <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
      <Setter Property="MaxDropDownHeight" Value="280"/>
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="ToggleButton"
                            Focusable="False"
                            ClickMode="Press"
                            HorizontalAlignment="Stretch"
                            VerticalAlignment="Stretch"
                            Background="#1E1F22"
                            Template="{StaticResource DarkComboToggle}"
                            IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
              <ContentPresenter x:Name="ContentSite"
                                IsHitTestVisible="False"
                                Margin="10,6,28,6"
                                VerticalAlignment="Center"
                                HorizontalAlignment="Left"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                TextElement.Foreground="#F2F3F5"/>
              <Popup x:Name="PART_Popup"
                     Placement="Bottom"
                     AllowsTransparency="True"
                     Focusable="False"
                     PopupAnimation="Slide"
                     IsOpen="{TemplateBinding IsDropDownOpen}">
                <Border MinWidth="{TemplateBinding ActualWidth}"
                        MaxHeight="{TemplateBinding MaxDropDownHeight}"
                        Background="#1E1F22"
                        BorderBrush="#3F4147"
                        BorderThickness="1"
                        CornerRadius="6"
                        Padding="2">
                  <ScrollViewer SnapsToDevicePixels="True">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ListBox">
      <Setter Property="Background" Value="#1E1F22"/>
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBox">
            <Border Background="#1E1F22" CornerRadius="6" Padding="4">
              <ScrollViewer Focusable="False">
                <ItemsPresenter/>
              </ScrollViewer>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#F2F3F5"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Padding" Value="8,4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#35373C"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#5865F2"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#F2F3F5"/>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#DCDDDE"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Margin" Value="2,6,0,4"/>
    </Style>
    <ControlTemplate x:Key="BtnTpl" TargetType="Button">
      <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <ControlTemplate x:Key="BtnTplSquare" TargetType="Button">
      <Grid x:Name="root" Background="{TemplateBinding Background}" SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="root" Property="Opacity" Value="0.88"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter TargetName="root" Property="Opacity" Value="0.4"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#DBDEE1"/>
      <Setter Property="Background" Value="#4E5058"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="MinHeight" Value="28"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template" Value="{StaticResource BtnTpl}"/>
    </Style>
    <Style x:Key="BtnAccent" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#248046"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
    <Style x:Key="BtnBlurple" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#5865F2"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
    <Style x:Key="BtnDanger" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#DA373C"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
  </Window.Resources>
  <Grid Background="#313338">
    <Grid.RowDefinitions>
      <RowDefinition Height="34"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#202225" Padding="0" SnapsToDevicePixels="True">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="46"/>
          <ColumnDefinition Width="46"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="DragSettings" Background="Transparent" Padding="12,0">
          <TextBlock Text="НАСТРОЙКИ ZAPRET" Foreground="#DCDDDE" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </Border>
        <Button Grid.Column="1" x:Name="BtnMinimizeSettings" Content="—" Style="{StaticResource Btn}" Width="Auto" Height="34" Margin="0" Padding="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#202225" FontSize="16"/>
        <Button Grid.Column="2" x:Name="BtnCloseSettings" Content="×" Style="{StaticResource Btn}" Template="{StaticResource BtnTplSquare}" Width="Auto" Height="34" Margin="0" Padding="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="#B83A3A" Foreground="White" FontSize="17"/>
      </Grid>
    </Border>
    <Grid Grid.Row="1">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="148"/>
      </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#2B2D31" Padding="12,8">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="Папка zapret" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="#DCDDDE"/>
        <Border Grid.Column="1" Background="#1E1F22" CornerRadius="6" Margin="0,0,8,0">
          <TextBox x:Name="TxtPath" Background="Transparent" VerticalContentAlignment="Center"/>
        </Border>
        <Button x:Name="BtnBrowse" Grid.Column="2" Content="Обзор" Style="{StaticResource Btn}" Margin="0,0,6,0" Padding="10,5" Width="Auto"/>
        <Button x:Name="BtnScan" Grid.Column="3" Content="Сканировать" Style="{StaticResource BtnBlurple}" Margin="0" Padding="10,5" Width="Auto"/>
      </Grid>
    </Border>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="360"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#2B2D31" Padding="10,8">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <StackPanel>
            <TextBlock Text="СТРАТЕГИЯ" Style="{StaticResource Section}" Margin="2,0,0,4"/>
            <Border Background="#1E1F22" CornerRadius="6" Margin="0,0,0,6" Padding="0,1">
              <ComboBox x:Name="CmbStrategy" Margin="0" Background="#1E1F22" Foreground="#F2F3F5" BorderThickness="0"/>
            </Border>
            <TextBlock Text="АВТОПРОВЕРКА" Style="{StaticResource Section}" Margin="2,0,0,4"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
              <Border Background="#1E1F22" CornerRadius="6" Width="64" Height="28" Margin="0,0,8,0">
                <TextBox x:Name="TxtHealthInterval" Text="1" Padding="4,2" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>
              </Border>
              <TextBlock Text="минут" Foreground="#DCDDDE" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock Text="СЛУЖБА И ТЕСТЫ" Style="{StaticResource Section}"/>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <Button Grid.Row="0" Grid.Column="0" x:Name="BtnRestart" Content="Перезапустить" Style="{StaticResource Btn}"/>
              <Button Grid.Row="0" Grid.Column="1" x:Name="BtnInstallService" Content="В службу" Style="{StaticResource Btn}" Margin="0,0,0,6" ToolTip="Выбранную стратегию поставить службой"/>
              <Button Grid.Row="1" Grid.Column="0" x:Name="BtnRemoveService" Content="Снять службу" Style="{StaticResource BtnDanger}"/>
              <Button Grid.Row="1" Grid.Column="1" x:Name="BtnTestCurrent" Content="Тест текущей" Style="{StaticResource Btn}" Margin="0,0,0,6"/>
              <Button Grid.Row="2" Grid.Column="0" x:Name="BtnTestAll" Content="Тест всех" Style="{StaticResource Btn}" ToolTip="Тест всех стратегий"/>
              <Button Grid.Row="2" Grid.Column="1" x:Name="BtnCancelTest" Content="Стоп теста" Style="{StaticResource BtnDanger}" Margin="0,0,0,6" IsEnabled="False" ToolTip="Остановить тест"/>
              <Button Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" x:Name="BtnAutoBest" Content="Автотест лучшей → служба" Style="{StaticResource BtnBlurple}" Margin="0,0,0,6"/>
              <Button Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" x:Name="BtnOfficialTest" Content="Консольный тест zapret" Style="{StaticResource Btn}" Margin="0,0,0,0"/>
            </Grid>
          </StackPanel>
          <StackPanel Grid.Row="1" Margin="0,8,0,0">
            <TextBlock x:Name="LblStrategies" Text="" Foreground="#DCDDDE" FontSize="12" Margin="2,0,0,4"/>
            <TextBlock x:Name="LblMode" TextWrapping="Wrap" Foreground="#DCDDDE" Margin="2,0,2,0" FontSize="12"/>
          </StackPanel>
        </Grid>
      </Border>
      <Border Grid.Column="1" Padding="12,8">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="Списки сайтов" FontSize="16" FontWeight="Bold" Foreground="#F2F3F5" Margin="0,0,0,8"/>
          <Border Grid.Row="1" Background="#1E1F22" CornerRadius="6" Margin="0,0,0,8" Padding="0,1">
            <ComboBox x:Name="CmbList" Margin="0" Background="#1E1F22" Foreground="#F2F3F5" BorderThickness="0"/>
          </Border>
          <DockPanel Grid.Row="2" Margin="0,0,0,8">
            <CheckBox x:Name="ChkRestart" Content="Перезапускать после изменения" IsChecked="True" VerticalAlignment="Center"/>
            <TextBlock x:Name="LblListHint" TextWrapping="Wrap" Foreground="#DCDDDE" FontSize="12" Margin="12,0,0,0"/>
          </DockPanel>
          <Grid Grid.Row="3" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="8"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border Background="#1E1F22" CornerRadius="6">
              <TextBox x:Name="TxtCheckHost" Background="Transparent" VerticalContentAlignment="Center" ToolTip="Проверка сайта через curl, как в тестах zapret"/>
            </Border>
            <Button x:Name="BtnCheckSite" Grid.Column="2" Content="Проверить сайт" Style="{StaticResource Btn}" Margin="0" Padding="10,5" Width="Auto"/>
          </Grid>
          <Border Grid.Row="4" Background="#2B2D31" CornerRadius="6" Padding="4" Margin="0,0,0,8">
            <ListBox x:Name="LstSites" Background="Transparent"/>
          </Border>
          <DockPanel Grid.Row="5">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
              <Button x:Name="BtnRemove" Content="Удалить" Style="{StaticResource BtnDanger}" Margin="0,0,6,0" Padding="10,5" Width="Auto"/>
              <Button x:Name="BtnFolder" Content="Папка lists" Style="{StaticResource Btn}" Margin="0" Padding="10,5" Width="Auto"/>
            </StackPanel>
            <TextBlock x:Name="LblCount" Text="" Foreground="#F2F3F5" VerticalAlignment="Center"/>
          </DockPanel>
        </Grid>
      </Border>
    </Grid>
    <Border Grid.Row="2" Background="#2B2D31" Padding="12,8">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="0,0,0,6">
          <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
            <Button x:Name="BtnLatestReport" Content="Последний отчёт" Style="{StaticResource Btn}" Margin="0,0,6,0" Padding="8,4" Width="Auto"/>
            <Button x:Name="BtnCopyLog" Content="Копировать" Style="{StaticResource Btn}" Margin="0,0,6,0" Padding="8,4" Width="Auto"/>
            <Button x:Name="BtnClearLog" Content="Очистить" Style="{StaticResource Btn}" Margin="0" Padding="8,4" Width="Auto"/>
          </StackPanel>
          <TextBlock Text="ЛОГ" Foreground="#DCDDDE" FontWeight="Bold" FontSize="12" VerticalAlignment="Center"/>
        </DockPanel>
        <Border Grid.Row="1" Background="#1E1F22" CornerRadius="6" Padding="6">
          <RichTextBox x:Name="LogBox" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                       Background="Transparent" Foreground="#DCDDDE" BorderThickness="0" FontFamily="Consolas" FontSize="12"
                       AcceptsReturn="True"/>
        </Border>
      </Grid>
    </Border>
    </Grid>
  </Grid>
</Window>
'@

try {
    $window = [ZapretUiHost]::LoadMain($xaml)
    $script:SettingsWindow = [ZapretUiHost]::LoadSettings($xamlSettings)
} catch {
    $buildDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message "Не удалось построить окно:`n$($_.Exception.Message)"
    exit 1
}

function Bind-GuiNames {
    param($Win, [string[]]$List)
    foreach ($n in $List) {
        $ctrl = $Win.FindName($n)
        if ($ctrl) { Set-Variable -Name $n -Scope Script -Value $ctrl }
    }
}
Bind-GuiNames $window @(
    'DragMain','BtnMinimizeMain','BtnCloseMain',
    'BtnSettings','BtnStart','BtnStop','DotStatus','LblStatus','LblGuiVersion','LblZapretVer','PnlUpdate','LblUpdate','BtnRelease',
    'ImgSettingsGear','TxtSettingsGearFallback',
    'CardDiscord','CardYoutube','PnlDiscord','PnlYoutube','LblDiscordSummary','LblYoutubeSummary','TxtHost','TxtHostHint','BtnAdd',
    'PnlOverlay','LblOverlayTitle','LblOverlaySub','PrgOverlay','LblOverlayPct','BtnOverlayRetry'
)
Bind-GuiNames $script:SettingsWindow @(
    'DragSettings','BtnMinimizeSettings','BtnCloseSettings',
    'TxtPath','BtnBrowse','BtnScan','CmbStrategy','BtnRestart','BtnInstallService','BtnRemoveService',
    'BtnAutoBest','BtnTestCurrent','BtnTestAll','BtnCancelTest','BtnOfficialTest','LblStrategies','LblMode',
    'TxtHealthInterval',
    'CmbList','ChkRestart','LblListHint','TxtCheckHost','LstSites','BtnCheckSite','BtnRemove','BtnFolder','LblCount',
    'BtnLatestReport','BtnCopyLog','BtnClearLog','LogBox'
)
$window.Title = "ZAPRET  $($script:GuiVersion)"
if ($script:SettingsWindow) { $script:SettingsWindow.Title = "Настройки · GUI $($script:GuiVersion)" }
if ($script:LblGuiVersion) { $script:LblGuiVersion.Text = "GUI $($script:GuiVersion)" }
function Get-SettingsGearImage {
    $filePath = Join-Path $script:AppDir 'settings-gear.png'
    $hasFile = Test-Path -LiteralPath $filePath -PathType Leaf
    $raw = [string]$script:EmbeddedSettingsGearPngBase64
    $hasEmbed = -not [string]::IsNullOrWhiteSpace($raw)
    if (-not $hasFile -and -not $hasEmbed) { return $null }
    $stream = $null
    try {
        $settingsIcon = [Windows.Media.Imaging.BitmapImage]::new()
        $settingsIcon.BeginInit()
        $settingsIcon.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        if ($hasFile) {
            $settingsIcon.UriSource = [Uri]::new($filePath, [UriKind]::Absolute)
        } else {
            $stream = [IO.MemoryStream]::new([Convert]::FromBase64String($raw))
            $settingsIcon.StreamSource = $stream
        }
        $settingsIcon.EndInit()
        $settingsIcon.Freeze()
        return $settingsIcon
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}
try {
    $settingsIcon = Get-SettingsGearImage
    if ($settingsIcon) {
        if ($script:ImgSettingsGear) {
            $script:ImgSettingsGear.Source = $settingsIcon
            $script:ImgSettingsGear.Visibility = 'Visible'
            if ($script:TxtSettingsGearFallback) { $script:TxtSettingsGearFallback.Visibility = 'Collapsed' }
        }
        if ($window) { $window.Icon = $settingsIcon }
        if ($script:SettingsWindow) { $script:SettingsWindow.Icon = $settingsIcon }
    }
} catch {
    Add-Log "Значок настроек не загружен: $($_.Exception.Message)" '#E8C36A'
}
Initialize-TrayIcon
$script:AllowSettingsClose = $false
$script:SettingsWindow.Add_Closing({
    param($s, $e)
    if (-not $script:AllowSettingsClose) {
        $e.Cancel = $true
        try { $hiddenSettings = [ZapretUiHost]::HideSettings() } catch { }
    }
})

if ($script:LstSites) { $script:LstSites.SelectionMode = 'Extended' }
if ($script:LogBox) { $script:LogBox.Document = New-Object Windows.Documents.FlowDocument }
$script:HealthBusy = $false
$script:HealthResults = [System.Collections.Generic.List[object]]::new()

function Show-SettingsWindow {
    $shownSettings = [ZapretUiHost]::ShowSettings()
}

function Invoke-Browse {
    $d = New-Object Windows.Forms.FolderBrowserDialog
    $d.Description = 'Укажите папку zapret (там service.bat и стратегии .bat)'
    if ($script:Root -and (Test-Path -LiteralPath $script:Root)) { $d.SelectedPath = $script:Root }
    if ($d.ShowDialog() -eq 'OK') {
        try {
            Set-ZapretRoot $d.SelectedPath
            if (-not $script:FirstRunCompleted) { Show-FirstRunStrategyOffer }
        } catch {
            Add-Log $_.Exception.Message '#FF8A8A'
            $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
        }
    }
}

if ($script:DragMain) {
    $script:DragMain.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ChangedButton -eq [Windows.Input.MouseButton]::Left) {
            $windowAction = [ZapretUiHost]::DragMain()
        }
    })
}
if ($script:BtnMinimizeMain) {
    $script:BtnMinimizeMain.Add_Click({ $windowAction = [ZapretUiHost]::MinimizeMain() })
}
if ($script:BtnCloseMain) {
    $script:BtnCloseMain.Add_Click({ $windowAction = [ZapretUiHost]::CloseMain() })
}
if ($script:DragSettings) {
    $script:DragSettings.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ChangedButton -eq [Windows.Input.MouseButton]::Left) {
            $windowAction = [ZapretUiHost]::DragSettings()
        }
    })
}
if ($script:BtnMinimizeSettings) {
    $script:BtnMinimizeSettings.Add_Click({ $windowAction = [ZapretUiHost]::MinimizeSettings() })
}
if ($script:BtnCloseSettings) {
    $script:BtnCloseSettings.Add_Click({ $windowAction = [ZapretUiHost]::CloseSettings() })
}
if ($script:BtnSettings) {
    $script:BtnSettings.Add_Click({ Show-SettingsWindow })
}
if ($script:CardDiscord) {
    $script:CardDiscord.Add_MouseLeftButtonUp({ Start-LiveHealthCheck -Force })
}
if ($script:CardYoutube) {
    $script:CardYoutube.Add_MouseLeftButtonUp({ Start-LiveHealthCheck -Force })
}
$script:BtnBrowse.Add_Click({ Invoke-Browse })
$script:BtnScan.Add_Click({
    try {
        $p = [string]$script:TxtPath.Text
        Set-ZapretRoot $p
    } catch {
        Add-Log $_.Exception.Message '#FF8A8A'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:TxtPath.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') { $script:BtnScan.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) }
})
$script:CmbStrategy.Add_SelectionChanged({
    Refresh-ListCombo
    Refresh-SiteList
    Save-SettingsSafe
})
$script:CmbList.Add_SelectionChanged({
    Refresh-SiteList
    Save-SettingsSafe
})
if ($script:ChkRestart) {
    $script:ChkRestart.Add_Click({ Save-SettingsSafe })
}
if ($script:TxtHealthInterval) {
    $script:TxtHealthInterval.Add_LostKeyboardFocus({
        Set-HealthIntervalMinutes -Value $script:TxtHealthInterval.Text -Save
    })
    $script:TxtHealthInterval.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') {
            Set-HealthIntervalMinutes -Value $script:TxtHealthInterval.Text -Save
        }
    })
}
$script:BtnAdd.Add_Click({
    try { Add-CurrentHost } catch {
        Add-Log $_.Exception.Message '#FF8A8A'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:TxtHost.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') {
        try { Add-CurrentHost } catch {
            Add-Log $_.Exception.Message '#FF8A8A'
            $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
        }
    }
})
if ($script:TxtHost) {
    $script:TxtHost.Add_TextChanged({
        if ($script:TxtHostHint) {
            $has = -not [string]::IsNullOrWhiteSpace($script:TxtHost.Text)
            $script:TxtHostHint.Visibility = if ($has) { 'Collapsed' } else { 'Visible' }
        }
    })
}
$script:BtnRemove.Add_Click({ Remove-SelectedEntry })
$script:BtnFolder.Add_Click({
    if ($script:Lists -and (Test-Path -LiteralPath $script:Lists)) {
        Start-Process explorer.exe -ArgumentList "`"$script:Lists`""
    }
})
$script:BtnStart.Add_Click({
    try {
        Start-ZapretFromMain
        Start-Sleep -Milliseconds 700
        Refresh-Status
    } catch {
        Add-Log $_.Exception.Message '#FF8A8A'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:BtnStop.Add_Click({
    Stop-Zapret
    Add-Log 'Обход остановлен' '#E8C36A'
    Refresh-Status
    Start-LiveHealthCheck -Force
})
$script:BtnRestart.Add_Click({
    try {
        $state = Get-ZapretState
        if ($state.ServiceInstalled) {
            Restart-Service -Name 'zapret' -Force
            Add-Log 'Служба перезапущена' '#3DDC97'
        } else {
            Stop-Zapret -Quiet
            Start-Sleep -Milliseconds 400
            Start-StrategyFile ([string]$script:CmbStrategy.SelectedItem)
        }
        Start-Sleep -Milliseconds 700
        Refresh-Status
        Start-LiveHealthCheck -Force
    } catch {
        Add-Log $_.Exception.Message '#FF8A8A'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:BtnRemoveService.Add_Click({
    try {
        $svc = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name 'zapret' -Force -ErrorAction SilentlyContinue
            sc.exe delete zapret | Out-Null
        }
        Stop-Zapret -Quiet
        foreach ($name in @('WinDivert', 'WinDivert14')) {
            sc.exe stop $name 2>$null | Out-Null
            sc.exe delete $name 2>$null | Out-Null
        }
        Add-Log 'Служба zapret снята' '#E8C36A'
        Refresh-Status
    } catch { Add-Log $_.Exception.Message '#FF8A8A' }
})
$script:BtnTestCurrent.Add_Click({
    $name = [string]$script:CmbStrategy.SelectedItem
    if (-not $name) { Add-Log 'Сначала выберите стратегию' '#E8C36A'; return }
    Start-StrategyTestsSafe @($name)
})
$script:BtnTestAll.Add_Click({
    $names = @($script:CmbStrategy.Items | ForEach-Object { [string]$_ })
    Start-StrategyTestsSafe $names
})
$script:BtnAutoBest.Add_Click({
    $names = @($script:CmbStrategy.Items | ForEach-Object { [string]$_ })
    if ($names.Count -eq 0) { Add-Log 'Сначала укажите папку zapret со стратегиями' '#F0B232'; return }
    $ok = Show-ZapretDialog -Title 'Автотест лучшей стратегии' -Buttons 'YesNo' -Message "Прогоню все стратегии, выберу лучшую и поставлю её службой zapret.`nОбход будет стартовать вместе с Windows."
    if ($ok -ne 'Yes') { return }
    Start-StrategyTestsSafe $names -AutoInstallBest
})
$script:BtnInstallService.Add_Click({
    $name = [string]$script:CmbStrategy.SelectedItem
    if (-not $name) { Add-Log 'Сначала выберите стратегию' '#F0B232'; return }
    try { Install-ZapretService -StrategyName $name } catch {
        Add-Log $_.Exception.Message '#F23F42'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:BtnCancelTest.Add_Click({
    if ($script:TestSync) { $script:TestSync.Cancel = $true }
    $script:TestCancel = $true
    Add-Log 'Остановка теста...' '#E8C36A'
})
$script:BtnCheckSite.Add_Click({
    try {
        $raw = ''
        if ($script:TxtCheckHost -and $script:TxtCheckHost.Text) { $raw = [string]$script:TxtCheckHost.Text }
        if (-not $raw -and $script:TxtHost) { $raw = [string]$script:TxtHost.Text }
        if (-not $raw -and $script:LstSites -and $script:LstSites.SelectedItem) { $raw = [string]$script:LstSites.SelectedItem }
        $hostName = ConvertTo-HostName $raw
        if (-not $hostName) { throw 'Введите сайт для проверки' }
        if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe не найден' }
        $url = "https://$hostName"
        Add-Log "Проверка $url ..." '#6EC6FF'
        $tok = Test-OneUrl $url
        $color = if ($tok -match 'ERROR') { '#FF8A8A' } else { '#3DDC97' }
        Add-Log ("  " + ($tok -join '  ')) $color
        $state = Get-ZapretState
        if (-not $state.Running) { Add-Log 'zapret сейчас не запущен — это проверка без обхода' '#E8C36A' }
    } catch {
        Add-Log $_.Exception.Message '#FF8A8A'
        $warnDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message $_.Exception.Message
    }
})
$script:BtnOfficialTest.Add_Click({
    $test = Find-OfficialTest
    if (-not $test) {
        Add-Log 'В этой сборке не найден test zapret.ps1 / blockcheck' '#E8C36A'
        return
    }
    Add-Log "Консольный тест: $test" '#6EC6FF'
    if ($test -like '*.ps1') {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$test`"" -WorkingDirectory $script:Root -WindowStyle Hidden
    } else {
        Start-Process $test -WorkingDirectory $script:Root -WindowStyle Hidden
    }
})
$script:BtnLatestReport.Add_Click({ Open-LatestReport })
$script:BtnClearLog.Add_Click({ $script:LogBox.Document.Blocks.Clear() })
$script:BtnCopyLog.Add_Click({
    $range = New-Object Windows.Documents.TextRange($script:LogBox.Document.ContentStart, $script:LogBox.Document.ContentEnd)
    [Windows.Clipboard]::SetText($range.Text)
    Add-Log 'Лог скопирован' '#8B9BB4'
})
$script:BtnRelease.Add_Click({ Start-Process $script:GithubReleasesUrl })
if ($script:BtnOverlayRetry) {
    $script:BtnOverlayRetry.Add_Click({
        Hide-BusyOverlay
        if ($script:OverlayRetryUpdate) {
            $script:OverlayRetryUpdate = $false
            Start-ZapretAutoSetup -Update
        } else {
            Invoke-Browse
            if ($script:Root) { Start-GithubCheck }
        }
    })
}

$window.Add_Loaded({
    try {
        try { $attachedSettings = [ZapretUiHost]::AttachSettingsOwner() } catch { }
        if ($script:TxtHost) { $script:TxtHost.Focus() }
        Add-Log 'Ищу zapret рядом с программой...' '#B5BAC1'
        Register-GuiWindowsAutostart
        $cfg = Get-Settings
        if ($cfg -and $null -ne $cfg.FirstRunCompleted) {
            $script:FirstRunCompleted = [bool]$cfg.FirstRunCompleted
        }
        if ($cfg -and $null -ne $cfg.RestartAfterEdit -and $script:ChkRestart) {
            $script:ChkRestart.IsChecked = [bool]$cfg.RestartAfterEdit
        }
        if ($cfg -and $null -ne $cfg.HealthIntervalMinutes) {
            Set-HealthIntervalMinutes -Value $cfg.HealthIntervalMinutes
        } else {
            Set-HealthIntervalMinutes -Value $script:HealthIntervalMinutes
        }
        if ($cfg -and $cfg.NotifiedZapretVersion) {
            $script:NotifiedZapretVersion = [string]$cfg.NotifiedZapretVersion
        }
        if ($cfg -and $cfg.LastZapretUpdateCheck) {
            $script:LastZapretUpdateCheck = [string]$cfg.LastZapretUpdateCheck
        }
        $path = Resolve-ZapretPath
        if ($path) {
            if (-not $script:Root) {
                try { Set-ZapretRoot $path -Silent; Add-Log "Подключено: $path" '#00A8FC' } catch { Add-Log $_.Exception.Message '#F23F42' }
            } else {
                Add-Log "Подключено: $($script:Root)" '#00A8FC'
            }
            try {
                Start-InstalledZapretService
            } catch {
                Add-Log "Не удалось автоматически запустить службу: $($_.Exception.Message)" '#F23F42'
            }
            Start-GithubCheck
            if (-not $script:FirstRunCompleted) {
                Show-FirstRunStrategyOffer
            }
        } else {
            Show-ZapretSetupOffer
        }
        if ($script:StartInTray -and $script:FirstRunCompleted -and $script:Root) {
            $hiddenMain = [ZapretUiHost]::HideMain()
        }
    } catch {
        Add-Log $_.Exception.Message '#F23F42'
    }
})
$window.Add_Closing({
    param($s, $e)
    if (-not $script:AllowMainClose) {
        $e.Cancel = $true
        Hide-MainToTray
        return
    }
    if ($script:TestBusy) {
        $answer = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'YesNo' -Message "Сейчас выполняется тест стратегий.`nЗавершить тест и закрыть программу?"
        if ($answer -ne 'Yes') {
            $e.Cancel = $true
            $script:AllowMainClose = $false
            return
        }
        if ($script:TestSync) { $script:TestSync.Cancel = $true }
        Add-Log 'Тест остановлен при закрытии программы' '#E8C36A'
    } elseif ($script:TestSync) {
        $script:TestSync.Cancel = $true
    }
    Save-SettingsSafe
    Stop-Watcher
    Dispose-TrayIcon
    $script:AllowSettingsClose = $true
    if ($script:SettingsWindow) {
        try { $closedSettings = [ZapretUiHost]::CloseSettings() } catch { }
    }
})

$uiTimer = New-Object Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$uiTimer.Add_Tick({
    try {
        Flush-LogQueue
        Update-BusyOverlayFromState
        Complete-ZapretAutoSetup
        Complete-StrategyTests
        Complete-GithubCheck
        Complete-LiveHealthCheck
        if (-not $script:Restarting -and -not $script:TestBusy) { Refresh-Status }
        $now = Get-Date
        if ($now -ge $script:NextHealthCheckAt) {
            $script:NextHealthCheckAt = $now.AddMinutes($script:HealthIntervalMinutes)
            Start-LiveHealthCheck
        }
        if ($now -ge $script:NextGithubCheckAt) {
            $script:NextGithubCheckAt = $now.Date.AddDays(1)
            Start-GithubCheck
        }
    } catch {
        Add-Log $_.Exception.Message '#F23F42'
    }
})
$uiTimer.Start()

$script:WatchTimer = New-Object Windows.Threading.DispatcherTimer
$script:WatchTimer.Interval = [TimeSpan]::FromMilliseconds(800)
$script:WatchTimer.Add_Tick({
    $script:WatchTimer.Stop()
    try {
        if ($script:Root) {
            $old = @($script:CmbStrategy.Items | ForEach-Object { "$_" })
            Refresh-Strategies
            Refresh-ListCombo
            $new = @($script:CmbStrategy.Items | ForEach-Object { "$_" })
            $added = @($new | Where-Object { $old -notcontains $_ })
            $removed = @($old | Where-Object { $new -notcontains $_ })
            if ($added) { Add-Log ('Новые стратегии: ' + ($added -join ', ')) '#3DDC97' }
            if ($removed) { Add-Log ('Удалены стратегии: ' + ($removed -join ', ')) '#E8C36A' }
        }
    } catch {
        Add-Log $_.Exception.Message '#F23F42'
    }
})

$window.Add_Closed({
    $uiTimer.Stop()
    if ($script:WatchTimer) { $script:WatchTimer.Stop() }
})

try {
    if ($script:StartInTray) {
        $window.ShowInTaskbar = $false
        $window.WindowState = [Windows.WindowState]::Minimized
    }
    $mainLoopDone = [ZapretUiHost]::StartMainLoop()
} catch {
    $crashDir = Join-Path $env:APPDATA 'ZapretGUI'
    $crashPath = Join-Path $crashDir 'crash.log'
    try {
        if (-not (Test-Path -LiteralPath $crashDir)) {
            New-Item -ItemType Directory -Path $crashDir -Force | Out-Null
        }
        $details = @(
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
            "Message: $($_.Exception.Message)"
            "Exception: $($_.Exception.ToString())"
            "ScriptStackTrace: $($_.ScriptStackTrace)"
            "Position: $($_.InvocationInfo.PositionMessage)"
            "ErrorRecord:"
            ($_ | Out-String)
        ) -join [Environment]::NewLine
        [IO.File]::WriteAllText($crashPath, $details, [Text.UTF8Encoding]::new($false))
    } catch { }
    $crashDlg = Show-ZapretDialog -Title 'ZAPRET GUI' -Buttons 'OK' -Message "$($_.Exception.Message)`nПодробности: $crashPath"
} finally {
    $releasedInstance = [ZapretSingleInstance]::Release()
}
