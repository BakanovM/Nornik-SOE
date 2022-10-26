<# 
Скрипт выполняет обслуживание корпоративного программного обеспечения и его конфигуририрование при работе специальной заливки для удаленки за пределами КСПД.

Запускается триггерами планировщика заданий SoftwareMaintenance как PowerShell.exe -Exec Bypass -NoProfile -File %Tools%\SoftwareMaintenance.ps1
На данный момент реализовано автоматическое обновление через интернет клиента VMware Horizon и установка DameWare MRC с нашего сервера.
Для запуска скрипта в 32-битной среде 64-разрядной ОС Win10 (например Каспером) лучше использовать запуск через "C:\Windows\SysNative\WindowsPowerShell\v1.0\PowerShell.exe"

Автор - Максим Баканов 2022-10-26

ToDo:
+ само-обновление скрипта нужно выполнять не после выполнения работ по обновлению ПО, а перед ними, т.е. в начале скрипта реализовать само-перезапуск, если в инете есть новая версия скрипта. Тогда можно быстро остановить массовые обновления косячной новой версии ПО.
+ для старой ОС Win10 LTSB 2016 v1607 нужно задать максимально применимую версию 8.4.0 2111.1 b19480429 2022-03-15;
+ ограничить авто-обновление определнной допустимой версией, выше которой авто-обновление работать не будет;
+ Возможность скачивать не только из внешнего интернета, но также и через корп. прокси;
- Configure VMware URL Content Redirection
- выключить LOGINASCURRENTUSER_DEFAULT в уже установленном клиенте Horizon
- Пользователя оповестить о начале и окончании обновления приложения
- На время обновления приложения заблокировать юзеру его запуск
- Перенести лог из пользовательской временной папки $Env:Temp\VMware_Horizon_Client_2021MMDDhhmmss.log
#>


# Название приложения, по которому будет производится поиск в реестре и по которому будут распознаваться запущенные процессы приложения.
$App_Name = "VMware Horizon Client";  

# Название компании-разработчика, по которому будут отбираться запущенные процессы
$App_Vendor = "VMware";

# Строка параметров для EXE-инсталлятора приложения. Исключить параметр /norestart нельзя, т.к. инсталлятор сразу отправит винду в перезагрузку и скрипт даже не успеет записать в лог об успешном завершении инсталляции.
$App_setup_params = "/silent /norestart VDM_SERVER=HV.nornik.ru INSTALL_SFB=1 INSTALL_HTML5MMR=1";  # параметр LOGINASCURRENTUSER_DEFAULT=1 полезен токо для domain-joined компов

# Максимально допустимая версия для обновления, выше которой более новые версии из интернета загружаться не будут.
$App_Allowed_Ver = "2209" # она же 8.7.0

# Потребовались исключения в автоматическом обновлении Horizon Client в связи единичными случаями проблемы в работе новых версий клиента 8.4.0 и 8.5.0 при старом агенте Horizon 8.2.0
$Comp_list_Exclude = @("nMs27008","v-Bak-Sar76") # ZakharinskiyEYu


# Задаем Лог-файл действий моего скрипта и путь-имя данного скрипта для случаев как штатного исполнения внутри скрипта, так и для случая интерактивной отладки
$Script_Path = $MyInvocation.MyCommand.Source # При исполнении внутри скрипта - тут будет полный путь к PS1 файлу скрипта. При интерактивной работе в PoSh-консоли или в ISE среде тут будет пустая строка
# $MyInvocation.MyCommand.Definition; # При исполнении скрипта - тут будет полный путь к PS1 файлу скрипта. При работе в ISE среде тут строка "$MyInvocation.MyCommand.Definition"
if (!$Script_Path) # При исполнении в режиме отладки нужно правильно задать переменные лог-файла и пути-имени скрипта
    { $Script_Path = "$Env:WinDir\SoftwareDistribution\Download\SoftwareMaintenance2.ps1" }
$Script_Name = Split-Path $Script_Path -Leaf; $Script_Dir = Split-Path $Script_Path -Parent # if ($Script_Path -match ".+\\(.+\.ps1)") { $Script_Name = $Matches[1] };  
if ($Script_Name -match "(^.+)\..+") { $Script_Name_no_ext = $Matches[1] }
$logFile = "$($Env:WinDir)\Temp\$Script_Name_no_ext.log"
# Start-Transcript $logFile -Append


# параметры для определения старой версии ОС Win10 LTSB 2016, для которой нужно применять старую версию ПО.
$WMI_OS = gwmi Win32_OperatingSystem;  $Reg_HKLM_MS_WinNT = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\"
if ([int]$WMI_OS.BuildNumber -le 14393 -or $WMI_OS.Version -eq "10.0.14393" -or [int]$Reg_HKLM_MS_WinNT.CurrentBuild -le 14393 -or $Reg_HKLM_MS_WinNT.ReleaseId -eq "1607" -or $Reg_HKLM_MS_WinNT.ProductName -match "Windows 10 Enterprise 2016 LTSB")
{ $required_Old_version = $true }


# решаем проблему с безумно медленной закачкой и сохранением через командлет IWR Invoke-WebRequest
# https://stackoverflow.com/questions/28682642/powershell-why-is-using-invoke-webrequest-much-slower-than-a-browser-download
# In Windows PowerShell, the progress bar was updated pretty much all the time and this had a significant impact on cmdlets (not just the web cmdlets but any that updated progress). 
# With PSCore6, we have a timer to only update the progress bar every 200ms on a single thread so that the CPU spends more time in the cmdlet and less time updating the screen. 
$Progr_Pref = $ProgressPreference; $ProgressPreference = 'SilentlyContinue' 


function Finish-Script {
# Stop-Transcript
"$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - The End of PoSh script.`n" | Out-File $logFile -Append
}

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
if ($Process2) { # отключил пока с вер 2206  
    "Found process executed as Local Admin:`n$([string]$Process)" | Out-File $logFile -Append
    # Finish-Script; Return
} 

# По умолчанию PoSh в старой Win10 v1607 использует TLS 1.0, а современные сайты TLS 1.2 и можем получить error request secure channel SSL/TLS при вызове Invoke-WebRequest
# https://stackoverflow.com/questions/41618766/powershell-invoke-webrequest-fails-with-ssl-tls-secure-channel
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


# Проверяем доступность интернета для загрузки актуальной версии нашего приложения
$corp_proxy = "vMs06wCG01";  # в отладочных целях также предусмотрена загрузка из интернета через прокси, даже находясь в корп. сети.
$Test_Net1 = Test-NetConnection "ya.ru" -Port 443
if ($Test_Net1.TcpTestSucceeded) { # есть ли прямое соединение с инетом ?
    $Msg = "Direct Internet connection is Working."; echo $Msg; $Msg | Out-File $logFile -Append

} else {
    $Msg = "Failed Test for Direct Internet connection to ya.ru:443 !"; echo $Msg; $Msg | Out-File $logFile -Append

    if (-not $corp_proxy) { 
        $Msg = "There is NO corp proxy in script code. Exiting."; echo $Msg; $Msg | Out-File $logFile -Append
        Finish-Script; Return 
    }

    if (Test-Connection $corp_proxy -Count 1) { # если задан прокси сервер и он доступен в сети КСПД
        [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy("http://$corp_proxy`:18080") # задаем прокси для всех Web-запросов в PoSh-командлетах Invoke-WebRequest
        
        try { IWR "http://ya.ru" -UseBasicParsing } catch { # если загрузка из инета через прокси невозможна, то нету смысла далее продолжать работу
            Msg = "Error in test Web Request via proxy: $($_.Exception.Message)"; echo $Msg; $Msg | Out-File $logFile -Append
            Finish-Script; Return
        }
        $Msg = "Internet via Proxy is Working. We continue now."; echo $Msg; $Msg | Out-File $logFile -Append
    } else {
        $Msg = "Proxy server is NOT available."; echo $Msg; $Msg | Out-File $logFile -Append
        Finish-Script; Return
    }
}


# Автоматическое обновления скрипта на случай будущих изменений/улучшений в данном скрипте-автоматике с само-перезапуском новой версии данного скрипта (если такая есть в инете).
# Само-обновление скрипта выполняем ДО всех работ по обновлению ПО - для того чтобы в будещем можно было быстро остановить массовые обновления косячной новой версии ПО.
Push-Location
$Reg_param = "ETag_" + $Script_Name_no_ext # if ($Script_Name -match "(^.+)\..+") { $Reg_param = "ETag_" + $Matches[1] }
$URI = "https://github.com/BakanovM/Nornik-SOE/raw/main/OSD_scripts/$Script_Name"
# "Requesting info about my script from Internet with URI: $URI" | Out-File $logFile -Append
try { $Web = IWR -Uri $URI -Method Head -UseBasicParsing } # Запрашиваем инфу о скрипте в инете - для того чтобы узнать обновился ли он
catch { "Error when requesting info about my script from Internet ! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }
$Web_ETag = $Web.Headers.ETag.Trim('"')
$Reg_path = "HKLM:\SOFTWARE\Company" # ветка реестра со корпоративными параметрами в нашей организации (например название корп. заливки)
$Reg_value = (Get-ItemProperty $Reg_path -Name $Reg_param -EA 0).$Reg_param

if ($Web_ETag -ne $Reg_value) { # обнаружена новая версия скрипта в интернете
    "Found NEW version of script in Internet with ETag = $Web_ETag" | Out-File $logFile -Append
    Set-Location (Split-Path $Script_Path -Parent)
    try { IWR -Uri $URI -OutFile "$Script_Path.new" } # Загружаем обновленную версию скрипта скрипта из инетернет
    catch { "Error downloading updated script! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }

    New-Item $Reg_path -EA 0 | Out-Null; Set-ItemProperty $Reg_path -Name $Reg_param -Value $Web_ETag -EA 0

    "Self-updating of this Script $Script_Path and Re-Starting it again." | Out-File $logFile -Append;  
    # Не подошел вариант Invoke-Command -AsJob
    # Set-Location $Script_Dir; Rename-Item $Script_Name -NewName "$Script_Name.old"; Rename-Item "$Script_Name.new" -NewName $Script_Name; Remove-Item "$Script_Name.old"
    Start-Process "PowerShell.exe" -Arg "-Exec Bypass -Command `"& { sleep -Sec 5; cd $Script_Dir; ren $Script_Name -N `"$Script_Name.old`"; ren `"$Script_Name.new`" -N $Script_Name; del `"$Script_Name.old`";  .\$Script_Name After_Self_Update }`""
    Finish-Script; Return # покидаем старую версию скрипта, т.к. параллельно запущено его обновление и перезапуск.
}
Pop-Location 


# Задаем папку, в которой будут складываться инсталляторы приложения.
if ($env:Tools) { 
    $App_setup_path = (Split-Path $env:Tools -Parent) 
} else {
    $App_setup_path = $env:WinDir + '\Temp\'
}


# Configure VMware URL Content Redirection,  https://docs.vmware.com/en/VMware-Horizon/2111/horizon-remote-desktop-features/GUID-2D2D33AA-0B0A-45B4-B8A2-19CDCD02A634.html
# Install the URL Content Redirection Helper Extension for Microsoft Edge (Chromium) on Windows,  https://docs.vmware.com/en/VMware-Horizon/2111/horizon-remote-desktop-features/GUID-F88E146C-B1C4-46EC-880A-8AF5173A0F98.html


####### Авто-обновление клиента VMware Horizon - начало #######

# Проверяем есть ли запущенные процессы обновляемого приложения, которые могут помешать ходу его обновления.
$Process = Get-Process * -IncludeUserName | ? { $_.Company -match $App_Vendor -and $_.UserName -NotMatch "^NT AUTHORITY\\"  -and ($_.Description -match $App_Name -or $_.Product -match $App_Name)}`
| select ProcessName,Description,Product,UserName,StartTime,FileVersion,Path

if ($Process) {
    $Msg = "We will NOT try to update App '$App_Name'. Found running processes of this App:"; echo $Msg; $Msg | Out-File $logFile -Append
    # https://stackoverflow.com/questions/32252707/remove-blank-lines-in-powershell-output/39554482  https://stackoverflow.com/questions/25106675/why-does-removal-of-empty-lines-from-multiline-string-in-powershell-fail-using-r/25110997
    ($Process | select * -Excl UserName | sort -Unique Path | FT -Au | Out-String).Trim() | Out-File $logFile -Append -Width 500
} else {
$Msg = "There is NO running App '$App_Name' in user session."; echo $Msg; $Msg | Out-File $logFile -Append

try { # для обработки ошибок интернет запросов

# Интернет-Адрес JSON странички как хорошее начало поиска закачки актуальной версии приложения без привязки к его версии.
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/products/getRelatedDLGList?locale=en_US&category=desktop_end_user_computing&product=vmware_horizon_clients&version=horizon_8&dlgType=PRODUCT_BINARY"

$WebPage_getRelatedDLGList_JSON = (Invoke-WebRequest -Uri $URI -UseBasicParsing).Content | ConvertFrom-JSON
$Soft = ($WebPage_getRelatedDLGList_JSON.dlgEditionsLists | where name -Match "for Windows").dlgList;
$Soft_code = $Soft.code ;  $Soft_productId = $Soft.productId ;  $Soft_releasePackageId = $Soft.releasePackageId;  # Приходится дублировать в переменные, доступные для изменения - для случая подмены старой версии ПО под старую ОС.
# Можно обойтись единственным запросом интернет-страничики и анализировать параметр $Soft.releaseDate.Remove(10)

# для старой ОС Win10 LTSB 2016 будет ставить 8.4.0 2111.1 b19480429 2022-03-15
if ( $required_Old_version ) {
    "Detected OLD operating system - {0} {1} {2}. Therefore will be istalled OLD soft - Horizon client 8.4.0 2111.1" -f $Reg_HKLM_MS_WinNT.ProductName, $Reg_HKLM_MS_WinNT.ReleaseId, $WMI_OS.Version | Out-File $logFile -Append
    $Soft_code = "CART23FQ1_WIN_2111_1";  $Soft_productId = "1027";  $Soft_releasePackageId = "95669";  # $Soft.releaseDate = "2022-03-15"
    # т.е. страница загрузки будет https://customerconnect.vmware.com/en/downloads/details?downloadGroup=CART23FQ1_WIN_2111_1&productId=1027&rPId=95669
}

# реально в браузере проходим еще одну страничку - "customerconnect.vmware.com/en/downloads/details?downloadGroup=$($Soft.code)&productId=$($Soft.productId)&rPId=$($Soft.releasePackageId)"
$URI = "customerconnect.vmware.com/channel/public/api/v1.0/dlg/details?locale=en_US&downloadGroup=$($Soft_code)&productId=$($Soft_productId)&rPId=$($Soft_releasePackageId)"
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
        $Msg = "Already installed previous App '$($RIP.DisplayName)' $($RIP.DisplayVersion)"; echo $Msg; $Msg | Out-File $logFile -Append
        # ($RIP | select @("DisplayName", "DisplayVersion", "QuietUninstallString", "BundleProviderKey", "BundleUpgradeCode") | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500
        
        # Предварительная деинсталляция старой версии, для отката новой версии в условиях старой ОС (либо вообще, если инсталлятор приложения не поддерживает обновление "накатом")
        if ($Soft_orig_installer -gt $Soft2.fileName) {
        "Roll Back from current $Soft_orig_installer to the old version $($Soft2.fileName)" | Out-File $logFile -Append
        $Uninst_str = $RIP.QuietUninstallString + " /norestart" # https://docs.vmware.com/en/VMware-Horizon-Client-for-Windows/2206/horizon-client-windows-installation/GUID-2DDF9C24-A1E9-4357-A832-2A5A19352D61.html
        if ($Uninst_str -match '^"(.+?)" (.+)$') {
            "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start Uninstallation:  $Uninst_str" | Out-File $logFile -Append
            $Process = Start-Process -FilePath $Matches[1] -Arg $Matches[2] -Wait -PassThru;  $LastExitCode = $Process.ExitCode
        }
        "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Duration of deletion of old version of App is " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds,  ExitCode: $LastExitCode" | Out-File $logFile -Append
        }
        $Soft_Install_required = $true
    }
}
if ($Soft_Install_required) { # Если есть все условия для обновления приложения

if ($HostName -in $Comp_list_Exclude) { # исключение по имени компа
    "This computer $HostName is included in the list of exceptions for automatic update of software '$App_Name': $([string]$Comp_list_Exclude)" | Out-File $logFile -Append
} elseif ($Soft2.version -gt $App_Allowed_Ver) { # исключение слишком новой непротестированной версии ПО
    "New App version $($Soft2.version) is greater then allowed version $App_Allowed_Ver. Therefore we do NOT update App!" | Out-File $logFile -Append
} else {
# Решено приступить к установке/обновлению ПО.

$Msg = "from Internet is available actual App '$($Soft2.title) $($Soft2.version)', build $($Soft2.build), release Date $($Soft2.releaseDate), fileSize $($Soft2.fileSize)"; echo $Msg; $Msg | Out-File $logFile -Append
# ($Soft2 | select title, version, description, build, releaseDate, fileSize, description, thirdPartyDownloadUrl, sha256checksum | FL | Out-String).Trim() | Out-File $logFile -Append -Width 500

# Готовим папку для дистрибутива приложения
$Path = $App_setup_path + '\' + ($App_Name -replace " ", "_"); New-Item $Path -ItemType Directory -Force | Out-Null; Set-Location $Path

# Скачиваем EXE-инсталлятор софта в текущую папку
# -OutFile Specifies the output file for which this cmdlet saves the response body. Enter a path and file name. If you omit the path, the default is the current location. The name is treated as a literal path.
$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start downloading $($Soft2.fileName) from internet URL:`n$($Soft2.thirdPartyDownloadUrl)"; echo $Msg; $Msg | Out-File $logFile -Append
Invoke-WebRequest -Uri $Soft2.thirdPartyDownloadUrl -OutFile $Soft2.fileName

# На время обновления приложения заблокировать юзеру его запуск
# "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\VMware Horizon Client.lnk", "C:\Users\Public\Desktop\VMware Horizon Client.lnk", "C:\Program Files\VMware\VMware Horizon View Client\vmware-view.exe"

$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start the Installation - $($Soft2.fileName) $App_setup_params"; echo $Msg; $Msg | Out-File $logFile -Append
$Process = Start-Process -FilePath $Soft2.fileName -ArgumentList $App_setup_params -Wait -PassThru;  $LastExitCode = $Process.ExitCode
$Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - The installation time for a new version of App '$App_Name' is " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds with ExitCode $LastExitCode"
echo $Msg; $Msg | Out-File $logFile -Append
}}
} catch { # [System.Net.WebException] обработка ошибок интернет запросов
    $Msg = "Error in Web Requests - Exception.Status: {0}, Exception.Response.StatusCode: {1}, {2} `n{3}" -f $_.Exception.Status, $_.Exception.Response.StatusCode, $_.Exception.Message, $_.Exception.Response.ResponseUri.AbsoluteURI
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
# https://documentation.solarwinds.com/en/success_center/dameware/content/mrc_client_agent_service_installation_methods.htm
# $Process = Start-Process $Inst_Exe -Arg "-ap ""TRANSFORMS=$Inst_MST OVERWRITEREMOTECFG=1""" -Wait -PassThru -EV Err
# https://support.solarwinds.com/SuccessCenter/s/article/Install-DRS-and-MRC-from-the-command-line?language=en_US
# https://www.itninja.com/software/dameware-development/dameware-mini-remote-control-client-agent-service/7-1052
# $Process = Start-Process $Inst_Exe -Arg "/args ""/qn TRANSFORMS=$Inst_MST OVERWRITEREMOTECFG=1 reboot=reallysuppress SILENT=yes""" -Wait -PassThru -EV Err

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
    "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - End downloading $URI" | Out-File $logFile -Append
    Invoke-WebRequest -Uri $URI2 -OutFile $Inst_MST
    "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - End downloading $URI2" | Out-File $logFile -Append
    # -OutFile Specifies the output file for which this cmdlet saves the response body. Enter a path and file name. If you omit the path, the default is the current location. The name is treated as a literal path.
    
    if (-Not (Test-Path $Inst_MSI)) {
        "We can NOT start installation! Downloaded, but NOT exist MSI file - $Path\$Inst_MSI" | Out-File $logFile -Append
    } else {
        # Запускаем инсталляцию ПО как msiexec.exe MSI+MST. В случае успеха установки, когда ExitCode=0 - параметрами реестра донастраивает ПО.
        $Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") - Start the Installation: MSIexec.exe $App_setup_params"; echo $Msg; $Msg | Out-File $logFile -Append
        $Process = Start-Process "MSIexec.exe" -Arg $App_setup_params -Wait -PassThru -EV Err
    }
    if ($Err) { 
        "Installation is NOT executed normally. Error $Err" | Out-File $logFile -Append 
    } else {    $ExitCode = $Process.ExitCode    $Msg = "$(Get-Date -format "yyyy-MM-dd HH:mm:ss") Duration of Installation for this App: " + [int]($process.ExitTime - $process.StartTime).TotalSeconds + " seconds,  ExitCode: " + $ExitCode    echo $Msg; $Msg | Out-File $logFile -Append    if ($ExitCode -eq 0) {        if (Test-Path $App_Reg_Path) { $Msg = Get-ItemProperty $App_Reg_Path -EA 0 } else { $Msg = "Not found registry key !" }; Write-Debug "DameWare Settings in registry $Reg_path : `n $Msg"; 

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

if ($ExitCode -eq 0) { # Если была успешня инсталляция
# Перезапускаем службу чтобы сразу после установки ПО оно заработало с заданными настройками.
Get-Service DWMRCS | Restart-Service # DameWare Mini Remote Control
}

####### Установка/обновление DameWare - закончено #######


$Msg = @() # Различные признаки необходимости перезапуска системы описаны тут: https://adamtheautomator.com/pending-reboot-registry/
if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $Msg += "RebootPending" }
if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending") { $Msg += "PackagesPending" }
# HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager
if ($Msg) { $Msg = "Detected Component Based Servicing pending operations - " + [string]$Msg; echo $Msg; $Msg | Out-File $logFile -Append }


$ProgressPreference = $Progr_Pref # восстанавливаем прогресс бар
Finish-Script; Return
