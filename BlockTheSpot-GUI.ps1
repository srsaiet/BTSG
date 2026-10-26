#Requires -Version 5.1
# ==============================================================================
#  BlockTheSpot-GUI.ps1  -  Control Center 3.0
#  Interfaz grafica para instalar, actualizar o desinstalar BlockTheSpot.
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File .\BlockTheSpot-GUI.ps1
#
#  Requiere Windows 10/11 x64 y Spotify Desktop instalado desde spotify.com.
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# DPI awareness + ventana sin bordes con redimensionado nativo.
if (-not ([System.Management.Automation.PSTypeName]'BtsNative').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class BtsNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}

public class BtsForm : Form {
    public int ResizeBorder { get; set; }
    public int CaptionHeight { get; set; }
    public int CaptionLeft { get; set; }
    public int CaptionRight { get; set; }
    public int SidebarWidth { get; set; }
    public int BrandHeight { get; set; }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MINMAXINFO {
        public POINT ptReserved;
        public POINT ptMaxSize;
        public POINT ptMaxPosition;
        public POINT ptMinTrackSize;
        public POINT ptMaxTrackSize;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    public BtsForm() {
        this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        this.SetStyle(ControlStyles.ResizeRedraw, true);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0024) {
            base.WndProc(ref m);
            try {
                IntPtr mon = MonitorFromWindow(this.Handle, 2);
                MONITORINFO mi = new MONITORINFO();
                mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
                if (GetMonitorInfo(mon, ref mi)) {
                    MINMAXINFO mmi = (MINMAXINFO)Marshal.PtrToStructure(m.LParam, typeof(MINMAXINFO));
                    mmi.ptMaxPosition.X = mi.rcWork.Left - mi.rcMonitor.Left;
                    mmi.ptMaxPosition.Y = mi.rcWork.Top - mi.rcMonitor.Top;
                    mmi.ptMaxSize.X = mi.rcWork.Right - mi.rcWork.Left;
                    mmi.ptMaxSize.Y = mi.rcWork.Bottom - mi.rcWork.Top;
                    Marshal.StructureToPtr(mmi, m.LParam, false);
                }
            } catch { }
            return;
        }
        if (m.Msg == 0x0084) {
            base.WndProc(ref m);
            if ((int)m.Result == 1) {
                Point p = this.PointToClient(Cursor.Position);
                if (this.WindowState != FormWindowState.Maximized) {
                    int b = this.ResizeBorder;
                    bool left = p.X <= b, right = p.X >= this.ClientSize.Width - b;
                    bool top = p.Y <= b, bottom = p.Y >= this.ClientSize.Height - b;
                    if (top && left) { m.Result = (IntPtr)13; return; }
                    if (top && right) { m.Result = (IntPtr)14; return; }
                    if (bottom && left) { m.Result = (IntPtr)16; return; }
                    if (bottom && right) { m.Result = (IntPtr)17; return; }
                    if (left) { m.Result = (IntPtr)10; return; }
                    if (right) { m.Result = (IntPtr)11; return; }
                    if (top) { m.Result = (IntPtr)12; return; }
                    if (bottom) { m.Result = (IntPtr)15; return; }
                }
                bool mainCaption = p.Y < this.CaptionHeight && p.X >= this.CaptionLeft && p.X < this.ClientSize.Width - this.CaptionRight;
                bool brandCaption = p.Y < this.BrandHeight && p.X < this.SidebarWidth;
                if (mainCaption || brandCaption) { m.Result = (IntPtr)2; return; }
            }
            return;
        }
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll'
}
[BtsNative]::SetProcessDPIAware() | Out-Null

$gfxScale = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$global:UiScale = $gfxScale.DpiX / 96.0
$gfxScale.Dispose()

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$PSDefaultParameterValues['Stop-Process:ErrorAction'] = 'SilentlyContinue'

# ==============================================================================
#  RUTAS Y VERSION
# ==============================================================================
[System.Version]$MinVer = '1.2.8.923'
$SpDir    = Join-Path $env:APPDATA 'Spotify'
$SpExe    = Join-Path $SpDir 'Spotify.exe'
$CElfDst  = Join-Path $SpDir 'chrome_elf.dll'
$CElfBak  = Join-Path $SpDir 'chrome_elf_required.dll'
$BtsDll   = Join-Path $SpDir 'blockthespot.dll'
$CfgIni   = Join-Path $SpDir 'config.ini'
$BaseUrl  = 'https://github.com/Nuzair46/BlockTheSpot/releases/latest/download'
$UrlElf   = "$BaseUrl/chrome_elf.dll"
$UrlBts   = "$BaseUrl/blockthespot.dll"
$UrlCfg   = "$BaseUrl/config.ini"

# ==============================================================================
#  PALETA Y TIPOGRAFIA
# ==============================================================================
$script:FontUi      = 'Segoe UI Variable Text'
$script:FontDisplay = 'Segoe UI Variable Display'
$script:FontIcon    = 'Segoe Fluent Icons'

# Paletas de referencia. Los valores hex se convierten a Color mas abajo.
$script:PaletteDark = @{
    Sidebar                = '#080C12'
    SidebarHover           = '#141C27'
    SidebarLine            = '#1B2431'
    SidebarText            = '#EDF2F8'
    SidebarMuted           = '#8B98AA'
    SidebarFaint           = '#58657A'
    SidebarCard            = '#0F151E'
    SidebarDisabledTint    = '#10161F'
    SidebarDisabledIcon    = '#3B4757'
    SidebarDisabledTitle   = '#536176'
    SidebarDisabledSub     = '#3F4C5E'
    SidebarDisabledChevron = '#323E4C'
    NavChevron             = '#465468'
    Link                   = '#8B98AA'

    Bg                     = '#0D1219'
    Card                   = '#141A22'
    CardSoft               = '#181F29'
    Border                 = '#222B37'
    BorderStrong           = '#303B4A'
    Text                   = '#E6EDF5'
    TextSecondary          = '#A2AEBD'
    TextMuted              = '#74808F'
    WindowHover            = '#1B2430'
    OutlineHover           = '#1B2430'
    DisabledBg             = '#1A212B'
    DisabledText           = '#5C6878'
    PillDarkHover          = '#D5DEE8'
    PillGreenHover         = '#18A64A'
    OnAccent               = '#FFFFFF'
    LogoEnd                = '#0A7030'
    NeutralDeep            = '#1A222D'

    Green                  = '#1DB954'
    GreenDark              = '#4ADE80'
    GreenSoft              = '#122A1D'
    GreenDeep              = '#0E2A1B'
    Blue                   = '#5B9BFF'
    BlueSoft               = '#13243D'
    BlueDeep               = '#142C4D'
    Red                    = '#FF6B70'
    RedSoft                = '#2A1618'
    RedDeep                = '#341A1E'
    Yellow                 = '#F0B429'
    YellowSoft             = '#2A2210'
    YellowDeep             = '#33280E'
    YellowText             = '#F0B429'
    YellowTextDeep         = '#F5C451'

    Hero1                  = '#121C2B'
    Hero2                  = '#090F18'
    HeroPanel              = '#0A111B'
    HeroLine               = '#1E2A3A'
    HeroBorder             = '#253346'
    HeroCaption            = '#7C8CA2'
    HeroStatCap            = '#6F8097'
    HeroStatSub            = '#8494A8'
    HeroDetail             = '#9AABBF'
    HeroFoot               = '#68798F'
    HeroText               = '#F2F6FA'

    LogBg                  = '#070B11'
    LogText                = '#B9C6D6'
    LogMuted               = '#5F7189'
    LogStep                = '#6EA8FF'
    LogThumb               = '#2C3847'
    LogThumbHover          = '#3C4B5E'
}

$script:PaletteLight = @{
    Sidebar                = '#0B1220'
    SidebarHover           = '#162237'
    SidebarLine            = '#1C2A3E'
    SidebarText            = '#F5F7FA'
    SidebarMuted           = '#8491A6'
    SidebarFaint           = '#4F5D70'
    SidebarCard            = '#111C2C'
    SidebarDisabledTint    = '#151D2B'
    SidebarDisabledIcon    = '#485568'
    SidebarDisabledTitle   = '#606D80'
    SidebarDisabledSub     = '#445163'
    SidebarDisabledChevron = '#344051'
    NavChevron             = '#4A5A70'
    Link                   = '#8D9AAE'

    Bg                     = '#F4F6F9'
    Card                   = '#FFFFFF'
    CardSoft               = '#FAFBFC'
    Border                 = '#E4E9F0'
    BorderStrong           = '#D6DEE8'
    Text                   = '#17202E'
    TextSecondary          = '#5B6779'
    TextMuted              = '#8B95A5'
    WindowHover            = '#F2F4F7'
    OutlineHover           = '#F6F8FB'
    DisabledBg             = '#EFF2F6'
    DisabledText           = '#8B95A5'
    PillDarkHover          = '#233044'
    PillGreenHover         = '#18A64A'
    OnAccent               = '#FFFFFF'
    LogoEnd                = '#0A7030'
    NeutralDeep            = '#1E2735'

    Green                  = '#1DB954'
    GreenDark              = '#0F7A37'
    GreenSoft              = '#E8F7EE'
    GreenDeep              = '#0C3B22'
    Blue                   = '#2F6FED'
    BlueSoft               = '#EAF0FE'
    BlueDeep               = '#102B57'
    Red                    = '#E5484D'
    RedSoft                = '#FDECEC'
    RedDeep                = '#3A1519'
    Yellow                 = '#D99A0B'
    YellowSoft             = '#FFF6E0'
    YellowDeep             = '#3A2E0B'
    YellowText             = '#976704'
    YellowTextDeep         = '#795202'

    Hero1                  = '#16253B'
    Hero2                  = '#0B1524'
    HeroPanel              = '#09121F'
    HeroLine               = '#1C2C42'
    HeroBorder             = '#26364E'
    HeroCaption            = '#7E8FA6'
    HeroStatCap            = '#6F8097'
    HeroStatSub            = '#8494A8'
    HeroDetail             = '#9AABBF'
    HeroFoot               = '#68798F'
    HeroText               = '#FFFFFF'

    LogBg                  = '#0C1624'
    LogText                = '#B6C2D2'
    LogMuted               = '#5E7088'
    LogStep                = '#609AFF'
    LogThumb               = '#2C3B50'
    LogThumbHover          = '#3A4C64'
}

foreach ($pal in @($script:PaletteDark, $script:PaletteLight)) {
    foreach ($key in @($pal.Keys)) {
        $pal[$key] = [Drawing.ColorTranslator]::FromHtml([string]$pal[$key])
    }
}

# $global:Pal es un unico objeto que se muta al cambiar de tema. Asi los
# closures creados con GetNewClosure() siempre leen los colores vigentes.
$script:Themes = @{ Dark = $script:PaletteDark; Light = $script:PaletteLight }
$global:ThemeName = 'Dark'
$global:Pal = @{}
foreach ($key in $script:PaletteDark.Keys) { $global:Pal[$key] = $script:PaletteDark[$key] }
$global:StatusState = @{ Accent = $global:Pal.Green }
$script:ThemeBindings = New-Object System.Collections.ArrayList
$script:ThemeActions = New-Object System.Collections.ArrayList

$script:IcoCheck     = [string][char]0xE73E
$script:IcoDownload  = [string][char]0xE896
$script:IcoDelete    = [string][char]0xE74D
$script:IcoFolder    = [string][char]0xE8B7
$script:IcoCopy      = [string][char]0xE8C8
$script:IcoClear     = [string][char]0xE894
$script:IcoRefresh   = [string][char]0xE72C
$script:IcoChevron   = [string][char]0xE76C
$script:IcoInfo      = [string][char]0xE946
$script:IcoWarning   = [string][char]0xE7BA
$script:IcoShield    = [string][char]0xE83D
$script:IcoExternal  = [string][char]0xE8A7
$script:IcoMinimize  = [string][char]0xE921
$script:IcoMaximize  = [string][char]0xE922
$script:IcoRestore   = [string][char]0xE923
$script:IcoClose     = [string][char]0xE8BB
$script:IcoSun       = [string][char]0xE706
$script:IcoMoon      = [string][char]0xE708

# ==============================================================================
#  HELPERS DE INTERFAZ
# ==============================================================================
function Get-RoundedPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $r = [Math]::Max(0, [Math]::Min($Radius, [Math]::Min($Rect.Width, $Rect.Height) / 2))
    if ($r -le 0) {
        $path.AddRectangle($Rect)
    } else {
        $d = $r * 2
        $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
        $path.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
        $path.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
        $path.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
        $path.CloseFigure()
    }
    return $path
}

function Set-RoundedRegion {
    param($Control, [int]$Radius)
    if ($null -eq $Control -or $Control.Width -le 0 -or $Control.Height -le 0) { return }
    $scale = if ($null -ne $global:UiScale -and $global:UiScale -gt 0) { $global:UiScale } else { 1 }
    $r = [int][Math]::Round($Radius * $scale)
    $path = Get-RoundedPath -Rect ([System.Drawing.Rectangle]::new(0, 0, $Control.Width, $Control.Height)) -Radius $r
    $old = $Control.Region
    $Control.Region = New-Object Drawing.Region($path)
    $path.Dispose()
    if ($null -ne $old) { $old.Dispose() }
}

# --- Registro de temas --------------------------------------------------------
function Register-Theme {
    param($Control, [hashtable]$Map)
    if ($null -eq $Control -or $null -eq $Map) { return }
    foreach ($prop in $Map.Keys) {
        [void]$script:ThemeBindings.Add([pscustomobject]@{
            Control  = $Control
            Property = [string]$prop
            Key      = [string]$Map[$prop]
        })
    }
}

function Register-ThemeAction {
    param([scriptblock]$Action)
    if ($null -ne $Action) { [void]$script:ThemeActions.Add($Action) }
}

function Get-PillPalette {
    param([string]$Kind)
    switch ($Kind) {
        'Dark' {
            return @{
                Back = $global:Pal.Text; Hover = $global:Pal.PillDarkHover
                Text = $global:Pal.Card; HoverText = $global:Pal.Card
                Border = $global:Pal.Text; BorderKey = 'Text'
            }
        }
        'Green' {
            return @{
                Back = $global:Pal.Green; Hover = $global:Pal.PillGreenHover
                Text = $global:Pal.OnAccent; HoverText = $global:Pal.OnAccent
                Border = $global:Pal.Green; BorderKey = 'Green'
            }
        }
        default {
            return @{
                Back = $global:Pal.Card; Hover = $global:Pal.OutlineHover
                Text = $global:Pal.Text; HoverText = $global:Pal.Text
                Border = $global:Pal.BorderStrong; BorderKey = 'BorderStrong'
            }
        }
    }
}

function Apply-Theme {
    param([ValidateSet('Dark', 'Light')][string]$Name)
    if (-not $script:Themes.ContainsKey($Name)) { return }
    $global:ThemeName = $Name
    $src = $script:Themes[$Name]
    foreach ($key in $src.Keys) { $global:Pal[$key] = $src[$key] }

    foreach ($b in $script:ThemeBindings) {
        try {
            $prop = $b.Property
            $b.Control.$prop = $global:Pal[$b.Key]
        } catch { }
    }
    foreach ($a in $script:ThemeActions) {
        try { & $a } catch { }
    }

    $F.BackColor = $global:Pal.Sidebar
    $F.ForeColor = $global:Pal.Text
    if ($F.IsHandleCreated) {
        try {
            $dark = if ($Name -eq 'Dark') { 1 } else { 0 }
            [BtsNative]::DwmSetWindowAttribute($F.Handle, 20, [ref]$dark, 4) | Out-Null
        } catch { }
    }
    if ($null -ne $btnTheme) {
        $btnTheme.Label.Text = if ($Name -eq 'Dark') { $script:IcoSun } else { $script:IcoMoon }
        if ($null -ne $tip) {
            $tip.SetToolTip($btnTheme.Panel, $(if ($Name -eq 'Dark') { 'Cambiar a tema claro' } else { 'Cambiar a tema oscuro' }))
        }
    }
    $F.Invalidate($true)
    foreach ($c in @($hero, $activity, $system, $sideSystem, $titlebar, $logShell)) {
        if ($null -ne $c) { $c.Invalidate() }
    }
}

function Switch-Theme {
    $next = if ($global:ThemeName -eq 'Dark') { 'Light' } else { 'Dark' }
    Apply-Theme -Name $next
    Refresh-Status
    Update-LogScroll
    Log "Tema $(if ($next -eq 'Dark') { 'oscuro' } else { 'claro' }) aplicado." 'info'
}

function New-Label {
    param(
        [string]$Text = '',
        [int]$X = 0, [int]$Y = 0, [int]$W = 100, [int]$H = 20,
        [single]$Size = 9,
        [string]$Family = $script:FontUi,
        [Drawing.FontStyle]$Style = [Drawing.FontStyle]::Regular,
        [Drawing.Color]$Color = $global:Pal.Text,
        [System.Drawing.ContentAlignment]$Align = [System.Drawing.ContentAlignment]::MiddleLeft,
        [bool]$Ellipsis = $false
    )
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text
    $l.Location = [Drawing.Point]::new($X, $Y)
    $l.Size = [Drawing.Size]::new($W, $H)
    $l.Font = [Drawing.Font]::new($Family, $Size, $Style, [Drawing.GraphicsUnit]::Point)
    $l.ForeColor = $Color
    $l.BackColor = [Drawing.Color]::Transparent
    $l.TextAlign = $Align
    $l.AutoEllipsis = $Ellipsis
    $l.UseMnemonic = $false
    return $l
}

function New-Card {
    param(
        [int]$Radius = 14,
        [Drawing.Color]$BackColor = $global:Pal.Card,
        [Drawing.Color]$BorderColor = $global:Pal.Border,
        [bool]$Border = $true,
        [string]$BackKey = 'Card',
        [string]$BorderKey = 'Border'
    )
    $p = New-Object Windows.Forms.Panel
    $p.BackColor = $BackColor
    Set-RoundedRegion $p $Radius
    $p.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius $Radius }.GetNewClosure())
    if ($BackKey) { Register-Theme $p @{ BackColor = $BackKey } }
    if ($Border) {
        $p.Add_Paint({
            param($s, $e)
            if ($s.Width -lt 2 -or $s.Height -lt 2) { return }
            $rr = [int][Math]::Round($Radius * $global:UiScale)
            $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width - 1, $s.Height - 1)
            $path = Get-RoundedPath -Rect $rect -Radius $rr
            $pen = [Drawing.Pen]::new($global:Pal[$BorderKey], 1)
            $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
            $path.Dispose()
        }.GetNewClosure())
    }
    return $p
}

function New-IconButton {
    param(
        [string]$Icon,
        [int]$W = 28, [int]$H = 28,
        [string]$ColorKey = 'TextMuted',
        [string]$Tip = ''
    )
    $color = $global:Pal[$ColorKey]
    $p = New-Object Windows.Forms.Panel
    $p.Size = [Drawing.Size]::new($W, $H)
    $p.BackColor = $global:Pal.Card
    $p.Cursor = [Windows.Forms.Cursors]::Hand
    Set-RoundedRegion $p 8
    $p.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 8 }.GetNewClosure())

    $l = New-Label -Text $Icon -X 0 -Y 0 -W $W -H $H -Size 9.5 -Family $script:FontIcon -Color $color -Align MiddleCenter
    $l.Cursor = [Windows.Forms.Cursors]::Hand
    $p.Controls.Add($l)

    $enter = {
        if ($p.Enabled) {
            $p.BackColor = $global:Pal.Bg
            $l.ForeColor = $global:Pal.Text
        }
    }.GetNewClosure()
    $leave = {
        if (-not $p.ClientRectangle.Contains($p.PointToClient([Windows.Forms.Cursor]::Position))) {
            $p.BackColor = $global:Pal.Card
            $l.ForeColor = $global:Pal[$ColorKey]
        }
    }.GetNewClosure()
    foreach ($ctrl in @($p, $l)) {
        $ctrl.Add_MouseEnter($enter)
        $ctrl.Add_MouseLeave($leave)
    }

    $button = [pscustomobject]@{
        Panel = $p; Label = $l; ColorKey = $ColorKey; NormalColor = $color
    }
    Register-ThemeAction ({
        $button.NormalColor = $global:Pal[$ColorKey]
        $button.Panel.BackColor = $global:Pal.Card
        $button.Label.ForeColor = $button.NormalColor
    }.GetNewClosure())
    return $button
}

function New-PillButton {
    param(
        [string]$Text,
        [string]$Glyph,
        [int]$W,
        [int]$H,
        [ValidateSet('Outline', 'Dark', 'Green')]
        [string]$Kind = 'Outline'
    )
    $pal = Get-PillPalette -Kind $Kind

    $p = New-Card -Radius 9 -BackColor $pal.Back -BorderColor $pal.Border -BackKey '' -BorderKey $pal.BorderKey
    $p.Size = [Drawing.Size]::new($W, $H)
    $p.Cursor = [Windows.Forms.Cursors]::Hand

    $textX = if ($Glyph) { 34 } else { 10 }
    $iconLabel = $null
    if ($Glyph) {
        $iconLabel = New-Label -Text $Glyph -X 14 -Y 0 -W 16 -H $H -Size 9.5 -Family $script:FontIcon -Color $pal.Text -Align MiddleCenter
        $iconLabel.Cursor = [Windows.Forms.Cursors]::Hand
        $p.Controls.Add($iconLabel)
    }
    $textLabel = New-Label -Text $Text -X $textX -Y 0 -W ($W - $textX - 8) -H $H -Size 8.25 -Family $script:FontUi -Style Bold -Color $pal.Text -Align MiddleLeft
    $textLabel.Cursor = [Windows.Forms.Cursors]::Hand
    $p.Controls.Add($textLabel)

    $p.Add_SizeChanged({
        $s = $global:UiScale
        $textLabel.Width = [Math]::Max(10, $this.ClientSize.Width - [int][Math]::Round($textX * $s) - [int][Math]::Round(8 * $s))
    }.GetNewClosure())

    $enter = {
        if ($p.Enabled) {
            $current = Get-PillPalette -Kind $Kind
            $p.BackColor = $current.Hover
            $textLabel.ForeColor = $current.HoverText
            if ($null -ne $iconLabel) { $iconLabel.ForeColor = $current.HoverText }
        }
    }.GetNewClosure()
    $leave = {
        if (-not $p.ClientRectangle.Contains($p.PointToClient([Windows.Forms.Cursor]::Position))) {
            $current = Get-PillPalette -Kind $Kind
            $p.BackColor = $current.Back
            $textLabel.ForeColor = $current.Text
            if ($null -ne $iconLabel) { $iconLabel.ForeColor = $current.Text }
        }
    }.GetNewClosure()
    foreach ($ctrl in @($p, $textLabel, $iconLabel)) {
        if ($null -eq $ctrl) { continue }
        $ctrl.Add_MouseEnter($enter)
        $ctrl.Add_MouseLeave($leave)
    }

    $button = [pscustomobject]@{
        Panel = $p; Label = $textLabel; IconLabel = $iconLabel; Kind = $Kind
        IsEnabled = $true
        NormalBack = $pal.Back; HoverBack = $pal.Hover
        NormalText = $pal.Text; HoverText = $pal.HoverText
        NormalBorder = $pal.Border
    }
    Register-ThemeAction ({
        $current = Get-PillPalette -Kind $Kind
        $button.NormalBack = $current.Back
        $button.HoverBack = $current.Hover
        $button.NormalText = $current.Text
        $button.HoverText = $current.HoverText
        $button.NormalBorder = $current.Border
        if ($button.IsEnabled) {
            $button.Panel.BackColor = $current.Back
            $button.Label.ForeColor = $current.Text
            if ($null -ne $button.IconLabel) { $button.IconLabel.ForeColor = $current.Text }
        } else {
            $button.Panel.BackColor = $global:Pal.DisabledBg
            $button.Label.ForeColor = $global:Pal.DisabledText
            if ($null -ne $button.IconLabel) { $button.IconLabel.ForeColor = $global:Pal.DisabledText }
        }
    }.GetNewClosure())
    return $button
}

function Set-PillEnabled {
    param($Button, [bool]$Enabled)
    $Button.IsEnabled = $Enabled
    $Button.Panel.Enabled = $Enabled
    $pal = Get-PillPalette -Kind $Button.Kind
    $Button.NormalBack = $pal.Back
    $Button.HoverBack = $pal.Hover
    $Button.NormalText = $pal.Text
    $Button.HoverText = $pal.HoverText
    $Button.NormalBorder = $pal.Border
    if ($Enabled) {
        $Button.Panel.BackColor = $pal.Back
        $Button.Label.ForeColor = $pal.Text
        if ($null -ne $Button.IconLabel) { $Button.IconLabel.ForeColor = $pal.Text }
        $Button.Panel.Cursor = [Windows.Forms.Cursors]::Hand
    } else {
        $Button.Panel.BackColor = $global:Pal.DisabledBg
        $Button.Label.ForeColor = $global:Pal.DisabledText
        if ($null -ne $Button.IconLabel) { $Button.IconLabel.ForeColor = $global:Pal.DisabledText }
        $Button.Panel.Cursor = [Windows.Forms.Cursors]::Default
    }
}

function New-NavItem {
    param(
        [string]$Title,
        [string]$Subtitle,
        [string]$Icon,
        [string]$AccentKey,
        [string]$TintKey,
        [int]$Top
    )
    $accent = $global:Pal[$AccentKey]
    $tint = $global:Pal[$TintKey]
    $p = New-Card -Radius 10 -BackColor $global:Pal.Sidebar -Border $false -BackKey 'Sidebar'
    $p.Size = [Drawing.Size]::new(204, 56)
    $p.Location = [Drawing.Point]::new(20, $Top)
    $p.Cursor = [Windows.Forms.Cursors]::Hand

    $bar = New-Object Windows.Forms.Panel
    $bar.Size = [Drawing.Size]::new(3, 28)
    $bar.Location = [Drawing.Point]::new(0, 14)
    $bar.BackColor = $global:Pal.Sidebar
    Set-RoundedRegion $bar 2
    $bar.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 2 }.GetNewClosure())
    $p.Controls.Add($bar)

    $iconBox = New-Object Windows.Forms.Panel
    $iconBox.Size = [Drawing.Size]::new(34, 34)
    $iconBox.Location = [Drawing.Point]::new(14, 11)
    $iconBox.BackColor = $tint
    Set-RoundedRegion $iconBox 9
    $iconBox.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 9 }.GetNewClosure())
    $p.Controls.Add($iconBox)

    $iconLabel = New-Label -Text $Icon -X 0 -Y 0 -W 34 -H 34 -Size 11.5 -Family $script:FontIcon -Color $accent -Align MiddleCenter
    $iconBox.Controls.Add($iconLabel)

    $titleLabel = New-Label -Text $Title -X 58 -Y 8 -W 122 -H 19 -Size 8.5 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarText -Ellipsis $true
    $subLabel = New-Label -Text $Subtitle -X 58 -Y 28 -W 124 -H 15 -Size 7.25 -Family $script:FontUi -Color $global:Pal.SidebarMuted -Ellipsis $true
    $chevron = New-Label -Text $script:IcoChevron -X 184 -Y 18 -W 12 -H 20 -Size 8 -Family $script:FontIcon -Color $global:Pal.NavChevron -Align MiddleCenter
    $p.Controls.Add($titleLabel)
    $p.Controls.Add($subLabel)
    $p.Controls.Add($chevron)

    foreach ($ctrl in @($p, $bar, $iconBox, $iconLabel, $titleLabel, $subLabel, $chevron)) {
        $ctrl.Cursor = [Windows.Forms.Cursors]::Hand
    }

    $nav = [pscustomobject]@{
        Panel = $p; AccentBar = $bar; IconBox = $iconBox; IconLabel = $iconLabel
        TitleLabel = $titleLabel; SubLabel = $subLabel; Chevron = $chevron
        AccentKey = $AccentKey; TintKey = $TintKey
        Accent = $accent; Tint = $tint; IsEnabled = $true
    }
    Register-ThemeAction ({
        $nav.Accent = $global:Pal[$AccentKey]
        $nav.Tint = $global:Pal[$TintKey]
        $nav.Panel.BackColor = $global:Pal.Sidebar
        $nav.AccentBar.BackColor = $global:Pal.Sidebar
        if ($nav.IsEnabled) {
            $nav.IconBox.BackColor = $nav.Tint
            $nav.IconLabel.ForeColor = $nav.Accent
            $nav.TitleLabel.ForeColor = $global:Pal.SidebarText
            $nav.SubLabel.ForeColor = $global:Pal.SidebarMuted
            $nav.Chevron.ForeColor = $global:Pal.NavChevron
        } else {
            $nav.IconBox.BackColor = $global:Pal.SidebarDisabledTint
            $nav.IconLabel.ForeColor = $global:Pal.SidebarDisabledIcon
            $nav.TitleLabel.ForeColor = $global:Pal.SidebarDisabledTitle
            $nav.SubLabel.ForeColor = $global:Pal.SidebarDisabledSub
            $nav.Chevron.ForeColor = $global:Pal.SidebarDisabledChevron
        }
    }.GetNewClosure())
    return $nav
}

function Add-NavEvents {
    param($Nav, $OnClick)
    $enter = {
        if ($Nav.Panel.Enabled) {
            $Nav.Panel.BackColor = $global:Pal.SidebarHover
            $Nav.AccentBar.BackColor = $Nav.Accent
            $Nav.Chevron.ForeColor = $global:Pal.SidebarText
        }
    }.GetNewClosure()
    $leave = {
        if (-not $Nav.Panel.ClientRectangle.Contains($Nav.Panel.PointToClient([Windows.Forms.Cursor]::Position))) {
            $Nav.Panel.BackColor = $global:Pal.Sidebar
            $Nav.AccentBar.BackColor = $global:Pal.Sidebar
            $Nav.Chevron.ForeColor = $global:Pal.NavChevron
        }
    }.GetNewClosure()
    $click = {
        if ($Nav.Panel.Enabled) { & $OnClick }
    }.GetNewClosure()
    foreach ($ctrl in @($Nav.Panel, $Nav.AccentBar, $Nav.IconBox, $Nav.IconLabel, $Nav.TitleLabel, $Nav.SubLabel, $Nav.Chevron)) {
        $ctrl.Add_MouseEnter($enter)
        $ctrl.Add_MouseLeave($leave)
        $ctrl.Add_Click($click)
    }
}

function Set-NavEnabled {
    param($Nav, [bool]$Enabled)
    $Nav.IsEnabled = $Enabled
    $Nav.Panel.Enabled = $Enabled
    $Nav.Panel.BackColor = $global:Pal.Sidebar
    $Nav.AccentBar.BackColor = $global:Pal.Sidebar
    if ($Enabled) {
        $Nav.IconBox.BackColor = $Nav.Tint
        $Nav.IconLabel.ForeColor = $Nav.Accent
        $Nav.TitleLabel.ForeColor = $global:Pal.SidebarText
        $Nav.SubLabel.ForeColor = $global:Pal.SidebarMuted
        $Nav.Chevron.ForeColor = $global:Pal.NavChevron
        $Nav.Panel.Cursor = [Windows.Forms.Cursors]::Hand
    } else {
        $Nav.IconBox.BackColor = $global:Pal.SidebarDisabledTint
        $Nav.IconLabel.ForeColor = $global:Pal.SidebarDisabledIcon
        $Nav.TitleLabel.ForeColor = $global:Pal.SidebarDisabledTitle
        $Nav.SubLabel.ForeColor = $global:Pal.SidebarDisabledSub
        $Nav.Chevron.ForeColor = $global:Pal.SidebarDisabledChevron
        $Nav.Panel.Cursor = [Windows.Forms.Cursors]::Default
    }
}

function New-WindowButton {
    param([string]$Glyph, [bool]$IsClose = $false)
    $p = New-Object Windows.Forms.Panel
    $p.Size = [Drawing.Size]::new(44, 46)
    $p.Margin = [Windows.Forms.Padding]::new(0)
    $p.BackColor = $global:Pal.Card
    $p.Cursor = [Windows.Forms.Cursors]::Hand

    $l = New-Label -Text $Glyph -X 0 -Y 0 -W 44 -H 46 -Size 9.5 -Family $script:FontIcon -Color $global:Pal.TextSecondary -Align MiddleCenter
    $l.Cursor = [Windows.Forms.Cursors]::Hand
    $p.Controls.Add($l)

    $enter = {
        if ($IsClose) {
            $p.BackColor = $global:Pal.Red
            $l.ForeColor = $global:Pal.OnAccent
        } else {
            $p.BackColor = $global:Pal.WindowHover
            $l.ForeColor = $global:Pal.Text
        }
    }.GetNewClosure()
    $leave = {
        if (-not $p.ClientRectangle.Contains($p.PointToClient([Windows.Forms.Cursor]::Position))) {
            $p.BackColor = $global:Pal.Card
            $l.ForeColor = $global:Pal.TextSecondary
        }
    }.GetNewClosure()
    foreach ($ctrl in @($p, $l)) {
        $ctrl.Add_MouseEnter($enter)
        $ctrl.Add_MouseLeave($leave)
    }
    $button = [pscustomobject]@{ Panel = $p; Label = $l; IsClose = $IsClose }
    Register-ThemeAction ({
        $button.Panel.BackColor = $global:Pal.Card
        $button.Label.ForeColor = $global:Pal.TextSecondary
    }.GetNewClosure())
    return $button
}

function New-AppIcon {
    try {
        $bmp = [Drawing.Bitmap]::new(64, 64)
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = [System.Drawing.Rectangle]::new(3, 3, 58, 58)
        $path = Get-RoundedPath -Rect $rect -Radius 17
        $brush = [Drawing.Drawing2D.LinearGradientBrush]::new($rect, $global:Pal.Green, $global:Pal.LogoEnd, 45)
        $g.FillPath($brush, $path)
        $font = [Drawing.Font]::new($script:FontDisplay, 31, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        $fmt = [Drawing.StringFormat]::new()
        $fmt.Alignment = [Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [Drawing.StringAlignment]::Center
        $white = [Drawing.SolidBrush]::new([Drawing.Color]::White)
        $g.DrawString('B', $font, $white, [Drawing.RectangleF]::new(0, 1, 64, 64), $fmt)
        $hIcon = $bmp.GetHicon()
        $icon = [Drawing.Icon]::FromHandle($hIcon).Clone()
        [BtsNative]::DestroyIcon($hIcon) | Out-Null
        $white.Dispose(); $fmt.Dispose(); $font.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose(); $bmp.Dispose()
        return $icon
    } catch {
        return [Drawing.SystemIcons]::Application
    }
}

# ==============================================================================
#  FORMULARIO
# ==============================================================================
$F = New-Object BtsForm
$F.Text = 'BlockTheSpot Installer 3.0'
$F.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$F.FormBorderStyle = [Windows.Forms.FormBorderStyle]::None
$F.BackColor = $global:Pal.Sidebar
$F.ForeColor = $global:Pal.Text
$F.Font = [Drawing.Font]::new($script:FontUi, 9)
$F.MinimizeBox = $true
$F.MaximizeBox = $true
$F.ShowInTaskbar = $true
$F.KeyPreview = $true
$F.Icon = New-AppIcon

$root = New-Object Windows.Forms.TableLayoutPanel
$root.Dock = [Windows.Forms.DockStyle]::Fill
$root.ColumnCount = 2
$root.RowCount = 1
$root.BackColor = $global:Pal.Bg
$root.Margin = [Windows.Forms.Padding]::new(0)
$root.Padding = [Windows.Forms.Padding]::new(0)
$root.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 244)) | Out-Null
$root.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$F.Controls.Add($root)

# ------------------------------------------------------------------------------
#  SIDEBAR
# ------------------------------------------------------------------------------
$sidebar = New-Object Windows.Forms.Panel
$sidebar.Dock = [Windows.Forms.DockStyle]::Fill
$sidebar.BackColor = $global:Pal.Sidebar
$sidebar.Margin = [Windows.Forms.Padding]::new(0)
$root.Controls.Add($sidebar, 0, 0)

$brand = New-Object Windows.Forms.Panel
$brand.Location = [Drawing.Point]::new(0, 0)
$brand.Size = [Drawing.Size]::new(244, 94)
$brand.BackColor = $global:Pal.Sidebar
$sidebar.Controls.Add($brand)

$logo = New-Object Windows.Forms.Panel
$logo.Size = [Drawing.Size]::new(42, 42)
$logo.Location = [Drawing.Point]::new(22, 24)
$logo.BackColor = $global:Pal.Green
Set-RoundedRegion $logo 12
$logo.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 12 }.GetNewClosure())
$logo.Add_Paint({
    param($s, $e)
    $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
    $brush = [Drawing.Drawing2D.LinearGradientBrush]::new($rect, $global:Pal.Green, $global:Pal.LogoEnd, 45)
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
}.GetNewClosure())
$brand.Controls.Add($logo)

$logoText = New-Label -Text 'B' -X 0 -Y 1 -W 42 -H 40 -Size 18 -Family $script:FontDisplay -Style Bold -Color $global:Pal.Card -Align MiddleCenter
$logo.Controls.Add($logoText)

$brandTitle = New-Label -Text 'BlockTheSpot' -X 76 -Y 24 -W 150 -H 22 -Size 12.5 -Family $script:FontDisplay -Style Bold -Color $global:Pal.SidebarText
$brandSub = New-Label -Text 'CONTROL CENTER' -X 77 -Y 48 -W 150 -H 14 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarMuted
$brand.Controls.Add($brandTitle)
$brand.Controls.Add($brandSub)

$brandVersion = New-Label -Text 'v3.0' -X 188 -Y 28 -W 34 -H 18 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.Green -Align MiddleCenter
$brandVersion.BackColor = $global:Pal.GreenDeep
Set-RoundedRegion $brandVersion 5
$brandVersion.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 5 }.GetNewClosure())
$brand.Controls.Add($brandVersion)
$brandVersion.BringToFront()

$brandLine = New-Object Windows.Forms.Panel
$brandLine.Location = [Drawing.Point]::new(22, 93)
$brandLine.Size = [Drawing.Size]::new(200, 1)
$brandLine.BackColor = $global:Pal.SidebarLine
$brand.Controls.Add($brandLine)

$lActions = New-Label -Text 'ACCIONES' -X 24 -Y 112 -W 150 -H 14 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarFaint
$sidebar.Controls.Add($lActions)

$nav1 = New-NavItem -Title 'Instalar parche' -Subtitle 'Solo BlockTheSpot' -Icon $script:IcoCheck -AccentKey 'Green' -TintKey 'GreenDeep' -Top 134
$nav2 = New-NavItem -Title 'Instalar Spotify' -Subtitle 'Con BlockTheSpot' -Icon $script:IcoDownload -AccentKey 'Blue' -TintKey 'BlueDeep' -Top 198
$nav3 = New-NavItem -Title 'Desinstalar' -Subtitle 'Restaurar Spotify' -Icon $script:IcoDelete -AccentKey 'Red' -TintKey 'RedDeep' -Top 262
$sidebar.Controls.Add($nav1.Panel)
$sidebar.Controls.Add($nav2.Panel)
$sidebar.Controls.Add($nav3.Panel)

$lSystem = New-Label -Text 'SISTEMA' -X 24 -Y 342 -W 150 -H 14 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarFaint
$sidebar.Controls.Add($lSystem)

$sideSystem = New-Card -Radius 12 -BackColor $global:Pal.SidebarCard -BorderColor $global:Pal.SidebarLine -BackKey 'SidebarCard' -BorderKey 'SidebarLine'
$sideSystem.Location = [Drawing.Point]::new(20, 362)
$sideSystem.Size = [Drawing.Size]::new(204, 108)
$sidebar.Controls.Add($sideSystem)

$dotSideSpotify = New-Object Windows.Forms.Panel
$dotSideSpotify.Size = [Drawing.Size]::new(6, 6)
$dotSideSpotify.Location = [Drawing.Point]::new(14, 20)
$dotSideSpotify.BackColor = $global:Pal.Green
Set-RoundedRegion $dotSideSpotify 3
$dotSideSpotify.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$sideSystem.Controls.Add($dotSideSpotify)

$lSideSpotify = New-Label -Text 'Spotify' -X 26 -Y 12 -W 80 -H 18 -Size 7.5 -Family $script:FontUi -Color $global:Pal.SidebarMuted
$vSideSpotify = New-Label -Text 'Detectando...' -X 78 -Y 12 -W 112 -H 18 -Size 7.5 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarText -Align MiddleRight
$sideSystem.Controls.Add($lSideSpotify)
$sideSystem.Controls.Add($vSideSpotify)

$sideLine1 = New-Object Windows.Forms.Panel
$sideLine1.Location = [Drawing.Point]::new(14, 36)
$sideLine1.Size = [Drawing.Size]::new(176, 1)
$sideLine1.BackColor = $global:Pal.SidebarLine
$sideSystem.Controls.Add($sideLine1)

$dotSideAdmin = New-Object Windows.Forms.Panel
$dotSideAdmin.Size = [Drawing.Size]::new(6, 6)
$dotSideAdmin.Location = [Drawing.Point]::new(14, 52)
$dotSideAdmin.BackColor = $global:Pal.Yellow
Set-RoundedRegion $dotSideAdmin 3
$dotSideAdmin.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$sideSystem.Controls.Add($dotSideAdmin)

$lSideAdmin = New-Label -Text 'Permisos' -X 26 -Y 44 -W 80 -H 18 -Size 7.5 -Family $script:FontUi -Color $global:Pal.SidebarMuted
$vSideAdmin = New-Label -Text 'Comprobando' -X 78 -Y 44 -W 112 -H 18 -Size 7.5 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarText -Align MiddleRight
$sideSystem.Controls.Add($lSideAdmin)
$sideSystem.Controls.Add($vSideAdmin)

$sideLine2 = New-Object Windows.Forms.Panel
$sideLine2.Location = [Drawing.Point]::new(14, 68)
$sideLine2.Size = [Drawing.Size]::new(176, 1)
$sideLine2.BackColor = $global:Pal.SidebarLine
$sideSystem.Controls.Add($sideLine2)

$dotSideOs = New-Object Windows.Forms.Panel
$dotSideOs.Size = [Drawing.Size]::new(6, 6)
$dotSideOs.Location = [Drawing.Point]::new(14, 84)
$dotSideOs.BackColor = $global:Pal.Green
Set-RoundedRegion $dotSideOs 3
$dotSideOs.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$sideSystem.Controls.Add($dotSideOs)

$lSideOs = New-Label -Text 'Sistema' -X 26 -Y 76 -W 80 -H 18 -Size 7.5 -Family $script:FontUi -Color $global:Pal.SidebarMuted
$vSideOs = New-Label -Text 'Windows x64' -X 78 -Y 76 -W 112 -H 18 -Size 7.5 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarText -Align MiddleRight
$sideSystem.Controls.Add($lSideOs)
$sideSystem.Controls.Add($vSideOs)

$sideBottom = New-Object Windows.Forms.Panel
$sideBottom.Dock = [Windows.Forms.DockStyle]::Bottom
$sideBottom.Height = 140
$sideBottom.BackColor = $global:Pal.Sidebar
$sidebar.Controls.Add($sideBottom)

$sideBottomLine = New-Object Windows.Forms.Panel
$sideBottomLine.Location = [Drawing.Point]::new(22, 0)
$sideBottomLine.Size = [Drawing.Size]::new(200, 1)
$sideBottomLine.BackColor = $global:Pal.SidebarLine
$sideBottom.Controls.Add($sideBottomLine)

$lLinks = New-Label -Text 'ENLACES' -X 24 -Y 14 -W 150 -H 14 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.SidebarFaint
$sideBottom.Controls.Add($lLinks)

$linkBts = New-Object Windows.Forms.LinkLabel
$linkBts.Text = 'BlockTheSpot  ↗'
$linkBts.Location = [Drawing.Point]::new(24, 34)
$linkBts.Size = [Drawing.Size]::new(196, 18)
$linkBts.Font = [Drawing.Font]::new($script:FontUi, 7.5)
$linkBts.LinkColor = $global:Pal.Link
$linkBts.ActiveLinkColor = $global:Pal.Green
$linkBts.VisitedLinkColor = $global:Pal.Link
$linkBts.LinkBehavior = [Windows.Forms.LinkBehavior]::NeverUnderline
$linkBts.BackColor = $global:Pal.Sidebar
$sideBottom.Controls.Add($linkBts)

$linkInstaller = New-Object Windows.Forms.LinkLabel
$linkInstaller.Text = 'Installer oficial  ↗'
$linkInstaller.Location = [Drawing.Point]::new(24, 56)
$linkInstaller.Size = [Drawing.Size]::new(196, 18)
$linkInstaller.Font = [Drawing.Font]::new($script:FontUi, 7.5)
$linkInstaller.LinkColor = $global:Pal.Link
$linkInstaller.ActiveLinkColor = $global:Pal.Green
$linkInstaller.VisitedLinkColor = $global:Pal.Link
$linkInstaller.LinkBehavior = [Windows.Forms.LinkBehavior]::NeverUnderline
$linkInstaller.BackColor = $global:Pal.Sidebar
$sideBottom.Controls.Add($linkInstaller)

$dotVersion = New-Object Windows.Forms.Panel
$dotVersion.Size = [Drawing.Size]::new(5, 5)
$dotVersion.Location = [Drawing.Point]::new(24, 121)
$dotVersion.BackColor = $global:Pal.Green
Set-RoundedRegion $dotVersion 3
$dotVersion.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$sideBottom.Controls.Add($dotVersion)

$lVersion = New-Label -Text 'v3.0  ·  Windows x64' -X 35 -Y 112 -W 190 -H 18 -Size 7 -Family $script:FontUi -Color $global:Pal.SidebarFaint
$sideBottom.Controls.Add($lVersion)

# ------------------------------------------------------------------------------
#  AREA PRINCIPAL
# ------------------------------------------------------------------------------
$main = New-Object Windows.Forms.Panel
$main.Dock = [Windows.Forms.DockStyle]::Fill
$main.BackColor = $global:Pal.Bg
$main.Margin = [Windows.Forms.Padding]::new(0)
$root.Controls.Add($main, 1, 0)

$content = New-Object Windows.Forms.Panel
$content.Dock = [Windows.Forms.DockStyle]::Fill
$content.BackColor = $global:Pal.Bg
$content.Padding = [Windows.Forms.Padding]::new(28, 20, 28, 14)

$titlebar = New-Object Windows.Forms.Panel
$titlebar.Dock = [Windows.Forms.DockStyle]::Fill
$titlebar.Height = 46
$titlebar.BackColor = $global:Pal.Card

$tbDot = New-Object Windows.Forms.Panel
$tbDot.Size = [Drawing.Size]::new(6, 6)
$tbDot.Location = [Drawing.Point]::new(28, 20)
$tbDot.BackColor = $global:Pal.Green
Set-RoundedRegion $tbDot 3
$tbDot.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$titlebar.Controls.Add($tbDot)

$tbTitle = New-Label -Text 'BTS CONTROL CENTER' -X 42 -Y 0 -W 300 -H 46 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted
$titlebar.Controls.Add($tbTitle)

$windowTools = New-Object Windows.Forms.FlowLayoutPanel
$windowTools.Dock = [Windows.Forms.DockStyle]::Right
$windowTools.Width = 176
$windowTools.FlowDirection = [Windows.Forms.FlowDirection]::RightToLeft
$windowTools.WrapContents = $false
$windowTools.BackColor = $global:Pal.Card
$windowTools.Margin = [Windows.Forms.Padding]::new(0)
$windowTools.Padding = [Windows.Forms.Padding]::new(0)
$titlebar.Controls.Add($windowTools)

$btnClose = New-WindowButton -Glyph $script:IcoClose -IsClose $true
$btnMax = New-WindowButton -Glyph $script:IcoMaximize
$btnMin = New-WindowButton -Glyph $script:IcoMinimize
$btnTheme = New-WindowButton -Glyph $script:IcoSun
$windowTools.Controls.Add($btnClose.Panel)
$windowTools.Controls.Add($btnMax.Panel)
$windowTools.Controls.Add($btnMin.Panel)
$windowTools.Controls.Add($btnTheme.Panel)

$titlebarLine = New-Object Windows.Forms.Panel
$titlebarLine.Dock = [Windows.Forms.DockStyle]::Bottom
$titlebarLine.Height = 1
$titlebarLine.BackColor = $global:Pal.Border
$titlebar.Controls.Add($titlebarLine)

$mainLayout = New-Object Windows.Forms.TableLayoutPanel
$mainLayout.Dock = [Windows.Forms.DockStyle]::Fill
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 2
$mainLayout.BackColor = $global:Pal.Bg
$mainLayout.Margin = [Windows.Forms.Padding]::new(0)
$mainLayout.Padding = [Windows.Forms.Padding]::new(0)
$mainLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$mainLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 46)) | Out-Null
$mainLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$main.Controls.Add($mainLayout)
$mainLayout.Controls.Add($titlebar, 0, 0)
$mainLayout.Controls.Add($content, 0, 1)

# ------------------------------------------------------------------------------
#  LAYOUT DEL CONTENIDO
# ------------------------------------------------------------------------------
$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = [Windows.Forms.DockStyle]::Fill
$layout.ColumnCount = 1
$layout.RowCount = 8
$layout.BackColor = $global:Pal.Bg
$layout.Margin = [Windows.Forms.Padding]::new(0)
$layout.Padding = [Windows.Forms.Padding]::new(0)
$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 60))  | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 12))  | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 126)) | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 16))  | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 10))  | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 20))  | Out-Null
$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 16))  | Out-Null
$content.Controls.Add($layout)

# ------------------------------------------------------------------------------
#  CABECERA DE PAGINA
# ------------------------------------------------------------------------------
$pageHeader = New-Object Windows.Forms.Panel
$pageHeader.Dock = [Windows.Forms.DockStyle]::Fill
$pageHeader.BackColor = $global:Pal.Bg
$pageHeader.Margin = [Windows.Forms.Padding]::new(0)
$layout.Controls.Add($pageHeader, 0, 0)

$lOverline = New-Label -Text 'RESUMEN' -X 0 -Y 0 -W 300 -H 12 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.GreenDark
$lPageTitle = New-Label -Text 'Estado de la instalación' -X 0 -Y 12 -W 560 -H 30 -Size 18.5 -Family $script:FontDisplay -Style Bold -Color $global:Pal.Text
$lPageSub = New-Label -Text 'Administra Spotify y BlockTheSpot desde un solo panel.' -X 0 -Y 42 -W 560 -H 17 -Size 8.25 -Family $script:FontUi -Color $global:Pal.TextSecondary
$pageHeader.Controls.Add($lOverline)
$pageHeader.Controls.Add($lPageTitle)
$pageHeader.Controls.Add($lPageSub)

$refreshWrap = New-Object Windows.Forms.Panel
$refreshWrap.Dock = [Windows.Forms.DockStyle]::Right
$refreshWrap.Width = 118
$refreshWrap.BackColor = $global:Pal.Bg
$refreshWrap.Margin = [Windows.Forms.Padding]::new(0)
$pageHeader.Controls.Add($refreshWrap)

$btnRefresh = New-PillButton -Text 'Actualizar' -Glyph $script:IcoRefresh -W 112 -H 34 -Kind Outline
$btnRefresh.Panel.Location = [Drawing.Point]::new(0, 13)
$refreshWrap.Controls.Add($btnRefresh.Panel)

# ------------------------------------------------------------------------------
#  TARJETA HERO DE ESTADO
# ------------------------------------------------------------------------------
$hero = New-Object Windows.Forms.Panel
$hero.Dock = [Windows.Forms.DockStyle]::Fill
$hero.BackColor = $global:Pal.Hero1
$hero.Margin = [Windows.Forms.Padding]::new(0)
Set-RoundedRegion $hero 16
$hero.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 16 }.GetNewClosure())
$hero.Add_Paint({
    param($s, $e)
    $rect = [System.Drawing.Rectangle]::new(0, 0, $s.Width, $s.Height)
    $brush = [Drawing.Drawing2D.LinearGradientBrush]::new($rect, $global:Pal.Hero1, $global:Pal.Hero2, 22)
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
    $e.Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $glow = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(18, $global:StatusState.Accent))
    $e.Graphics.FillEllipse($glow, -100, $s.Height - 110, 250, 250)
    $glow.Dispose()
    $path = Get-RoundedPath -Rect ([System.Drawing.Rectangle]::new(0, 0, $s.Width - 1, $s.Height - 1)) -Radius ([int][Math]::Round(16 * $global:UiScale))
    $pen = [Drawing.Pen]::new($global:Pal.HeroBorder, 1)
    $e.Graphics.DrawPath($pen, $path)
    $pen.Dispose()
    $path.Dispose()
}.GetNewClosure())
$layout.Controls.Add($hero, 0, 2)

$heroStats = New-Object Windows.Forms.Panel
$heroStats.Dock = [Windows.Forms.DockStyle]::Right
$heroStats.Width = 350
$heroStats.BackColor = $global:Pal.HeroPanel
$heroStats.Margin = [Windows.Forms.Padding]::new(0)
$hero.Controls.Add($heroStats)

$heroStatsLine = New-Object Windows.Forms.Panel
$heroStatsLine.Dock = [Windows.Forms.DockStyle]::Left
$heroStatsLine.Width = 1
$heroStatsLine.BackColor = $global:Pal.HeroLine
$heroStats.Controls.Add($heroStatsLine)

$statsGrid = New-Object Windows.Forms.TableLayoutPanel
$statsGrid.Dock = [Windows.Forms.DockStyle]::Fill
$statsGrid.ColumnCount = 3
$statsGrid.RowCount = 1
$statsGrid.BackColor = $global:Pal.HeroPanel
$statsGrid.Margin = [Windows.Forms.Padding]::new(0)
$statsGrid.Padding = [Windows.Forms.Padding]::new(0)
$statsGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 33.33)) | Out-Null
$statsGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 33.33)) | Out-Null
$statsGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 33.34)) | Out-Null
$statsGrid.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$heroStats.Controls.Add($statsGrid)

function New-HeroStat {
    param([string]$Caption, [string]$Value, [string]$Sub, [int]$Column, [bool]$First = $false)
    $cell = New-Object Windows.Forms.Panel
    $cell.Dock = [Windows.Forms.DockStyle]::Fill
    $cell.BackColor = $global:Pal.HeroPanel
    $cell.Margin = [Windows.Forms.Padding]::new(0)
    if (-not $First) {
        $line = New-Object Windows.Forms.Panel
        $line.Dock = [Windows.Forms.DockStyle]::Left
        $line.Width = 1
        $line.BackColor = $global:Pal.HeroLine
        $cell.Controls.Add($line)
    }
    $cap = New-Label -Text $Caption -X 18 -Y 27 -W 94 -H 12 -Size 6.5 -Family $script:FontUi -Style Bold -Color $global:Pal.HeroStatCap
    $val = New-Label -Text $Value -X 18 -Y 43 -W 100 -H 20 -Size 9 -Family $script:FontUi -Style Bold -Color $global:Pal.HeroText -Ellipsis $true
    $subl = New-Label -Text $Sub -X 18 -Y 65 -W 100 -H 15 -Size 6.75 -Family $script:FontUi -Color $global:Pal.HeroStatSub -Ellipsis $true
    $cell.Controls.Add($cap)
    $cell.Controls.Add($val)
    $cell.Controls.Add($subl)
    $statsGrid.Controls.Add($cell, $Column, 0)
    Register-Theme $cell @{ BackColor = 'HeroPanel' }
    Register-Theme $cap @{ ForeColor = 'HeroStatCap' }
    Register-Theme $val @{ ForeColor = 'HeroText' }
    Register-Theme $subl @{ ForeColor = 'HeroStatSub' }
    if (-not $First) { Register-Theme $line @{ BackColor = 'HeroLine' } }
    return [pscustomobject]@{ Panel = $cell; Value = $val; Sub = $subl }
}

$statSpotify = New-HeroStat -Caption 'SPOTIFY' -Value 'Detectando...' -Sub 'Comprobando...' -Column 0 -First $true
$statPatch   = New-HeroStat -Caption 'PARCHE' -Value '—' -Sub 'Sin datos' -Column 1
$statAdmin   = New-HeroStat -Caption 'PERMISOS' -Value '—' -Sub 'Comprobando' -Column 2
$vHeroSpotify = $statSpotify.Value
$vHeroPatch = $statPatch.Value
$vHeroAdmin = $statAdmin.Value
$vHeroSpotifySub = $statSpotify.Sub
$vHeroPatchSub = $statPatch.Sub
$vHeroAdminSub = $statAdmin.Sub

$heroIconPanel = New-Object Windows.Forms.Panel
$heroIconPanel.Size = [Drawing.Size]::new(52, 52)
$heroIconPanel.Location = [Drawing.Point]::new(26, 37)
$heroIconPanel.BackColor = $global:Pal.GreenDeep
Set-RoundedRegion $heroIconPanel 14
$heroIconPanel.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 14 }.GetNewClosure())
$hero.Controls.Add($heroIconPanel)

$heroIconLabel = New-Label -Text $script:IcoInfo -X 0 -Y 0 -W 52 -H 52 -Size 18 -Family $script:FontIcon -Color $global:Pal.Green -Align MiddleCenter
$heroIconPanel.Controls.Add($heroIconLabel)

$lHeroCaption = New-Label -Text 'ESTADO ACTUAL' -X 94 -Y 22 -W 320 -H 12 -Size 6.75 -Family $script:FontUi -Style Bold -Color $global:Pal.HeroCaption
$lHeroStatus = New-Label -Text 'Verificando...' -X 94 -Y 38 -W 340 -H 27 -Size 15.5 -Family $script:FontDisplay -Style Bold -Color $global:Pal.HeroText -Ellipsis $true
$lHeroDetail = New-Label -Text 'Comprobando la instalación de Spotify...' -X 94 -Y 69 -W 340 -H 18 -Size 8 -Family $script:FontUi -Color $global:Pal.HeroDetail -Ellipsis $true
$lHeroFoot = New-Label -Text 'Los cambios se aplican al reiniciar Spotify.' -X 94 -Y 94 -W 340 -H 14 -Size 6.75 -Family $script:FontUi -Color $global:Pal.HeroFoot -Ellipsis $true
$hero.Controls.Add($lHeroCaption)
$hero.Controls.Add($lHeroStatus)
$hero.Controls.Add($lHeroDetail)
$hero.Controls.Add($lHeroFoot)

$hero.Add_SizeChanged({
    $w = [Math]::Max(160, $this.ClientSize.Width - $heroStats.Width - [int][Math]::Round(118 * $global:UiScale))
    $lHeroStatus.Width = $w
    $lHeroDetail.Width = $w
    $lHeroFoot.Width = $w
}.GetNewClosure())

# ------------------------------------------------------------------------------
#  CUERPO: ACTIVIDAD + SISTEMA
# ------------------------------------------------------------------------------
$body = New-Object Windows.Forms.TableLayoutPanel
$body.Dock = [Windows.Forms.DockStyle]::Fill
$body.ColumnCount = 3
$body.RowCount = 1
$body.BackColor = $global:Pal.Bg
$body.Margin = [Windows.Forms.Padding]::new(0)
$body.Padding = [Windows.Forms.Padding]::new(0)
$body.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 61.5)) | Out-Null
$body.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 16))  | Out-Null
$body.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 38.5)) | Out-Null
$body.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$layout.Controls.Add($body, 0, 4)

$activity = New-Card -Radius 14
$activity.Dock = [Windows.Forms.DockStyle]::Fill
$activity.Margin = [Windows.Forms.Padding]::new(0)
$body.Controls.Add($activity, 0, 0)

$lActTitle = New-Label -Text 'Actividad' -X 18 -Y 11 -W 260 -H 21 -Size 10.5 -Family $script:FontDisplay -Style Bold -Color $global:Pal.Text
$lActSub = New-Label -Text 'Registro del instalador en tiempo real' -X 18 -Y 32 -W 320 -H 14 -Size 7.25 -Family $script:FontUi -Color $global:Pal.TextMuted
$activity.Controls.Add($lActTitle)
$activity.Controls.Add($lActSub)

$logTools = New-Object Windows.Forms.Panel
$logTools.Size = [Drawing.Size]::new(76, 54)
$logTools.Location = [Drawing.Point]::new(500, 0)
$logTools.BackColor = $global:Pal.Card
$activity.Controls.Add($logTools)

$btnCopyLog = New-IconButton -Icon $script:IcoCopy -W 28 -H 28 -ColorKey 'TextMuted'
$btnCopyLog.Panel.Location = [Drawing.Point]::new(4, 13)
$logTools.Controls.Add($btnCopyLog.Panel)

$btnClearLog = New-IconButton -Icon $script:IcoClear -W 28 -H 28 -ColorKey 'TextMuted'
$btnClearLog.Panel.Location = [Drawing.Point]::new(36, 13)
$logTools.Controls.Add($btnClearLog.Panel)

$actLine = New-Object Windows.Forms.Panel
$actLine.Location = [Drawing.Point]::new(18, 53)
$actLine.Size = [Drawing.Size]::new(400, 1)
$actLine.BackColor = $global:Pal.Border
$activity.Controls.Add($actLine)

$logShell = New-Object Windows.Forms.Panel
$logShell.Location = [Drawing.Point]::new(14, 64)
$logShell.Size = [Drawing.Size]::new(400, 200)
$logShell.BackColor = $global:Pal.LogBg
$logShell.Padding = [Windows.Forms.Padding]::new(10, 9, 4, 9)
Set-RoundedRegion $logShell 10
$logShell.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 10 }.GetNewClosure())
$activity.Controls.Add($logShell)

$rtLog = New-Object Windows.Forms.RichTextBox
$rtLog.Dock = [Windows.Forms.DockStyle]::Fill
$rtLog.BackColor = $global:Pal.LogBg
$rtLog.ForeColor = $global:Pal.LogText
$rtLog.Font = [Drawing.Font]::new('Consolas', 8.25)
$rtLog.ReadOnly = $true
$rtLog.BorderStyle = [Windows.Forms.BorderStyle]::None
$rtLog.ScrollBars = [Windows.Forms.RichTextBoxScrollBars]::None
$rtLog.DetectUrls = $false
$rtLog.WordWrap = $true
$rtLog.ShortcutsEnabled = $true
$logShell.Controls.Add($rtLog)

$logScroll = New-Object Windows.Forms.Panel
$logScroll.Dock = [Windows.Forms.DockStyle]::Right
$logScroll.Width = 10
$logScroll.BackColor = $global:Pal.LogBg
$logScroll.Cursor = [Windows.Forms.Cursors]::Default
$logShell.Controls.Add($logScroll)

$logThumb = New-Object Windows.Forms.Panel
$logThumb.Size = [Drawing.Size]::new(6, 40)
$logThumb.Location = [Drawing.Point]::new(2, 0)
$logThumb.BackColor = $global:Pal.LogThumb
$logThumb.Cursor = [Windows.Forms.Cursors]::Hand
Set-RoundedRegion $logThumb 3
$logThumb.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 3 }.GetNewClosure())
$logScroll.Controls.Add($logThumb)

$logThumb.Add_MouseEnter({ $logThumb.BackColor = $global:Pal.LogThumbHover })
$logThumb.Add_MouseLeave({
    if (-not $global:LogThumbDragging) { $logThumb.BackColor = $global:Pal.LogThumb }
})

$activity.Add_SizeChanged({
    $s = $global:UiScale
    $w = $this.ClientSize.Width
    $h = $this.ClientSize.Height
    $actLine.Location = [Drawing.Point]::new([int][Math]::Round(18 * $s), [int][Math]::Round(53 * $s))
    $actLine.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $logTools.Location = [Drawing.Point]::new([Math]::Max(0, $w - [int][Math]::Round(76 * $s)), 0)
    $logTools.Size = [Drawing.Size]::new([int][Math]::Round(76 * $s), [int][Math]::Round(54 * $s))
    $logShell.Location = [Drawing.Point]::new([int][Math]::Round(14 * $s), [int][Math]::Round(64 * $s))
    $logShell.Size = [Drawing.Size]::new(
        [Math]::Max(10, $w - [int][Math]::Round(28 * $s)),
        [Math]::Max(10, $h - [int][Math]::Round(78 * $s)))
}.GetNewClosure())

$system = New-Card -Radius 14
$system.Dock = [Windows.Forms.DockStyle]::Fill
$system.Margin = [Windows.Forms.Padding]::new(0)
$body.Controls.Add($system, 2, 0)

$lSysTitle = New-Label -Text 'Sistema' -X 18 -Y 11 -W 240 -H 21 -Size 10.5 -Family $script:FontDisplay -Style Bold -Color $global:Pal.Text
$lSysSub = New-Label -Text 'Entorno detectado' -X 18 -Y 32 -W 240 -H 14 -Size 7.25 -Family $script:FontUi -Color $global:Pal.TextMuted
$system.Controls.Add($lSysTitle)
$system.Controls.Add($lSysSub)

$sysLine = New-Object Windows.Forms.Panel
$sysLine.Location = [Drawing.Point]::new(18, 53)
$sysLine.Size = [Drawing.Size]::new(260, 1)
$sysLine.BackColor = $global:Pal.Border
$system.Controls.Add($sysLine)

$sysBadge = New-Object Windows.Forms.Panel
$sysBadge.Location = [Drawing.Point]::new(16, 66)
$sysBadge.Size = [Drawing.Size]::new(284, 34)
$sysBadge.BackColor = $global:Pal.GreenSoft
Set-RoundedRegion $sysBadge 8
$sysBadge.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 8 }.GetNewClosure())
$system.Controls.Add($sysBadge)

$sysBadgeIcon = New-Label -Text $script:IcoCheck -X 10 -Y 0 -W 16 -H 34 -Size 9 -Family $script:FontIcon -Color $global:Pal.GreenDark -Align MiddleCenter
$sysBadgeText = New-Label -Text 'Sistema compatible' -X 30 -Y 0 -W 240 -H 34 -Size 7.75 -Family $script:FontUi -Style Bold -Color $global:Pal.GreenDark
$sysBadge.Controls.Add($sysBadgeIcon)
$sysBadge.Controls.Add($sysBadgeText)

$lInfoVersionCap = New-Label -Text 'VERSIÓN DE SPOTIFY' -X 18 -Y 108 -W 240 -H 12 -Size 6.25 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted
$vInfoVersion = New-Label -Text 'Detectando...' -X 18 -Y 121 -W 260 -H 18 -Size 8.25 -Family $script:FontUi -Style Bold -Color $global:Pal.Text -Ellipsis $true
$lInfoPathCap = New-Label -Text 'RUTA DE INSTALACIÓN' -X 18 -Y 146 -W 240 -H 12 -Size 6.25 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted
$vInfoPath = New-Label -Text 'Comprobando...' -X 18 -Y 159 -W 260 -H 18 -Size 7.5 -Family $script:FontUi -Color $global:Pal.TextSecondary -Ellipsis $true
$lInfoSourceCap = New-Label -Text 'ORIGEN' -X 18 -Y 184 -W 240 -H 12 -Size 6.25 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted
$vInfoSource = New-Label -Text 'Detectando...' -X 18 -Y 197 -W 260 -H 18 -Size 8 -Family $script:FontUi -Style Bold -Color $global:Pal.Text -Ellipsis $true
$system.Controls.Add($lInfoVersionCap)
$system.Controls.Add($vInfoVersion)
$system.Controls.Add($lInfoPathCap)
$system.Controls.Add($vInfoPath)
$system.Controls.Add($lInfoSourceCap)
$system.Controls.Add($vInfoSource)

$sysDivider = New-Object Windows.Forms.Panel
$sysDivider.Location = [Drawing.Point]::new(18, 228)
$sysDivider.Size = [Drawing.Size]::new(260, 1)
$sysDivider.BackColor = $global:Pal.Border
$system.Controls.Add($sysDivider)

$btnOpenFolder = New-PillButton -Text 'Abrir carpeta de Spotify' -Glyph $script:IcoFolder -W 284 -H 34 -Kind Dark
$btnOpenFolder.Panel.Location = [Drawing.Point]::new(16, 250)
$system.Controls.Add($btnOpenFolder.Panel)

$system.Add_SizeChanged({
    $s = $global:UiScale
    $w = $this.ClientSize.Width
    $h = $this.ClientSize.Height
    $sysLine.Location = [Drawing.Point]::new([int][Math]::Round(18 * $s), [int][Math]::Round(53 * $s))
    $sysLine.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $sysBadge.Location = [Drawing.Point]::new([int][Math]::Round(16 * $s), [int][Math]::Round(66 * $s))
    $sysBadge.Width = [Math]::Max(10, $w - [int][Math]::Round(32 * $s))
    $sysBadgeText.Width = [Math]::Max(10, $w - [int][Math]::Round(72 * $s))
    $vInfoVersion.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $vInfoPath.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $vInfoSource.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $btnOpenFolder.Panel.Width = [Math]::Max(10, $w - [int][Math]::Round(32 * $s))
    $btnOpenFolder.Panel.Location = [Drawing.Point]::new(
        [int][Math]::Round(16 * $s),
        [Math]::Max([int][Math]::Round(236 * $s), $h - [int][Math]::Round(50 * $s)))
    $sysDivider.Location = [Drawing.Point]::new(
        [int][Math]::Round(18 * $s),
        [Math]::Max([int][Math]::Round(224 * $s), $h - [int][Math]::Round(62 * $s)))
    $sysDivider.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
}.GetNewClosure())

# ------------------------------------------------------------------------------
#  PROGRESO Y PIE
# ------------------------------------------------------------------------------
$progressRow = New-Object Windows.Forms.TableLayoutPanel
$progressRow.Dock = [Windows.Forms.DockStyle]::Fill
$progressRow.ColumnCount = 3
$progressRow.RowCount = 1
$progressRow.BackColor = $global:Pal.Bg
$progressRow.Margin = [Windows.Forms.Padding]::new(0)
$progressRow.Padding = [Windows.Forms.Padding]::new(0)
$progressRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 64))  | Out-Null
$progressRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$progressRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 42))  | Out-Null
$progressRow.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100)) | Out-Null
$layout.Controls.Add($progressRow, 0, 6)

$lProgCap = New-Label -Text 'PROGRESO' -X 0 -Y 0 -W 64 -H 20 -Size 6.25 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted
$progressRow.Controls.Add($lProgCap, 0, 0)

$pgTrack = New-Object Windows.Forms.Panel
$pgTrack.Dock = [Windows.Forms.DockStyle]::Fill
$pgTrack.Margin = [Windows.Forms.Padding]::new(0, 8, 12, 8)
$pgTrack.BackColor = $global:Pal.Border
Set-RoundedRegion $pgTrack 2
$pgTrack.Add_SizeChanged({ Set-RoundedRegion -Control $this -Radius 2 }.GetNewClosure())
$progressRow.Controls.Add($pgTrack, 1, 0)

$pgFill = New-Object Windows.Forms.Panel
$pgFill.Location = [Drawing.Point]::new(0, 0)
$pgFill.Size = [Drawing.Size]::new(0, 4)
$pgFill.BackColor = $global:Pal.Green
$pgTrack.Controls.Add($pgFill)

$lProg = New-Label -Text '0%' -X 0 -Y 0 -W 42 -H 20 -Size 7 -Family $script:FontUi -Style Bold -Color $global:Pal.TextMuted -Align MiddleRight
$progressRow.Controls.Add($lProg, 2, 0)

$footer = New-Object Windows.Forms.Panel
$footer.Dock = [Windows.Forms.DockStyle]::Fill
$footer.BackColor = $global:Pal.Bg
$footer.Margin = [Windows.Forms.Padding]::new(0)
$layout.Controls.Add($footer, 0, 7)

$lFoot = New-Label -Text 'BlockTheSpot no está afiliado a Spotify AB.' -X 0 -Y 0 -W 420 -H 16 -Size 6.75 -Family $script:FontUi -Color $global:Pal.TextMuted
$lFoot.Dock = [Windows.Forms.DockStyle]::Left
$footer.Controls.Add($lFoot)

$lFootRight = New-Label -Text 'Windows x64  ·  Interfaz 3.0' -X 0 -Y 0 -W 220 -H 16 -Size 6.75 -Family $script:FontUi -Color $global:Pal.TextMuted -Align MiddleRight
$lFootRight.Dock = [Windows.Forms.DockStyle]::Right
$footer.Controls.Add($lFootRight)

# ==============================================================================
#  ENLACES DE TEMA
# ==============================================================================
Register-Theme $F @{ BackColor = 'Sidebar'; ForeColor = 'Text' }
Register-Theme $root @{ BackColor = 'Bg' }
Register-Theme $sidebar @{ BackColor = 'Sidebar' }
Register-Theme $brand @{ BackColor = 'Sidebar' }
Register-Theme $logo @{ BackColor = 'Green' }
Register-Theme $logoText @{ ForeColor = 'OnAccent' }
Register-Theme $brandTitle @{ ForeColor = 'SidebarText' }
Register-Theme $brandSub @{ ForeColor = 'SidebarMuted' }
Register-Theme $brandVersion @{ ForeColor = 'Green'; BackColor = 'GreenDeep' }
Register-Theme $brandLine @{ BackColor = 'SidebarLine' }
Register-Theme $lActions @{ ForeColor = 'SidebarFaint' }
Register-Theme $lSystem @{ ForeColor = 'SidebarFaint' }
Register-Theme $lLinks @{ ForeColor = 'SidebarFaint' }
Register-Theme $lVersion @{ ForeColor = 'SidebarFaint' }
Register-Theme $sideBottom @{ BackColor = 'Sidebar' }
Register-Theme $sideBottomLine @{ BackColor = 'SidebarLine' }
Register-Theme $dotVersion @{ BackColor = 'Green' }
Register-Theme $dotSideOs @{ BackColor = 'Green' }
Register-Theme $lSideSpotify @{ ForeColor = 'SidebarMuted' }
Register-Theme $vSideSpotify @{ ForeColor = 'SidebarText' }
Register-Theme $lSideAdmin @{ ForeColor = 'SidebarMuted' }
Register-Theme $vSideAdmin @{ ForeColor = 'SidebarText' }
Register-Theme $lSideOs @{ ForeColor = 'SidebarMuted' }
Register-Theme $vSideOs @{ ForeColor = 'SidebarText' }
Register-Theme $sideLine1 @{ BackColor = 'SidebarLine' }
Register-Theme $sideLine2 @{ BackColor = 'SidebarLine' }
Register-Theme $linkBts @{ LinkColor = 'Link'; ActiveLinkColor = 'Green'; VisitedLinkColor = 'Link'; BackColor = 'Sidebar' }
Register-Theme $linkInstaller @{ LinkColor = 'Link'; ActiveLinkColor = 'Green'; VisitedLinkColor = 'Link'; BackColor = 'Sidebar' }

Register-Theme $main @{ BackColor = 'Bg' }
Register-Theme $content @{ BackColor = 'Bg' }
Register-Theme $titlebar @{ BackColor = 'Card' }
Register-Theme $tbDot @{ BackColor = 'Green' }
Register-Theme $tbTitle @{ ForeColor = 'TextMuted' }
Register-Theme $windowTools @{ BackColor = 'Card' }
Register-Theme $titlebarLine @{ BackColor = 'Border' }
Register-Theme $mainLayout @{ BackColor = 'Bg' }
Register-Theme $layout @{ BackColor = 'Bg' }
Register-Theme $pageHeader @{ BackColor = 'Bg' }
Register-Theme $lOverline @{ ForeColor = 'GreenDark' }
Register-Theme $lPageTitle @{ ForeColor = 'Text' }
Register-Theme $lPageSub @{ ForeColor = 'TextSecondary' }
Register-Theme $refreshWrap @{ BackColor = 'Bg' }

Register-Theme $hero @{ BackColor = 'Hero1' }
Register-Theme $heroStats @{ BackColor = 'HeroPanel' }
Register-Theme $heroStatsLine @{ BackColor = 'HeroLine' }
Register-Theme $statsGrid @{ BackColor = 'HeroPanel' }
Register-Theme $lHeroCaption @{ ForeColor = 'HeroCaption' }
Register-Theme $lHeroStatus @{ ForeColor = 'HeroText' }
Register-Theme $lHeroDetail @{ ForeColor = 'HeroDetail' }
Register-Theme $lHeroFoot @{ ForeColor = 'HeroFoot' }

Register-Theme $body @{ BackColor = 'Bg' }
Register-Theme $lActTitle @{ ForeColor = 'Text' }
Register-Theme $lActSub @{ ForeColor = 'TextMuted' }
Register-Theme $logTools @{ BackColor = 'Card' }
Register-Theme $actLine @{ BackColor = 'Border' }
Register-Theme $logShell @{ BackColor = 'LogBg' }
Register-Theme $rtLog @{ BackColor = 'LogBg'; ForeColor = 'LogText' }
Register-Theme $logScroll @{ BackColor = 'LogBg' }
Register-Theme $logThumb @{ BackColor = 'LogThumb' }

Register-Theme $lSysTitle @{ ForeColor = 'Text' }
Register-Theme $lSysSub @{ ForeColor = 'TextMuted' }
Register-Theme $sysLine @{ BackColor = 'Border' }
Register-Theme $lInfoVersionCap @{ ForeColor = 'TextMuted' }
Register-Theme $vInfoVersion @{ ForeColor = 'Text' }
Register-Theme $lInfoPathCap @{ ForeColor = 'TextMuted' }
Register-Theme $vInfoPath @{ ForeColor = 'TextSecondary' }
Register-Theme $lInfoSourceCap @{ ForeColor = 'TextMuted' }
Register-Theme $vInfoSource @{ ForeColor = 'Text' }
Register-Theme $sysDivider @{ BackColor = 'Border' }

Register-Theme $progressRow @{ BackColor = 'Bg' }
Register-Theme $lProgCap @{ ForeColor = 'TextMuted' }
Register-Theme $pgTrack @{ BackColor = 'Border' }
Register-Theme $pgFill @{ BackColor = 'Green' }
Register-Theme $lProg @{ ForeColor = 'TextMuted' }
Register-Theme $footer @{ BackColor = 'Bg' }
Register-Theme $lFoot @{ ForeColor = 'TextMuted' }
Register-Theme $lFootRight @{ ForeColor = 'TextMuted' }

# ==============================================================================
#  FUNCIONES DE LOGICA
# ==============================================================================
$global:ProgressValue = 0
$global:LogScrollReady = $false
$global:LogThumbDragging = $false
$global:LogDragScreenY = 0
$global:LogDragStartFirst = 0

function Get-LogMetrics {
    $trackH = [Math]::Max(1, $logScroll.ClientSize.Height)
    $total = $rtLog.GetLineFromCharIndex($rtLog.TextLength) + 1
    $lineH = [Math]::Max(1, [int][Math]::Ceiling($rtLog.Font.GetHeight()))
    $visible = [Math]::Max(1, [int][Math]::Floor(($rtLog.ClientSize.Height - 2) / $lineH))
    $first = 0
    if ($rtLog.IsHandleCreated) {
        $first = [BtsNative]::SendMessage($rtLog.Handle, 0xCE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    }
    return [pscustomobject]@{
        Track = $trackH; Total = $total; Visible = $visible
        First = $first; MaxFirst = [Math]::Max(0, $total - $visible)
    }
}

function Update-LogScroll {
    if (-not $global:LogScrollReady) { return }
    if ($null -eq $rtLog -or $null -eq $logScroll -or $null -eq $logThumb) { return }
    $m = Get-LogMetrics
    if ($m.Total -le $m.Visible -or $m.MaxFirst -le 0) {
        $logThumb.Visible = $false
        return
    }
    $logThumb.Visible = $true
    $s = $global:UiScale
    $thumbW = [Math]::Max(4, [int][Math]::Round(6 * $s))
    $minH = [int][Math]::Round(24 * $s)
    $thumbH = [int][Math]::Round($m.Track * $m.Visible / $m.Total)
    $thumbH = [Math]::Min($m.Track, [Math]::Max($minH, $thumbH))
    $first = [Math]::Min([Math]::Max(0, $m.First), $m.MaxFirst)
    $top = [int][Math]::Round(($m.Track - $thumbH) * ($first / $m.MaxFirst))
    $logThumb.Size = [Drawing.Size]::new($thumbW, $thumbH)
    $logThumb.Location = [Drawing.Point]::new(
        [Math]::Max(0, [int][Math]::Round(($logScroll.ClientSize.Width - $thumbW) / 2)), $top)
    Set-RoundedRegion $logThumb 3
}

function Scroll-LogTo {
    param([int]$FirstLine)
    if (-not $rtLog.IsHandleCreated) { return }
    $m = Get-LogMetrics
    $target = [Math]::Min([Math]::Max(0, $FirstLine), $m.MaxFirst)
    $delta = $target - $m.First
    if ($delta -ne 0) {
        [BtsNative]::SendMessage($rtLog.Handle, 0xB6, [IntPtr]::Zero, [IntPtr]$delta) | Out-Null
    }
    Update-LogScroll
}

function Scroll-LogBy {
    param([int]$Lines)
    $m = Get-LogMetrics
    Scroll-LogTo -FirstLine ($m.First + $Lines)
}

$rtLog.Add_VScroll({ Update-LogScroll })
$rtLog.Add_TextChanged({ Update-LogScroll })
$rtLog.Add_Resize({ Update-LogScroll })
$logScroll.Add_Resize({ Update-LogScroll })
$logScroll.Add_MouseWheel({
    param($s, $e)
    Scroll-LogBy -Lines (3 * [Math]::Sign($e.Delta) * -1)
})
$logScroll.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
    $m = Get-LogMetrics
    if ($m.MaxFirst -le 0) { return }
    $range = [Math]::Max(1, $m.Track - $logThumb.Height)
    $ratio = ($e.Y - ($logThumb.Height / 2)) / $range
    Scroll-LogTo -FirstLine ([int][Math]::Round($ratio * $m.MaxFirst))
})
$logThumb.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
    $global:LogThumbDragging = $true
    $global:LogDragScreenY = [Windows.Forms.Cursor]::Position.Y
    $global:LogDragStartFirst = (Get-LogMetrics).First
    $logThumb.Capture = $true
})
$logThumb.Add_MouseMove({
    param($s, $e)
    if (-not $global:LogThumbDragging) { return }
    $m = Get-LogMetrics
    $range = [Math]::Max(1, $m.Track - $logThumb.Height)
    $dy = [Windows.Forms.Cursor]::Position.Y - $global:LogDragScreenY
    $target = $global:LogDragStartFirst + [int][Math]::Round(($dy / $range) * $m.MaxFirst)
    Scroll-LogTo -FirstLine $target
})
$logThumb.Add_MouseUp({
    param($s, $e)
    if (-not $global:LogThumbDragging) { return }
    $global:LogThumbDragging = $false
    $logThumb.Capture = $false
    if ($logThumb.ClientRectangle.Contains($logThumb.PointToClient([Windows.Forms.Cursor]::Position))) {
        $logThumb.BackColor = $global:Pal.LogThumbHover
    } else {
        $logThumb.BackColor = $global:Pal.LogThumb
    }
})

function Log {
    param([string]$Msg, [string]$T = 'info')
    $ts = Get-Date -Format 'HH:mm:ss'
    $pre = switch ($T) {
        'ok'    { 'OK  ' }
        'warn'  { 'WARN' }
        'err'   { 'ERR ' }
        'step'  { '... ' }
        default { '    ' }
    }
    $col = switch ($T) {
        'ok'    { $global:Pal.Green }
        'warn'  { $global:Pal.Yellow }
        'err'   { $global:Pal.Red }
        'step'  { $global:Pal.LogStep }
        default { $global:Pal.LogText }
    }
    $rtLog.SelectionStart = $rtLog.TextLength
    $rtLog.SelectionLength = 0
    $rtLog.SelectionColor = $global:Pal.LogMuted
    $rtLog.AppendText("[$ts] ")
    $rtLog.SelectionColor = $col
    $rtLog.AppendText("$pre $Msg`n")
    $rtLog.ScrollToCaret()
    Update-LogScroll
    [Windows.Forms.Application]::DoEvents()
}

function Prog {
    param([int]$V)
    $global:ProgressValue = [Math]::Min([Math]::Max($V, 0), 100)
    $w = [int]($pgTrack.ClientSize.Width * $global:ProgressValue / 100)
    $pgFill.Visible = $w -gt 0
    if ($w -gt 0) {
        $pgFill.Width = $w
        $pgFill.Height = [Math]::Max(1, $pgTrack.ClientSize.Height)
        Set-RoundedRegion $pgFill 2
    }
    $lProg.Text = "$global:ProgressValue%"
}

function LockUI {
    param([bool]$On)
    foreach ($nav in @($nav1, $nav2, $nav3)) { Set-NavEnabled -Nav $nav -Enabled (-not $On) }
    Set-PillEnabled -Button $btnRefresh -Enabled (-not $On)
    Set-PillEnabled -Button $btnOpenFolder -Enabled (-not $On)
}

function Confirm-Action {
    param([string]$Msg, [string]$Title)
    $r = [Windows.Forms.MessageBox]::Show(
        $F, $Msg, $Title,
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [Windows.Forms.DialogResult]::Yes)
}

function Show-Info {
    param([string]$Msg, [string]$Title)
    [Windows.Forms.MessageBox]::Show(
        $F, $Msg, $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-Warn {
    param([string]$Msg, [string]$Title)
    [Windows.Forms.MessageBox]::Show(
        $F, $Msg, $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Show-Err {
    param([string]$Msg, [string]$Title)
    [Windows.Forms.MessageBox]::Show(
        $F, $Msg, $Title,
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function Get-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Status {
    $spInst = Test-Path $SpExe
    $btsOn = (Test-Path $CElfDst) -and (Test-Path $BtsDll)
    $isStore = $false
    try {
        $isStore = $null -ne (Get-AppxPackage -Name SpotifyAB.SpotifyMusic -ErrorAction SilentlyContinue)
    } catch {
        $isStore = $false
    }
    $isAdmin = Get-IsAdmin

    $vText = 'desconocida'
    if ($spInst) {
        try {
            $v = (Get-Item $SpExe).VersionInfo.ProductVersionRaw
            if ($null -ne $v) { $vText = $v.ToString() }
        } catch { }
    }

    $accent = $global:Pal.Green
    $tint = $global:Pal.GreenDeep
    $glyph = $script:IcoCheck
    $status = ''
    $detail = ''

    if ($isStore) {
        $accent = $global:Pal.Yellow
        $tint = $global:Pal.YellowDeep
        $glyph = $script:IcoWarning
        $status = 'Spotify de Microsoft Store'
        $detail = 'Esta edición no es compatible. Instala Spotify Desktop desde spotify.com.'
    } elseif (-not $spInst) {
        $accent = $global:Pal.TextMuted
        $tint = $global:Pal.NeutralDeep
        $glyph = $script:IcoInfo
        $status = 'Spotify Desktop no instalado'
        $detail = 'Usa "Instalación completa" para descargar Spotify y aplicar el parche.'
    } elseif ($btsOn) {
        $status = 'BlockTheSpot está activo'
        $detail = "Spotify $vText  ·  El parche se cargará al iniciar la aplicación."
    } else {
        $accent = $global:Pal.Blue
        $tint = $global:Pal.BlueDeep
        $glyph = $script:IcoDownload
        $status = 'Spotify listo para parchear'
        $detail = "Spotify $vText  ·  BlockTheSpot aún no está aplicado."
    }

    $global:StatusState.Accent = $accent
    $heroIconPanel.BackColor = $tint
    $heroIconLabel.Text = $glyph
    $heroIconLabel.ForeColor = $accent
    $lHeroStatus.Text = $status
    $lHeroDetail.Text = $detail
    $hero.Invalidate()

    if ($spInst) {
        $vHeroSpotify.Text = 'Instalado'
        $vHeroSpotifySub.Text = "v$vText"
        $dotSideSpotify.BackColor = $global:Pal.Green
        $vSideSpotify.Text = 'Instalado'
        $vSideSpotify.ForeColor = $global:Pal.SidebarText
        $vInfoVersion.Text = $vText
        $vInfoPath.Text = $SpDir
        $vInfoSource.Text = 'Sitio oficial'
    } else {
        $vHeroSpotify.Text = 'No detectado'
        $vHeroSpotifySub.Text = 'Sin instalación'
        $dotSideSpotify.BackColor = $global:Pal.TextMuted
        $vSideSpotify.Text = 'No detectado'
        $vSideSpotify.ForeColor = $global:Pal.SidebarText
        $vInfoVersion.Text = 'No instalado'
        $vInfoPath.Text = 'No disponible'
        $vInfoSource.Text = 'No detectado'
    }

    if ($isStore) {
        $vHeroSpotify.Text = 'Microsoft Store'
        $vHeroSpotifySub.Text = 'Edición no compatible'
        $dotSideSpotify.BackColor = $global:Pal.Yellow
        $vSideSpotify.Text = 'Microsoft Store'
        $vSideSpotify.ForeColor = $global:Pal.Yellow
        $vInfoSource.Text = 'Microsoft Store'
    }

    if ($btsOn) {
        $vHeroPatch.Text = 'Activo'
        $vHeroPatchSub.Text = 'blockthespot.dll'
    } elseif ($spInst) {
        $vHeroPatch.Text = 'Inactivo'
        $vHeroPatchSub.Text = 'Sin aplicar'
    } else {
        $vHeroPatch.Text = '—'
        $vHeroPatchSub.Text = 'Sin datos'
    }

    $vHeroAdmin.Text = if ($isAdmin) { 'Administrador' } else { 'Estándar' }
    $vHeroAdminSub.Text = if ($isAdmin) { 'Cuenta elevada' } else { 'Sin elevación' }
    $dotSideAdmin.BackColor = if ($isAdmin) { $global:Pal.Green } else { $global:Pal.Yellow }
    $vSideAdmin.Text = if ($isAdmin) { 'Administrador' } else { 'Estándar' }
    $vSideAdmin.ForeColor = if ($isAdmin) { $global:Pal.SidebarText } else { $global:Pal.Yellow }

    if ($isStore) {
        $sysBadge.BackColor = $global:Pal.YellowSoft
        $sysBadgeIcon.Text = $script:IcoWarning
        $sysBadgeIcon.ForeColor = $global:Pal.YellowTextDeep
        $sysBadgeText.Text = 'Revisar instalación'
        $sysBadgeText.ForeColor = $global:Pal.YellowText
    } elseif (-not $spInst) {
        $sysBadge.BackColor = $global:Pal.DisabledBg
        $sysBadgeIcon.Text = $script:IcoInfo
        $sysBadgeIcon.ForeColor = $global:Pal.TextSecondary
        $sysBadgeText.Text = 'Spotify no detectado'
        $sysBadgeText.ForeColor = $global:Pal.TextSecondary
    } else {
        $sysBadge.BackColor = $global:Pal.GreenSoft
        $sysBadgeIcon.Text = $script:IcoCheck
        $sysBadgeIcon.ForeColor = $global:Pal.GreenDark
        $sysBadgeText.Text = 'Sistema compatible'
        $sysBadgeText.ForeColor = $global:Pal.GreenDark
    }

    if ($null -ne $tip) { $tip.SetToolTip($vInfoPath, $SpDir) }
}

function Stop-Sp {
    Log 'Deteniendo Spotify...' 'step'
    Stop-Process -Name Spotify -ErrorAction SilentlyContinue
    Stop-Process -Name SpotifyWebHelper -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Log 'Spotify detenido.' 'ok'
}

function Get-WebFile {
    param([string]$Url, [string]$Out, [string]$Label)
    Log "Descargando $Label..." 'step'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
        $kb = [Math]::Round((Get-Item $Out).Length / 1KB, 1)
        Log "$Label OK ($kb KB)" 'ok'
        return $true
    } catch {
        Log "Error descargando $Label" 'err'
        return $false
    }
}

function Do-InstallBTS {
    if (-not (Test-Path $SpDir)) {
        Log "No existe la carpeta $SpDir. Instala Spotify primero." 'err'
        return $false
    }

    foreach ($old in @(
        (Join-Path $SpDir 'dpapi.dll'),
        (Join-Path $SpDir 'blockthespot_settings.json')
    )) {
        if (Test-Path $old) {
            Remove-Item -Force $old
            $n = Split-Path $old -Leaf
            Log "Archivo antiguo eliminado: $n" 'warn'
        }
    }

    Log 'Verificando chrome_elf.dll original...' 'step'

    if (Test-Path $CElfBak) {
        Log 'Backup chrome_elf_required.dll ya existe.' 'ok'
        if (Test-Path $CElfDst) {
            $sz = (Get-Item $CElfDst).Length
            if ($sz -lt 1MB) { Remove-Item -Force $CElfDst }
        }
    } elseif (Test-Path $CElfDst) {
        $sz = (Get-Item $CElfDst).Length
        if ($sz -gt 1MB) {
            Rename-Item -Path $CElfDst -NewName 'chrome_elf_required.dll' -Force
            Log 'chrome_elf.dll original guardado como backup.' 'ok'
        } else {
            Remove-Item -Force $CElfDst
            Log 'chrome_elf.dll de BTS anterior eliminado.' 'warn'
        }
    }

    Prog 40
    $r1 = Get-WebFile -Url $UrlElf -Out $CElfDst -Label 'chrome_elf.dll'
    Prog 65
    $r2 = Get-WebFile -Url $UrlBts -Out $BtsDll  -Label 'blockthespot.dll'
    Prog 85
    $r3 = Get-WebFile -Url $UrlCfg -Out $CfgIni  -Label 'config.ini'
    Prog 100

    if (-not ($r1 -and $r2)) {
        Log 'Descarga fallida. Revisa tu conexión.' 'err'
        if ((-not (Test-Path $CElfDst)) -and (Test-Path $CElfBak)) {
            Rename-Item -Path $CElfBak -NewName 'chrome_elf.dll' -Force
            Log 'chrome_elf.dll original restaurado.' 'warn'
        }
        return $false
    }
    return $true
}

function Do-InstallSpotify {
    $setup = Join-Path $env:TEMP 'SpotifySetup.exe'
    $url = if ([Environment]::Is64BitOperatingSystem) {
        'https://download.scdn.co/SpotifyFullSetupX64.exe'
    } else {
        'https://download.scdn.co/SpotifyFullSetup.exe'
    }

    if (-not (Get-WebFile -Url $url -Out $setup -Label 'SpotifySetup.exe')) { return $false }

    Prog 20
    Log 'Instalando Spotify...' 'step'

    $isAdmin = Get-IsAdmin

    if ($isAdmin) {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -Command `"& '$setup'`""
        $trg = New-ScheduledTaskTrigger -Once -At (Get-Date)
        $cfg = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
        Register-ScheduledTask -Action $act -Trigger $trg -TaskName 'BTS_SpSetup' -Settings $cfg -Force | Out-Null
        Start-ScheduledTask -TaskName 'BTS_SpSetup'
        Start-Sleep -Seconds 3
        Unregister-ScheduledTask -TaskName 'BTS_SpSetup' -Confirm:$false -ErrorAction SilentlyContinue
    } else {
        Start-Process -FilePath $setup
    }

    Log 'Esperando instalación de Spotify...' 'step'
    $t = 0
    while ($t -lt 120) {
        if (Get-Process -Name Spotify -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Milliseconds 500
        $t += 0.5
        [Windows.Forms.Application]::DoEvents()
    }
    Start-Sleep -Seconds 2

    Stop-Process -Name Spotify -ErrorAction SilentlyContinue
    Stop-Process -Name SpotifyWebHelper -ErrorAction SilentlyContinue
    Stop-Process -Name SpotifyFullSetupX64 -ErrorAction SilentlyContinue
    Stop-Process -Name SpotifyFullSetup -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (-not (Test-Path $SpExe)) {
        Log 'No se pudo verificar la instalación de Spotify.' 'err'
        return $false
    }
    Log 'Spotify instalado correctamente.' 'ok'
    return $true
}

# ==============================================================================
#  EVENTOS DE ACCION
# ==============================================================================
$clickB1 = {
    if (-not (Test-Path $SpExe)) {
        Show-Warn "Spotify Desktop no está instalado.`nUsa la opción 'Instalación completa'." 'Spotify no encontrado'
        return
    }

    $v = $null
    try { $v = [System.Version](Get-Item $SpExe).VersionInfo.ProductVersionRaw } catch { }
    if ($null -ne $v -and $v -lt $MinVer) {
        $msg = "Spotify $v es anterior a la versión mínima requerida ($MinVer).`nPuede no funcionar. ¿Continuar de todas formas?"
        if (-not (Confirm-Action $msg 'Versión antigua')) { return }
    }
    if (-not (Confirm-Action "Se instalará BlockTheSpot.`nSpotify se cerrará durante el proceso. ¿Continuar?" 'Instalar BlockTheSpot')) { return }

    LockUI $true
    $rtLog.Clear()
    Prog 0
    try {
        Log 'Iniciando instalación de BlockTheSpot...' 'step'
        Stop-Sp
        Prog 15
        $ok = Do-InstallBTS
        if ($ok) {
            Log 'BlockTheSpot instalado correctamente.' 'ok'
            Refresh-Status
            Start-Process -WorkingDirectory $SpDir -FilePath $SpExe
            Show-Info "BlockTheSpot instalado correctamente.`nSpotify se está iniciando." 'Éxito'
        } else {
            Refresh-Status
            Show-Err "Hubo un error en la instalación.`nRevisa el registro para más detalles." 'Error'
        }
    } finally {
        LockUI $false
    }
}

$clickB2 = {
    if (-not (Confirm-Action "Se descargará e instalará Spotify Desktop y BlockTheSpot.`nSi tienes Spotify de la Store, se desinstalará automáticamente.`n`n¿Continuar?" 'Instalación completa')) { return }

    LockUI $true
    $rtLog.Clear()
    Prog 0
    try {
        Log 'Iniciando instalación completa...' 'step'

        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }
        if (Get-AppxPackage -Name SpotifyAB.SpotifyMusic -ErrorAction SilentlyContinue) {
            Log 'Desinstalando Spotify Store...' 'warn'
            Get-AppxPackage -Name SpotifyAB.SpotifyMusic | Remove-AppxPackage
            Log 'Spotify Store desinstalado.' 'ok'
        }

        Stop-Sp
        Prog 5
        $ok = Do-InstallSpotify
        if (-not $ok) {
            Refresh-Status
            Show-Err "No se pudo instalar Spotify.`nInténtalo manualmente desde spotify.com." 'Error'
            return
        }

        Prog 30
        Log 'Instalando BlockTheSpot...' 'step'
        Stop-Sp
        $ok = Do-InstallBTS

        if ($ok) {
            Log 'Instalación completa exitosa.' 'ok'
            Refresh-Status
            Start-Process -WorkingDirectory $SpDir -FilePath $SpExe
            Show-Info "Spotify + BlockTheSpot instalados correctamente.`nSpotify se está iniciando." 'Éxito'
        } else {
            Refresh-Status
            Show-Warn "Spotify se instaló pero BlockTheSpot falló.`nRevisa el registro." 'Error parcial'
        }
    } finally {
        LockUI $false
    }
}

$clickB3 = {
    if (-not (Confirm-Action "Se eliminarán los archivos de BlockTheSpot y se restaurará chrome_elf.dll original.`n`n¿Continuar?" 'Desinstalar BlockTheSpot')) { return }

    LockUI $true
    $rtLog.Clear()
    Prog 0
    try {
        Log 'Iniciando desinstalación...' 'step'
        Stop-Sp
        Prog 30

        $removed = $false
        foreach ($f in @($CElfDst, $BtsDll, $CfgIni)) {
            if (Test-Path $f) {
                Remove-Item -Force $f
                $n = Split-Path $f -Leaf
                Log "Eliminado: $n" 'ok'
                $removed = $true
            }
        }
        Prog 70

        if (Test-Path $CElfBak) {
            if (-not (Test-Path $CElfDst)) {
                Rename-Item -Path $CElfBak -NewName 'chrome_elf.dll' -Force
                Log 'chrome_elf.dll original restaurado.' 'ok'
            } else {
                Log 'chrome_elf.dll ya existía. Sin cambios.' 'warn'
            }
        } else {
            Log 'Backup no encontrado. Puede necesitar reinstalar Spotify.' 'warn'
        }
        Prog 100

        if ($removed) { Log 'BlockTheSpot desinstalado correctamente.' 'ok' }
        else          { Log 'No se encontraron archivos de BlockTheSpot instalados.' 'warn' }

        Refresh-Status
        Start-Process -WorkingDirectory $SpDir -FilePath $SpExe -ErrorAction SilentlyContinue
        Show-Info "BlockTheSpot desinstalado.`nSpotify restaurado al estado original." 'Desinstalación completa'
    } finally {
        LockUI $false
    }
}

# ==============================================================================
#  EVENTOS DE LA INTERFAZ
# ==============================================================================
function Add-PillClick {
    param($Button, $Handler)
    foreach ($ctrl in @($Button.Panel, $Button.Label, $Button.IconLabel)) {
        if ($null -ne $ctrl) { $ctrl.Add_Click($Handler) }
    }
}

function Add-IconButtonClick {
    param($Button, $Handler)
    $Button.Panel.Add_Click($Handler)
    $Button.Label.Add_Click($Handler)
}

Add-NavEvents -Nav $nav1 -OnClick $clickB1
Add-NavEvents -Nav $nav2 -OnClick $clickB2
Add-NavEvents -Nav $nav3 -OnClick $clickB3

Add-PillClick -Button $btnRefresh -Handler {
    Log 'Verificando estado de Spotify...' 'step'
    Refresh-Status
    Log 'Estado actualizado.' 'ok'
}

Add-PillClick -Button $btnOpenFolder -Handler {
    if (Test-Path $SpDir) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $SpDir
    } else {
        Show-Warn "La carpeta de Spotify no existe:`n$SpDir" 'Carpeta no encontrada'
    }
}

Add-IconButtonClick -Button $btnCopyLog -Handler {
    try {
        if ($rtLog.TextLength -gt 0) {
            try {
                [Windows.Forms.Clipboard]::SetText($rtLog.Text)
            } catch {
                Set-Clipboard -Value $rtLog.Text
            }
            Log 'Registro copiado al portapapeles.' 'ok'
        } else {
            Log 'El registro está vacío.' 'warn'
        }
    } catch {
        Show-Err "No se pudo copiar el registro al portapapeles.`n$($_.Exception.Message)" 'Error'
    }
}

Add-IconButtonClick -Button $btnClearLog -Handler {
    $rtLog.Clear()
    Log 'Registro limpiado.' 'info'
}

$linkBts.Add_LinkClicked({
    Start-Process 'https://github.com/Nuzair46/BlockTheSpot'
})

$linkInstaller.Add_LinkClicked({
    Start-Process 'https://github.com/Nuzair46/BlockTheSpot-Installer'
})

$clickMin = { $F.WindowState = [Windows.Forms.FormWindowState]::Minimized }
$clickMax = {
    if ($F.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) {
        $F.WindowState = [Windows.Forms.FormWindowState]::Normal
    } else {
        $F.WindowState = [Windows.Forms.FormWindowState]::Maximized
    }
}
$clickClose = { $F.Close() }
$clickTheme = { Switch-Theme }
foreach ($ctrl in @($btnMin.Panel, $btnMin.Label)) { $ctrl.Add_Click($clickMin) }
foreach ($ctrl in @($btnMax.Panel, $btnMax.Label)) { $ctrl.Add_Click($clickMax) }
foreach ($ctrl in @($btnClose.Panel, $btnClose.Label)) { $ctrl.Add_Click($clickClose) }
foreach ($ctrl in @($btnTheme.Panel, $btnTheme.Label)) { $ctrl.Add_Click($clickTheme) }

$updateMaxGlyph = {
    if ($F.WindowState -eq [Windows.Forms.FormWindowState]::Maximized) {
        $btnMax.Label.Text = $script:IcoRestore
    } else {
        $btnMax.Label.Text = $script:IcoMaximize
    }
}
$F.Add_Resize($updateMaxGlyph)
$F.Add_Resize({ Sync-UiLayout })

$pgTrack.Add_SizeChanged({ Prog $global:ProgressValue })

# ------------------------------------------------------------------------------
#  TOOLTIPS
# ------------------------------------------------------------------------------
$tip = New-Object Windows.Forms.ToolTip
$tip.AutoPopDelay = 12000
$tip.InitialDelay = 450
$tip.ReshowDelay = 100
$tip.ShowAlways = $true

$tip.SetToolTip($btnRefresh.Panel, 'Volver a comprobar el estado (F5)')
$tip.SetToolTip($btnOpenFolder.Panel, 'Abrir la carpeta de instalación de Spotify')
$tip.SetToolTip($btnCopyLog.Panel, 'Copiar todo el registro al portapapeles')
$tip.SetToolTip($btnClearLog.Panel, 'Vaciar el registro')
$tip.SetToolTip($btnMin.Panel, 'Minimizar')
$tip.SetToolTip($btnMax.Panel, 'Maximizar o restaurar')
$tip.SetToolTip($btnClose.Panel, 'Cerrar')
$tip.SetToolTip($btnTheme.Panel, 'Cambiar a tema claro')
$tip.SetToolTip($vInfoPath, $SpDir)
$tip.SetToolTip($nav1.Panel, 'Descargar el parche y aplicarlo a la instalación actual')
$tip.SetToolTip($nav2.Panel, 'Descargar Spotify Desktop y aplicar BlockTheSpot')
$tip.SetToolTip($nav3.Panel, 'Eliminar el parche y restaurar la DLL original')
$tip.SetToolTip($lHeroStatus, $null)

# ------------------------------------------------------------------------------
#  AJUSTE FINO DE MEDIDAS
# ------------------------------------------------------------------------------
function Sync-UiLayout {
    $s = $global:UiScale
    $w = $activity.ClientSize.Width
    $h = $activity.ClientSize.Height
    $actLine.Location = [Drawing.Point]::new([int][Math]::Round(18 * $s), [int][Math]::Round(53 * $s))
    $actLine.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $logTools.Location = [Drawing.Point]::new([Math]::Max(0, $w - [int][Math]::Round(76 * $s)), 0)
    $logTools.Size = [Drawing.Size]::new([int][Math]::Round(76 * $s), [int][Math]::Round(54 * $s))
    $logShell.Location = [Drawing.Point]::new([int][Math]::Round(14 * $s), [int][Math]::Round(64 * $s))
    $logShell.Size = [Drawing.Size]::new(
        [Math]::Max(10, $w - [int][Math]::Round(28 * $s)),
        [Math]::Max(10, $h - [int][Math]::Round(78 * $s)))

    $w = $system.ClientSize.Width
    $h = $system.ClientSize.Height
    $sysLine.Location = [Drawing.Point]::new([int][Math]::Round(18 * $s), [int][Math]::Round(53 * $s))
    $sysLine.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $sysBadge.Location = [Drawing.Point]::new([int][Math]::Round(16 * $s), [int][Math]::Round(66 * $s))
    $sysBadge.Width = [Math]::Max(10, $w - [int][Math]::Round(32 * $s))
    $sysBadgeText.Width = [Math]::Max(10, $w - [int][Math]::Round(72 * $s))
    $vInfoVersion.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $vInfoPath.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $vInfoSource.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))
    $btnOpenFolder.Panel.Width = [Math]::Max(10, $w - [int][Math]::Round(32 * $s))
    $btnOpenFolder.Panel.Location = [Drawing.Point]::new(
        [int][Math]::Round(16 * $s),
        [Math]::Max([int][Math]::Round(236 * $s), $h - [int][Math]::Round(50 * $s)))
    $sysDivider.Location = [Drawing.Point]::new(
        [int][Math]::Round(18 * $s),
        [Math]::Max([int][Math]::Round(224 * $s), $h - [int][Math]::Round(62 * $s)))
    $sysDivider.Width = [Math]::Max(10, $w - [int][Math]::Round(36 * $s))

    $w = [Math]::Max(160, $hero.ClientSize.Width - $heroStats.Width - [int][Math]::Round(118 * $s))
    $lHeroStatus.Width = $w
    $lHeroDetail.Width = $w
    $lHeroFoot.Width = $w

    Prog $global:ProgressValue
    Update-LogScroll
}

# ------------------------------------------------------------------------------
#  VENTANA, DPI Y ARRANQUE
# ------------------------------------------------------------------------------
$F.Add_Load({
    $F.ResizeBorder = [int][Math]::Round(6 * $global:UiScale)
    $F.CaptionHeight = [int][Math]::Round(46 * $global:UiScale)
    $F.CaptionLeft = [int][Math]::Round(244 * $global:UiScale)
    $F.CaptionRight = [int][Math]::Round(176 * $global:UiScale)
    $F.SidebarWidth = [int][Math]::Round(244 * $global:UiScale)
    $F.BrandHeight = [int][Math]::Round(94 * $global:UiScale)
    try {
        $round = 2
        [BtsNative]::DwmSetWindowAttribute($F.Handle, 33, [ref]$round, 4) | Out-Null
        $dark = if ($global:ThemeName -eq 'Dark') { 1 } else { 0 }
        [BtsNative]::DwmSetWindowAttribute($F.Handle, 20, [ref]$dark, 4) | Out-Null
    } catch { }
})

$F.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [Windows.Forms.Keys]::F5) {
        Log 'Verificando estado de Spotify...' 'step'
        Refresh-Status
        Log 'Estado actualizado.' 'ok'
    }
})

$F.Add_Shown({
    Sync-UiLayout
    try { [BtsNative]::SetWindowTheme($rtLog.Handle, 'DarkMode_Explorer', $null) | Out-Null } catch { }
    $global:LogScrollReady = $true
    Update-LogScroll
    Log 'BlockTheSpot Control Center 3.0 iniciado.' 'info'
    if (Get-IsAdmin) {
        Log 'Ejecutando como Administrador.' 'ok'
    } else {
        Log 'ADVERTENCIA: No eres Administrador. Algunas operaciones pueden fallar.' 'warn'
    }
    Log 'Verificando estado de Spotify...' 'step'
    Refresh-Status
    Prog 0
    Log 'Listo.' 'ok'
})

# El escalado DPI se configura al final, cuando todos los controles existen.
$F.ClientSize = [Drawing.Size]::new(1120, 640)
$F.MinimumSize = [Drawing.Size]::new(1020, 630)
$F.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
$F.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi

Apply-Theme -Name $global:ThemeName

[Windows.Forms.Application]::Run($F)
