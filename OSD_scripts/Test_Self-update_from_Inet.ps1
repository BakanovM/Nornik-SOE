<# Скрипт обслуживания корп. ПО и его конфигуририрование при работе специальной заливки для удаленки за пределами КСПД.
Тест само-обновления скрипта через интернет с последующим перезапуском скрипта
Автор - Максим Баканов 2022-10-25
#>

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
try { $Web = IWR -Uri $URI -Method Head -UseBasicParsing } # Запрашиваем инфу о скрипте в инете - для того чтобы узнать обновился ли он
catch { "Error request info for updated script! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }
$Web_ETag = $Web.Headers.ETag.Trim('"')
$Reg_path = "HKLM:\SOFTWARE\Company" # ветка реестра со корпоративными параметрами в нашей организации (например название корп. заливки)
$Reg_value = (Get-ItemProperty $Reg_path -Name $Reg_param -EA 0).$Reg_param

if ($Web_ETag -ne $Reg_value) { # обнаружена новая версия скрипта в интернете
    "Found NEW version of script in Internet with ETag = $Web_ETag" | Out-File $logFile -Append
    Set-Location (Split-Path $Script_Path -Parent)
    try { IWR -Uri $URI -OutFile "$Script_Path.new" } # Загружаем обновленную версию скрипта скрипта из инетернет
    catch { "Error downloading updated script! $($_.Exception.Message)" | Out-File $logFile -Append; Finish-Script; Return }

    New-Item $Reg_path -EA 0 | Out-Null; Set-ItemProperty $Reg_path -Name $Reg_param -Value $Web_ETag -EA 0

    echo "Self-updating of this Script $Script_Path" | Out-File $logFile -Append;  # Не подошел вариант Invoke-Command -AsJob
    # Set-Location $Script_Dir; Rename-Item $Script_Name -NewName "$Script_Name.old"; Rename-Item "$Script_Name.new" -NewName $Script_Name; Remove-Item "$Script_Name.old"
    Start-Process "PowerShell.exe" -Arg "-Exec Bypass -Command `"& { sleep -Sec 5; cd $Script_Dir; ren $Script_Name -N `"$Script_Name.old`"; ren `"$Script_Name.new`" -N $Script_Name; del `"$Script_Name.old`";  .\$Script_Name After_Self_Update }`""
    Finish-Script; Return # покидаем старую версию скрипта, т.к. параллельно запущено его обновление и исполнение
}
Pop-Location 

"Now we are working with new version of script" | Out-File $logFile -Append
