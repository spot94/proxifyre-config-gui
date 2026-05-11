#requires -Version 5.1
# ProxiFyre Config Editor — PowerShell WPF GUI
# Compatible with PowerShell 5.1+ and PowerShell 7+

# Auto-elevate to Administrator if needed (required for service management)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psPath = (Get-Process -Id $PID).Path
    $filePath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if (-not $filePath) {
        [void][System.Windows.MessageBox]::Show("Cannot auto-elevate: script path is unknown. Please run as Administrator manually.", "Elevation Required", "OK", "Error")
        exit
    }
    Start-Process -FilePath $psPath -ArgumentList "-ExecutionPolicy Bypass -File `"$filePath`"" -Verb RunAs
    exit
}

# (no parameters)

#region Assembly Loading
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.ServiceProcess
#endregion

#region C# Data Models
$CSharpCode = @"
using System;
using System.Collections.ObjectModel;

public enum LogLevel { Error, Warning, Info, Debug, All }
public enum Protocol { TCP, UDP }

public class ProxyConfig
{
    public ObservableCollection<string> appNames { get; set; } = new ObservableCollection<string>();
    public string socks5ProxyEndpoint { get; set; }
    public string username { get; set; }
    public string password { get; set; }
    public ObservableCollection<Protocol> supportedProtocols { get; set; } = new ObservableCollection<Protocol>();

    // Display helpers for WPF binding
    public string appNamesDisplay => string.Join(", ", appNames);
    public string protocolsDisplay => string.Join(", ", supportedProtocols);
}

public class AppConfig
{
    public LogLevel logLevel { get; set; } = LogLevel.Error;
    public bool bypassLan { get; set; } = false;
    public ObservableCollection<ProxyConfig> proxies { get; set; } = new ObservableCollection<ProxyConfig>();
    public ObservableCollection<string> excludes { get; set; } = new ObservableCollection<string>();
}
"@

Add-Type -TypeDefinition $CSharpCode -ErrorAction Stop
#endregion

#region XAML Definitions
$script:MainWindowXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ProxiFyre Config Editor" Height="850" Width="950"
        WindowStartupLocation="CenterScreen">
  <DockPanel>
    <Menu DockPanel.Dock="Top">
      <MenuItem Header="_File">
        <MenuItem Header="_New" InputGestureText="Ctrl+N" Name="menuNew"/>
        <MenuItem Header="_Open..." InputGestureText="Ctrl+O" Name="menuOpen"/>
        <MenuItem Header="_Save" InputGestureText="Ctrl+S" Name="menuSave"/>
        <MenuItem Header="Save _As..." InputGestureText="Ctrl+Shift+S" Name="menuSaveAs"/>
        <Separator/>
        <MenuItem Header="E_xit" Name="menuExit"/>
      </MenuItem>
      <MenuItem Header="_Tools">
        <MenuItem Header="_Validate JSON" Name="menuValidate"/>
        <MenuItem Header="Copy JSON to _Clipboard" Name="menuCopyJson"/>
        <MenuItem Header="_Process Picker" Name="menuProcessPicker"/>
      </MenuItem>
      <MenuItem Header="_Service">
        <MenuItem Header="_Install" Name="menuSvcInstall"/>
        <MenuItem Header="_Uninstall" Name="menuSvcUninstall"/>
        <Separator/>
        <MenuItem Header="_Start" Name="menuSvcStart"/>
        <MenuItem Header="S_top" Name="menuSvcStop"/>
        <MenuItem Header="_Restart" Name="menuSvcRestart"/>
      </MenuItem>
    </Menu>

    <StatusBar DockPanel.Dock="Bottom">
      <StatusBarItem DockPanel.Dock="Left">
        <TextBlock Name="txtStatus" Text="Ready"/>
      </StatusBarItem>
      <StatusBarItem DockPanel.Dock="Left">
        <TextBlock Name="txtFilePath" Text=""/>
      </StatusBarItem>
      <StatusBarItem DockPanel.Dock="Right">
        <TextBlock Name="txtServiceStatus" Text="Checking..." FontWeight="Bold"/>
      </StatusBarItem>
    </StatusBar>

    <Grid Margin="10">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="2*"/>
        <RowDefinition Height="140"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <GroupBox Header="Global Settings" Grid.Row="0" Margin="0,0,0,10">
        <StackPanel Orientation="Horizontal" Margin="5">
          <TextBlock Text="Log Level:" VerticalAlignment="Center" Margin="0,0,5,0"/>
          <ComboBox Name="cmbLogLevel" Width="120" VerticalAlignment="Center"/>
          <CheckBox Name="chkBypassLan" Content="Bypass LAN traffic" Margin="20,0,0,0"
                    VerticalAlignment="Center"/>
        </StackPanel>
      </GroupBox>

      <GroupBox Header="Proxy Rules" Grid.Row="1" Margin="0,0,0,10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <ListView Name="lvProxies" Grid.Row="0">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Applications" Width="220"
                  DisplayMemberBinding="{Binding appNamesDisplay}"/>
                <GridViewColumn Header="SOCKS5 Endpoint" Width="180"
                  DisplayMemberBinding="{Binding socks5ProxyEndpoint}"/>
                <GridViewColumn Header="Username" Width="100"
                  DisplayMemberBinding="{Binding username}"/>
                <GridViewColumn Header="Protocols" Width="100"
                  DisplayMemberBinding="{Binding protocolsDisplay}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,5,0,0">
            <Button Name="btnAddProxy" Content="Add" Width="80" Margin="0,0,5,0"/>
            <Button Name="btnEditProxy" Content="Edit" Width="80" Margin="0,0,5,0"/>
            <Button Name="btnRemoveProxy" Content="Remove" Width="80" Margin="0,0,5,0"/>
            <Button Name="btnCloneProxy" Content="Clone" Width="80"/>
          </StackPanel>
        </Grid>
      </GroupBox>

      <GroupBox Header="JSON Preview" Grid.Row="2" Margin="0,0,0,10">
        <TextBox Name="txtJsonPreview" IsReadOnly="True"
                 VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="11"
                 TextWrapping="NoWrap"/>
      </GroupBox>

      <GroupBox Header="Exclusions (bypass proxy)" Grid.Row="3">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <ListBox Name="lbExcludes" Grid.Column="0" Height="120"/>
          <StackPanel Grid.Column="1" Margin="10,0,0,0">
            <Button Name="btnAddExclude" Content="Add" Width="100" Margin="0,0,0,5"/>
            <Button Name="btnRemoveExclude" Content="Remove" Width="100" Margin="0,0,0,5"/>
            <Button Name="btnBrowseExclude" Content="Browse..." Width="100" Margin="0,0,0,5"/>
            <Button Name="btnPickExclude" Content="Pick Process" Width="100"/>
          </StackPanel>
        </Grid>
      </GroupBox>
    </Grid>
  </DockPanel>
</Window>
"@

$script:EditProxyDialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit Proxy Rule" Height="500" Width="520"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <Grid Margin="15">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="SOCKS5 Endpoint (host:port):" FontWeight="Bold"/>
      <TextBox Name="txtEndpoint" Margin="0,3,0,0"/>
    </StackPanel>

    <Grid Grid.Row="1" Margin="0,0,0,10">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Margin="0,0,5,0">
        <TextBlock Text="Username (optional):"/>
        <TextBox Name="txtUsername" Margin="0,3,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Margin="5,0,0,0">
        <TextBlock Text="Password (optional):"/>
        <PasswordBox Name="txtPassword" Margin="0,3,0,0"/>
      </StackPanel>
    </Grid>

    <StackPanel Grid.Row="2" Margin="0,0,0,10">
      <TextBlock Text="Protocols:" FontWeight="Bold"/>
      <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
        <CheckBox Name="chkTcp" Content="TCP" IsChecked="True" Margin="0,0,15,0"/>
        <CheckBox Name="chkUdp" Content="UDP"/>
      </StackPanel>
    </StackPanel>

    <StackPanel Grid.Row="3" Margin="0,0,0,5">
      <TextBlock Text="Applications:" FontWeight="Bold"/>
      <CheckBox Name="chkApplyAll" Content="Apply to all apps" Margin="0,3,0,0"/>
    </StackPanel>

    <ListBox Name="lbAppNames" Grid.Row="4" Margin="0,0,0,5"/>

    <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,0,0,15">
      <Button Name="btnAddApp" Content="Add" Width="80" Margin="0,0,5,0"/>
      <Button Name="btnRemoveApp" Content="Remove" Width="80" Margin="0,0,5,0"/>
      <Button Name="btnPickProcess" Content="Pick Process" Width="100" Margin="0,0,5,0"/>
      <Button Name="btnBrowseApp" Content="Browse..." Width="100"/>
    </StackPanel>

    <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="btnDialogOk" Content="OK" Width="80" Margin="0,0,5,0" IsDefault="True"/>
      <Button Name="btnDialogCancel" Content="Cancel" Width="80" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@

$script:ProcessPickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Process Picker" Height="500" Width="450"
        WindowStartupLocation="CenterOwner">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="Select a process (double-click to choose):" Grid.Row="0" Margin="0,0,0,5"/>
    <ListView Name="lvProcesses" Grid.Row="1">
      <ListView.View>
        <GridView>
          <GridViewColumn Header="Name" Width="150" DisplayMemberBinding="{Binding Name}"/>
          <GridViewColumn Header="Path" Width="250" DisplayMemberBinding="{Binding Path}"/>
        </GridView>
      </ListView.View>
    </ListView>
    <Button Name="btnClosePicker" Content="Close" Grid.Row="2" Width="80"
            HorizontalAlignment="Right" Margin="0,10,0,0"/>
  </Grid>
</Window>
"@

$script:InputBoxXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="INPUT_TITLE" Height="160" Width="380"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="INPUT_MESSAGE" Grid.Row="0" Margin="0,0,0,5"
               TextWrapping="Wrap"/>
    <TextBox Name="txtInput" Grid.Row="1"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button Name="btnInputOk" Content="OK" Width="75" Margin="0,0,5,0" IsDefault="True"/>
      <Button Name="btnInputCancel" Content="Cancel" Width="75" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@
#endregion

#region Helper Functions
function Show-InputBox {
    [CmdletBinding()]
    param(
        [string]$Title = "Input",
        [string]$Message = "Enter value:",
        [string]$DefaultText = ""
    )
    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
    $xaml = $script:InputBoxXaml.Replace("INPUT_TITLE", $escapedTitle).Replace("INPUT_MESSAGE", $escapedMessage)
    [xml]$xml = $xaml
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)
    $txtInput = $win.FindName("txtInput")
    $btnOk = $win.FindName("btnInputOk")
    if ($DefaultText) { $txtInput.Text = $DefaultText }
    $btnOk.Add_Click({
        $win.Tag = $txtInput.Text
        $win.DialogResult = $true
        $win.Close()
    })
    if ($win.ShowDialog() -eq $true) { return $win.Tag }
    return $null
}

function Show-ProcessPicker {
    [CmdletBinding()]
    param()
    [xml]$xml = $script:ProcessPickerXaml
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)
    $lv = $win.FindName("lvProcesses")
    $btnClose = $win.FindName("btnClosePicker")

    try {
        $procs = Get-Process | Where-Object { $_.Path } |
            Select-Object Name, Path |
            Sort-Object Name -Unique
        foreach ($p in $procs) { [void]$lv.Items.Add($p) }
    } catch {
        [void][System.Windows.MessageBox]::Show("Failed to enumerate processes: $_", "Error", "OK", "Error")
        return $null
    }

    $lv.Add_MouseDoubleClick({
        param($sender, $e)
        $selected = $lv.SelectedItem
        if (-not $selected) { return }

        # Determine which column was double-clicked by hit-testing position against column widths
        $source = $e.OriginalSource
        $current = $source
        while ($current -and $current.GetType().Name -ne 'ListViewItem') {
            $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
        }

        $resultValue = $selected.Path
        if ($current) {
            $point = $e.GetPosition($current)
            $columns = $lv.View.Columns
            $cumulativeWidth = 0
            $clickedColumnIndex = 0
            for ($i = 0; $i -lt $columns.Count; $i++) {
                $cumulativeWidth += $columns[$i].ActualWidth
                if ($point.X -le $cumulativeWidth) {
                    $clickedColumnIndex = $i
                    break
                }
            }
            if ($clickedColumnIndex -eq 0) {
                $resultValue = $selected.Name -replace '\.exe$',''
            }
        }

        $win.Tag = $resultValue
        $win.DialogResult = $true
        $win.Close()
    })
    $btnClose.Add_Click({ $win.Close() })
    if ($win.ShowDialog() -eq $true) { return $win.Tag }
    return $null
}

function Test-Endpoint {
    [CmdletBinding()]
    param([string]$Endpoint)
    if ([string]::IsNullOrWhiteSpace($Endpoint)) { return $false }
    # host:port or [ipv6]:port
    if ($Endpoint -match '^([^\[\]:]+|\[[0-9a-fA-F:]+\]):(\d+)$') {
        $port = [int]$Matches[2]
        return ($port -ge 1 -and $port -le 65535)
    }
    return $false
}

function Test-Rule {
    [CmdletBinding()]
    param([ProxyConfig]$Rule)
    $errors = @()
    if (-not (Test-Endpoint $Rule.socks5ProxyEndpoint)) {
        $errors += "Invalid endpoint format. Expected host:port"
    }
    if ($Rule.appNames.Count -eq 0) {
        $errors += "appNames cannot be empty"
    }
    if ($Rule.supportedProtocols.Count -eq 0) {
        $errors += "Select at least one protocol"
    }
    return $errors
}

function Test-UniqueAppNames {
    [CmdletBinding()]
    param()
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($proxy in $script:Config.proxies) {
        foreach ($name in $proxy.appNames) {
            if ($seen.Contains($name)) {
                return "Duplicate app name detected: '$name'"
            }
            [void]$seen.Add($name)
        }
    }
    return $null
}

function Get-InitialDirectory {
    $scriptDir = Split-Path -Parent $PSCommandPath
    if (-not $scriptDir) { $scriptDir = $PWD.Path }
    $exePath = Join-Path $scriptDir "ProxiFyre.exe"
    if (Test-Path $exePath) { return $scriptDir }
    return $scriptDir
}

function Update-Status {
    param([string]$Message)
    $script:Controls.txtStatus.Text = $Message
}

function Update-ServiceStatus {
    try {
        $svc = Get-Service -Name "ProxiFyreService" -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            $script:Controls.txtServiceStatus.Text = "Service: ON"
            $script:Controls.txtServiceStatus.Foreground = [System.Windows.Media.Brushes]::Green
        } else {
            $script:Controls.txtServiceStatus.Text = "Service: OFF"
            $script:Controls.txtServiceStatus.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
    } catch {
        $script:Controls.txtServiceStatus.Text = "Service: NOT INSTALLED"
        $script:Controls.txtServiceStatus.Foreground = [System.Windows.Media.Brushes]::Gray
    }
}

function Sync-ModelFromUI {
    $sel = $script:Controls.cmbLogLevel.SelectedItem
    if ($sel) {
        $script:Config.logLevel = [LogLevel]::Parse([LogLevel], $sel)
    }
    $script:Config.bypassLan = [bool]$script:Controls.chkBypassLan.IsChecked
}

function Update-UI {
    $script:Controls.cmbLogLevel.SelectedItem = $script:Config.logLevel.ToString()
    $script:Controls.chkBypassLan.IsChecked = $script:Config.bypassLan
    $script:Controls.txtFilePath.Text = $script:CurrentPath
    $script:Controls.lvProxies.ItemsSource = $script:Config.proxies
    $script:Controls.lbExcludes.ItemsSource = $script:Config.excludes
}

function Update-JsonPreview {
    try {
        Sync-ModelFromUI
        $json = ConvertTo-AppConfigJson -Config $script:Config
        $script:Controls.txtJsonPreview.Text = $json
    } catch {
        $script:Controls.txtJsonPreview.Text = "Error generating preview: $_"
    }
}

function Get-ProxiFyreExePath {
    if ($script:ProxiFyrePath -and (Test-Path $script:ProxiFyrePath)) {
        return $script:ProxiFyrePath
    }
    $scriptDir = Split-Path -Parent $PSCommandPath
    if (-not $scriptDir) { $scriptDir = $PWD.Path }
    $exe = Join-Path $scriptDir "ProxiFyre.exe"
    if (Test-Path $exe) {
        $script:ProxiFyrePath = $exe
        return $exe
    }
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "Executable files (*.exe)|*.exe"
    $fd.Title = "Select ProxiFyre.exe"
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ProxiFyrePath = $fd.FileName
        return $fd.FileName
    }
    return $null
}

function Invoke-ProxiFyre {
    param([string]$Argument)
    $path = Get-ProxiFyreExePath
    if (-not $path) { return }
    $proc = Start-Process -FilePath $path -ArgumentList $Argument -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Update-Status "ProxiFyre $Argument completed"
    } else {
        Update-Status "ProxiFyre $Argument exited with code $($proc.ExitCode)"
        if ($proc.ExitCode -ne 2) {
            [void][System.Windows.MessageBox]::Show("ProxiFyre $Argument exited with code $($proc.ExitCode).", "Warning", "OK", "Warning")
        }
    }
    Update-ServiceStatus
}

function Invoke-ScService {
    param([string]$Action)
    $proc = Start-Process -FilePath "sc.exe" -ArgumentList $Action,"ProxiFyreService" -Wait -PassThru -NoNewWindow
    switch ($proc.ExitCode) {
        0       { Update-Status "Service $Action completed" }
        1056    { Update-Status "Service is already running"; [void][System.Windows.MessageBox]::Show("Service is already running.", "Info", "OK", "Information") }
        1062    { Update-Status "Service is already stopped"; [void][System.Windows.MessageBox]::Show("Service is already stopped.", "Info", "OK", "Information") }
        default { Update-Status "Service $Action failed with code $($proc.ExitCode)"; [void][System.Windows.MessageBox]::Show("Service $Action failed with code $($proc.ExitCode).", "Error", "OK", "Error") }
    }
    Update-ServiceStatus
}

function Install-ProxiFyreService  { Invoke-ProxiFyre -Argument 'install' }
function Uninstall-ProxiFyreService { Invoke-ProxiFyre -Argument 'uninstall' }
function Start-ProxiFyreService    { Invoke-ScService -Action 'start' }
function Stop-ProxiFyreService     { Invoke-ScService -Action 'stop' }
function Restart-ProxiFyreService {
    Invoke-ScService -Action 'stop'
    # Wait for the service to actually stop before starting again
    $timeout = 30
    for ($i = 0; $i -lt $timeout; $i++) {
        try {
            $svc = Get-Service -Name "ProxiFyreService" -ErrorAction Stop
            if ($svc.Status -eq 'Stopped') { break }
        } catch { break }
        Start-Sleep -Seconds 1
    }
    Invoke-ScService -Action 'start'
}
#endregion

#region JSON Serialization (Version-Aware)
function ConvertFrom-AppConfigJson {
    [CmdletBinding()]
    param([string]$Json)

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $options = [System.Text.Json.JsonSerializerOptions]::new()
        $options.PropertyNameCaseInsensitive = $true
        $options.Converters.Add([System.Text.Json.Serialization.JsonStringEnumConverter]::new())
        return [System.Text.Json.JsonSerializer]::Deserialize($Json, [AppConfig], $options)
    }
    else {
        # PowerShell 5.1 fallback
        try {
            $obj = $Json | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Invalid JSON: $_"
        }

        $config = [AppConfig]::new()

        if ($obj.logLevel) {
            $ll = [LogLevel]::Error
            if ([Enum]::TryParse([LogLevel], $obj.logLevel, $true, [ref]$ll)) {
                $config.logLevel = $ll
            }
        }
        if ($obj.bypassLan -ne $null) {
            $config.bypassLan = [bool]$obj.bypassLan
        }

        if ($obj.proxies) {
            foreach ($p in $obj.proxies) {
                $proxy = [ProxyConfig]::new()
                $proxy.socks5ProxyEndpoint = $p.socks5ProxyEndpoint
                if ($p.appNames) {
                    foreach ($an in $p.appNames) { $proxy.appNames.Add($an) }
                }
                if ($p.supportedProtocols) {
                    foreach ($sp in $p.supportedProtocols) {
                        $proto = [Protocol]::TCP
                        if ([Enum]::TryParse([Protocol], $sp, $true, [ref]$proto)) {
                            $proxy.supportedProtocols.Add($proto)
                        }
                    }
                }
                if ($p.username) { $proxy.username = $p.username }
                if ($p.password) { $proxy.password = $p.password }
                $config.proxies.Add($proxy)
            }
        }

        if ($obj.excludes) {
            foreach ($ex in $obj.excludes) { $config.excludes.Add($ex) }
        }

        return $config
    }
}

function ConvertTo-AppConfigJson {
    [CmdletBinding()]
    param([AppConfig]$Config)

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Normalize nulls for empty collections/auth fields (use reflection because PS $null becomes '' for C# string properties)
        $propUsername = [ProxyConfig].GetProperty('username')
        $propPassword = [ProxyConfig].GetProperty('password')
        $propAppNames = [ProxyConfig].GetProperty('appNames')
        $propProtocols = [ProxyConfig].GetProperty('supportedProtocols')
        $propExcludes = [AppConfig].GetProperty('excludes')

        $originals = @()
        foreach ($proxy in $Config.proxies) {
            $originals += @{
                appNames = $proxy.appNames
                protocols = $proxy.supportedProtocols
                username = $proxy.username
                password = $proxy.password
            }
            if ($proxy.appNames.Count -eq 0) { $propAppNames.SetValue($proxy, $null) }
            if ($proxy.supportedProtocols.Count -eq 0) { $propProtocols.SetValue($proxy, $null) }
            if ([string]::IsNullOrWhiteSpace($proxy.username)) { $propUsername.SetValue($proxy, $null) }
            if ([string]::IsNullOrWhiteSpace($proxy.password)) { $propPassword.SetValue($proxy, $null) }
        }
        $origExcludes = $Config.excludes
        if ($Config.excludes.Count -eq 0) { $propExcludes.SetValue($Config, $null) }

        $options = [System.Text.Json.JsonSerializerOptions]::new()
        $options.WriteIndented = $true
        $options.PropertyNamingPolicy = [System.Text.Json.JsonNamingPolicy]::CamelCase
        $options.IgnoreReadOnlyProperties = $true
        $options.Converters.Add([System.Text.Json.Serialization.JsonStringEnumConverter]::new(
            [System.Text.Json.JsonNamingPolicy]::CamelCase))
        $options.DefaultIgnoreCondition = [System.Text.Json.Serialization.JsonIgnoreCondition]::WhenWritingNull
        $json = [System.Text.Json.JsonSerializer]::Serialize($Config, $options)

        for ($i = 0; $i -lt $Config.proxies.Count; $i++) {
            $propAppNames.SetValue($Config.proxies[$i], $originals[$i].appNames)
            $propProtocols.SetValue($Config.proxies[$i], $originals[$i].protocols)
            $propUsername.SetValue($Config.proxies[$i], $originals[$i].username)
            $propPassword.SetValue($Config.proxies[$i], $originals[$i].password)
        }
        $propExcludes.SetValue($Config, $origExcludes)
        return $json
    }
    else {
        # PowerShell 5.1 fallback — build hashtable with camelCase keys
        $proxies = @()
        foreach ($proxy in $Config.proxies) {
            $p = @{
                socks5ProxyEndpoint = $proxy.socks5ProxyEndpoint
            }
            if ($proxy.appNames.Count -gt 0) {
                $p['appNames'] = @($proxy.appNames)
            }
            if ($proxy.supportedProtocols.Count -gt 0) {
                $p['supportedProtocols'] = @($proxy.supportedProtocols | ForEach-Object { $_.ToString() })
            }
            if (-not [string]::IsNullOrWhiteSpace($proxy.username)) {
                $p['username'] = $proxy.username
            }
            if (-not [string]::IsNullOrWhiteSpace($proxy.password)) {
                $p['password'] = $proxy.password
            }
            $proxies += $p
        }

        $obj = @{
            logLevel = $Config.logLevel.ToString().ToLower()
            bypassLan = $Config.bypassLan
            proxies = $proxies
        }
        if ($Config.excludes.Count -gt 0) {
            $obj['excludes'] = @($Config.excludes)
        }
        return ($obj | ConvertTo-Json -Depth 10)
    }
}

function Load-Config {
    [CmdletBinding()]
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) {
            throw "File not found: $Path"
        }
        $json = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $script:Config = ConvertFrom-AppConfigJson -Json $json
        $script:CurrentPath = $Path
        Update-UI
        Update-JsonPreview
        Update-Status "Loaded: $Path"
    } catch {
        [void][System.Windows.MessageBox]::Show("Failed to load config:`n$_", "Load Error", "OK", "Error")
    }
}

function Save-Config {
    [CmdletBinding()]
    param([string]$Path)
    try {
        Sync-ModelFromUI
        $json = ConvertTo-AppConfigJson -Config $script:Config

        # Backup existing file
        if (Test-Path $Path) {
            $backup = "$Path.bak"
            Copy-Item -Path $Path -Destination $backup -Force -ErrorAction SilentlyContinue
        }

        $json | Set-Content -Path $Path -Encoding UTF8 -NoNewline -ErrorAction Stop
        $script:CurrentPath = $Path
        Update-UI
        Update-Status "Saved: $Path"
        Update-JsonPreview
    } catch {
        [void][System.Windows.MessageBox]::Show("Failed to save config:`n$_", "Save Error", "OK", "Error")
    }
}
#endregion

#region Dialog Functions
function Show-ProxyDialog {
    [CmdletBinding()]
    param([ProxyConfig]$Proxy = $null)

    [xml]$xml = $script:EditProxyDialogXaml
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader)

    $txtEndpoint    = $dlg.FindName("txtEndpoint")
    $txtUsername    = $dlg.FindName("txtUsername")
    $txtPassword    = $dlg.FindName("txtPassword")
    $chkTcp         = $dlg.FindName("chkTcp")
    $chkUdp         = $dlg.FindName("chkUdp")
    $lbAppNames     = $dlg.FindName("lbAppNames")
    $chkApplyAll    = $dlg.FindName("chkApplyAll")
    $btnAddApp      = $dlg.FindName("btnAddApp")
    $btnRemoveApp   = $dlg.FindName("btnRemoveApp")
    $btnPickProcess = $dlg.FindName("btnPickProcess")
    $btnBrowseApp   = $dlg.FindName("btnBrowseApp")
    $btnOk          = $dlg.FindName("btnDialogOk")

    if ($Proxy) {
        $txtEndpoint.Text = $Proxy.socks5ProxyEndpoint
        $txtUsername.Text = $Proxy.username
        if ($Proxy.password) { $txtPassword.Password = $Proxy.password }
        $chkTcp.IsChecked = $Proxy.supportedProtocols -contains [Protocol]::TCP
        $chkUdp.IsChecked = $Proxy.supportedProtocols -contains [Protocol]::UDP
        foreach ($app in $Proxy.appNames) {
            [void]$lbAppNames.Items.Add($app)
        }
        if ($Proxy.appNames.Count -eq 1 -and $Proxy.appNames[0] -eq "") {
            $chkApplyAll.IsChecked = $true
            $lbAppNames.IsEnabled = $false
            $btnAddApp.IsEnabled = $false
            $btnRemoveApp.IsEnabled = $false
            $btnPickProcess.IsEnabled = $false
            $btnBrowseApp.IsEnabled = $false
        }
    }

    $refreshAppListState = {
        if ($chkApplyAll.IsChecked) {
            $lbAppNames.IsEnabled = $false
            $btnAddApp.IsEnabled = $false
            $btnRemoveApp.IsEnabled = $false
            $btnPickProcess.IsEnabled = $false
            $btnBrowseApp.IsEnabled = $false
            $lbAppNames.Items.Clear()
        } else {
            $lbAppNames.IsEnabled = $true
            $btnAddApp.IsEnabled = $true
            $btnRemoveApp.IsEnabled = $true
            $btnPickProcess.IsEnabled = $true
            $btnBrowseApp.IsEnabled = $true
        }
    }
    $chkApplyAll.Add_Checked($refreshAppListState)
    $chkApplyAll.Add_Unchecked($refreshAppListState)

    $btnAddApp.Add_Click({
        $input = Show-InputBox -Title "Add Application" -Message "Enter application name (with or without .exe):"
        if ($input) {
            $clean = $input.Trim() -replace '\.exe$',''
            if ($clean) {
                [void]$lbAppNames.Items.Add($clean)
            }
        }
    })

    $btnRemoveApp.Add_Click({
        if ($lbAppNames.SelectedItem -ne $null) {
            [void]$lbAppNames.Items.Remove($lbAppNames.SelectedItem)
        }
    })

    $btnPickProcess.Add_Click({
        $result = Show-ProcessPicker
        if ($result) {
            [void]$lbAppNames.Items.Add($result)
        }
    })

    $btnBrowseApp.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog
        $fd.Filter = "Executable files (*.exe)|*.exe|All files (*.*)|*.*"
        $fd.InitialDirectory = [Environment]::GetFolderPath('ProgramFiles')
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            [void]$lbAppNames.Items.Add($fd.FileName)
        }
    })

    $btnOk.Add_Click({
        $endpoint = $txtEndpoint.Text.Trim()
        if (-not (Test-Endpoint $endpoint)) {
            [void][System.Windows.MessageBox]::Show("Invalid endpoint format. Expected host:port", "Validation", "OK", "Warning")
            return
        }

        $appNames = @()
        if ($chkApplyAll.IsChecked) {
            $appNames += ""
        } else {
            if ($lbAppNames.Items.Count -eq 0) {
                [void][System.Windows.MessageBox]::Show("Add at least one application or enable 'Apply to all apps'.", "Validation", "OK", "Warning")
                return
            }
            foreach ($item in $lbAppNames.Items) { $appNames += $item }
        }

        $protocols = @()
        if ($chkTcp.IsChecked) { $protocols += [Protocol]::TCP }
        if ($chkUdp.IsChecked) { $protocols += [Protocol]::UDP }
        if ($protocols.Count -eq 0) {
            [void][System.Windows.MessageBox]::Show("Select at least one protocol.", "Validation", "OK", "Warning")
            return
        }

        $result = [ProxyConfig]::new()
        $result.socks5ProxyEndpoint = $endpoint

        $u = $txtUsername.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($u)) { $result.username = $u }

        $pw = $txtPassword.SecurePassword
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw)
        $plainPw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        if (-not [string]::IsNullOrWhiteSpace($plainPw)) { $result.password = $plainPw }

        foreach ($an in $appNames) { $result.appNames.Add($an) }
        foreach ($p in $protocols) { $result.supportedProtocols.Add($p) }

        $dlg.Tag = $result
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    if ($dlg.ShowDialog() -eq $true) {
        return $dlg.Tag
    }
    return $null
}
#endregion

#region Main Window Initialization
function Initialize-MainWindow {
    [xml]$xml = $script:MainWindowXaml
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $script:Window = [System.Windows.Markup.XamlReader]::Load($reader)

    $script:Controls = @{}
    $xml.SelectNodes("//*[@Name]") | ForEach-Object {
        $script:Controls[$_.Name] = $script:Window.FindName($_.Name)
    }

    # Populate LogLevel combo
    [Enum]::GetValues([LogLevel]) | ForEach-Object {
        [void]$script:Controls.cmbLogLevel.Items.Add($_.ToString())
    }

    # Bind data
    $script:Controls.lvProxies.ItemsSource = $script:Config.proxies
    $script:Controls.lbExcludes.ItemsSource = $script:Config.excludes
    Update-ServiceStatus

    # Menu handlers
    $script:Controls.menuNew.Add_Click({
        $script:Config = [AppConfig]::new()
        $script:CurrentPath = $null
        Update-UI
        Update-JsonPreview
        Update-Status "New config created"
    })

    $script:Controls.menuOpen.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog
        $fd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $fd.InitialDirectory = Get-InitialDirectory
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Load-Config -Path $fd.FileName
        }
    })

    $script:Controls.menuSave.Add_Click({
        if ($script:CurrentPath) {
            Save-Config -Path $script:CurrentPath
        } else {
            $script:Controls.menuSaveAs.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
        }
    })

    $script:Controls.menuSaveAs.Add_Click({
        $fd = New-Object System.Windows.Forms.SaveFileDialog
        $fd.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
        $fd.InitialDirectory = Get-InitialDirectory
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Save-Config -Path $fd.FileName
        }
    })

    $script:Controls.menuExit.Add_Click({ $script:Window.Close() })

    $script:Controls.menuValidate.Add_Click({
        $errors = @()
        $dup = Test-UniqueAppNames
        if ($dup) { $errors += $dup }
        foreach ($proxy in $script:Config.proxies) {
            $e = Test-Rule $proxy
            if ($e) { $errors += $e }
        }
        if ($errors.Count -eq 0) {
            [void][System.Windows.MessageBox]::Show("Configuration is valid!", "Validation", "OK", "Information")
        } else {
            [void][System.Windows.MessageBox]::Show(($errors -join "`n"), "Validation Errors", "OK", "Warning")
        }
    })

    $script:Controls.menuCopyJson.Add_Click({
        Sync-ModelFromUI
        try {
            $json = ConvertTo-AppConfigJson -Config $script:Config
            [System.Windows.Clipboard]::SetText($json)
            Update-Status "JSON copied to clipboard"
        } catch {
            [void][System.Windows.MessageBox]::Show("Failed to copy JSON: $_", "Error", "OK", "Error")
        }
    })

    $script:Controls.menuProcessPicker.Add_Click({
        $result = Show-ProcessPicker
        if ($result) {
            $selected = $script:Controls.lvProxies.SelectedItem
            if ($selected) {
                $selected.appNames.Add($result)
                $script:Controls.lvProxies.Items.Refresh()
                Update-JsonPreview
            } else {
                [void][System.Windows.MessageBox]::Show("Select a proxy rule first to add the process to.", "Info", "OK", "Information")
            }
        }
    })

    # Service menu
    $script:Controls.menuSvcInstall.Add_Click({ Install-ProxiFyreService })
    $script:Controls.menuSvcUninstall.Add_Click({ Uninstall-ProxiFyreService })
    $script:Controls.menuSvcStart.Add_Click({ Start-ProxiFyreService })
    $script:Controls.menuSvcStop.Add_Click({ Stop-ProxiFyreService })
    $script:Controls.menuSvcRestart.Add_Click({ Restart-ProxiFyreService })

    # Proxy buttons
    $script:Controls.btnAddProxy.Add_Click({
        $result = Show-ProxyDialog
        if ($result) {
            $script:Config.proxies.Add($result)
            Update-JsonPreview
        }
    })

    $script:Controls.btnEditProxy.Add_Click({
        $selected = $script:Controls.lvProxies.SelectedItem
        if (-not $selected) { return }
        $index = $script:Config.proxies.IndexOf($selected)
        $result = Show-ProxyDialog -Proxy $selected
        if ($result) {
            $script:Config.proxies[$index] = $result
            Update-JsonPreview
        }
    })

    $script:Controls.btnRemoveProxy.Add_Click({
        $selected = $script:Controls.lvProxies.SelectedItem
        if ($selected) {
            [void]$script:Config.proxies.Remove($selected)
            Update-JsonPreview
        }
    })

    $script:Controls.btnCloneProxy.Add_Click({
        $selected = $script:Controls.lvProxies.SelectedItem
        if (-not $selected) { return }
        $clone = [ProxyConfig]::new()
        $clone.socks5ProxyEndpoint = $selected.socks5ProxyEndpoint
        $clone.username = $selected.username
        $clone.password = $selected.password
        foreach ($an in $selected.appNames) { $clone.appNames.Add($an) }
        foreach ($p in $selected.supportedProtocols) { $clone.supportedProtocols.Add($p) }
        $script:Config.proxies.Add($clone)
        Update-JsonPreview
    })

    # Exclusion buttons
    $script:Controls.btnAddExclude.Add_Click({
        $input = Show-InputBox -Title "Add Exclusion" -Message "Enter application name or path (with or without .exe):"
        if ($input) {
            $clean = $input.Trim()
            $script:Config.excludes.Add($clean)
            Update-JsonPreview
        }
    })

    $script:Controls.btnRemoveExclude.Add_Click({
        $selected = $script:Controls.lbExcludes.SelectedItem
        if ($selected -ne $null) {
            [void]$script:Config.excludes.Remove($selected)
            Update-JsonPreview
        }
    })

    $script:Controls.btnBrowseExclude.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog
        $fd.Filter = "Executable files (*.exe)|*.exe|All files (*.*)|*.*"
        $fd.InitialDirectory = Get-InitialDirectory
        if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            # Store without .exe extension to match ProxiFyre convention
            $name = [System.IO.Path]::GetFileNameWithoutExtension($fd.FileName)
            $script:Config.excludes.Add($name)
            Update-JsonPreview
        }
    })

    $script:Controls.btnPickExclude.Add_Click({
        $result = Show-ProcessPicker
        if ($result) {
            $script:Config.excludes.Add($result)
            Update-JsonPreview
        }
    })

    # Global settings change handlers
    $script:Controls.cmbLogLevel.Add_SelectionChanged({ Update-JsonPreview })
    $script:Controls.chkBypassLan.Add_Checked({ Update-JsonPreview })
    $script:Controls.chkBypassLan.Add_Unchecked({ Update-JsonPreview })
}
#endregion

#region Entry Point
$script:Config = [AppConfig]::new()
$script:CurrentPath = $null

Initialize-MainWindow
Update-UI
Update-JsonPreview

# Auto-detect ProxiFyre folder
$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $scriptDir) { $scriptDir = $PWD.Path }
$autoConfig = Join-Path $scriptDir "app-config.json"
if (Test-Path $autoConfig) {
    Load-Config -Path $autoConfig
}

[void]$script:Window.ShowDialog()
#endregion
