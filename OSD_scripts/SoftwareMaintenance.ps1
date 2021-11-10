# Скрипт выполняет обслуживание корпоративного программного обеспечения и его конфигуририрование при работе спец. заливки для удаленки за пределами КСПД.
# Запускается триггерами назначеннного задания SoftwareMaintenance как PowerShell.exe -Exec Bypass -NoProfile -File %Tools%\SoftwareMaintenance.ps1
# На данный момент реализовано автоматическое обновление через интернет клиента VMware Horizon


# Название приложения, по которому будет производится поиск в реестре и 
$App_Name = "VMware Horizon Client";  

# название компании-разработчика, по которому будут отбираться запущенные процессы
$App_Vendor = "VMware"

# Строка параметров для EXE-инсталлятора приложения. Исключить параметр /norestart нельзя, т.к. инсталлятор сразу отправит винду в перезагрузку и скрипт даже не успеет записать в лог об успешном завершении инсталляции.
$App_setup_params = "/silent /norestart VDM_SERVER=HV.nornik.ru LOGINASCURRENTUSER_DEFAULT=1 INSTALL_SFB=1 INSTALL_HTML5MMR=1"


# Лог файл
$logFile = "$($myInvocation.MyCommand -replace "\.ps1$").log"; if (!$logFile) { $logFile = "SoftwareMaintenance.log" }; $logFile = "$($Env:WinDir)\Temp\$logFile"
# Start-Transcript $logFile -Append

# Задаем ширину окна консоли, чтобы вывод в лог-файл не обрезался по ширине 80 символов.  http://stackoverflow.com/questions/978777/powershell-output-column-width
$rawUI = $Host.UI.RawUI;  $oldSize = $rawUI.BufferSize;  $typeName = $oldSize.GetType().FullName; $newSize = New-Object $typeName (256, 8192);
if ($rawUI.BufferSize.Width -lt 256) { $rawUI.BufferSize = $newSize }


$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name # https://www.optimizationcore.com/scripting/ways-get-current-logged-user-powershell/
$HostName = [System.Net.Dns]::GetHostName() # https://virot.eu/getting-the-computername-in-powershell/  https://adamtheautomator.com/powershell-get-computer-name/
"`n`n$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - Start of PoSh script for Software Maintenance as $UserName on $HostName with argument '$($Args[0])'." | Out-File $logFile -Append

function Finish-Script {
# Stop-Transcript
"$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - The End of PoSh script." | Out-File $logFile -Append
}

# Уже Неактуально без автологона. Задаем пользовательской учетке User пустой пароль
# Set-LocalUser -Name "User" -Password (new-object System.Security.SecureString)

# Автоматический логон от непривилегированной учетки User. Автологон задавать не потребуется, если в списке локальных учеток входа в винду останется видна одна единственная и без пароля. 
# Но если это сделано с помощью сокрытия админ-учетки через реестр  HKLM:\Soft\MS\WinNT\Winlogon\SpecialAccounts\UserList\ то тогда в графическом интерфейсе винды не получится запускать от имени админа по ПКМ 

# НЕ Задаем автоматический юзер-логон в винду через параметры реестра - задавать во время работы OSD TaskSeq их нельзя, т.к. TaskSeq Manager их сам использует
# несмотря на то, что учетка эта будет одинаковая для всех юзеров, от идеи автологна пришлось отказаться, т.к. иначе теряет смысл шифрование BitLocker
# cd "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\"; Set-Alias SIP Set-ItemProperty;  Remove-ItemProperty . "AutoLogonSID" -EA 0
# SIP . -N "AutoAdminLogon" -V "1";  SIP . -N "DefaultUserName" -V "User";  SIP . -N "DefaultDomainName" -V ".";  SIP . -N "DefaultPassword" -V ""; 

# Утилита SysInternals не умеет задавать автологон с пустым паролем. 
# & "$Env:Tools\SysInternals\AutoLogon64.exe" /? /AcceptEULA

# Через планировщик заданий мне так и не удалось отловить момент завершения системы
# $Flag_System_Shutdown_Started = [System.Environment]::HasShutdownStarted;  "Flag_System_Shutdown_Started = $Flag_System_Shutdown_Started" | Out-File $logFile -Append

$Sys_UpTime = (Get-Date) - (Get-CimInstance "Win32_OperatingSystem" | Select -Exp LastBootUpTime); $Sys_UpTime_minutes = [int]$Sys_UpTime.TotalMinutes
"System UpTime is $Sys_UpTime_minutes minutes." | Out-File $logFile -Append


# Проверяем есть ли процессы от лок.адмиснкой учетки, чтобы не мешать своей автоматизацией тех. поддержке. 
$Process = Get-Process -IncludeUserName | ? UserName -match "\\Install$" | where ProcessName -ne "conhost" | sort StartTime | select ProcessName,Description,StartTime,FileVersion,Path -Last 1
if ($Process) {
    "Found process executed as LA Install:`n$([string]$Process)" | Out-File $logFile -Append
    Finish-Script; Return
} 

# Проверяем есть ли запущенные процессы обновляемого приложения, которые могут помешать ходу его обновления.
$Process = Get-Process * -IncludeUserName | where Company -match $App_Vendor | where UserName -NotMatch "^NT AUTHORITY\\" | select ProcessName,Description,UserName,StartTime,FileVersion,Path
if ($Process) {
    "Found running software:" | Out-File $logFile -Append
    # https://stackoverflow.com/questions/32252707/remove-blank-lines-in-powershell-output/39554482  https://stackoverflow.com/questions/25106675/why-does-removal-of-empty-lines-from-multiline-string-in-powershell-fail-using-r/25110997
    ($Process | select * -Excl UserName | sort -Unique Path | FT -Au | Out-String).Trim() | Out-File $logFile -Append -Width 500
    Finish-Script; Return
} 
"There is NO running software in user session." | Out-File $logFile -Append

# Проверяем доступность интернета для загрузки актуальной версии нашего приложения
$Test_Net1 = Test-NetConnection "ya.ru" -Port 443
if (-Not($Test_Net1.TcpTestSucceeded)) { 
    "Test for Direct Internet connection to ya.ru:443 is Failed !" | Out-File $logFile -Append
    Finish-Script; Return
}
"There is Direct Internet connection." | Out-File $logFile -Append

# Интернет-Адрес JSON странички как хорошее начало поиска закачки актуальной версии приложения без привязки к его версии.
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/products/getRelatedDLGList?locale=en_US&category=desktop_end_user_computing&product=vmware_horizon_clients&version=horizon_8&dlgType=PRODUCT_BINARY"

$WebPage_getRelatedDLGList_JSON = (Invoke-WebRequest -Uri $URI ).Content | ConvertFrom-JSON
$Soft = ($WebPage_getRelatedDLGList_JSON.dlgEditionsLists | where name -Match "for Windows").dlgList
# Можно обойтись единственным запросом интернет-страничики и анализировать параметр $Soft.releaseDate.Remove(10)

try { # для обработки ошибок интернет запросов
# реально в браузере проходим еще одну страничку - "customerconnect.vmware.com/en/downloads/details?downloadGroup=$($Soft.code)&productId=$($Soft.productId)&rPId=$($Soft.releasePackageId)"
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/dlg/details?locale=en_US&downloadGroup=$($Soft.code)&productId=$($Soft.productId)&rPId=$($Soft.releasePackageId)"
$Soft2 = ((Invoke-WebRequest -Uri $URI ).Content | ConvertFrom-JSON).downloadFiles

# Для поиска установленного приложения - работаем с обоими ветками реестра Uninstall для 32-бит и 64-бит вариантов. Выибираем софт по названию DisplayName и без признака SystemComponent=1
$Reg_path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";  $Reg_path_to_Unistall = @($Reg_path -replace "WOW6432Node\\"); if (Test-Path $Reg_path) { $Reg_path_to_Unistall += $Reg_path }
$Reg_Uninst_Item = $Reg_path_to_Unistall | % { Get-ChildItem $_ } | ? { (GP $_.PSpath -Name "DisplayName" -EA 0).DisplayName -match $App_Name -and (GP $_.PSpath -Name "SystemComponent" -EA 0).SystemComponent -ne 1 } 
# альяс GP для команды найден так: Alias | ? { $_.ResolvedCommandName -match "Get-ItemProp" }

if (($Reg_Uninst_Item | measure).Count -ge 2) { # внутренняя недораобтка в скрипте при поиске инфы об установленном софте - найдено несколько разделов Uninstall в реестре
    "Internal script error: in registry in Uninstall area found 2 or more sections with info about Software!" | Out-File $logFile -Append
    Finish-Script; Return
}

if (!$Reg_Uninst_Item) { # Если наш софт вообще НЕ был установлен
    $Soft_Install_required = $true
} else { # Если наш софт установлен
    if ($RIP.BundleCachePath -match ".+\\(.+\.exe)") { $Soft_orig_installer = $Matches[1] } # имя EXE-инсталлятора установленного приложения
    if ($Soft_orig_installer -eq $Soft2.fileName) { # Если установленное приложение является актуальным
        "Installed application '$($RIP.DisplayName)' has actual version $($RIP.DisplayVersion)" | Out-File $logFile -Append
        $Soft_Install_required = $false
    } else { # Если версия установленного приложения отличается от актуальной
        "Already installed old software:" | Out-File $logFile -Append
        $RIP = Get-ItemProperty $Reg_Uninst_Item.PSPath;  # Извлекаем Самую инересную инфу об уже установленном ПО.
        ($RIP | select @("DisplayName", "DisplayVersion", "QuietUninstallString", "BundleProviderKey", "BundleCachePath") | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500
        # $Soft_DispName = $RIP.DisplayName;  $Soft_Ver = $RIP.DisplayVersion; $Soft_UnInst_Str = $RIP.QuietUninstallString; $Soft_BundleCachePath = $RIP.BundleCachePath; $Soft_BundleProviderKey = $RIP.BundleProviderKey
        
        # Здесь можно разместить предварительную деинсталляцию старой версии, если инсталлятор приложения не поддерживает обновление "накатом".

        # "$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - Delete the old version of the program for " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds,  ExitCode: $LastExitCode" # Time to delete old version of the program is

        $Soft_Install_required = $true
    }
}
if ($Soft_Install_required) { # Если принято решение обновлять приложение и все условия для этого есть

"Actual Application available on the internet is:" | Out-File $logFile -Append
($Soft2 | select title, version, build, releaseDate, fileSize, description, thirdPartyDownloadUrl, sha256checksum | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500

# Задаем папку, в которой будут складываться инсталляторы приложения.
if ($env:Tools) { 
    $App_setup_path = (Split-Path $env:Tools -Parent) + '\' + ($App_Name -replace " ", "_")
} else {
    $App_setup_path = $env:WinDir + '\Temp\' + ($App_Name -replace " ", "_")
}

New-Item $App_setup_path -ItemType Directory -Force | Out-Null
Set-Location $App_setup_path

# https://stackoverflow.com/questions/28682642/powershell-why-is-using-invoke-webrequest-much-slower-than-a-browser-download
# In Windows PowerShell, the progress bar was updated pretty much all the time and this had a significant impact on cmdlets (not just the web cmdlets but any that updated progress). 
# With PSCore6, we have a timer to only update the progress bar every 200ms on a single thread so that the CPU spends more time in the cmdlet and less time updating the screen. 
$ProgressPreference = 'SilentlyContinue' # решаем проблему с безумно медленной закачкой и сохранением через командлет IWR 

# Скачиваем EXE-инсталлятор софта в текущую папку
# -OutFile Specifies the output file for which this cmdlet saves the response body. Enter a path and file name. If you omit the path, the default is the current location. The name is treated as a literal path.
"$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - Start downloading of actual version from Internet" | Out-File $logFile -Append
Invoke-WebRequest -Uri $Soft2.thirdPartyDownloadUrl -OutFile $Soft2.fileName

$ProgressPreference = 'Continue'

"$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - Start the Installation of new version of Application." | Out-File $logFile -Append
$Process = Start-Process -FilePath $Soft2.fileName -ArgumentList $App_setup_params -Wait -PassThru;  $LastExitCode = $Process.ExitCode
"$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - The installation time for a new version of the program is " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds with ExitCode $LastExitCode" | Out-File $logFile -Append

}
} catch [System.Net.WebException] { # обработка ошибок интернет запросов
    $Msg = "System.Net.WebException - Exception.Status: {0}, Exception.Response.StatusCode: {1}, {2} `n{3}" -f $_.Exception.Status, $_.Exception.Response.StatusCode, $_.Exception.Message, $_.Exception.Response.ResponseUri.AbsoluteURI
    # $_.Exception.Status = ProtocolError, $_.Exception.Response.StatusCode = NotFound, $_.Exception.Response.StatusDescription = "Not Found",  $_.Exception.Response.GetType().Name = HttpWebResponse
    "$(Get-Date -format "yyyy-MM-dd HH.mm.ss") - $Msg" | Out-File $logFile -Append
}


Finish-Script; Return


<# Subject: Windows detect system idle state OR event PowerShell, System service input idle detection system-wide user input across all running sessions.
У винды легко можно запросить о простое пользователя только в текущей сессии через GetLastInputInfo. Но при исполнении от LocalSystem задача становится сложнее, требуются хуки через Low-Level API или инжект в процесс.

https://docs.microsoft.com/en-us/windows/win32/taskschd/task-idle-conditions

https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastinputinfo
This function GetLastInputInfo (winuser.h) is useful for input idle detection. However, GetLastInputInfo does not provide system-wide user input information across all running sessions. 
Rather, GetLastInputInfo provides session-specific user input information for only the session that invoked the function.

https://www.codeproject.com/Articles/9104/How-to-check-for-user-inactivity-with-and-without
https://www.codeproject.com/Articles/7294/Processing-Global-Mouse-and-Keyboard-Hooks-in-C

#>

# https://stackoverflow.com/questions/39312540/how-to-detect-user-activity-input-or-lack-thereof-on-a-pc
Add-Type @'
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    namespace PInvoke.Win32 {
        public static class UserInput {
            [DllImport("user32.dll", SetLastError=false)]
            private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
            [StructLayout(LayoutKind.Sequential)]
            private struct LASTINPUTINFO {
                public uint cbSize;
                public int dwTime;
            }
            public static DateTime LastInput {
                get {
                    DateTime bootTime = DateTime.UtcNow.AddMilliseconds(-Environment.TickCount);
                    DateTime lastInput = bootTime.AddMilliseconds(LastInputTicks);
                    return lastInput;
                }
            }
            public static TimeSpan IdleTime {
                get {
                    return DateTime.UtcNow.Subtract(LastInput);
                }
            }
            public static int LastInputTicks {
                get {
                    LASTINPUTINFO lii = new LASTINPUTINFO();
                    lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
                    GetLastInputInfo(ref lii);
                    return lii.dwTime;
                }
            }
        }
    }
'@
# Наглядная демонстрация распознавания насколько давно юзер использовалл клаву или мышь
# ForEach ($i in 0..9) { echo "Last input $([PInvoke.Win32.UserInput]::LastInput), Idle for $([PInvoke.Win32.UserInput]::IdleTime)";  Start-Sleep -Sec (Get-Random -Min 1 -Max 3) }

$LastInput = [PInvoke.Win32.UserInput]::LastInput; $Idle = [PInvoke.Win32.UserInput]::IdleTime; $LastStr = $LastInput.ToLocalTime().ToString("yyyy-MM-dd hh:mm:ss");
echo "So, Last user keyboard/mouse input via WinAPI GetLastInputInfo(): $LastStr, Idle for $($Idle.Days) days, $($Idle.Hours) hours, $($Idle.Minutes) minutes, $($Idle.Seconds) seconds." | Out-File $logFile -Append


<#  Я гуглил "intercept web request header" 
https://developer.mozilla.org/en-US/docs/Tools/Network_Monitor
The Network Monitor shows you all the HTTP requests Firefox makes (for example, when it loads a page), how long each request takes, and details of each request.
There are a few different ways to open the Network Monitor:  Press  Ctrl + Shift + E.  Select "Network" from the Web Developer menu
The Network Monitor will appear at the bottom of the browser window. When it first opens, the Network Monitor does not show request information.

User-Agent request header examples - https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/User-Agent http://www.useragentstring.com/pages/useragentstring.php

Вот такие заголовки Web-запроса имеет браузер FireFox в формате JSON если их все скопировать из FireFox Dev Tools Network Monitor
#>
$Req_Headers_FireFox_as_text = @"
{
		"headers": [
			{
				"name": "Accept",
				"value": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
			},
			{
				"name": "Accept-Encoding",
				"value": "gzip, deflate, br"
			},
			{
				"name": "Accept-Language",
				"value": "ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3"
			},
			{
				"name": "Cache-Control",
				"value": "max-age=0"
			},
			{
				"name": "Connection",
				"value": "keep-alive"
			},
			{
				"name": "Host",
				"value": "customerconnect.vmware.com"
			},
			{
				"name": "Sec-Fetch-Dest",
				"value": "document"
			},
			{
				"name": "Sec-Fetch-Mode",
				"value": "navigate"
			},
			{
				"name": "Sec-Fetch-Site",
				"value": "none"
			},
			{
				"name": "Sec-Fetch-User",
				"value": "?1"
			},
			{
				"name": "Upgrade-Insecure-Requests",
				"value": "1"
			},
			{
				"name": "User-Agent",
				"value": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:94.0) Gecko/20100101 Firefox/94.0"
			}
		]
	}
"@
$WebReq_Headers_as_JSON = ConvertFrom-JSON $Req_Headers_as_text
$WebReq_Headers = @{}; $WebReq_Headers_as_JSON.headers | % {$Name = $_.Name; $Value = $_.Value; if ($Name -ne "Connection") { $WebReq_Headers += @{$Name = $Value} } }

<#  Изучаем что загружается при переходе по ссылкам начиная с запроса https://hv.nornik.ru/
https://www.vmware.com/go/viewclients#win64
https://customerconnect.vmware.com/en/downloads/info/slug/desktop_end_user_computing/vmware_horizon_clients/horizon_8#win64
https://customerconnect.vmware.com/channel/public/api/v1.0/products/getRelatedDLGList?locale=en_US&category=desktop_end_user_computing&product=vmware_horizon_clients&version=horizon_8&dlgType=PRODUCT_BINARY
https://customerconnect.vmware.com/en/downloads/details?downloadGroup=CART22FQ2_WIN_2106&amp;productId=1027&amp;rPId=74408
https://customerconnect.vmware.com/channel/public/api/v1.0/dlg/details?locale=en_US&downloadGroup=CART22FQ2_WIN_2106&productId=1027&rPId=74408
https://download3.vmware.com/software/view/viewclients/CART22FQ2/VMware-Horizon-Client-2106-8.3.0-18287501.exe

Wrangling REST APIs with PowerShell and JSON, 2020-12  https://adamtheautomator.com/powershell-json/
#>

<# Subject: PowerShell Invoke-WebRequest redirect 302 OR 307 location
https://winblog.it.umn.edu/2018/05/19/getting-redirected-uris-in-powershell/
https://dotnet-helpers.com/powershell/getting-redirected-301-302-uris-in-powershell-using-invoke-webrequest-method/
https://jmcnatt.net/quick-tips/powershell-capturing-a-redirected-url-from-a-web-request/
#>
$URI_start = "https://www.vmware.com/go/viewclients#win64" # Начинаем с адреса, который точно редиректит
$Web_Resp = IWR -URI $URI_start -MaximumRedirection 0 -Method Head -EA 0
if ($Web_Resp.StatusCode -eq 302) {
    $Web_Resp_head = IWR -URI $URI_start -Method Head
    $URI = $Web_Resp_head.BaseResponse.ResponseUri.AbsoluteUri
} else { $URI = "https://customerconnect.vmware.com/en/downloads/info/slug/desktop_end_user_computing/vmware_horizon_clients/horizon_8" }

# Попытка пострить адрес стартовой странички JSON без зависимости от названия сайта customerconnect.vmware.com и от пути к страничке после серьезных изменений во фронтэнде у разрабов VMware
$Web_Resp = IWR -URI $URI;  if ($Web_Resp.Content -match '<script src="downloads/main\.(\S+)\.js" defer></script>') { $URI_js = "https://customerconnect.vmware.com/downloads/main.$($Matches[1]).js" }
(IWR $URI_js).Content | Out-File main.js -Encoding utf8; # в этом JS-скрипте встречаются ,getDLGsEndpoint:"/channel/public/api/v1.0/products/getRelatedDLGList", и PRODUCT_BINARY, которые используются при генерации адреса стартовой странички JSON
