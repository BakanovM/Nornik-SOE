<#
Скрипт выполняет обслуживание корпоративного программного обеспечения и его конфигуририрование при работе специальной заливки для удаленки за пределами КСПД.
На данный момент реализовано автоматическое обновление через интернет клиента VMware Horizon и установка DameWare MRC с нашего сервера.
Автор - Максим Баканов 2022-02-15
#>

# Название приложения, по которому будет производится поиск в реестре и по которому будут распознаваться запущенные процессы приложения.
$App_Name = "VMware Horizon Client";  

# Название компании-разработчика, по которому будут отбираться запущенные процессы
$App_Vendor = "VMware"

# Строка параметров для EXE-инсталлятора приложения. Исключить параметр /norestart нельзя, т.к. инсталлятор сразу отправит винду в перезагрузку и скрипт даже не успеет записать в лог об успешном завершении инсталляции.
$App_setup_params = "/silent /norestart VDM_SERVER=HV.nornik.ru LOGINASCURRENTUSER_DEFAULT=1 INSTALL_SFB=1 INSTALL_HTML5MMR=1"


# Задаем Лог-файл действий моего скрипта и путь-имя данного скрипта для случаев как штатного исполнения внутри скрипта, так и для случая интерактивной отладки
$Script_Path = $MyInvocation.MyCommand.Source # При исполнении внутри скрипта - тут будет полный путь к PS1 файлу скрипта. При интерактивной работе в PoSh-консоли или в ISE среде тут будет пустая строка
# $MyInvocation.MyCommand.Definition; # При исполнении скрипта - тут будет полный путь к PS1 файлу скрипта. При работе в ISE среде тут строка "$MyInvocation.MyCommand.Definition"
if (!$Script_Path) # При исполнении в режиме отладки нужно правильно задать переменные лог-файла и пути-имени скрипта
    { $Script_Path = "$Env:WinDir\SoftwareDistribution\Download\SoftwareMaintenance.ps1" }
$Script_Name = Split-Path $Script_Path -Leaf; $Script_Dir = Split-Path $Script_Path -Parent # if ($Script_Path -match ".+\\(.+\.ps1)") { $Script_Name = $Matches[1] };  
if ($Script_Name -match "(^.+)\..+") { $Script_Name_no_ext = $Matches[1] }
$logFile = "$($Env:WinDir)\Temp\$Script_Name_no_ext.log"
# Start-Transcript $logFile -Append


# решаем проблему с безумно медленной закачкой и сохранением через командлет IWR Invoke-WebRequest
# https://stackoverflow.com/questions/28682642/powershell-why-is-using-invoke-webrequest-much-slower-than-a-browser-download
# In Windows PowerShell, the progress bar was updated pretty much all the time and this had a significant impact on cmdlets (not just the web cmdlets but any that updated progress). 
# With PSCore6, we have a timer to only update the progress bar every 200ms on a single thread so that the CPU spends more time in the cmdlet and less time updating the screen. 
$Progr_Pref = $ProgressPreference; $ProgressPreference = 'SilentlyContinue' 


function Finish-Script {
# Stop-Transcript
"$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - The End of PoSh script." | Out-File $logFile -Append
}
Push-Location

# Задаем ширину окна консоли, чтобы вывод в лог-файл не обрезался по ширине 80 символов.  http://stackoverflow.com/questions/978777/powershell-output-column-width
$rawUI = $Host.UI.RawUI;  $oldSize = $rawUI.BufferSize;  $typeName = $oldSize.GetType().FullName; $newSize = New-Object $typeName (256, 8192);
if ($rawUI.BufferSize.Width -lt 256) { $rawUI.BufferSize = $newSize }

# Общая инфа о среде исполнения и о данном скрипте
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name # https://www.optimizationcore.com/scripting/ways-get-current-logged-user-powershell/
$HostName = [System.Net.Dns]::GetHostName() # https://virot.eu/getting-the-computername-in-powershell/  https://adamtheautomator.com/powershell-get-computer-name/
$Msg = "`n`n$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start of Software Maintenance as $UserName on $HostName with argument '$($Args[0])' as PoSh script:`n$Script_Path, "
$Msg += [string](Get-Item $Script_Path).Length + ' bytes, '
$S = Select-String -Path $Script_Path -Pattern "Автор .+ (\d{4}-\d\d(-\d\d)?)"; if ($S) { $Msg += $S.Matches[0].Groups[1].Value }
$Msg | Out-File $logFile -Append

####### Конфигурирование системы и ПО, не требующее доступа в интернет #######

$Sys_UpTime = (Get-Date) - (Get-CimInstance "Win32_OperatingSystem" | Select -Exp LastBootUpTime); $Sys_UpTime_minutes = [int]$Sys_UpTime.TotalMinutes
"System UpTime is $Sys_UpTime_minutes minutes." | Out-File $logFile -Append

# Проверяем есть ли процессы от лок.адмиснкой учетки, чтобы не мешать своей автоматизацией тех. поддержке. 
$Process = Get-Process -IncludeUserName | ? UserName -match "\\Install$" | where ProcessName -ne "conhost" | sort StartTime | select ProcessName,Description,StartTime,FileVersion,Path -Last 1
if ($Process) {
    "Found process executed as LA Install:`n$([string]$Process)" | Out-File $logFile -Append
    # Finish-Script; Return
} 

# Проверяем доступность интернета для загрузки актуальной версии нашего приложения
$Test_Net1 = Test-NetConnection "ya.ru" -Port 443
if (-Not($Test_Net1.TcpTestSucceeded)) { 
    $Msg = "Failed Test for Direct Internet connection to ya.ru:443 !"; echo $Msg; $Msg | Out-File $logFile -Append
    Finish-Script; Return
}
$Msg = "Direct Internet connection is Working."; echo $Msg; $Msg | Out-File $logFile -Append

# По умолчанию PoSh в старой Win10 v1607 использует TLS 1.0, а современные сайты TLS 1.2 и можем получить error request secure channel SSL/TLS при вызове Invoke-WebRequest
# https://stackoverflow.com/questions/41618766/powershell-invoke-webrequest-fails-with-ssl-tls-secure-channel
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Задаем папку, в которой будут складываться инсталляторы приложения.
if ($env:Tools) { 
    $App_setup_path = (Split-Path $env:Tools -Parent) 
} else {
    $App_setup_path = $env:WinDir + '\Temp\'
}

####### Авто-обновление клиента VMware Horizon - начало #######

# Проверяем есть ли запущенные процессы обновляемого приложения, которые могут помешать ходу его обновления.
$Process = Get-Process * -IncludeUserName | ? { $_.Company -match $App_Vendor -and $_.UserName -NotMatch "^NT AUTHORITY\\"  -and ($_.Description -match $App_Name -or $_.Product -match $App_Name)}`
| select ProcessName,Description,Product,UserName,StartTime,FileVersion,Path

if ($Process) {
    $Msg = "Found running processes of App '$App_Name'"; echo $Msg; $Msg | Out-File $logFile -Append
    # https://stackoverflow.com/questions/32252707/remove-blank-lines-in-powershell-output/39554482  https://stackoverflow.com/questions/25106675/why-does-removal-of-empty-lines-from-multiline-string-in-powershell-fail-using-r/25110997
    ($Process | select * -Excl UserName | sort -Unique Path | FT -Au | Out-String).Trim() | Out-File $logFile -Append -Width 500
    # Finish-Script; Return
} else {
$Msg = "There is NO running App '$App_Name' in user session."; echo $Msg; $Msg | Out-File $logFile -Append

try { # для обработки ошибок интернет запросов

# Интернет-Адрес JSON странички как хорошее начало поиска закачки актуальной версии приложения без привязки к его версии.
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/products/getRelatedDLGList?locale=en_US&category=desktop_end_user_computing&product=vmware_horizon_clients&version=horizon_8&dlgType=PRODUCT_BINARY"

$WebPage_getRelatedDLGList_JSON = (Invoke-WebRequest -Uri $URI -UseBasicParsing).Content | ConvertFrom-JSON
$Soft = ($WebPage_getRelatedDLGList_JSON.dlgEditionsLists | where name -Match "for Windows").dlgList
# Можно обойтись единственным запросом интернет-страничики и анализировать параметр $Soft.releaseDate.Remove(10)

# реально в браузере проходим еще одну страничку - "customerconnect.vmware.com/en/downloads/details?downloadGroup=$($Soft.code)&productId=$($Soft.productId)&rPId=$($Soft.releasePackageId)"
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/dlg/details?locale=en_US&downloadGroup=$($Soft.code)&productId=$($Soft.productId)&rPId=$($Soft.releasePackageId)"
$Soft2 = ((Invoke-WebRequest -Uri $URI -UseBasicParsing).Content | ConvertFrom-JSON).downloadFiles

if ($Env:Processor_ArchiteW6432) { Write-Debug "Detected WoW64 powershell host" };  if ([IntPtr]::size -eq 4) { Write-Debug "This is a 32 bit process" }

# Для поиска установленного приложения - работаем с обоими ветками реестра Uninstall для 32-бит и 64-бит вариантов. Выибираем софт по названию DisplayName и без признака SystemComponent=1
$Reg_path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";  $Reg_path_to_Unistall = @($Reg_path -replace "WOW6432Node\\"); 
if ((Test-Path $Reg_path) -and [Environment]::Is64BitProcess) { $Reg_path_to_Unistall += $Reg_path } 
$Reg_Uninst_Item = $Reg_path_to_Unistall | % { Get-ChildItem $_ } | ? { (GP $_.PSpath -Name "DisplayName" -EA 0).DisplayName -match $App_Name -and (GP $_.PSpath -Name "SystemComponent" -EA 0).SystemComponent -ne 1 } 
# альяс GP для команды найден так: Alias | ? { $_.ResolvedCommandName -match "Get-ItemProp" }

if (($Reg_Uninst_Item | measure).Count -ge 2) { # при поиске инфы об установленном софте найдено несколько разделов Uninstall в реестре, возможно недоработка в скрипте, втретился редкий случай.
    "Internal script error: in registry in Uninstall area found 2 or more sections with info about App!" | Out-File $logFile -Append
    Get-ItemProperty $Reg_Uninst_Item.PSPath | % { $_.DisplayName + ' ' + $_.DisplayVersion } | Out-File $logFile -Append
    Finish-Script; Return
}

if (!$Reg_Uninst_Item) { # Если наш софт вообще НЕ был установлен
    $Soft_Install_required = $true
} else { # Если наш софт установлен
    $RIP = Get-ItemProperty $Reg_Uninst_Item.PSPath;  # Извлекаем Самую инересную инфу об уже установленном ПО.
    if ($RIP.BundleCachePath -match ".+\\(.+\.exe)") { $Soft_orig_installer = $Matches[1] } # имя EXE-инсталлятора установленного приложения

    if ($Soft_orig_installer -eq $Soft2.fileName) { # Если установленное приложение является актуальным
        $Msg = "Installed application '$($RIP.DisplayName)' has actual version $($RIP.DisplayVersion)"; echo $Msg; $Msg | Out-File $logFile -Append
        $Soft_Install_required = $false
    } else { # Если версия установленного приложения отличается от актуальной
        $Msg = "Already installed old App '$($RIP.DisplayName)' $($RIP.DisplayVersion)"; echo $Msg; $Msg | Out-File $logFile -Append
        ($RIP | select @("DisplayName", "DisplayVersion", "QuietUninstallString", "BundleProviderKey", "BundleCachePath") | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500
        # $Soft_DispName = $RIP.DisplayName;  $Soft_Ver = $RIP.DisplayVersion; $Soft_UnInst_Str = $RIP.QuietUninstallString; $Soft_BundleCachePath = $RIP.BundleCachePath; $Soft_BundleProviderKey = $RIP.BundleProviderKey
        
        # Здесь можно разместить предварительную деинсталляцию старой версии, если инсталлятор приложения не поддерживает обновление "накатом".

        # "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Delete the old version of the program for " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds,  ExitCode: $LastExitCode" # Time to delete old version of the program is

        $Soft_Install_required = $true
    }
}
if ($Soft_Install_required) { # Если принято решение обновлять приложение и все условия для этого есть

$Msg = "Actual App version available from Internet is ver$($Soft2.version) build$($Soft2.build)"; echo $Msg; $Msg | Out-File $logFile -Append
($Soft2 | select title, version, build, releaseDate, fileSize, description, thirdPartyDownloadUrl, sha256checksum | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500

# Готовим папку для дистрибутива приложения
$Path = $App_setup_path + '\' + ($App_Name -replace " ", "_"); New-Item $Path -ItemType Directory -Force | Out-Null; Set-Location $Path

# Скачиваем EXE-инсталлятор софта в текущую папку
# -OutFile Specifies the output file for which this cmdlet saves the response body. Enter a path and file name. If you omit the path, the default is the current location. The name is treated as a literal path.
$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start downloading from Internet the actual version of App '$App_Name' "; echo $Msg; $Msg | Out-File $logFile -Append
Invoke-WebRequest -Uri $Soft2.thirdPartyDownloadUrl -OutFile $Soft2.fileName

# На время обновления приложения заблокировать юзеру его запуск
# "C:\ProgramData\Microsoft\Windows\Start Menu\Programs" 

$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start the Installation of App '$App_Name'"; echo $Msg; $Msg | Out-File $logFile -Append
$Process = Start-Process -FilePath $Soft2.fileName -ArgumentList $App_setup_params -Wait -PassThru;  $LastExitCode = $Process.ExitCode
$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - The installation time for a new version of App '$App_Name' is " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds with ExitCode $LastExitCode"
echo $Msg; $Msg | Out-File $logFile -Append

}
} catch [System.Net.WebException] { # обработка ошибок интернет запросов
    $Msg = "System.Net.WebException - Exception.Status: {0}, Exception.Response.StatusCode: {1}, {2} `n{3}" -f $_.Exception.Status, $_.Exception.Response.StatusCode, $_.Exception.Message, $_.Exception.Response.ResponseUri.AbsoluteURI
    # $_.Exception.Status = ProtocolError, $_.Exception.Response.StatusCode = NotFound, $_.Exception.Response.StatusDescription = "Not Found",  $_.Exception.Response.GetType().Name = HttpWebResponse
    "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - $Msg" | Out-File $logFile -Append
}
} ####### Авто-обновление клиента VMware Horizon - закончено #######


####### Установка/обновление DameWare - начало #######

$App_Name = "DameWare Mini Remote Control Service";  # Название приложения, по которому будет производится поиск в реестре

# $App_Vendor = "SolarWinds"  # Название компании-разработчика, по которому будут отбираться запущенные процессы

# инсталлятор ПО в виде MSI+MST со встроенного в DameWare сервер своего веб-сервера, который предоставляет содержимое папки ProgramFiles\DameWare\Binary 
$URI = "https://dmwr.nornik.ru/dwnl/binary/SolarWinds-Dameware-Agent-x64.MSI"
if ($URI -match ".+\/(\S+\.MSI)$") { $Inst_MSI = $Matches[1] };  $Inst_MST = $Inst_MSI -replace ".MSI$",".MST";  $URI2 = $URI -replace ".MSI$",".MST"

# Строка аргументов запсука MSIexe инсталлятора приложения. (Исключить параметр /norestart нельзя, т.к. инсталлятор сразу отправит винду в перезагрузку и скрипт даже не успеет записать в лог об успешном завершении инсталляции)
$App_setup_params = "/i $Inst_MSI TRANSFORMS=$Inst_MST /qn /Log $Env:windir\Temp\DameWare_MRC_install.log"

# Путь к ветке реестра с настройками приложения
$App_Reg_Path = 'HKLM:\SOFTWARE\DameWare Development\Mini Remote Control Service\Settings'

# Готовим папку для дистрибутива приложения
$Path = $App_setup_path + '\DameWare_MRC_Agent'; New-Item $Path -ItemType Directory -Force | Out-Null; Set-Location $Path

# Для поиска установленного приложения - работаем только с одной веткой реестра Uninstall, т.к. 64-битная версия ПО правильно выбирает Uninstall раздел реестра. 
$Reg_path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall";  
$Reg_Uninst_Item = Get-ChildItem $Reg_path | ? { (GP $_.PSpath -Name "DisplayName" -EA 0).DisplayName -match $App_Name }

if (-Not $Reg_Uninst_Item) # Наше приложение в системе отсутствует ?
{   # ДА, Наше приложение еще НЕ установлено, точнее по инфе из Uninstall раздела реестра (который может быть недоступен при WoW64)

    if ($Env:Processor_ArchiteW6432) { # Приходится выкручиваться в случае 32-бит среды исполнения и потребности в обслуживании 64-битного ПО.
        [String]$Reg64 = reg.exe Query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EA9A6570-008F-4F5F-ADF6-21AD5CB2D751}" /v "DisplayVersion" /Reg:64
        if ($Reg64 -match "DisplayVersion\s+REG_SZ\s+(.+)") { $App_ver = $Matches[1]; $Msg = "Found already Installed application '$App_Name' $App_ver (in WoW64)." }
    } else { 
        $Msg = "In this system is NOT Installed App '$App_Name'"; $App_ver = "0" 
    }
} else { # Наше приложение уже установлено в системе
    $RIP = Get-ItemProperty $Reg_Uninst_Item.PSPath;  # Извлекаем инфу об уже установленном ПО.
    $App_ver = $RIP.DisplayVersion
    $Msg = "Found already Installed application '$($RIP.Publisher) $($RIP.DisplayName)' $App_ver."
}
echo $Msg; $Msg | Out-File $logFile -Append

if ($App_ver -lt "12.02.0.0") { # Если текущая установленная версия ниже целевой либо отсутствует вовсе, то приступаем к загрузке и установке ПО

    # Скачиваем EXE-инсталлятор софта в текущую папку по ссылке со страницы "https://dmwr.nornik.ru/dwnl/advancedDownload.html?dl=UR1M0GZ7"
    # $URI = "https://dmwr.nornik.ru/dwnl/binary/SolarWinds-Dameware-Agent-x64.exe";  if ($URI -match ".+\/(\S+\.exe)$") { $Inst_Exe = $Matches[1] }

    $Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start downloading from Internet the App 'DameWare MRC agent' "; echo $Msg; $Msg | Out-File $logFile -Append

try { # для обработки ошибок интернет запросов

    # Скачиваем в текущую папку инсталлятор ПО в виде двух файлов MSI и MST.
    Invoke-WebRequest -Uri $URI  -OutFile $Inst_MSI
    Invoke-WebRequest -Uri $URI2 -OutFile $Inst_MST
    # -OutFile Specifies the output file for which this cmdlet saves the response body. Enter a path and file name. If you omit the path, the default is the current location. The name is treated as a literal path.
    
    # Запускаем инсталляцию ПО как msiexec.exe MSI+MST. В случае успеха установки, когда ExitCode=0 - параметрами реестра донастраивает ПО.
    $Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start the Installation of Application as MSIexec with MSI+MST."; echo $Msg; $Msg | Out-File $logFile -Append
    $Process = Start-Process "MSIexec.exe" -Arg $App_setup_params -Wait -PassThru -EV Err
            
    # https://documentation.solarwinds.com/en/success_center/dameware/content/mrc_client_agent_service_installation_methods.htm
    # $Process = Start-Process $Inst_Exe -Arg "-ap ""TRANSFORMS=$Inst_MST OVERWRITEREMOTECFG=1""" -Wait -PassThru -EV Err

    # https://support.solarwinds.com/SuccessCenter/s/article/Install-DRS-and-MRC-from-the-command-line?language=en_US
    # https://www.itninja.com/software/dameware-development/dameware-mini-remote-control-client-agent-service/7-1052
    # $Process = Start-Process $Inst_Exe -Arg "/args ""/qn TRANSFORMS=$Inst_MST OVERWRITEREMOTECFG=1 reboot=reallysuppress SILENT=yes""" -Wait -PassThru -EV Err
  
    if ($Err) { "Installator is NOT executed normally ! `n MSIexec.exe $App_setup_params" | Out-File $logFile -Append } 
    else {
    $ExitCode = $Process.ExitCode
    $Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") Duration of Installation for this App: " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds,  ExitCode: " + $ExitCode
    echo $Msg; $Msg | Out-File $logFile -Append

    if ($ExitCode -eq 0) {
        if (Test-Path $App_Reg_Path) { $Msg = Get-ItemProperty $App_Reg_Path -EA 0 } else { $Msg = "Not found registry key !" }; Write-Debug "DameWare Settings in registry $Reg_path : `n $Msg"; 

        # Задаем список локальных и доменных групп, члены которых рулят в DameWare (в т.ч. и AD группа полевых инженеров)
        # Многообразие групп доступа к Remote Control - https://social.technet.microsoft.com/Forums/ru-RU/8e32ab4c-bb03-4aff-a0e9-1c95da58881c/105210851086107510861086107310881072107910801077
        $Groups_list = @('Administrators', 'Администраторы', 'Пользователи удаленного управления ConfigMgr', 'Пользователи удаленного управления Configuration Manager', 'ConfigMgr Remote Control Users', 'NPR\$Engineers') 

        0..($Groups_list.Count-1) | % { 
            if ($Env:Processor_ArchiteW6432) { # Приходится выкручиваться в случае 32-бит среды исполнения и потребности в настройке реестра для 64-битного ПО
                reg.exe Add ($App_Reg_Path -replace ':') /v "Group $_" /d $Groups_list[$_] /Reg:64 /f | Out-Null
            } else {
                New-ItemProperty -Path $App_Reg_Path -Name "Group $_" -Value $Groups_list[$_] -PropertyType String -Force | Out-Null  # При обычном исполнении в 64-битной среде
            }
        }
    }}
} catch [System.Net.WebException] { # обработка ошибок интернет запросов
    $Msg = "System.Net.WebException - Exception.Status: {0}, Exception.Response.StatusCode: {1}, {2} `n{3}" -f $_.Exception.Status, $_.Exception.Response.StatusCode, $_.Exception.Message, $_.Exception.Response.ResponseUri.AbsoluteURI
    "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - $Msg" | Out-File $logFile -Append
}
}
# Настриваем DameWare MRC чтобы агент не справшивал у пользователя подтверждения на входящее подключение к графическому сеансу
if (-Not (Test-Path $App_Reg_Path)) { New-Item -Path $App_Reg_Path -Force | Out-Null }
New-ItemProperty -Path $App_Reg_Path -Name "Permission Required" -Value 0 -Force | Out-Null
New-ItemProperty -Path $App_Reg_Path -Name "Permission Required for non Admin" -Value 1 -Force | Out-Null

if ($ExitCode -eq 0) {
# Перезапускаем службу чтобы сразу после установки ПО оно заработало с заданными настройками.
Get-Service DWMRCS | Restart-Service # DameWare Mini Remote Control
}

####### Установка/обновление DameWare - закончено #######


$Msg = @() # Различные признаки необходимости перезапуска системы описаны тут: https://adamtheautomator.com/pending-reboot-registry/
if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $Msg += "RebootPending" }
if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending") { $Msg += "PackagesPending" }
# HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager
if ($Msg) { $Msg = "Detected Component Based Servicing pending operations - " + [string]$Msg; echo $Msg; $Msg | Out-File $logFile -Append }

# Автоматическое обновления скрипта на случай будущих изменений/улучшений в данном скрипте-автоматике.
Pop-Location
$Reg_param = "ETag_" + $Script_Name_no_ext # if ($Script_Name -match "(^.+)\..+") { $Reg_param = "ETag_" + $Matches[1] }
$URI = "https://github.com/BakanovM/Nornik-SOE/raw/main/OSD_scripts/$Script_Name"
try { $Web = IWR -Uri $URI -Method Head -UseBasicParsing } # Запрашиваем инфу о скрипте в инете - для того чтобы узнать обновился ли он
catch { "Error request info for updated script! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }
$Web_ETag = $Web.Headers.ETag.Trim('"')
$Reg_value = (Get-ItemProperty "HKLM:\SOFTWARE\Company" -Name $Reg_param -EA 0).$Reg_param

if ($Web_ETag -ne $Reg_value) { # обнаружена новая версия скрипта в интернете
    "Found NEW version of script in Internet with ETag = $Web_ETag" | Out-File $logFile -Append
    Set-Location (Split-Path $Script_Path -Parent)
    try { IWR -Uri $URI -OutFile "$Script_Path.new" } # Загружаем обновленную версию скрипта скрипта из инетернет
    catch { "Error downloading updated script! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }

    Set-ItemProperty "HKLM:\SOFTWARE\Company" -Name $Reg_param -Value $Web_ETag -EA 0

    echo "Self-updating of this Script $Script_Path" | Out-File $logFile -Append;  # Не подошел вариант Invoke-Command -AsJob
    # Set-Location $Script_Dir; Rename-Item $Script_Name -NewName "$Script_Name.old"; Rename-Item "$Script_Name.new" -NewName $Script_Name; Remove-Item "$Script_Name.old"
    Start "PowerShell" -Arg "-Exec Bypass -Command `"& { sleep -Sec 5; cd $Script_Dir; ren $Script_Name -N `"$Script_Name.old`"; ren `"$Script_Name.new`" -N $Script_Name; del `"$Script_Name.old`" }`""
}

$ProgressPreference = $Progr_Pref # восстанавливаем прогресс бар
Finish-Script; Return

#   
