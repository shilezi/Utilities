exit
# PSScriptAnalyzer
Install-PackageProvider -Name NuGet -Force
Install-Module -Name PSScriptAnalyzer -Force
Save-Module -Name PSScriptAnalyzer -Path D:\
Invoke-ScriptAnalyzer -Path "D:\Программы\Прочее\ps1\Win 10.ps1"

# Перерегистрация всех UWP-приложений
(Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications | Get-ItemProperty).Path | Add-AppxPackage -Register -DisableDevelopmentMode

# Установка Microsoft Store из appxbundle
SW_DVD9_NTRL_Win_10_1903_32_64_ARM64_MultiLang_App_Update_X22-01657.ISO
https://store.rg-adguard.net
CategoryID: 64293252-5926-453c-9494-2d4021f1c78d
New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx -Name AllowAllTrustedApps -Value 1 -Force
Add-AppxProvisionedPackage -Online -PackagePath D:\Store.appxbundle -LicensePath D:\Store.xml
New-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx -Name AllowAllTrustedApps -Value 0 -Force

# Разрешить подключаться одноуровневому домену
New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters -Name AllowSingleLabelDnsDomain -Value 1 -Force

# Стать владельцем ключа в Реестре
$ParentACL = Get-Acl -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt"
$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice","ReadWriteSubTree","TakeOwnership")
$acl = $k.GetAccessControl()
$null = $acl.SetAccessRuleProtection($false,$true)
$rule = New-Object System.Security.AccessControl.RegistryAccessRule ($ParentACL.Owner,"FullControl","Allow")
$null = $acl.SetAccessRule($rule)
$rule = New-Object System.Security.AccessControl.RegistryAccessRule ($ParentACL.Owner,"SetValue","Deny")
$null = $acl.RemoveAccessRule($rule)
$null = $k.SetAccessControl($acl)

# Стать владельцем ключа в Реестре
function ElevatePrivileges
{
	param($Privilege)
	$Definition = @"
	using System;
	using System.Runtime.InteropServices;
	public class AdjPriv
	{
		[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
		internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr rele);
		[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
		internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
		[DllImport("advapi32.dll", SetLastError = true)]
		internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
		[StructLayout(LayoutKind.Sequential, Pack = 1)]
		internal struct TokPriv1Luid
		{
			public int Count;
			public long Luid;
			public int Attr;
		}
		internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
		internal const int TOKEN_QUERY = 0x00000008;
		internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
		public static bool EnablePrivilege(long processHandle, string privilege)
		{
			bool retVal;
			TokPriv1Luid tp;
			IntPtr hproc = new IntPtr(processHandle);
			IntPtr htok = IntPtr.Zero;
			retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
			tp.Count = 1;
			tp.Luid = 0;
			tp.Attr = SE_PRIVILEGE_ENABLED;
			retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
			retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
			return retVal;
		}
	}
"@
	$ProcessHandle = (Get-Process -id $pid).Handle
	$type = Add-Type $definition -PassThru
	$type[0]::EnablePrivilege($processHandle, $Privilege)
}

function TakeownRegistry($key)
{
	switch ($key.split("\")[0])
	{
		"HKEY_CLASSES_ROOT"
		{
			$reg = [Microsoft.Win32.Registry]::ClassesRoot
			$key = $key.substring(18)
		}
		"HKEY_CURRENT_USER"
		{
			$reg = [Microsoft.Win32.Registry]::CurrentUser
			$key = $key.substring(18)
		}
		"HKEY_LOCAL_MACHINE"
		{
			$reg = [Microsoft.Win32.Registry]::LocalMachine
			$key = $key.substring(19)
		}
	}
	$admins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
	$admins = $admins.Translate([System.Security.Principal.NTAccount])
	$key = $reg.OpenSubKey($key, "ReadWriteSubTree", "TakeOwnership")
	$acl = $key.GetAccessControl()
	$acl.SetOwner($admins)
	$key.SetAccessControl($acl)
	$acl = $key.GetAccessControl()
	$rule = New-Object System.Security.AccessControl.RegistryAccessRule($admins, "FullControl", "Allow")
	$acl.SetAccessRule($rule)
	$key.SetAccessControl($acl)
}

do {} until (ElevatePrivileges SeTakeOwnershipPrivilege)
TakeownRegistry ("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WinDefend")

# Включение в Планировщике задач удаление устаревших обновлений Office, кроме Office 2019
$action = New-ScheduledTaskAction -Execute powershell.exe -Argument @"
	`$getservice = Get-Service -Name wuauserv
	`$getservice.WaitForStatus("Stopped", '01:00:00')
	Start-Process -FilePath D:\Программы\Прочее\Office_task.bat
"@
$trigger = New-ScheduledTaskTrigger -Weekly -At 9am -DaysOfWeek Thursday -WeeksInterval 4
$settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserID System -RunLevel Highest
$params = @{
	"TaskName"	= "Office"
	"Action"	= $action
	"Trigger"	= $trigger
	"Settings"	= $settings
	"Principal"	= $principal
}
Register-ScheduledTask @Params -Force

# Создать в Планировщике задач задачу со всплывающим окошком с сообщением о перезагрузке
$action = New-ScheduledTaskAction -Execute powershell.exe -Argument @"
	-WindowStyle Hidden `
	Add-Type -AssemblyName System.Windows.Forms
	`$global:balmsg = New-Object System.Windows.Forms.NotifyIcon
	`$path = (Get-Process -Id `$pid).Path
	`$balmsg.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(`$path)
	`$balmsg.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
	`$balmsg.BalloonTipText = 'Перезагрузка через 1 мин.'
	`$balmsg.BalloonTipTitle = 'Внимание'
	`$balmsg.Visible = `$true
	`$balmsg.ShowBalloonTip(60000)
	Start-Sleep -s 60
"@
$trigger = New-ScheduledTaskTrigger -Weekly -At 10am -DaysOfWeek Thursday -WeeksInterval 4
$settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserID $env:USERNAME -RunLevel Highest
$params = @{
	"TaskName"	= "Reboot"
	"Action"	= $action
	"Trigger"	= $trigger
	"Settings"	= $settings
	"Principal"	= $principal
}
Register-ScheduledTask @Params -Force

# Найти диски, не подключенные через USB и не являющиеся загрузочными, исключая диски с пустыми буквами (исключаются внешние жесткие диски)
(Get-Disk | Where-Object -FilterScript {$_.BusType -ne "USB" -and $_.IsBoot -eq $false} | Get-Partition | Get-Volume | Where-Object -FilterScript {$null -ne $_.DriveLetter}).DriveLetter | ForEach-Object -Process {Join-Path ($_ + ":") $Path}
# Найти диски, не являющиеся загрузочными, исключая диски с пустыми буквами (не исключаются внешние жесткие диски)
(Get-Disk | Where-Object -FilterScript {$_.IsBoot -eq $false} | Get-Partition | Get-Volume | Where-Object -FilterScript {$null -ne $_.DriveLetter}).DriveLetter | ForEach-Object -Process {Join-Path ($_ + ":") $Path}
# Найти первый диск, подключенный через USB, исключая диски с пустыми буквами
(Get-Disk | Where-Object -FilterScript {$_.BusType -eq "USB"} | Get-Partition | Get-Volume | Where-Object -FilterScript {$null -ne $_.DriveLetter}).DriveLetter | ForEach-Object -Process {Join-Path ($_ + ":") $Path} | Select-Object -First 1

# Добавление доменов в hosts
$hostfile = "$env:SystemRoot\System32\drivers\etc\hosts"
$domains = @("site.com","site2.com")
foreach ($hostentry in $domains)
{
	IF (-not (Get-Content -Path $hostfile | Select-String "0.0.0.0 `t $hostentry"))
	{
		Add-Content -Path $hostfile -Value "0.0.0.0 `t $hostentry"
	}
}

# Отделить название от пути
Split-Path -Path file.ext -Leaf
# Отделить путь от названия
Split-Path -Path file.ext -Parent
# Отделить от пути название последней папки
Get-Item -Path file.ext | Split-Path -Parent | Split-Path -Parent | Split-Path -Leaf

# Проверить тип запуска службы
IF ((Get-Service -ServiceName wuauserv).StartType -eq "Disabled")
{
	Start-Service -ServiceName wuauserv -Force
	Set-Service -ServiceName wuauserv -StartupType Automatic
}

# Получить события из журналов событий и файлов журналов отслеживания событий
<#
	LogAlways 0
	Critical 1
	Error 2
	Warning 3
	Informational 4
	Verbose 5
#>
Get-WinEvent -LogName Security | Where-Object -FilterScript {$_.ID -eq 5157}
Get-WinEvent -LogName System | Where-Object -FilterScript {$_.ID -like "1001" -and $_.Source -like "bugcheck"}
Get-WinEvent -LogName System | Where-Object -FilterScript {$_.LevelDisplayName -match "Критическая" -or $_.LevelDisplayName -match "Ошибка"}
Get-WinEvent -FilterHashtable @{LogName = "System"; level = "1"}
Get-WinEvent -FilterHashtable @{LogName = "System"} | Where-Object -FilterScript {$_.Level -eq 2 -or $_.Level -eq 3}
Get-WinEvent -LogName Application | Where-Object -FilterScript {$_.ProviderName -match "Windows Error*"}

# Настройка и проверка исключений Защитника Windows
Add-MpPreference -ExclusionProcess D:\folder\file.ext
Add-MpPreference -ExclusionPath D:\folder
Add-MpPreference -ExclusionExtension .ext

# Скачать файл
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$HT = @{
	Uri = "https://site.com/1.js"
	OutFile = "D:\1.js"
	UseBasicParsing = [switch]::Present
	Verbose = [switch]::Present
}
Invoke-WebRequest @HT

# Передача больших файлов по медленным и нестабильным сетям
Import-Module BitsTransfer # Нагружает диск
Start-BitsTransfer -Source $url -Destination $output
# Start-BitsTransfer -Source $url -Destination $output -Asynchronous

# Скачать и отобразить текстовый файл
(Invoke-WebRequest -Uri "https://site.com/1.js" -OutFile D:\1.js -PassThru).Content

# Прочитать содержимое текстового файла
(Invoke-WebRequest -Uri "https://site.com/1.js").Content

# Подсчет времени
$start_time = Get-Date
Write-Output "Time taken: $((Get-Date).Subtract($start_time).Milliseconds) second(s)"

# Разархивировать архив
$HT = @{
	Path = "D:\1.zip"
	DestinationPath = "D:\1"
	Force = [switch]::Present
	Verbose = [switch]::Present
}
Expand-Archive @HT

# Конвертировать в кодировку UTF8 с BOM
(Get-Content -Path "D:\1.ps1" -Encoding UTF8) | Set-Content -Encoding UTF8 -Path "D:\1.ps1"

# Вычленить букву диска
Split-Path -Path "D:\file.mp3" -Qualifier

# Получение контрольной суммы файла (MD2, MD4, MD5, SHA1, SHA256, SHA384, SHA512)
certutil -hashfile C:\file.txt SHA1
# Преобразование кодов ошибок в текстовое сообщение
certutil -error 0xc0000409

# Вычислить значение хеш-суммы строки
Function Get-StringHash
{
	param
	(
		[Parameter(Mandatory = $true)]
		[string]$String,

		[Parameter(Mandatory = $true)]
		[ValidateSet("MACTripleDES", "MD5", "RIPEMD160", "SHA1", "SHA256", "SHA384", "SHA512")]
		[String] $HashName
	)
	$StringBuilder = New-Object System.Text.StringBuilder
	[System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))| ForEach-Object -Process {
		[Void]$StringBuilder.Append($_.ToString("x2"))
	}
	$StringBuilder.ToString()
}
Get-StringHash 2 sha1

# Вычислить значение хеш-суммы файла
Get-FileHash D:\1.txt -Algorithm MD5

# Получить список установленных приложений
(Get-Itemproperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName

# Развернуть окно с заголовком "Диспетчер задач", а остальные окна свернуть
$Win32ShowWindowAsync = @{
	Namespace = "Win32Functions"
	Name = "Win32ShowWindowAsync"
	Language = "CSharp"
	MemberDefinition = @"
		[DllImport("user32.dll")]
		public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@
}
IF (-not ("Win32Functions.Win32ShowWindowAsync" -as [type]))
{
	Add-Type @Win32ShowWindowAsync
}
$title = "Диспетчер задач"
Get-Process | Where-Object -FilterScript {$_.MainWindowHandle -ne 0} | ForEach-Object -Process {
	IF ($_.MainWindowTitle -eq $title)
	{
		[Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($_.MainWindowHandle, 3) | Out-Null
	}
	else
	{
		[Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($_.MainWindowHandle, 6) | Out-Null
	}
}

# Закрепить на начальном экране ярлык 1809
$Target = Get-Item -Path "D:\folder\file.lnk"
$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace($target.DirectoryName)
$file = $folder.ParseName($Target.Name)
$verb = $file.Verbs() | Where-Object -FilterScript {$_.Name -like "Закрепить на начальном &экране"}
$verb.DoIt()

# Закрепить на панели задач ярлык 1809
$Target = Get-Item -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\file.lnk"
$Value = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\Windows.taskbarpin").ExplorerCommandHandler
IF (-not (Test-Path -Path "HKCU:\Software\Classes\*\shell\pin"))
{
	New-Item -Path "HKCU:\Software\Classes\*\shell\pin" -Force
}
New-ItemProperty -LiteralPath "HKCU:\Software\Classes\*\shell\pin" -Name ExplorerCommandHandler -Type String -Value $Value -Force
$Shell = New-Object -ComObject Shell.Application
$Folder = $Shell.NameSpace($Target.DirectoryName)
$Item = $Folder.ParseName($Target.Name)
$Item.InvokeVerb("pin")
Remove-Item -LiteralPath "HKCU:\Software\Classes\*\shell\pin" -Recurse

# Открепить от панели задач ярлык 1809
$Target = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\file.lnk"
$Value = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\Windows.taskbarpin").ExplorerCommandHandler
IF (-not (Test-Path -Path "HKCU:\Software\Classes\*\shell\pin"))
{
	New-Item -Path "HKCU:\Software\Classes\*\shell\pin" -Force
}
New-ItemProperty -LiteralPath "HKCU:\Software\Classes\*\shell\pin" -Name ExplorerCommandHandler -Type String -Value $Value -Force
$Shell = New-Object -ComObject "Shell.Application"
$Folder = $Shell.Namespace((Get-Item -Path $Target).DirectoryName)
$Item = $Folder.ParseName((Get-Item -Path $Target).Name)
$Item.InvokeVerb("pin")
Remove-Item -LiteralPath "HKCU:\Software\Classes\*\shell\pin" -Recurse

# Установить состояние показа окна
function WindowState
{
	param(
		[Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0)]
		[ValidateScript({$_ -ne 0})]
		[System.IntPtr] $MainWindowHandle,
		[ValidateSet("FORCEMINIMIZE", "HIDE", "MAXIMIZE", "MINIMIZE", "RESTORE",
				"SHOW", "SHOWDEFAULT", "SHOWMAXIMIZED", "SHOWMINIMIZED",
				"SHOWMINNOACTIVE", "SHOWNA", "SHOWNOACTIVATE", "SHOWNORMAL")]
		[String] $State = "SHOW"
	)
	$WindowStates = @{
		"FORCEMINIMIZE"		=	11
		"HIDE"				=	0
		"MAXIMIZE"			=	3
		"MINIMIZE"			=	6
		"RESTORE"			=	9
		"SHOW"				=	5
		"SHOWDEFAULT"		=	10
		"SHOWMAXIMIZED"		=	3
		"SHOWMINIMIZED"		=	2
		"SHOWMINNOACTIVE"	=	7
		"SHOWNA"			=	8
		"SHOWNOACTIVATE"	=	4
		"SHOWNORMAL"		=	1
	}
	$Win32ShowWindowAsync = @{
	Namespace = "Win32Functions"
	Name = "Win32ShowWindowAsync"
	Language = "CSharp"
	MemberDefinition = @"
		[DllImport("user32.dll")]
		public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@
	}
	IF (-not ("Win32Functions.Win32ShowWindowAsync" -as [type]))
	{
		Add-Type @Win32ShowWindowAsync
	}
	[Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($MainWindowHandle , $WindowStates[$State])
}
$MainWindowHandle = (Get-Process -Name notepad | Where-Object -FilterScript {$_.MainWindowHandle -ne 0}).MainWindowHandle
$MainWindowHandle | WindowState -State HIDE

# Установить бронзовый курсор из Windows XP
# Функция для нахождения буквы диска, когда файл находится в известной папке, но не известна буква диска. Подходит, когда файл располагается на USB-носителе
$cursor = "Программы\Прочее\bronze.cur"
function Get-ResolvedPath
{
	param (
		[Parameter(ValueFromPipeline = 1)]
		$Path
	)
	(Get-Disk | Where-Object -FilterScript {$_.BusType -eq "USB"} | Get-Partition | Get-Volume | Where-Object -FilterScript {$null -ne $_.DriveLetter}).DriveLetter | ForEach-Object -Process {Join-Path ($_ + ":") $Path -Resolve -ErrorAction SilentlyContinue}
}
$cursor | Get-ResolvedPath | Copy-Item -Destination $env:SystemRoot\Cursors -Force
New-ItemProperty -Path "HKCU:\Control Panel\Cursors" -Name Arrow -Type ExpandString -Value "%SystemRoot%\cursors\bronze.cur" -Force
$Signature = @{
	Namespace = "SystemParamInfo"
	Name = "WinAPICall"
	Language = "CSharp"
	MemberDefinition = @"
		[DllImport("user32.dll", EntryPoint = "SystemParametersInfo")]
		public static extern bool SystemParametersInfo(
		uint uiAction,
		uint uiParam,
		uint pvParam,
		uint fWinIni);
"@
}
IF (-not ("SystemParamInfo.WinAPICall" -as [type]))
{
	Add-Type @Signature
}
[SystemParamInfo.WinAPICall]::SystemParametersInfo(0x0057,0,$null,0)

# Информация о ПК
Write-Output User
$PCName = @{
	Name = "Computer name"
	Expression = {$_.Name}
}
$Domain = @{
	Name = "Domain"
	Expression = {$_.Domain}
}
$UserName = @{
	Name = "User Name"
	Expression = {$_.UserName}
}
(Get-CimInstance –ClassName CIM_ComputerSystem | Select-Object -Property $PCName, $Domain, $UserName | Format-Table | Out-String).Trim()
Write-Output "`nOperating System"
$ProductName = @{
	Name = "Product Name"
	Expression = {$_.Caption}
}
$InstallDate = @{
	Name = "Install Date"
	Expression={$_.InstallDate.Tostring().Split("")[0]}
}
$Arch = @{
	Name = "Architecture"
	Expression = {$_.OSArchitecture}
}
$a = Get-CimInstance -ClassName CIM_OperatingSystem | Select-Object -Property $ProductName, $InstallDate, $Arch
$Build = @{
	Name = "Build"
	Expression = {"$($_.CurrentMajorVersionNumber).$($_.CurrentMinorVersionNumber).$($_.CurrentBuild).$($_.UBR)"}
}
$b = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows nt\CurrentVersion" | Select-Object -Property $Build
([PSCustomObject] @{
	"Product Name" = $a."Product Name"
	Build = $b.Build
	"Install Date" = $a."Install Date"
	Architecture = $a.Architecture
} | Out-String).Trim()
Write-Output "`nInstalled updates supplied by CBS"
$HotFixID = @{
	Name = "KB ID"
	Expression = {$_.HotFixID}
}
$InstalledOn = @{
	Name = "Installed on"
	Expression = {$_.InstalledOn.Tostring().Split("")[0]}
}
(Get-HotFix | Select-Object -Property $HotFixID, $InstalledOn -Unique | Format-Table | Out-String).Trim()
Write-Output "`nInstalled updates supplied by MSI/WU"
$Session = New-Object -ComObject "Microsoft.Update.Session"
$Searcher = $Session.CreateUpdateSearcher()
$historyCount = $Searcher.GetTotalHistoryCount()
$KB = @{
	Name = "KB ID"
	Expression = {[regex]::Match($_.Title,"(KB[0-9]{6,7})").Value}
}
$Date = @{
	Name = "Installed on"
	Expression = {$_.Date.Tostring().Split("")[0]}
}
($Searcher.QueryHistory(0, $historyCount) | Where-Object -FilterScript {$_.Title -like "*KB*"} | Select-Object $KB, $Date -Unique | Format-Table | Out-String).Trim()
Write-Output "`nBIOS"
$Version = @{
	Name = "Version"
	Expression = {$_.Name}
}
(Get-CimInstance -ClassName CIM_BIOSElement | Select-Object -Property Manufacturer, $Version | Format-Table | Out-String).Trim()
Write-Output "`nMotherboard"
(Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -Property Manufacturer, Product | Format-Table | Out-String).Trim()
Write-Output "`nCPU"
$Cores = @{
	Name = "Cores"
	Expression = {$_.NumberOfCores}
}
$L3CacheSize = @{
	Name = "L3, MB"
	Expression = {$_.L3CacheSize / 1024}
}
$Threads = @{
	Name = "Threads"
	Expression = {$_.NumberOfLogicalProcessors}
}
(Get-CimInstance -ClassName CIM_Processor | Select-Object -Property Name, $Cores, $L3CacheSize, $Threads | Format-Table | Out-String).Trim()
Write-Output "`nRAM"
$Speed = @{
	Name = "Speed, MHz"
	Expression = {$_.Configuredclockspeed}
}
$Capacity = @{
	Name = "Capacity, GB"
	Expression = {$_.Capacity / 1GB}
}
(Get-CimInstance -ClassName CIM_PhysicalMemory | Select-Object -Property Manufacturer, PartNumber, $Speed, $Capacity | Format-Table | Out-String).Trim()
Write-Output ""
Write-Output "Physical disks"
$Model = @{
	Name = "Model"
	Expression = {$_.FriendlyName}
}
$MediaType = @{
	Name = "Drive type"
	Expression = {$_.MediaType}
}
$Size = @{
	Name = "Size, GB"
	Expression = {[math]::round($_.Size / 1GB, 2)}
}
$BusType = @{
	Name = "Bus type"
	Expression = {$_.BusType}
}
(Get-PhysicalDisk | Select-Object -Property $Model, $MediaType, $BusType, $Size | Format-Table | Out-String).Trim()
Write-Output "`nLogical drives"
Enum DriveType
{
	RemovableDrive	=	2
	HardDrive		=	3
}
$Name = @{
	Name = "Name"
	Expression = {$_.DeviceID}
}
$Type = @{
	Name = "Drive Type"
	Expression = {[enum]::GetName([DriveType],$_.DriveType)}
}
$Path = @{
	Name = "Path"
	Expression = {$_.ProviderName}
}
$Size = @{
	Name = "Size, GB"
	Expression = {[math]::round($_.Size/1GB, 2)}
}
(Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object -FilterScript {$_.DriveType -ne 4} | Select-Object -Property $Name, $Type, $Path, $Size | Format-Table | Out-String).Trim()
Write-Output "`nMapped disks"
(Get-SmbMapping | Select-Object -Property LocalPath, RemotePath | Format-Table | Out-String).Trim()
Write-Output "`nVideo сontrollers"
$Caption = @{
	Name = "Model"
	Expression = {$_.Caption}
}
$VRAM = @{
	Name = "VRAM, GB"
	Expression = {[math]::round($_.AdapterRAM/1GB)}
}
(Get-CimInstance -ClassName CIM_VideoController | Select-Object -Property $Caption, $VRAM | Format-Table | Out-String).Trim()
Write-Output "`nDefault IP gateway"
(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration).DefaultIPGateway
Write-Output "`nVideo сontrollers"
# (Get-MpThreatDetection | Select-Object -Property Resources, ThreatID, InitialDetectionTime | Format-Table | Out-String).Trim()
Write-Output "`nVideo сontrollers"
# (Get-MpPreference | Select-Object -Property ExclusionPath, ThreatIDDefaultAction_Ids | Format-Table | Out-String).Trim()

# Стать владельцем файла
takeown /F D:\file.exe
icacls D:\file.exefile /grant:r %username%:F
# Стать владельцем папки
takeown /F C:\HV\10 /R
icacls C:\HV\10 /grant:r %username%:F /T

# Найти файл на всех локальных дисках и вывести его полный путь
$file = "file.ext"
(Get-ChildItem -Path ([System.IO.DriveInfo]::GetDrives() | Where-Object {$_.DriveType -ne "Network"}).Name -Recurse -ErrorAction SilentlyContinue | Where-Object -FilterScript {$_.Name -like "$file"}).FullName

# Создать ini-файл с кодировкой UCS-2 LE BOM
$rarregkey = @"
RAR registration data
Alexander Roshal
Unlimited Company License
UID=00f650198f81e6607ec5
64122122507ec5206fb48daec2aaa67b4afc9a80b6a2e60ac35c4d
78565fc0aaa9d24b459460fce6cb5ffde62890079861be57638717
7131ced835ed65cc743d9777f2ea71a8e32c7e593cf66794343565
b41bcf56929486b8bcdac33d50ecf77399602d355a7873c5e960f7
8c0c621c6c7c2040df0794978f4e20e362354119251b5ea1fecc9d
bfa426c154150408200be88b82c1234bc3d4ee6e979bfff660dfe8
821d4d458f9319f95f2533d09ce2d8b75beac25fb63a3215972308
"@
Set-Content -Path "$env:ProgramFiles\WinRAR\rarreg.key" -Value $rarregkey -Encoding Unicode -Force

# Удалить первые $c буквы в названиях файлов в папке
$path = "D:\folder"
$e = "flac"
$c = 4
(Get-ChildItem -Path $path -Filter *.$e) | Rename-Item -NewName {$_.Name.Substring($c)}

# Удалить последние $c буквы в названиях файлов в папке
$path = "D:\folder"
$e = "flac"
$c = 4
Get-ChildItem -Path $path -Filter *.$e | Rename-Item -NewName {$_.Name.Substring(0,$_.BaseName.Length-$c) + $_.Extension}

# Записать прописными буквами первую букву каждого слова в названии каждого файла в папке
$TextInfo = (Get-Culture).TextInfo
$path = "D:\folder"
$e = "flac"
Get-ChildItem -Path $path -Filter *.$e | Rename-Item -NewName {$TextInfo.ToTitleCase($_.BaseName) + $_.Extension}

# Найти файлы, в названии которых каждое слово не написано с заглавной буквы
(Get-ChildItem -Path $path -File -Recurse | Where-Object -FilterScript {($_.BaseName -replace "'|``") -cmatch "\b\p{Ll}\w*"}).FullName

# Добавить REG_NONE
New-ItemProperty -Path HKCU:\Software -Name Name -PropertyType None -Value ([byte[]]@()) -Force

# Выкачать видео с помощью youtube-dl
# https://github.com/ytdl-org/youtube-dl/releases
# https://ffmpeg.zeranoe.com/builds/
$urls= @(
	"https://",
	"https://"
)
$youtubedl = "D:\youtube-dl.exe"
# --list-formats url
# --format 43+35 url
# --username $username
# --password $password
# --video-password $videopassword
$output = "D:\"
$filename = "%(title)s.mp4"
foreach ($url in $urls)
{
	Start-Process -FilePath $youtubedl -ArgumentList "--output `"$output\$filename`" $url"
}