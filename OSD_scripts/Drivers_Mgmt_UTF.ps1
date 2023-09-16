<# Мои наработки по вопросам автоматизации всех процессов по теме поддержки драйверов: 
- загрузка и установка драйверов на компьютере новой модели с корп. заливкой;
- экспорт всех установленных драйверов, исключение неиспользуемых и дублирующихся драйверов разных версий;
- архивация всех этих драйверов на сетевой ресурс и обратная распаковка на сайт-сервере, перенос архива с драйверами в хламо-свалку в Мск;
- добавление драйверов в базу ConfMgr, наполнение CM DrvPackage, распространение контента, добавление шага в TaskSeq;
- обновление уже имеющегося драйвер-пака для случаев возврата исключенных драйверов и для случая актуализации обновленного набора драйверов;
- выбор и установки драйверов во время заливки;

Баканов Максим, 2023-07-10
#>


$Corp_Proxy = "vMs06wCG01:18080"; # Корпоративный прокси сервер без авторизации. в НН ГО он ограничивает по категориям ForcePoint

$Folder_with_Exported_Drivers = "C:\Setup\Drivers_Exported_with_PoSh_DISM" # папка на тестовом компе, куда будут экспортироваться все драйвера для новой модели
$FileName_Export = "Export_WinDrivers_with_PoSh_DISM" # название файлов, с подробностями об отдельном действии - экспорт всех драйверов из системы
$Exclude_folder = "!Excluded_Drv_not_used" # имя папки, в которую я решил отодвинуть часть экспортированных драйверов, которые не нужно добавлять в драйвер-пак

# сетевой путь для сохранения драйверов всех моделей в виде архивов
$Drivers_Archive_path = "\\VMSHQMDT01\Drv" # вариант первоначальный - не подошел из-за недоступности ресурса для тестовых компов
$Drivers_Archive_path = "\\npr.nornick.ru\er$\ИТ\SOE\Drv" # вариант основной из-за широкой доступности DFS ресурса
$Drivers_Archives_added_to_CM = "\\VMSHQMDT01\Drv\!added_to_ConfMgr" # сетевой путь куда перемещаются архивы драйверов после их добавления в ConfMgr

if (-Not $env:SMS_ADMIN_UI_PATH) { # начало блока работы на тестовом компьютере
# %SMS_ADMIN_UI_PATH% is an environment variable on a machine where SCCM Admin console is installed.

# Сбор информации о комьютере, полезной для автоматизации установки драйверов
$WMI_CompSys = gwmi Win32_ComputerSystem; $Comp_Manuf = $WMI_CompSys.Manufacturer; $Comp_Model = $WMI_CompSys.Model
$WMI_SysInfo = gwmi -namespace root\wmi -class MS_SystemInformation; $Comp_SKU = $WMI_SysInfo.SystemSKU
$WMI_BIOS = gwmi Win32_BIOS; $BIOS_ver = $WMI_BIOS.SMBIOSBIOSVersion; if ($WMI_BIOS.ReleaseDate -match "^(\d{4})(\d{2})(\d{2})") { $BIOS_Date = $Matches[1] + '-' + $Matches[2] + '-' + $Matches[3] }
$WMI_BaseBoard = gwmi Win32_BaseBoard;  $MoBo_Manuf = $WMI_BaseBoard.Manufacturer;  $MoBo_Product = $WMI_BaseBoard.Product;  $MoBo_SerialNum = $WMI_BaseBoard.SerialNumber

$BIOS_SerialNum = $WMI_BIOS.SerialNumber
$Comp_MoBo = $WMI_SysInfo.BaseBoardProduct

# Имя хоста с учетем заглавных и строчных символов как выдает HostName.exe
$CompName = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters\" -Name "HostName").HostName 

#(gwmi Win32_ComputerSystem | select Manufacturer,Model), (gwmi -namespace root\wmi -class MS_SystemInformation | select SystemSKU) | FL | Out-File "Model_WMI_identification.txt"
# $Comp_MoBo_all = $WMI_SysInfo.BaseBoardManufacturer + ' ' + $WMI_SysInfo.BaseBoardProduct + ' ' + $WMI_SysInfo.BaseBoardVersion

$Comp_Manuf_my = $Comp_Manuf

# Название производителя HP я встречал по-разному написанным
if ($Comp_Manuf -match "Hewlett|^HP$|^HP \w") { $Comp_Manuf_my = 'HP' }

if ($Comp_Manuf -match "^Dell$|^Dell Inc") { $Comp_Manuf_my = 'Dell' }

if ($Comp_Manuf -match "^Lenovo") { $Comp_Manuf_my = 'Lenovo' }

if ($Comp_Manuf -match "^Asus$|^ASUSTeK") { $Comp_Manuf_my = 'Asus' } # "ASUSTeK COMPUTER INC."


$Comp_Model_my = $Comp_Model

# Для некоторых производителей преобразовываем код модели в понятное название модели
if ($Comp_Manuf_my -eq 'HP') { # название моделей HP сокращаем
    $Comp_Model_my = $Comp_Model_my -replace "^HP ","" # убираем вендора из названия модели
    $Comp_Model_my = $Comp_Model_my -replace "MicroTower PC$","MT" # у компании HP есть только MicroTower, понятия MiniTower нету, поэтому сокращение логичное
    $Comp_Model_my = $Comp_Model_my -replace "Small Form Factor PC$", "SFF"
}

if ($Comp_Manuf_my -eq 'Dell') { # название моделей Dell сокращаем
    $Comp_Model_my = $Comp_Model_my -replace "^Dell ","" # убираем вендора из названия модели 
}

if ($Comp_Manuf_my -eq 'Lenovo') { # название моделей Lenovo переводим из кодового обозначения
    if ($Comp_Model -match "^11QC") { $Comp_Model_my = "V50t 13IOB G2" } # Comp_Model=11QC0013RU, Comp_SKU="LENOVO_MT_11QC_BU_Lenovo_FM_V50t Gen 2-13IOB", sn="PC29L572", Lenovo Desktop V50t-13IOB G2 (Type 11QC)
    if ($Comp_Model -match "^11EF") { $Comp_Model_my = "V50s 07IMB" } # Comp_Model=11EF000QRU, Comp_SKU="LENOVO_MT_11EF_BU_Lenovo_FM_V50s-07IMB", sn="YL01BREF", Lenovo Desktop V50t-07IMB (Type 11EF)
    if ($Comp_SKU -match "LENOVO_\w+_$Comp_Model_(\w|_)+_(.+)") { $Comp_Model_my = $Matches[2] } # Comp_Model=20WE, Comp_SKU="LENOVO_MT_20WE_BU_idea_FM_ThinkBook 14s Yoga ITL", Comp_MoBo=LNVNB161216,  SerialNum=MP2597ZF
}

if ($Comp_Manuf_my -eq 'Asus') { # название моделей брендовых моделей Asus сокращаем
    if ($Comp_Model -match "(.+ )(?<one>\S+)_?\k<one>") { $Comp_Model_my = ($Matches[1] + $Matches['one']) } # убираем дублирование модели материнки в названии модели компаю Например для "ZenBook UX535LI_UX535LI"
    elseif ($Comp_Model -match "(\w+)_ASUSLaptop ($Comp_MoBo)|($($Comp_MoBo)_\w+)|(\w+_$Comp_MoBo)$") { $Comp_Model_my = ($Matches[1] + ' ' + $Comp_MoBo) } # убираем "_ASUSLaptop" и оставляем один вариант из двух моделей материнки Model1_Model2. Например для "Vivobook_ASUSLaptop X7600PC_N7600PC"
}

if ($Comp_Manuf -eq "ASUS" -and $Comp_Model -match "System Product Name") { # попытка по модели материнки сделать предположение о модели компа Nerpa
    # для Asus материнок $MoBo_Manuf -eq "ASUSTeK COMPUTER INC."
    if ($Comp_MoBo -eq "PRIME B560M-K") { $Comp_Manuf_my = "Nerpa"; $Comp_Model_my = "I750 Baltic Ladoga" } # Wnr890100158644
    # Настольные ПК Nerpa BALTIC — экономичное решение для офиса и для удаленной работы.
    # Nerpa LADOGA — семейство высокопроизводительных графических и рабочих станций для выполнения широкого спектра ресурсоемких задач - для работы с большими объемами данных, инженерными расчетами, графикой и анимацией видеомонтажа и 3D-моделирования.
}

$Comp_Model_my_ = $Comp_Model_my -replace " ","_" # по мере доработки скрипта решил что мою модель буду сохранять не с подчеркиваниями '_', а с пробелами ' '

$Cur_date = Get-Date -format "yyyy-MM-dd" # Get-Date -format "yyyy-MM-dd HH:mm:ss"
$WorkFolder = "$Folder_with_Exported_Drivers\$Comp_Manuf_my\$Comp_Model_my_\$Cur_date" 
if (-not (Test-Path $WorkFolder)) { New-Item $WorkFolder -ItemType Directory | Out-Null }
Set-Location $WorkFolder


# Сохраняем собранную инфу в XML файл так чтобы потом легко её можно было загрузить в другом скрипте вместе с типами данных
$OrderedDictionary = [ordered]@{} # Создаем PoSh объект со свойствами и значениями из уже имеющихся переменных
"CompName", "Comp_Manuf", "Comp_Model", "Comp_Manuf_my", "Comp_Model_my", "Comp_SKU", "Comp_MoBo", "BIOS_ver", "BIOS_Date", "BIOS_SerialNum", "MoBo_Manuf", "MoBo_Product", "MoBo_SerialNum" |`
 % { $OrderedDictionary.Add($_, (Get-Variable $_).Value) };  $Comp_Info = New-Object -TypeName PSObject -Property $OrderedDictionary; $Comp_Info

echo "Attention! If my associations of computer vendor and computer model are NOT correct, then please stop this script and fix PoSh code. Otherwise we can continue."; pause

if (-not (Test-Path "Computer_System_Info.xml")) {
$Comp_Info | Export-Clixml "Computer_System_Info.xml" # Creates a Common Language Infrastructure (CLI) XML-based representation of an object(-s) and stores it in a file.
# $Comp_Info_test = Import-Clixml "Computer_System_Info.xml" # imports a Common Language Infrastructure (CLI) XML file with data that represents Microsoft .NET Framework objects and creates the PowerShell objects.
}

# увеличиваем счетчик количества циклов обновлений с перезагрузками
$Reg_path = "HKLM:\Software\Company" # https://stackoverflow.com/questions/5648931/test-if-registry-value-exists
if ( (Get-Item $Reg_path -EA Ignore).Property -notcontains "WU_cycle_num" ) {
    if (-Not (Test-Path $Reg_path)) { New-Item $Reg_path -Force | Out-Null }
    New-ItemProperty $Reg_path -Name "WU_cycle_num" -PropertyType DWord -Force -Value 1 | Out-Null # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-itemproperty
    $WU_cycle_num = 1
} else {
    $WU_cycle_num = (Get-ItemPropertyValue $Reg_path -Name "WU_cycle_num") + 1
    Set-ItemProperty $Reg_path -Name "WU_cycle_num" -Force -Value $WU_cycle_num
}


####################################################
# эксперименты с устройствами через WMI/CIM классы
# $CIM_VideoController = Get-CimInstance Win32_VideoController # список графических адаптеров для тех устройств у которых Status=OK и драйвера работают

$CIM_PnPEntity = Get-CimInstance Win32_PnPEntity # остальные свойства либо пустые, либо с одинаковым значением, либо дублируют уже выбранные - "Caption", "InstallDate", "DeviceID", "Availability", "ConfigManagerUserConfig", "CreationClassName", "ErrorCleared", "ErrorDescription", "LastErrorCode", "PowerManagementCapabilities", "PowerManagementSupported", "StatusInfo", "SystemCreationClassName", "SystemName", "Present"

echo "Query the Win32_PnPSignedDriver WMI class. It provides digital signature information about drivers. Please wait a few seconds .."
$CIM_PnPSignedDriver = Get-CimInstance Win32_PnPSignedDriver # исполняется 10 секунд
# остальные свойства либо пустые, либо с одинаковым значением, либо дублируют уже выбранные - Caption, Description, InstallDate, Name, Status, CreationClassName, Started, StartMode, SystemCreationClassName, SystemName, DevLoader, IsSigned

echo "Drivers Update cycle number is $WU_cycle_num. Now we have $(($CIM_PnPEntity | ? Status -ne 'OK').count) problem/unknown devices (info from Win32_PnPEntity)."

$DevHwId_pattern = "(PCI\\VEN_(\w|\d){4}&DEV_(\w|\d){4})((&SUBSYS_(\w|\d){4})|(&CC_(\w|\d){4}))?" # шаблон строки-индентификатора устройства PCI
$Display_Adapters_from_PnPEntity = $CIM_PnPEntity | ? { $_.Description -match "^3D" -or $_.PNPClass -eq "Display" } | where PNPDeviceID -Match $DevHwId_pattern # all physic devices with PNPClass="Display" or Description="3D-видео контроллер"
$Display_Adapters_from_PnPSignedDriver = $CIM_PnPSignedDriver | ? { $_.DeviceName -match "^3D" -or $_.DeviceClass -eq "Display" } | where HardWareID -Match $DevHwId_pattern # all physic devices with DeviceClass="Display" or DeviceName="3D Video Controller"

if ($WU_cycle_num -eq 1) {
    # echo "Before drivers updating we have $(($CIM_PnPEntity | ? Status -ne 'OK').count) unknown devices."

    $CIM_PnPEntity | select "PNPClass", "Service", "Manufacturer", "Description", "Name", "Status", "ConfigManagerErrorCode", "PNPDeviceID", "HardwareID", "CompatibleID", "ClassGuid" | Export-Clixml "CIM_PnPEntity_before_drivers_update.xml"
    $CIM_PnPSignedDriver | select DeviceClass, DeviceName, FriendlyName, DriverProviderName, DriverDate, DriverVersion, DriverName, Manufacturer, InfName, Location, HardWareID, DeviceID, CompatID, PDO, ClassGuid, IsSigned, Signer | Export-Clixml "CIM_PnPSignedDriver_before_drivers_update.xml"

    echo "The following Display Adapters (as PCI devices) were found in the system:"
    $Display_Adapters_from_PnPEntity | select @{n="HWid"; e={if ($_.PNPDeviceID -match $DevHwId_pattern) { $Matches[1] } }}, Description 
    # Без установленных драйверов граф адаптеры могут называться как "Базовый видеоадаптер (Майкрософт)". Примеры HWid для NVidia и Intel : PCI\VEN_10DE&DEV_2488, PCI\VEN_8086&DEV_9BC5

    # Специфика устройств NVidia графических адаптеров
    $HWid_Dev_Nvidia = "VEN_10DE" # HWid код вендора NVidia
    $NV_ListDevices_files = "^(.+)_ListDevices.txt" # Сама компания NVidia внутри своих exe-инcталляторов драйверов предоставляет файлы ListDevices.txt с описанием всех моделей GPU
    # $DevHwId_NV_in_ListDevices = '(DEV_(\w|\d){4}((&SUBSYS_(\w|\d){8})|(&CC_(\w|\d){4}))?)\s+"(.+)"'
   
    $NVidia_Adapter_from_PnPEntity = $Display_Adapters_from_PnPEntity | where PNPDeviceID -Match $HWid_Dev_Nvidia

    if ($NVidia_Adapter_from_PnPEntity) { # Обнаружен видеоадаптер NVidia, приступаем к установке
    $NVidia_Adapter_from_PnPEntity | select Description, PNPDeviceID, HardwareID, CompatibleID | FL

    # Пример отбора самых подходящих HWid имеющегося в системе NVidia GPU, содержащих Ven&Dev, Ven&Dev&SubSys, Ven&Dev&CC
    $DevHwId_NV_pattern = "PCI\\$HWid_Dev_Nvidia&(DEV_(\w|\d){4}((&SUBSYS_(\w|\d){8})|(&CC_(\w|\d){4}))?)$"
    $NVidia_Adapter_from_PnPEntity.HardwareID + $NVidia_Adapter_from_PnPEntity.CompatibleID | ? { $_ -Match $DevHwId_NV_pattern }

    # Но мы будет ориентироваться только на HWid в формате Ven&Dev&SubSys поскольку именно так принято у NVidia в файлах ListDevices.txt
    $DevHwId_NV_pattern = "PCI\\$HWid_Dev_Nvidia&((DEV_(\w|\d){4})&(SUBSYS_(\w|\d){8}))$"
    $DevHwId_NV_Dev = $DevHwId_NV_SubSys = ""
    $NVidia_Adapter_from_PnPEntity.HardwareID | % { if ($_ -Match $DevHwId_NV_pattern) { $DevHwId_NV_Dev = $Matches[2]; $DevHwId_NV_SubSys = $Matches[4]; $DevHwId_NV = $_ } }
    if (-not $DevHwId_NV_SubSys) { echo "Internal Error! Not found DevHwId_NV_Dev and DevHwId_NV_SubSys !"; pause }

    $DevHwId_NV_in_ListDevices2 = "($DevHwId_NV_Dev(&$DevHwId_NV_SubSys)?)\s+""(.+)"""


    # https://michlstechblog.info/blog/powershell-escape-a-string-for-regular-expression/
    [System.Text.RegularExpressions.Regex]::Escape("Sample * with a .special symbol ? (must be escaped) OK")

    $SelStr = Get-ChildItem "T:\BIG_size_drv\Video_NVidia" | where Name -Match $NV_ListDevices_files | % { Select-String -Path $_.Name -Pattern $DevHwId_NV_in_ListDevices3 } `
     | select @{n="NVidia_installator";e={if ($_.Filename -match $NV_ListDevices_files) {$Matches[1]}}}, @{n="DevHwId_NV";e={$_.Matches.Groups[1].Value}}, @{n="Device_Name";e={$_.Matches.Groups[3].Value}}
    echo "for NVidia graphics adapter in this system found DevHwId_NV: $DevHwId_NV."
    
    if (-Not $SelStr) { echo "There is NOT found Suitable Installators when parsing files ListDevices.txt !"; pause }
    
    echo "List of Suitable Installators:";  $SelStr | FT -Au

    $NV_installator = $SelStr | sort NVidia_installator,DevHwId_NV | select -Last 1
    echo "The best suitable software package is selected as follows:"; $NV_installator |FL
    # Оказалось неправильно выбирать только один подходящий инсталлятор по принципу самой свежей версии, т.к. даже при совместимости по HWid из двух драйверов -desktop- и -quadro-rtx-desktop-notebook только один подходящий

    $P = Start-Process ($NV_installator.NVidia_installator + ".exe") -Arg "-s" -Wait -PassThru -EV Err; $ExitCode = $P.ExitCode; 
    if ($Err) { "Internal Error: Installator is NOT executed normally from '$((Get-Location).Path)' !";  pause; } #Stop-Transcript; Exit 12304 }
    echo "Installation time of NVidia driver was $([int]($P.ExitTime - $P.StartTime).TotalSeconds) seconds,  ExitCode: $ExitCode"
    # if ($ExitCode) { Stop-Transcript; Exit $ExitCode }
    } # Закончили с установкой видеоадаптера NVidia

    # silent install without GeForce Experience https://forums.developer.nvidia.com/t/quadro-driver-only-install/67344
    # https://enterprise-support.nvidia.com/s/article/Silent-Install-of-GRID-VM-Driver-for-Windows  
    # https://www.dell.com/support/kbdoc/en-uk/000066381/how-to-customize-a-silent-install-of-nvidia-drivers-through-sccm
    # https://www.esense.be/33/2019/06/04/nvidia-drivers-silent-install/

    # Uninstall NV components "C:\WINDOWS\SysWOW64\RunDll32.EXE" "C:\Program Files\NVIDIA Corporation\Installer2\InstallerCore\NVI2.DLL",UninstallPackage Display.GFExperience FrameViewSdk -silent -deviceinitiated


    # Специфика устройств Intel графических адаптеров
    $HWid_Dev_Intel = "VEN_8086" # HWid код вендора Intel
    $Intel_Display_Adapter_PnPEntity = $Display_Adapters_from_PnPEntity | where PNPDeviceID -Match $HWid_Dev_Intel

    if ($Intel_Display_Adapter_PnPEntity) { # Обнаружен видеоадаптер Intel, приступаем к установке
    }
    if ($false) {
    $archive_file = Get-Item "C:\Setup\Video_Intel\gfx_win_101.4502.exe"
    
    $Output_Dir = $archive_file.DirectoryName + '\' + $archive_file.BaseName
    $Args_for_7zip = "x -r -o`"$Output_Dir`" $($archive_file.FullName) *.inf readme.txt";  echo "$7Zip_exe $Args_for_7zip"
    $P = Start-Process $7Zip_exe -Arg $Args_for_7zip -PassThru -Wait 
    if ($P.ExitCode -ne 0) { echo "Error extracting of exported drivers to '$Output_Dir' ! 7Zip returns ExitCode=$($P.ExitCode) !" } else { echo "Extracting of $($archive_file.Name) was successful." }

    }

}


##########################################
# Приступаем к работе с обновлениями !

echo "Enable system proxy WinHTTP without auth as $Corp_Proxy." # Включаем системный прокси без авторизации
$Reg_WinUpd_policy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate";  $Reg_WinUpd_leaf = Split-Path $Reg_WinUpd_policy -Leaf
netsh winhttp set proxy proxy-server="$Corp_Proxy"
if (Test-Path $Reg_WinUpd_policy) { 
    Rename-Item $Reg_WinUpd_policy -NewName ($Reg_WinUpd_leaf+'2') 
    Restart-Service WUAuserv
}

[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy("http://"+$Corp_Proxy) # задаем прокси для всех Web-запросов в PoSh-командлетах Invoke-WebRequest
# Тут можно выполнить действия, при которых система требует доступа в интернет не через прокси из настроек браузера

# Задаем настройки прокси у браузера IE/Edge для текущего пользователя - этим оказывается пользуется Win Update Agent для закачки обновлений
$Reg_Proxy_curUser = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"
Set-ItemProperty $Reg_Proxy_curUser -Name "ProxyEnable" -Value 1 -Force
New-ItemProperty $Reg_Proxy_curUser -Name "ProxyServer" -PropertyType String -Value $Corp_Proxy -Force | Out-Null
New-ItemProperty $Reg_Proxy_curUser -Name "ProxyOverride" -PropertyType String -Value "<local>" -Force | Out-Null


try { Import-Module PSWindowsUpdate }
catch { # на случай исполнения не в корп заливке, а в чистой OEM-винде, когда нужно загружать провайдер пакетов NuGet и модуль PSWindowsUpdate

# корневой доменный сертификат нужен чтобы для HTTPS-загрузки провайдера пакетов в условиях работу через корп прокси, подменяющего сертификаты.
Import-Certificate -FilePath "C:\Setup\nn-root-ca.cer" -CertStoreLocation "Cert:\LocalMachine\Root"

echo "Find-PackageProvider NuGet"; Find-PackageProvider NuGet -Force | select Name, Version, Status, ProviderName, Summary, FromTrustedSource, Source, Links
echo "Install-PackageProvider NuGet"; Install-PackageProvider -Name "NuGet" -Force
(Get-PackageProvider NuGet).ProviderPath

echo "Install-Module and Update-Module PowerShellGet";  Install-Module -Name PowerShellGet -Force; Update-Module -Name PowerShellGet -Force

echo "Install-Module PSWindowsUpdate"; 
Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -Confirm

Set-ExecutionPolicy -ExecutionPolicy Bypass -Force
Import-Module PSWindowsUpdate

# Register-PSRepository -Default; Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

}

do { $WU_status = ""; # цикл попыток запросить список доступных обновлений. повторения могут потребоваться из-за недоступности интернета.

# Сканирование доступных обновлений драйверов - может не с первого раза вернуть список
echo "Start WUagent scan for updates ..."
$WU_avail = Get-WindowsUpdate -UpdateType Driver # Get-WindowsUpdate -Category "Drivers"

if ($WU_avail) { # если после сканирования найдены обновления драйверов, то приступаем к их установке
echo "Found the following available updates:"
$WU_avail | select Size, DriverClass, DriverModel, Title, Description, DriverHardwareID  | FT -Au

$WU_avail | ? DriverClass -ne $null | select Size, DriverClass, DriverModel, Title, Description, LastDeploymentChangeTime, DriverVerDate, DriverHardwareID, DriverManufacturer |` # Out-GridView
Export-Csv -Path "Win_Updates_available-$WU_cycle_num.csv" -Encoding Unicode -NoTypeInformation -Delimiter ';' 

$WU_not_driver = $WU_avail | ? DriverClass -eq $null 
if ($WU_not_driver) {
    echo "List of Windows Updates that is NOT driver:"
    $WU_not_driver | select KB, Size, Title, Description, LastDeploymentChangeTime, @{n="Category";e={ $_.Categories | select -Exp Name}}, @{n="Categories_Descr";e={ $_.Categories | select -Exp Description}}
} else { echo "After Win Update Scan we have only drivers updates." }

# Основной процесс загрузки и установки драйверов от Майкрософт
$WU_installed = @(); do {
echo "Download and Install all Drivers Updates ..." # если не задать прокси у браузера, то командлет зависает на начале закачки первого же обновления драйвера
try { $WU_installed += Get-WindowsUpdate -Install -UpdateType Driver -AcceptAll -ForceDownload -ForceInstall -IgnoreReboot;  $WU_install_OK = $true }
catch {
    echo "Get-WindowsUpdate exception $($Error[0].Exception.Message) `n"; pause #  "Исключение из HRESULT: 0x80248007",  https://www.prajwaldesai.com/fix-windows-update-error-0x80248007/
# $Error[0].Exception.GetType().FullName = System.Runtime.InteropServices.COMException, FullyQualifiedErrorId : System.Runtime.InteropServices.COMException,PSWindowsUpdate.GetWindowsUpdate
    # это же исключение при установке [19/23] Intel Corp - System - 10.29.0.7767 102Mb
# после Get-WindowsUpdate exception Исключение из HRESULT: 0x80248007 никакие обновления не были установлены, перезагрузка не требуется и значит логику дальнейших действий нужно менять
    $WU_install_OK = $false
}
} while (-Not $WU_install_OK)

echo "The following updates were installed:"
$WU_installed | select Result,Size,Title,Description,DriverModel,DriverClass,DriverVerDate,@{n="Problem";e={$_.DeviceProblemNumber}},@{n="Reboot";e={$_.RebootRequired}},DeploymentAction | FT -Au

$WU_installed | select Result,Size,Title,Description,DriverClass,DriverHardwareID,DriverManufacturer,DriverProvider,DriverModel,DriverVerDate,DeviceProblemNumber,RebootRequired,DeploymentAction `
| Export-Clixml "Installed_Driver_Updates-$WU_cycle_num.xml"

if (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" ) { 
    $WU_status = "After installing of Driver Updates system Reboot is Required! Please restart Windows and run this script again ...";  echo $WU_status
    # https://www.powershellgallery.com/packages/PendingReboot/0.9.0.6
    pause
    shutdown -r -f -t 10
    pause
} else {
    $WU_status = "OK. After installing of Driver Updates system Reboot is NOT Required."; echo $WU_status
}

} else {
    echo "Now Win Update Scan returns NO avaliable driver updates."
    
# Пытаемся понять требуется ли еще повторить цикл установки обновлений

# Проверяем ситуацию 1: через прокси инет доступен, но сканирование доступных обновлений через GUI ругается ошибкой, а сканирование через Get-WindowsUpdate успешно возвращает пустой список (без ошибки)
    # Push-Location; Set-Location "C:\Windows\Logs\WindowsUpdate\"; Pop-Location
    $WU_etl_files = Get-Item "C:\Windows\Logs\WindowsUpdate\*.etl" | sort LastWriteTime | select -Last 1
    $WU_Log = "$WorkFolder\WinUpdate_avail.log"
    Get-WindowsUpdateLog -ETLPath $WU_etl_files.FullName -LogPath $WU_Log
    $SS = Select-String -Path $WU_Log -Pattern "(Agent\s+\*FAILED\*)|(ComApi\s+\* END \*)"
    if ($SS.Count -le 1) {  
        echo "There is NO errors in ETL logs of WinUpd agent."; pause
# Проверяем ситуацию 2: когда после установки обновлений драйверов отсутствует PendingRebootRequired, повторное сканирование обновлений возвращает 0 доступных, но при этом остались Unknown устройства 
    } else {
        echo "Found WinUpd agent errors in $($WU_etl_files.FullName):"
        $SS.Line | % { if ($_ -match "(\d|\s|\.|:)+\s+(\w+)\s+(.*)") { $Msg = "$($Matches[2]) $($Matches[3])";  echo $Msg } }
        $WU_status = "Error scan of available updates: $Msg"
        echo "`n Please provide Internet access by manually setting up an Internet connection. Will try again Microsoft updates scan."; pause
    }
}

} while ($WU_status -notmatch "^OK")

echo "There is NO need to repeat the driver update loop from Microsoft."; pause


# https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax
# Enumerate all devices on the system. Command available starting in Windows 10 version 1903. /problem [<code>] - filter by devices with problems or filter by specific problem code
$PnPUtil_out = PnPUtil.exe /enum-devices /problem
# с $PnPUtil_out можно работать как со строкой так и с массивом объектов. $PnPUtil_out.GetType() returns Name=Object[], BaseType=System.Array
$num_of_problem_devices = ($PnPUtil_out -Match "Состояние:\s+Проблема").count  #  [string] -OR $PnPUtil_out -Match "Состояние:\s+Проблема|Код ошибки:\s+28 \(0x1C\) \[CM_PROB_FAILED_INSTALL\]"

echo "Now we have $num_of_problem_devices problem/unknown devices (info from PnPUtil.exe)."

while ($num_of_problem_devices) { # все еще остаются проблемные устройства
    Write-Debug "There are still unknown devices in the system !"

if ($Comp_MoBo -eq "PRIME B560M-K") { # Попытка распознать компы Nerpa по модели материнки - в первом упрощенном приближении
echo "found Comp MoBo 'PRIME B560M-K', asuming this is Nerpa. Try download drivers from internet."

echo "Intel Chipset INF Utility - download and install ..."
# Intel Chipset INF Utility, ID 19347, Date 2023-03-28, v10.1.19444.8378 (at the moment 22.04.2023), from https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html
$URI = "https://downloadmirror.intel.com/774764/SetupChipset.exe"
if ($URI -match ".+\/(\S+\.exe)$") { $exe_name = $Matches[1] };  $exe_path = "$Env:WinDir\Temp\$exe_name"
Invoke-WebRequest $URI -OutFile $exe_path
$P = Start-Process $exe_path -Arg "-s -norestart" -Wait -PassThru

echo "Intel Serial IO I2C Host Controller driver - download and install ..."
# https://www.intel.com/content/www/us/en/download/773396/intel-serial-io-driver-for-windows-10-64-bit-windows-11-for-the-intel-nuc-11-pro-kits-mini-pcs-nuc11tn.html
# Intel® Serial IO Driver for Windows® 10 64-bit & Windows 11* for the Intel® NUC 11 Pro Kits & Mini PCs - NUC11TN, ID 773396, 2023-03-13, v30.100.2129.8 (Latest at the moment 22.04.2023)
$URI = "https://downloadmirror.intel.com/773397/SerialIO-Win10_Win11-30.100.2129.8.zip";  $path = "$Env:WinDir\Temp\Intel_SerialIO"
if ($URI -match ".+\/(\S+\.(exe|zip|cab|msi))$") { $downloaded_name = $Matches[1] };  $downloaded_path = "$path\$downloaded_name";  New-Item $path -ItemType Directory -Force| Out-Null
Invoke-WebRequest $URI -OutFile $downloaded_path
Expand-Archive $downloaded_path -Dest $path -Force
$P = Start-Process "$path\SetupSerialIO.exe" -Arg "-s" -Wait -PassThru
}

# список HWid для "Intel Thunderbolt Controller" - добыт из INF файла драйвера, скачанного с офиц сайта Intel.com
$Dev_Vendor = "PCI\VEN_8086&DEV_"; $DevHWids = "1134 1137 1575 1577 15BF 15D2 15D9 15DC 15DD 15DE 15E8 15EB 463E 466D 7EB2 7EC2 7EC3 8A0D 8A17 8AA0 8AA3 8AB0 8AB3 9A1B 9A1D 9A1F 9A21 A73E A76D" -split ' ' | % { $Dev_Vendor + $_ }
$Dev_Intel_Thunderbolt = $CIM_PnPEntity | where Status -ne 'OK' | ? { $_.PNPDeviceID -match $DevHwId_pattern -and ($_.PNPDeviceID).Substring(0,21) -in $DevHWids }
if ($Dev_Intel_Thunderbolt) { # попытка установить драйвер
    # https://www.anoopcnair.com/pnputil-driver-manager-tool-install-drivers/
    PnPUtil.exe /add-driver "C:\Setup\Intel_Thunderbolt_Controller\Inf\*.inf" /install
    echo "Found a device 'Intel Thunderbolt Controller' !"; pause 
}


$PnPUtil_out = PnPUtil.exe /enum-devices /problem
$num_of_problem_devices = ($PnPUtil_out -Match "Состояние:\s+Проблема").count  #  [string] -OR $PnPUtil_out -Match "Состояние:\s+Проблема|Код ошибки:\s+28 \(0x1C\) \[CM_PROB_FAILED_INSTALL\]"

if ($num_of_problem_devices) { echo "There are still $num_of_problem_devices problematic devices in the system (info from PnPUtil.exe) ! Please Install drivers manually."; pause }

} # конец блока когда когда все еще остаются проблемные устройства


echo "Getting Windows Update History ..."
$WUhistory = Get-WUHistory -MaxDate (Get-Date).AddDays(-30) -Last 200
if (-not $WUhistory) { 
    echo "Win Update History is empty! Either something went wrong or the system doesn’t need updates !"
    pause
    Return
}
$WUhistory | select Date, OperationName, Result, KB, Title, Description, ClientApplicationID, @{n="UpdateID";e={$_.UpdateIdentity.UpdateID}} | Export-Csv -Path "Win_Update_History.csv" -Encoding Unicode -Delimiter ';' 

$CIM_PnPEntity | select "PNPClass", "Service", "Manufacturer", "Description", "Name", "Status", "ConfigManagerErrorCode", "PNPDeviceID", "HardwareID", "CompatibleID", "ClassGuid" | Export-Clixml "CIM_PnPEntity_after_drivers_update.xml"
$CIM_PnPSignedDriver | select DeviceClass, DeviceName, FriendlyName, DriverProviderName, DriverDate, DriverVersion, DriverName, Manufacturer, InfName, Location, HardWareID, DeviceID, CompatID, PDO, ClassGuid, IsSigned, Signer | Export-Clixml "CIM_PnPSignedDriver_after_drivers_update.xml"

echo "The following Display Adapters (as PCI devices) are currently running on the system:"
$Display_Adapters_from_PnPEntity | select @{n="HWid"; e={if ($_.PNPDeviceID -match $DevHwId_pattern) { $Matches[1] } }}, Description 


echo "Export all installed drivers ..." # Экспорт всех установленных драйверов
$Drivers = Export-WindowsDriver -Online -Dest $WorkFolder -LogPath "$Folder\$FileName_Export.log" | select * -Exclude LogPath
$Path_to_oem_inf = "$Env:WinDir\System32\DriverStore\FileRepository\"; $Len = $Path_to_oem_inf.Length
$Drivers | % { if ($_.OriginalFileName.StartsWith($Path_to_oem_inf, "CurrentCultureIgnoreCase")) { $_.OriginalFileName = $_.OriginalFileName.Substring($Len) } } # убираем полный путь к oemXX.inf

echo "Delete all drivers from Microsoft and from System/Security software:"
# $Drivers_to_Exclude2 = Get-WindowsDriver -Online | where ProviderName -Match "Microsoft|VMware|Kaspersky|Dameware"
$Drivers_to_Exclude = $Drivers | where ProviderName -Match "Microsoft|VMware|Kaspersky|Dameware"
$Drivers_to_Exclude | select Driver, OriginalFileName, ProviderName, ClassName, Date, Version | FT -Au # @{n="OriginalFileName"; e={$_.OriginalFileName.Substring($Len)}}, 

# $Drivers_to_Exclude | % { if ($_.OriginalFileName -match "(.+\\)*(.+)\\.+\.inf$") { Remove-Item $Matches[2] -Recurse } }
$Drivers_to_Exclude | % { if ($_.OriginalFileName -match "(.+)\\.+\.inf$") { Remove-Item $Matches[1] -Recurse } }

$Drivers | select "OriginalFileName", "CatalogFile", "Driver", "Version", "Date", "ClassName", "ClassGuid", "ClassDescription", "ProviderName", "BootCritical" |`
 Export-Csv -Path "$FileName_Export.csv" -Encoding Unicode -Delimiter ';' # @{n="OriginalFileName"; e={$_.OriginalFileName.Substring($Len)}}
$Drivers | Export-Clixml -Path "$FileName_Export.xml"
# $Drivers = Import-Clixml -Path "$FileName_Export.xml" | select * -Exclude LogPath

$Tools_path = $env:Tools # пробуем найти две далее требуемые утилиты в корп. заливке
$DevCon_exe = "$Tools_path\DevCon_x64.exe"
$7Zip_exe = "$Tools_path\7-Zip\x64\7za.exe"

if ( (Test-Path $DevCon_exe) -and (Test-Path $DevCon_exe) ) {
    echo "We are Runnning from corp image because found utilities DevCon and 7Zip."
} else { # Если работаем не в нашей корп системе (например в OEM винде "из коробоки"), то придется две требуемые утилиты скачать из интернета
$DevCon_exe = "DevCon_x64.exe"

echo "We are Runnning NOT from corp image ! Provide please write access to the folder: `n$Drivers_Archive_path"

# https://superuser.com/questions/1002950/quick-method-to-install-devcon-exe
# for Win10 v1809 Build 10.0.17763, Driver Kit Build 10.0.17763, and also for Win 7/8/8.1/10 plus Windows Server 2008 (R2)/2012 (R2)/2016
$URI = "https://download.microsoft.com/download/1/4/0/140EBDB7-F631-4191-9DC0-31C8ECB8A11F/wdk/Installers/787bee96dbd26371076b37b13c405890.cab"
$file = "filbad6e2cce5ebc45a401e19c613d0a28f"; $cab_file = "upd_with_DevCon_64_v1809.cab"; 

Push-Location; Set-Location $Env:Temp

echo "Download from the Internet Microsoft CAB archive with DevCon.exe utility ..."
Invoke-WebRequest $URI -OutFile $cab_file

echo "Extract from CAB DevCon utility to WinDir\System32"
$P = Start-Process "Expand.exe" -Arg "$cab_file -F:$file ." -Wait -PassThru
if ($P.ExitCode -ne 0) { echo "Error extracting from CAB update file !"; Return }
Rename-Item $file -NewName $DevCon_exe; Move-Item $DevCon_exe -Dest "$Env:WinDir\System32"; Remove-Item $cab_file

echo "Download from the Internet 7Zip console archiver ..."
$URI_7Zip = "https://www.7-zip.org/a/7zr.exe";  if ($URI_7Zip -match ".+\/(\S+\.exe)$") { $7Zip_exe = $Matches[1] }
Invoke-WebRequest $URI_7Zip -OutFile "$Env:WinDir\System32\$7Zip_exe"

Pop-Location
}

$P = Start-Process "cmd.exe" -Arg "/c $DevCon_exe DriverNodes * >DevCon_DriverNodes.txt" -Wait -PassThru
Select-String -Path "DevCon_DriverNodes.txt" -Pattern "No driver nodes found for this device"
$P = Start-Process "cmd.exe" -Arg "/c $DevCon_exe DriverFiles * >DevCon_DriverFiles.txt" -Wait -PassThru
Select-String -Path "DevCon_DriverFiles.txt" -Pattern "No driver information available for the device"
# PnPutil.exe /enum-drivers & PnPutil.exe /enum-devices


# отодвигаем в сторону те экспортированные драйвера, которые сейчас реально не используются, оставляя только единственную версию драйвера, выбранную сейчас для работы устройства.
$All_OEM_inf_files = Select-String -Path "DevCon_DriverFiles.txt" -Pattern "Driver installed from C:\\WINDOWS\\INF\\(oem\d+\.inf) \[" | % { $_.Matches.Groups[1].Value }
# $All_OEM_inf_files2 = Select-String -Path "DevCon_DriverNodes.txt" -Pattern "Inf file is C:\\WINDOWS\\INF\\(oem\d+\.inf)" | % { $_.Matches.Groups[1].Value }
$Drivers_to_Exclude = $Drivers | where Driver -notin $All_OEM_inf_files # $All_OEM_inf_files -contains "oem1.inf" 
New-Item $Exclude_folder -ItemType Directory -EA 0 | Out-Null;

echo "All drivers, not used now in devices - remove it to the subfolder."
$Drivers_to_Exclude | % { if ($_.OriginalFileName -match "(.+)\\(.+\.inf)$") { 
    $Folder_name = $Matches[1]; $OrigInfName = $Matches[2]
    $All_versions = ($Drivers | where OriginalFileName -Match ('^' + $OrigInfName)).Version | sort
    echo "Exclude: $($OrigInfName) $($_.Version) $($_.ClassName) $($_.ClassDescription) $($_.ProviderName).  All versions: $([string]$All_versions)"
    if ( $_.Version -eq ($All_versions | select -Last 1) -and $All_versions.count -ne 1) { echo "Warning: $($OrigInfName) $($_.Version) - is the last version !" }
    Move-Item $Folder_name -Dest $Exclude_folder -EA 0
} }

# Дополнительно сохраняем логи работы работы утилиты HP SSM по установке HP SoftPaq и логи моего скрипта, который озадачивает эту утилиту
if ($Comp_Manuf_my -eq 'HP') { Copy-Item -Path "C:\Setup\Logs\OSD\HP_SSM*" -Dest "." -EA 0 } # DevCon*.txt


echo "Disable system proxy WinHTTP" # отключаем системный прокси
netsh winhttp reset proxy
if (-not (Test-Path $Reg_WinUpd_policy) -and (Test-Path ($Reg_WinUpd_policy+'2'))) { Rename-Item ($Reg_WinUpd_policy+'2') -NewName $Reg_WinUpd_leaf }
Restart-Service WUAuserv

# Отключаем настройки прокси у браузера IE/Edge для текущего пользователя
Set-ItemProperty $Reg_Proxy_curUser -Name "ProxyEnable" -Value 0 -Force
Remove-ItemProperty $Reg_Proxy_curUser -Name "ProxyServer"
Remove-ItemProperty $Reg_Proxy_curUser -Name "ProxyOverride"


# сохраняем все экспортированные драйверы и собранную инфу по этой теме в виде архива на сетевой DFS ресурс
Set-Location $Folder_with_Exported_Drivers
$Archive_name = "$Drivers_Archive_path\$Comp_Manuf_my-$Comp_Model_my_.7z" # $Comp_Manuf_my-$Comp_Model_my_.7z
while (-Not (Test-Path $Drivers_Archive_path)) {
    echo "To continue please make sure the network resource is available (to save archive with drivers): `n$Drivers_Archive_path"
    pause # При исполнении в системе не из корпоративного образа - может быть не доступен сетевой ресурс для сохранения архива всех собранных драйверов
}
echo "Archive exported drivers directly to a network resource ..."
echo "$7Zip_exe a -r $Archive_name $Folder_with_Exported_Drivers\*"
$P = Start-Process $7Zip_exe -Arg "a -r $Archive_name $Folder_with_Exported_Drivers\*" -PassThru -Wait 
if ($P.ExitCode -ne 0) { echo "Error archiving of exported drivers to the network location! 7Zip returns ExitCode=$($P.ExitCode) !" } else { echo "Drivers archival was successful." }

Return


# список HWid для "Intel Thunderbolt Controller" добыт из INF файла драйвера, скачанного с офиц сайта Intel.com
$Dev_Vendor = "PCI\VEN_8086&DEV_"; $DevHWids = "1134 1137 1575 1577 15BF 15D2 15D9 15DC 15DD 15DE 15E8 15EB 463E 466D 7EB2 7EC2 7EC3 8A0D 8A17 8AA0 8AA3 8AB0 8AB3 9A1B 9A1D 9A1F 9A21 A73E A76D" -split ' ' | % { $Dev_Vendor + $_ }
$SelStr = Select-String -Path "\\sms00802\Src\Drv\Intel_Thunderbolt_Controller\INF\TbtHostController.inf" -Pattern $DevHwId_pattern
[string]($SelStr | % { $_.Matches.Groups[1].Value } | sort -Unique | % { $_.Substring("PCI\VEN_8086&DEV_".Length) })
# $SelStr | % { $_.Matches.Groups[1].Value } | sort -Unique

} else { # конец блока работы на тестовом компьютере

########################################################
# Добавление в базу ConfMgr драйверов и Driver Packages

$All_Drivers_root = "\\sms00802\Src\Drv" # сетевой путь к корню структуры папок хранения драйверов всех вендоров и моделей компов
$All_Drivers_Src = "\\vMsHqMDT01\Drv\Src" # сетевой путь расположения импортируемых драйверов, как альтернатива для случая проблем с импортом драйверов в CM Driver Package когда файлы драйверов уже дедуплицированы
$All_Drivers_Src = $All_Drivers_root # сетевой путь к корню структуры папок хранения драйверов - либо основной вариант, либо альтернативный
$folder_for_all_MSFT_drivers = "from_Microsoft_Win_Updates" # имя папки для хранения всех драйверов, полученных через Microsoft Windows Update

$FileName_Export = "Export_WinDrivers_with_PoSh_DISM" # название файлов, с подробностями об отдельном действии - экспорт всех драйверов из системы

# все архивы с DFS ресурса распаковываем на сайт-сервер ConfMgr, после чего переносим их на хлама-свалку
$Tools_path = $env:Tools; $7Zip_exe = "$Tools_path\7-Zip\x64\7za.exe"
if (-not (Test-Path $7Zip_exe)) { echo "7zip archivator is not found !"; Return }

echo "Scan for 7zip archives with exported drivers in location: $Drivers_Archive_path"
$Arch_files = Get-Item "$Drivers_Archive_path\*.7z"; $Arch_files

echo "Extracting exported drivers from 7zip archives to a site server."
#$Arch_files | % { $archive_file = $_
foreach ($archive_file in $Arch_files) {

    $Args_for_7zip = "x -r -o`"$All_Drivers_root`" $($archive_file.FullName)";  echo "$7Zip_exe $Args_for_7zip"
    # Usage: 7za <command> [<switches>...] <archive_name> [<file_names>...] [@listfile]. command e : Extract files from archive (without using directory names). switch -o{Directory} set Output directory
    $P = Start-Process $7Zip_exe -Arg $Args_for_7zip -PassThru -Wait 
    if ($P.ExitCode -ne 0) { echo "Error extracting of exported drivers to '$Output_Dir' ! 7Zip returns ExitCode=$($P.ExitCode) !" } else { echo "Extracting of $($archive_file.Name) was successful." }

    # & $7Zip_exe 'x' '-r' "-o$All_Drivers_root" $archive_file.FullName # альтернативный вариант запуска внешней утилиты

    echo "Move Archive with drivers $archive_file to $Drivers_Archives_added_to_CM"
    Move-Item $archive_file -Dest $Drivers_Archives_added_to_CM
}

# Загружаем модуль ConfigMgr не используя абсолютные пути
$ConfMgr_Module_Path = (get-item $env:SMS_ADMIN_UI_PATH).parent.FullName + "\ConfigurationManager.psd1"; Import-Module $ConfMgr_Module_Path; # cd NN1:

# Проходимся по всей структуре папок хранения драйверов и выясняем какие из них требуют работы по добавлению в базу ConfMgr
Set-Location $All_Drivers_root
$All_HW_vendors = @("HP", "Dell", "Lenovo", "Acer", "Asus", "Huawei", "Nerpa", "iRu") # все производители компьютеров

$All_Comp_Model_folders_info = Get-ChildItem . -Directory | where Name -in $All_HW_vendors | % { Get-ChildItem $_ -Directory } | % {
    $CurDir = $_.FullName;  $Status = ""; $Comp_Info = $null; $Comp_Model_my = "" ; $Comp_Vendor_Model_my = ""

    $folders = Get-ChildItem $CurDir -Directory | where Name -Match "^(\d{4}-\d{2}-\d{2})$|^from_MSFT_Exported_with_PoSh_DISM$"
    $actual_date =  Get-ChildItem $CurDir -Directory | where Name -Match "^\d{4}-\d{2}-\d{2}$" | sort | select -Last 1 -Expand Name # выбираем папку с самой поздней датой
    if ($actual_date) {
        try {
            $Comp_Info = Import-Clixml "$CurDir\$actual_date\Computer_System_Info.xml" 

            $Comp_Model_my = ($Comp_Info.Comp_Model_my -replace '_',' ') # первые версии скрипта сохраняли мою модель с '_'. Потом решил мою модель именовать с пробелами
            # в PoSh командлет Export-CliXML сохраняет "Vivobook_X7600PC" как "Vivobook_x005F_X7600PC". Но и Import-CliXML считывает потом корректно - в первоначальную "Vivobook_X7600PC"
            $Comp_Vendor_Model_my = "$($Comp_Info.Comp_Manuf_my) $Comp_Model_my"
            if ($Comp_Vendor_Model_my -match "MoBo ") { $Comp_Vendor_Model_my = "Mobo " + ($Comp_Vendor_Model_my -replace "Mobo ") } # Если модель компа является моделью материнки, то признак "Mobo " переносим в начало названия модели

            if ($_.Name -ne ($Comp_Model_my -replace ' ','_')) { $Status = "Error: comp model in the wrong folder" } # $Comp_Info.Comp_Model_my может быть как с ' ' так и с '_' в разных версия скрипта
            
            Push-Location; Set-Location "NN1:"
            $CM_DrvPkg = Get-CMDriverPackage -Name $Comp_Vendor_Model_my -Fast
            Pop-Location

            if ($CM_DrvPkg) { # случай повтороного добавления драйверов в уже существующий в базе Drv Package
                $Measure = Get-ChildItem "$CurDir\$actual_date\$Exclude_folder" -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum

                if ($Measure) { $Status = "OK. DrvPackage exist in ConfMgr and size of excluded folders is $([int]($Measure.Sum/1Mb)) Mb" }
                elseif ($folders.count -ge 2) { $Status = "OK. DrvPackage exist in ConfMgr and there are many subfolders with drivers" }
                else { $Status = "Warning: DrvPackage exist in ConfMgr and there is NO previously excluded files need to be returned." }
                #if ($Measure.Sum/1Mb -gt 400) { $Status = "Warning: DrvPackage exist in ConfMgr and size of excluded folders is greater then 400Mb" }
                #else { $Status = "OK. DrvPackage exist in ConfMgr but previously excluded files need to be returned. The size of excluded folders is less then 400Mb" }

            } else { 
                if (-not (Get-ChildItem "$CurDir\$actual_date" -Dir)) { $Status = "Error: model is not exist in CM, but there is no any Driver folders to add" }
                # здесь можно добавлять другие проверки корректности именования моделей и правильности экспорта драйверов с тестовых компов
                if (-not $Status) { $Status = "OK. Model to be add" }
            }

        } catch { $Status = "Error: NO CompInfo XML" }
    } else { 
        $Status = "Error: No folder with date" 
    }
    
    New-Object -TypeName PSObject -Property ([ordered]@{ "Comp_Relative_path" = $_.Parent.Name + '\' + $_.Name + '\' + $actual_date; "RealDate" = ($_.CreationTime).ToString("yyyy-MM-dd");
    "Status" = $Status; "Comp_Model_my" = $Comp_Model_my; "Comp_Vendor_Model_my" = $Comp_Vendor_Model_my; "Comp_Info" = $Comp_Info; })
}

$All_Comp_Model_folders_info | sort Status,Comp_Relative_path -Descending | select Comp_Relative_path, RealDate, Comp_Vendor_Model_my, Status | FT -Au
$All_Comp_Model_folders_info | sort RealDate | select Comp_Relative_path, RealDate, Comp_Vendor_Model_my, Status | FT -Au

echo "All computer models ready to be added to ConfigMgr:"
$All_Comp_Model_folders_info | where Status -Match "^OK" | sort Comp_Relative_path | select Comp_Relative_path, RealDate, Comp_Vendor_Model_my | FT -Au

# Начало цикла добавления поддержки нескольких моделей
foreach ($Comp_Model_folders_info in ($All_Comp_Model_folders_info | where Status -Match "^OK. Model to be add")) { # "^OK"
    $Comp_Vendor_Model_my = $Comp_Model_folders_info.Comp_Vendor_Model_my
    $Comp_Info = $Comp_Model_folders_info.Comp_Info
    $Comp_Model = $Comp_Model_folders_info.Comp_Model_my # $Comp_Model = ($Comp_Info.Comp_Model_my -replace '_',' ')
    Set-Location "$All_Drivers_root\$($Comp_Model_folders_info.Comp_Relative_path)"
    $actual_date = (Get-Item .).Name
    
    $CMDrvPkg_Source_Path = "$((Get-Item '..').FullName)\CM_Drv_Package" # Split-Path (Get-Item '.') -Parent # 
    # $CMDrvPkg_Source_Path2 = "$All_Drivers_root\$($Comp_Info.Comp_Manuf_my)\$($Comp_Info.Comp_Model_my)\CM_Drv_Package"

    $CMDrivers_Source_Path = "$All_Drivers_Src\$($Comp_Model_folders_info.Comp_Relative_path)"
    # $CMDrivers_Source_Path2 = "$All_Drivers_Src\$($Comp_Info.Comp_Manuf_my)\$($Comp_Info.Comp_Model_my)\$actual_date"

    # $Drivers = Import-Clixml -Path "$FileName_Export.xml" | select * -Exclude LogPath

    if (Test-Path $CMDrvPkg_Source_Path) { # поскольку уже имеется папка 'CM_Drv_Package' - это CM DrvPackage Source Location, то далее добавляем отдельные ранее исключенные драйвера
        $All_Excluded_Drv = Get-ChildItem $Exclude_folder -Directory -EA 0 # для возврата в работу выбираем все ранее исключенные драйвера. Если таковых нету, то следующий цикл foreach in $null не шагнет ни разу

        $CMDrivers = @(); foreach ($Excluded_Drv in $All_Excluded_Drv) { # цикл по всем папкам ранее исключенных драйверов
            $one_drv_folder = $Excluded_Drv.BaseName
            Copy-Item $Excluded_Drv.FullName -Dest $one_drv_folder -Recurse # Именно копируем а не переносим, т.к. из-за прошедшей дедупликации уже не удастся добавить драйвер с файлами Repase-Point

            $one_drv_inf = (Get-Item "$CMDrivers_Source_Path\$one_drv_folder\*.inf" | select -First 1).FullName

            try { 
                Push-Location; Set-Location "NN1:"

                $CM_DrvPkg = Get-CMDriverPackage -Name $Comp_Vendor_Model_my -Fast
                echo "Add one CMdriver to CM Driver Package $($CM_DrvPkg.PackageID) from $one_drv_inf" # with Category Name '$Comp_Vendor_Model_my' from drivers source location:`n$CMDrivers_Source_Path"

                # Import one device driver into the driver catalog in ConfigMgr, add it to driver package, include it to Driver Category with the same name as Driver Package Name.
                $CMDriver = Import-CMDriver -Path $one_drv_inf -DriverPackage $CM_DrvPkg -AdministrativeCategoryName $Comp_Vendor_Model_my -EnableAndAllowInstall $true -ImportDuplicateDriverOption AppendCategory
                $CMDrivers += $CMDriver

                Pop-Location
                Remove-Item $Excluded_Drv.FullName -Recurse # Убираем один драйвер из папки исключенных драйверов, т.к. теперь он успешно добавлен в базу ConfMgr
            } catch { 
                echo "Error adding one CMdriver '$one_drv_inf' in Import-CMDriver ! $($Error[0].Exception.Message)"; $Error[0]; 
                pause
            }
        }
        if ($Comp_Model_folders_info.Status -match "there are many subfolders with drivers") { # Если имеется несколько папок с драйверами, то предполагаем обновление набора драйверов в драйвер-паке
            # единое расположение Driver Source Location для всех драйверов
            $folder_for_all_MSFT_drivers = "$All_Drivers_root\from_Microsoft_Win_Updates"

            Push-Location; Set-Location "NN1:"

            $CMcategory = Get-CMCategory -CategoryType "DriverCategories" -Name $Comp_Vendor_Model_my

            $CM_DrvPkg = Get-CMDriverPackage -Name $Comp_Model_folders_info.Comp_Vendor_Model_my -Fast
            $CMDrivers_old = Get-CMDriver -DriverPackageId $CM_DrvPkg.PackageID -Fast
            echo "Modify existing CM Driver Package ID=$($CM_DrvPkg.PackageID) '$Comp_Vendor_Model_my' with $($CMDrivers_old.Count) drivers."
            
            foreach ($CMdriver in $CMDrivers_old) { # цикл по всем уже имеющимся драйверам в составе драйвер-пака

                $CMdrv_old_ContentSourcePath = $CMdriver.ContentSourcePath
                if ($CMdrv_old_ContentSourcePath -match "^(.+)\\(.+?)$") { $drv_folder_name = $Matches[2] } else { echo "Internal Error: No match for $CMdrv_old_ContentSourcePath"; pause }
                $CMdrv_new_ContentSourcePath = "$folder_for_all_MSFT_drivers\$drv_folder_name"
                
                # при повторном перезапуске цикла из-за ошибок Set-CMDriver на первом цикле учитываем что папка драйвера была перенесана, но сам объект драйвер не изменен
                if ($CMdrv_old_ContentSourcePath -ne $CMdrv_new_ContentSourcePath) { 
                    Pop-Location # Папку старого драйвера переносим в единое расположение, т.к. потом путь к ней станет не актуальным
                    Move-Item $CMdrv_old_ContentSourcePath -Destination $folder_for_all_MSFT_drivers -EA 0
                    Push-Location; Set-Location "NN1:"
                } # else { continue # для пропуска тех драйверов, на которых я вручную отлаживал автоматику этого цикла }

                # Старый CM driver убираем из драйвер-пака, снимаем с него категорию, исправляем исходное расположение папки с контентом драйвера
                $CMDrv_info = "$($CMDriver.LocalizedDisplayName), $($CMDriver.DriverVersion) $($CMDriver.DriverDate), $($CMDriver.DriverINFFile), ID $($CMDriver.CI_ID), Drv categories '$($CMDriver.LocalizedCategoryInstanceNames -join '|')', CM Drv ContentSourcePath = $($CMDriver.ContentSourcePath)"
                Write-Progress "Change setting for CM driver: $CMDrv_info" 

                # The Set-CMDriver cmdlet changes settings of a device driver in the driver catalog.  https://learn.microsoft.com/en-us/powershell/module/configurationmanager/set-cmdriver
                # -DriverSource as String - Specifies the driver package source location. When you create a driver package, the source location of the package must point to an empty network share that is not used by another driver package.
                # -RemoveAdministrativeCategory as 	IResultObject[] - Specifies an array of administrative category objects that this cmdlet removes from a driver. To obtain an administrative category object, use Get-CMCategory.
                # -RemoveDriverPackage - Specifies an array of driver package objects. Use this parameter to remove the driver packages that ConfigMgr uses to distribute the device drivers. To obtain a driver package object, use the Get-CMDriverPackage cmdlet.
                try { $CMdriver | Set-CMDriver -DriverSource $CMdrv_new_ContentSourcePath -RemoveAdministrativeCategory $CMcategory -RemoveDriverPackage $CM_DrvPkg }
                catch { echo "Set-CMDriver exception ! $($_.Exception.Message), $($_.Exception.GetType().FullName)`n $CMDrv_info`n`n" }

                # командлет Set-CMDriver автивно кидается разными исключениями:
# The SMS Provider reported an error., Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlQueryException
# The RPC server is unavailable. (Exception from HRESULT: 0x800706BA), Microsoft.ConfigurationManagement.ManagementProvider.SmsConnectionException
# The remote procedure call failed. (Exception from HRESULT: 0x800706BE), Microsoft.ConfigurationManagement.ManagementProvider.SmsConnectionException
# Could not retrieve lock details for object 'SMS_DriverPackage.PackageID="NN000276"'. Object may not be lockable., System.InvalidOperationException
                sleep -Sec 3

                # Если драйвер остался без категорий реальных драйвер-паков, то для надежности драйвер лучше удалить.
            }
            $CMDrivers = $null

            # Import several device drivers into the driver catalog in ConfigMgr, add them to driver package, include them to Driver Category with the same name as Driver Package Name.
            echo "Add new CMdrivers to CM Driver Package $($CM_DrvPkg.PackageID) with Category Name '$Comp_Vendor_Model_my' from drivers source location:`n$CMDrivers_Source_Path"
            $CMDrivers = Import-CMDriver -Path $CMDrivers_Source_Path -DriverPackage $CM_DrvPkg -AdministrativeCategoryName $Comp_Vendor_Model_my -ImportFolder -EnableAndAllowInstall $true -ImportDuplicateDriverOption AppendCategory

            Pop-Location

            # Нужно удалить папку со источниками старых драйверов
        }
    } else { # начало добавления нового DrvPackage и его наполнения драйверами из папки с множеством вложенных подпапок с экспортированными драйверами

    # создаем папку для CM Driver Package Source Location
    New-Item $CMDrvPkg_Source_Path -ItemType Directory -EA 0 | Out-Null 

    if (Test-Path "$Exclude_folder") {

        # Теперь все ранее исключенные драйверы небольшего размера я решил добавлять драйвер-пак. Оставляю исключенными только неиспользуемые большого размера - это обычно графика Intel или NVidia
        Get-ChildItem $Exclude_folder | % {
            $size = (Get-ChildItem $_.FullName -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum).Sum/1Mb
            if ($size -lt 200) {
                Write-Debug ("Return back excluded driver folder $($_.Name)  {0:N3} Mb" -f $size)
                Move-Item $_.FullName -Dest '.'
            } else {
                Write-Output ("Leave excluded driver folder $($_.Name)  {0:N3} Mb" -f $size)
            }
        }
        
        # на время добавления драйверов отодвигаем папку с драйверами, которые добавлять не требуется
        Move-Item $Exclude_folder -Destination '..' 
    }

    Push-Location; Set-Location "NN1:"

try {
# Get started with Configuration Manager cmdlets 2022-10,  https://learn.microsoft.com/en-us/powershell/sccm/overview
# Manage drivers in Configuration Manager, 2022-10, https://learn.microsoft.com/en-us/mem/configmgr/osd/get-started/manage-drivers
$CM_DrvPkg = $null; $CMDrivers = $null
echo "Create ConfMgr new Driver Package '$Comp_Vendor_Model_my' with Manuf = '$($Comp_Info.Comp_Manuf_my)', Model = '$Comp_Model', orig WMI Model = '$($Comp_Info.Comp_Model)', WMI SKU='$($Comp_Info.Comp_SKU)', WMI MoBo '$($Comp_Info.Comp_MoBo)' here:`n$CMDrvPkg_Source_Path"
$CM_DrvPkg = New-CMDriverPackage -Path $CMDrvPkg_Source_Path -Name $Comp_Vendor_Model_my -DriverManuf $Comp_Info.Comp_Manuf_my -DriverModel $Comp_Model -Descr "from MSFT automatic win updates at $actual_date. Model='$($Comp_Info.Comp_Model)', SKU='$($Comp_Info.Comp_SKU)', MoBo='$($Comp_Info.Comp_MoBo)'"

# this cmdlet creates a configuration category in ConfigMgr. CM categories offer an optional method of sorting and filtering configuration baselines and configuration items in Configuration Manager and Configuration Manager reports.
# category type valid values are: BaselineCategories, DriverCategories, AppCategories, GlobalCondition, CatalogCategories. -Name Specifies an array of names of configuration categories, Type: String, Aliases: LocalizedCategoryInstanceName
$CMcategory = New-CMCategory -CategoryType "DriverCategories" -Name $Comp_Vendor_Model_my
# Get-CMCategory -CategoryType "DriverCategories" -Name "Dell*"

# Import several device drivers into the driver catalog in ConfigMgr, add them to driver package, include them to Driver Category with the same name as Driver Package Name.
echo "Add CMdrivers to CM Driver Package $($CM_DrvPkg.PackageID) with Category Name '$Comp_Vendor_Model_my' from drivers source location:`n$CMDrivers_Source_Path"
try { $CMDrivers = Import-CMDriver -Path $CMDrivers_Source_Path -DriverPackage $CM_DrvPkg -AdministrativeCategoryName $Comp_Vendor_Model_my -ImportFolder -EnableAndAllowInstall $true -ImportDuplicateDriverOption AppendCategory
} catch [System.InvalidOperationException] { echo "Error in Import-CMDriver -ImportFolder: $($_.Exception.Message)"; pause } # HashFile failed, Reparse Point that SMS does not support via downloads

# список DP-групп обычных АРМ, т.е. без серверов и медленных радиоканалов
$CM_DPgroups = Get-CMDistributionPointGroup; # $CM_DPgroups | sort Name | select Name, Description | FT -au
$CM_DPgroups_to_add = $CM_DPgroups.Name | ? { $_ -notmatch "Server|Radio Channel|Wave distribution updates packages|OS deploy DP group" } | sort
$CM_DPgroups2 = Get-CMDistributionPointGroup -Name "OS deploy DP group"

echo "for CM Driver Package $($CM_DrvPkg.PackageID) Start Content Distribution to DP groups: $($CM_DPgroups_to_add -join ', ')"
# distribute content from the content library on the site server to distribution points for the Driver Package object
Start-CMContentDistribution -DriverPackageId $CM_DrvPkg.PackageID -DistributionPointGroupName $CM_DPgroups_to_add

# Конструируем WMI query для данной модели данного производителя компа.
if ($Comp_Vendor_Model_my -match "MoBo ") {
    $WMI_namespace = "root\wmi"
    $WMI_query = "SELECT * FROM MS_SystemInformation WHERE BaseBoardProduct = '$($Comp_Info.Comp_Model)'" # Так вынуждены распознавать по модели материнки для компов Nerpa
} else {
    $WMI_namespace = "root\cimv2"
    $WMI_query = "SELECT * FROM Win32_ComputerSystem WHERE Model = '$($Comp_Info.Comp_Model)'" # Это четко работает для HP
}# $WMI_query = "SELECT * FROM Win32_ComputerSystem WHERE $WMI_query_where"

# https://msendpointmgr.com/2018/01/10/customize-task-sequences-in-configmgr-current-branch-using-powershell/
echo "Create condition for Apply Driver Package step: WMI query = `"$WMI_query`" in namespace `"$WMI_namespace`""
$CM_WMIQueryCondition = New-CMTSStepConditionQueryWmi -Namespace $WMI_namespace -Query $WMI_query

sleep -Sec 5
do {
    echo "pause while waiting for the object CM Driver Package '$($CM_DrvPkg.PackageID)' to be created and filled with CMdrivers..."
    sleep -Sec 5
    $CM_DrvPkg2 = Get-CMDriverPackage -Id $CM_DrvPkg.PackageID -Fast
    $CMDrivers2 = Get-CMDriver -DriverPackageId $CM_DrvPkg.PackageID -Fast
} while (-not ($CM_DrvPkg2 -and $CMDrivers2))

echo "Create a new Apply Driver Package step 'drv $Comp_Vendor_Model_my' after pause for 2 minutes ...";  sleep -Sec 120; $CM_TSstep_ApplyDriverPackage = $null
do { try {
    $CM_TSstep_ApplyDriverPackage = New-CMTaskSequenceStepApplyDriverPackage -Name "drv $Comp_Vendor_Model_my" -PackageId $CM_DrvPkg.PackageID -Description "WMI Model = '$($Comp_Info.Comp_Model)', SysSKU='$($Comp_Info.Comp_SKU)" -Condition $CM_WMIQueryCondition -ContinueOnError -Disable # -EnableUnsignedDriver
    # может взбрыкнуть исключением: "No driver package found with the specified package ID 'NN100594' which is not empty." InvalidOperationException ValidationFailed,Microsoft.ConfigurationManagement.PowerShell.Cmdlets.Osd.NewTSStepApplyDriverPackage
} catch { echo "Error in any ConfMgr cmdlet New-CMTaskSequenceStepApplyDriverPackage! $($Error[0].Exception.Message) !  We will take a brief pause .."; sleep -Sec 10 }
} while (-not $CM_TSstep_ApplyDriverPackage)

# Get Task Sequence object
$CM_TaskSequence = Get-CMTaskSequence -TaskSequencePackageId "NN000113" # -Name "Apply All Driver Packages"

# cmdlet to add a group or step to an existing task sequence. This cmdlet can only add steps to the main level of the task sequence, not in groups. by default the step is added to the beginning
$CM_TaskSequence | Add-CMTaskSequenceStep -Step $CM_TSstep_ApplyDriverPackage

echo "Add New Step to TaskSeq is Done."
} catch { "Error in any ConfMgr cmdlet! $($Error[0].Exception.Message)"; $Error[0]; pause}
Pop-Location

    # после добавления драйверов возвращаем обратно ранее отодвинутую в сторонку папку с неиспользуемыми драйверами
    if (Test-Path "..\$Exclude_folder") { Move-Item "..\$Exclude_folder" -Destination '.' }

} # конец добавления целого DrvPackage

    # Сохраняем подробности процесса добавления драйверов в базу ConfMgr
    if ($CMDrivers) { 
        echo "in ConfMgr added $($CMDrivers.Count) drivers into the CM Driver Package $($CM_DrvPkg.PackageID) '$Comp_Vendor_Model_my' with the same name of the CM driver category:"
        $CMDrivers | select DriverClass, DriverProvider, LocalizedDisplayName, DriverINFFile, DriverVersion, DriverDate | FT -Au
        
        $Imported_drv_XML_file = "..\Imported_CMdrivers_$actual_date.xml"
        if (Test-Path $Imported_drv_XML_file) { $CMDrivers0 = Import-Clixml $Imported_drv_XML_file } else { $CMDrivers0 = @() }
        ($CMDrivers0 + $CMDrivers) | select CI_ID, DriverClass, DriverProvider, LocalizedDisplayName, DriverINFFile, DriverVersion, DriverDate, DriverSigned, ContentSourcePath | Export-Clixml $Imported_drv_XML_file # @{n="Sign";e={$_.DriverSigned}}, Out-GridView

        $CMDrivers | % { $XML_file_path = "$($_.ContentSourcePath)\$($_.DriverINFFile -replace "\.inf$").CMxml"; if (-Not (Test-Path $XML_file_path)) { $_.SDMPackageXML | Set-Content -Path $XML_file_path } } # При добавлении драйвер уже может быть в базе и добавлялся для другой модели
    }
    # важнейшее свойство драйвера SDMPackageXML доступно только сразу после добавления драйвера в базу. Потом если запросить объект CMDriver, то это свойство SDMPackageXML будет с пустым  !
    # $CMDrivers2 = Get-CMDriver -AdministrativeCategory $CMcategory

} # Конец цикла добавления поддержки нескольких моделей

} # конец блока добавления драйверов в базу ConfMgr


Return

# после исключения драйверов из драйвер-паков командлетом Set-CMDriver после добавления новых дров - всплыли драйвера с единственной категорией Lenovo с исправленным ContentSourcePath на from_Microsoft_Win_Updates.
$CMDrivers_to_remove = Get-CMDriver -DriverPackageId $CM_DrvPkg.PackageID | % { $CMdrv_categ = $_.LocalizedCategoryInstanceNames; if ( ($CMdrv_categ.count -eq 1) -and ($CMdrv_categ -eq "Lenovo")) { $_ } }
$CMDrivers_to_remove | % { Write-Progress $_.ContentSourcePath; Remove-CMDriver -InputObject $_ -Force; Remove-Item "Microsoft.PowerShell.Core\FileSystem::$($_.ContentSourcePath)" -Recurse -Force }

Get-ChildItem *.inf -Recurse | measure
Get-ChildItem *.inf -Recurse | Select-String -Pattern "NVidia|(Intel.*(Display|Graphics|Gfx))"

$Tools_path = $env:Tools; $7Zip_exe = "$Tools_path\7-Zip\x64\7za.exe"
net use T: "\\VNR00-SC2012.npr.nornick.ru\DRIVERS"
Set-Location "T:\BIG_size_drv\Video_NVidia"

$NVidia_downloaded_EXE_pack_name_pattern = "(.+?)-((win10-)?(win11-))?64bit-international-dch-whql.exe$"
$NVidia_downloaded_EXE_pack = Get-Item "*.exe" | where Name -Match $NVidia_downloaded_EXE_pack_name_pattern | sort -Desc | select -First 1
if ($NVidia_downloaded_EXE_pack.Name -match $NVidia_downloaded_EXE_pack_name_pattern) { 
$Folder_to_Extract = "C:\NVidia\$($Matches[1])"

New-Item $Folder_to_Extract -ItemType Directory -Force | Out-Null

$Tools_path = $env:Tools; $7Zip_exe = "$Tools_path\7-Zip\x64\7za.exe"

$Args_for_7zip = "x -r -o`"$Folder_to_Extract`" $($NVidia_downloaded_EXE_pack.FullName)"
echo "Extracting of NVidia EXE pack (downloaded from nvidia.com):`n $7Zip_exe $Args_for_7zip"
# Usage: 7za <command> [<switches>...] <archive_name> [<file_names>...] [@listfile]. command e : Extract files from archive (without using directory names). switch -o{Directory} set Output directory
$P = Start-Process $7Zip_exe -Arg $Args_for_7zip -PassThru -Wait 
if ($P.ExitCode -ne 0) { echo "Error extracting of exported drivers to '$Folder_to_Extract' ! 7Zip returns ExitCode=$($P.ExitCode) !" } 
else { 
    echo "Extracting of $($NVidia_downloaded_EXE_pack.Name) was successful." 

    $NV_setup_args = "-s -n -log:`"$Folder_to_Extract\Logs_setup`"" # "Display.Driver HDAudio.Driver -clean -s" -loglevel:6"
    # https://enterprise-support.nvidia.com/s/article/Silent-Install-of-GRID-VM-Driver-for-Windows  https://lazyadmin.nl/it/deploy-nvidia-drivers/  https://help.pdq.com/hc/en-us/community/posts/115000015651-Silent-install-for-Nvidia-Quadro-Driver-375-63
    Set-Location $Folder_to_Extract;  $P = Start-Process "setup.exe" -Arg $NV_setup_args -PassThru -Wait 
    echo "NVidia setup.exe returns ExitCode=$($P.ExitCode)"
}

}

$Intel_Gfx_folder = "$All_Drivers_root\HP_SoftPaqs\BIG_size_drv\Video_Intel";  Set-Location $Intel_Gfx_folder
Get-Location | select -Expand ProviderPath # (Get-Item .).FullName

$Intel_Gfx_downloaded_EXE_pack = Get-Item "gfx_win_101.2125.exe"
$Intel_Gfx_downloaded_EXE_pack = Get-Item "gfx_win_101.4502.exe"
$Folder_to_Extract = "$Intel_Gfx_folder\$($Intel_Gfx_downloaded_EXE_pack.BaseName)" # "gfx_win_101.2125" "C:\Setup\Intel_Gfx\101.2125"
New-Item $Folder_to_Extract -ItemType Directory -Force | Out-Null
Set-Location $Folder_to_Extract

$Args_for_7zip = "x -r -o`"$Folder_to_Extract`" $($Intel_Gfx_downloaded_EXE_pack.FullName) *.inf installation_readme.txt"
echo "Extracting of Intel Graphic EXE pack (downloaded from Intel.com):`n $7Zip_exe $Args_for_7zip"
# Usage: 7za <command> [<switches>...] <archive_name> [<file_names>...] [@listfile]. command e : Extract files from archive (without using directory names). switch -o{Directory} set Output directory
$P = Start-Process $7Zip_exe -Arg $Args_for_7zip -PassThru -Wait 
if ($P.ExitCode -ne 0) { echo "Error extracting of Intel Graphic EXE pack to '$Folder_to_Extract' ! 7Zip returns ExitCode=$($P.ExitCode) !" } 

# Command Line Installation for Intel® Graphic Drivers, cmd params for Installer.exe - https://www.intel.com/content/www/us/en/support/articles/000006773/graphics.html
# https://superuser.com/questions/1771996/how-can-i-silently-install-the-intel-graphics-driver-dch  https://community.intel.com/t5/Graphics/Intel-DCH-driver-Silent-Install-Non-Interactive/td-p/1437287/page/2


# в SQL базе НН есть вьюшка "v_GS_SYSTEM_DEVICES" со всеми устройствами каждого компа


echo ("PreDownloadRule contains Comp_Model: " + ($CM_DrvPkg.PreDownloadRule -eq "@root\cimv2`nselect * from win32_computersystemproduct where name like `"%$Comp_Model%`""))

# https://homotechsual.dev/2023/01/10/Updating-Drivers-from-Microsoft-Update/
# Updating Drivers from Microsoft Update, 2023-01-10

    # Create a new update service manager COM object.
    $UpdateService = New-Object -ComObject Microsoft.Update.ServiceManager
    # If the Microsoft Update service is not enabled, enable it.
    $MicrosoftUpdateService = $UpdateService.Services | Where-Object { $_.ServiceId -eq '7971f918-a847-4430-9279-4a52d1efe18d' }
    if (!$MicrosoftUpdateService) {
        $UpdateService.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
    }
    # Create a new update session COM object.
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    # Create a new update searcher in the update session.
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    # Configure the update searcher to search for driver updates from Microsoft Update.
    ## Set the update searcher 
    $UpdateSearcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
    ## Set the update searcher to search for per-machine updates only.
    $UpdateSearcher.SearchScope = 1
    ## Set the update searcher to search non-Microsoft sources only (no WSUS, no Windows Update) so Microsoft Update and Manufacturers only.
    $UpdateSearcher.ServerSelection = 3
    # Set our search criteria to only search for driver updates.
    $SearchCriteria = "IsInstalled=0 and Type='Driver'"
    # Search for driver updates.
    Write-Verbose 'Searching for driver updates...'
    $UpdateSearchResult = $UpdateSearcher.Search($SearchCriteria)
    $UpdatesAvailable = $UpdateSearchResult.Updates
    # If no updates are available, output a message and exit.
    if (($UpdatesAvailable.Count -eq 0) -or ([string]::IsNullOrEmpty($UpdatesAvailable))) {
        Write-Warning 'No driver updates are available.'
    } else {
        Write-Verbose "Found $($UpdatesAvailable.Count) driver updates."
        # Output available updates.
        $UpdatesAvailable | Select-Object -Property Title, DriverModel, DriverVerDate, DriverClass, DriverManufacturer | Format-Table
        # Create a new update collection to hold the updates we want to download.
        $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        $UpdatesAvailable | ForEach-Object {
            # Add the update to the update collection.
            $UpdatesToDownload.Add($_) | Out-Null
        }
        # If there are updates to download, download them.
        if (($UpdatesToDownload.count -gt 0) -or (![string]::IsNullOrEmpty($UpdatesToDownload))) {
            # Create a fresh session to download and install updates.
            $UpdaterSession = New-Object -ComObject Microsoft.Update.Session
            $UpdateDownloader = $UpdaterSession.CreateUpdateDownloader()
            # Add the updates to the downloader.
            $UpdateDownloader.Updates = $UpdatesToDownload
            # Download the updates.
            Write-Verbose 'Downloading driver updates...'
            $UpdateDownloader.Download()
        }
        # Create a new update collection to hold the updates we want to install.
        $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        # Add downloaded updates to the update collection.
        $UpdatesToDownload | ForEach-Object { 
            if ($_.IsDownloaded) {
                # Add the update to the update collection if it has been downloaded.
                $UpdatesToInstall.Add($_) | Out-Null
            }
        }
        # If there are updates to install, install them.
        if (($UpdatesToInstall.count -gt 0) -or (![string]::IsNullOrEmpty($UpdatesToInstall))) {
            # Create an update installer.
            $UpdateInstaller = $UpdaterSession.CreateUpdateInstaller()
            # Add the updates to the installer.
            $UpdateInstaller.Updates = $UpdatesToInstall
            # Install the updates.
            Write-Verbose 'Installing driver updates...'
            $InstallationResult = $UpdateInstaller.Install()
            # If we need to reboot flag that information.
            if ($InstallationResult.RebootRequired) {
                Write-Warning 'Reboot required to complete driver updates.'
            }
        
            # Output the results of the installation.
            ## Result codes: 0 = Not Started, 1 = In Progress, 2 = Succeeded, 3 = Succeeded with Errors, 4 = Failed, 5 = Aborted
#            if (($InstallationResult.ResultCode -eq 1) -or ($InstallationResult.ResultCode -eq 2) -or ($InstallationResult.ResultCode -eq 3)) {
            if ($InstallationResult.ResultCode -in (1,2,3)) { # We consider 1, 2, and 3 to be successful here.
                Write-Verbose "Driver updates installed successfully. Installed $($UpdatesToInstall.Count) updates. Last updates run $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))"
            } else {
                Write-Warning "Driver updates failed to install. Result code: $($InstallationResult.ResultCode.ToString())"
            }
        }
    }

# из офиц дистра драйверов NVidia можно выкинуть лишних 300 Мб и распаковать MsLZ *.??_ чтобы потом круче перепаковать 
# распаковка *.dl_, *.sy_ внутри папки "C:\NVIDIA\DisplayDriver\531.41\Win11_Win10-DCH_64\International\Display.Driver"
Get-Item *.*_ | % { & $7Zip_exe 'e' '-r' $_.FullName; Remove-Item $_ }
# также нужно добавить папки: Display.Nview GFExperience nodejs NVI2 PhysX и все файлы из корня

<# на компах с одновременно двумя активными граф. адаптерами Intel и NVidia имеем проблему "Intel High Definition Audio", установить дрова не удалось ни вручную ни через авто-обновления Майкрософт
"Для устройства не установлены драйверы. (Код 28) Для этого устройства отсутствую совместимые драйверы. Размещение - HD Audio Bus Driver. Физ девайс Intel® Smart Sound Technology BUS PCI\VEN_8086&DEV_A0C8&SUBSYS_1A421043 PCI\VEN_8086&DEV_A0C8&CC_0403"
"Nnr890100152472", "Asus ViviBook X7600PC", "INTELAUDIO\FUNC_01&VEN_8086&DEV_2812", "Intel High Definition Audio"
"Asus\Vivobook_X7600PC\2023-06-02\!Excluded_Drv_not_used\intcdaud.inf_amd64_13b8ffa089ba1d60\intcdaud.inf", "Intel(R) Display Audio", "04/16/2021,11.2.0.8"
"Asus\Vivobook_X7600PC\2023-06-02\!Excluded_Drv_not_used\mshdadac.inf_amd64_d032a3c6dd6e5c7d\mshdadac.inf", "HD Audio Driver for Display Audio", "06/01/2021,27.20.100.9664"

"NNR890100152465", "HP Laptop 15s-fq2xxx", "INTELAUDIO\FUNC_01&VEN_8086&DEV_2812", "Intel High Definition Audio"
"HP\Laptop_15s-fq2xxx\2023-05-31\!Excluded_Drv_not_used\intcdaud.inf_amd64_874a553c257a86b6\intcdaud.inf", "Intel(R) Display Audio", "02/26/2020,11.2.0.4"
"HP\Laptop_15s-fq2xxx\2023-05-31\!Excluded_Drv_not_used\mshdadac.inf_amd64_a901c013bbf37c06\mshdadac.inf", "HD Audio Driver for Display Audio", "10/28/2020,27.20.100.8935"

#>

<# Примеры исключаемых из экспорта драйверов:
Driver   OriginalFileName                                                                                    ProviderName         Date               Version
------   ----------------                                                                                    ------------         ----               -------
oem6.inf C:\Windows\System32\DriverStore\FileRepository\vmusb.inf_amd64_c603306f7f2b335a\vmusb.inf           VMware, Inc.         23.03.2021 0:00:00 4.3.1.4
oem7.inf C:\Windows\System32\DriverStore\FileRepository\klim6.inf_amd64_51f3f6d4d1dcff4a\klim6.inf           Kaspersky Lab        28.03.2022 0:00:00 30.795.0.80
oem8.inf C:\Windows\System32\DriverStore\FileRepository\dwvkbd64.inf_amd64_cbf331f5af42a163\dwvkbd64.inf     DameWare             10.04.2007 0:00:00 1.0.0.1
oem9.inf C:\Windows\System32\DriverStore\FileRepository\dwmirror64.inf_amd64_2f70c243a0b0372c\dwmirror64.inf DameWare Development 14.03.2008 0:00:00 1.1.0.0
oem0.inf C:\Windows\System32\DriverStore\FileRepository\prnms001.inf_amd64_8bc1bda6cf47380c\prnms001.inf     Microsoft            21.06.2006 0:00:00 10.0.19041.1
oem1.inf C:\Windows\System32\DriverStore\FileRepository\prnms009.inf_amd64_a7412a554c9bc1fd\prnms009.inf     Microsoft            21.06.2006 0:00:00 10.0.19041.1
#>


<# Полезные ссылки по теме

https://www.powershellgallery.com/packages/Patchy/1.0
Install-WindowsUpdate uses ComObject "Microsoft.Update.UpdateColl" "Microsoft.Update.ServiceManager" "Microsoft.Update.Session"


https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates
Searching, Downloading, and Installing Updates, 2021-03-15
The scripting sample in this topic shows you how to use Windows Update Agent (WUA) to scan, download, and install updates.
The sample searches for all the applicable software updates and then lists those updates. Next, it creates a collection of updates to download and then downloads them. Finally, it creates a collection of updates to install and then installs them.


https://social.technet.microsoft.com/Forums/azure/en-US/8bd9f0fa-e901-4af8-bc68-4751905c36b7/server-2016-update-issue-quotmicrosoftupdatesessionquot
avout ComObject "Microsoft.Update.Session", UsoClient.exe, WUAUCLT.exe does not use the COM object


https://learn.microsoft.com/en-us/windows-server/get-started/removed-deprecated-features-windows-server-2016
The wuauclt.exe /detectnow command has been removed and is no longer supported. To trigger a scan for updates, run these PowerShell commands:
$AutoUpdates = New-Object -ComObject "Microsoft.Update.AutoUpdate"; $AutoUpdates.DetectNow()


https://www.wintips.org/how-to-run-windows-update-from-command-prompt-or-powershell-windows-10-11-server-2016-2019/
How to Run Windows Update from Command Prompt or PowerShell in Windows 10/11 & Server 2016/2019.
In latest Windows 10 versions the command 'WUAUCLT.EXE' does not work anymore and has been replaced by the command 'USOCLIENT.EXE'.
Info: The 'USOCLIENT.EXE' is the Update Session Orchestrator client that used to download and install Windows Updates. *
According to reports, not all Windows 10 and 11 versions support the USOCLIENT. If the same is true for your device, update your system using the PowerShell method.
Since USOCLIENT commands do not display anything on the screen at the time they are executed, the only way to determine if the command is working is to look at the events in the following destinations.
- C:\Windows\SoftwareDistribution\ReportingEvents.log
- Task Scheduler -> Microsoft -> Windows -> Update Orchestrator


# https://www.technewstoday.com/how-to-run-windows-update-from-command-line/
# On Win10-11, Microsoft uses the Update Session Orchestrator Client UsoClient.exe tool for updating your system components.
Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' | Select-Object @{Expression={$_.TaskName};Label="TaskName"}, @{Expression={$_.Actions.Execute + ' ' + $_.Actions.Arguments};Label="CommandLine"}
UsoClient StartScan – Start the scan for available updates
UsoClient StartDownload – Download but not install the updates or patches you scanned for.
UsoClient StartInstall – Install all downloaded updates.
UsoClient ScanInstallWait – Scans, downloads, and installs the updates
UsoClient RestartDevice – Restarts your computer to complete the update installation
UsoClient ResumeUpdate – Resumes the installation of update after reboot
UsoClient RefreshSettings – Refresh the update settings to the default


https://adamtheautomator.com/pswindowsupdate/
Run the Get-WUServiceManager to show the list of available update services.
There’s no official documentation about the update the sources, but each is defined below:
- Microsoft Update – the standard update source
- DCat Flighting Prod – an alternative MS supdate ource for specific flighted update items (from previews, etc)
- Windows Store (DCat Prod) – normally just Windows Store, but has Dcat Prod when for insider preview PC
- Windows Update – an older update source for Windows Vista and older Windows OS.

Get-WURebootStatus to determine if any of the Windows updates require a reboot. before installing updates, checking if updates require a system reboot is a good practice.  Why? 
Knowing whether the Windows updates require a reboot beforehand tells you to save all your work and complete other ongoing installations before diving to the Windows update.


https://www.idkrtm.com/windows-update-commands/
The USOclient is new to windows 10 and Server 2016. This replaces the wuauclt command in these Operating systems. 
I would recommend using powershell instead of this client when you are doing automation, since it will work on newer and older clients. 
However, this client is very simple to use. and is useful for one-off purposes.
WUAUCLT (Windows Update Automatic Update Client) - This client has been deprecated in windows 10 and server 2016.


https://www.deploymentresearch.com/configmgr-driver-management-in-just-four-steps-by-matthew-teegarden/
2017-03 The goal of this article is to show you how to move from managing ConfigMgr driver packages to something much more dynamic. 
You will no longer need to edit your task sequences with additional driver package steps. I was told that the cool kids don't use the Driver Packages node anymore..
while I was demonstrating some tools that automatically download and import driver packages into the Driver Package node !  Awkward.
The reason why ConfigMgr (SCCM) Driver Packages aren't so cool is the amount of data that gets put into the database.

https://cloudandback.org/2016/04/17/automatically-collect-drivers-and-build-configuration-manager-current-branch-driver-packages-with-powershell/
2016-05 Automatically Collect Drivers (as export on endpoint device) and Build ConfMgr Driver Packages with PoSh from


https://msendpointmgr.com/modern-driver-management/


https://learn.microsoft.com/en-us/powershell/module/configurationmanager/add-cmdrivertodriverpackage
The Add-CMDriverToDriverPackage cmdlet adds a device driver to a Configuration Manager driver package.
A driver package contains the content associated with one or more device drivers. Device drivers must to be added to a driver package and copied to a distribution point before Configuration Manager clients can install them.
You can add Windows device drivers that have been imported into the driver catalog to an existing driver package. When a device driver is added to a driver package, Configuration Manager copies the device driver content from the driver source location to the driver package.

https://garytown.com/driver-pack-mapping-and-pre-cache
Win10 In-Place Upgrade with dynamic Staged Driver Package via TS variable

wuauclt.exe описание параметров от Павла:
•	/DetectNow – ваш компьютер отправляет запрос на сервер о наличии обновления. Если приходит положительный ответ, то уже можно запускать обновление с помощью «/UpdateNow».
•	/detectnow /resetAuthorization. При подключении к серверу, компьютер должен быть авторизован. Эти команды сбрасывает авторизацию и проводит её повторно.
•	/reportnow – сбрасывает данные по обновлениям. Можно запускать перед «/DetectNow».
•	/ShowSettingsDialog – расписание обнов.
•	/ResetEulas – сброс соглашения, которые используются при обновлении ОС.
•	/ShowWindowsUpdate – показ всех обновлений. 

# Start-CMContentDistribution Use this cmdlet to distribute content from the content library on the site server to distribution points for the following deployable objects:
# Applications, Legacy packages, Software update deployment packages, Driver packages, OS images, OS upgrade packages, Boot images, Content referenced by task sequences
# You can distribute the content to distribution points, distribution point groups, or collections associated with distribution point groups.
# -DistributionPointGroupName Specify an array of distribution point group names to which to distribute the content. -DriverPackageId Specify an array of driver package IDs to distribute.

https://learn.microsoft.com/en-us/powershell/module/configurationmanager/Import-CMdriver
This cmdlet imports one or more device drivers into the driver catalog in ConfigMgr. When you import device drivers into the catalog, you can add the device drivers to driver packages or to boot image packages.
As part of the import process for the device driver, ConfigMgr reads the following information associated with the device: Provider, Class, Version, Signature, Supported hardware, Supported platform 
-Path a path to the driver files to import.
-AdministrativeCategory Specify an array of category objects. Assign the device drivers to a category for filtering purposes, such as Desktops or Notebooks. To get this object, use the Get-CMCategory cmdlet.
-AdministrativeCategoryName Instead of getting and specifying an object for a category with the AdministrativeCategory parameter, use this parameter to simply specify the name of a category. You can also use an array of category names.
-EnableAndAllowInstall enable the driver and allow clients to install it during the Auto Apply Driver task sequence step.
-ImportFolder add this parameter to import all the device drivers in the target folder.
-UpdateDriverPackageDistributionPoint If you use the -DriverPackage parameter, set this parameter to $true to update the driver package on assigned distribution points.
-ImportDuplicateDriverOption Specify how Configuration Manager manages duplicate device drivers.
 AppendCategory: Import the driver and append a new category to the existing categories
 KeepExistingCategory: Import the driver and keep the existing categories
 NotImport: Don't import the driver
 OverwriteCategory: Import the driver and overwrite the existing categories

https://learn.microsoft.com/en-us/powershell/module/configurationmanager/new-cmdriverpackage
The name of driver package has maximum 50 chars, description has maximum 127 chars, DriverModel has maximum 100 chars,
-Path specify a file path to the network location to source the driver files.
When you create a driver package, the source location of the package must point to an empty network share that's not used by another driver package. 
When you add device drivers to a driver package, ConfigMgr copies it to this path. You can add to a driver package only device drivers that you've imported and that are enabled in the driver catalog.

https://www.deploymentresearch.com/back-to-basics-pnputil-exe-vs-pnpunattend-exe/
Back to Basics – Updating Drivers – pnputil.exe vs. pnpunattend.exe by Johan Arwidmark, 2022-03-20
While pnputil.exe offers more features, it sometimes fails (hangs) when updating a larger set of drivers (150-200 drivers). pnpunattend.exe is more reliable, plus a bit faster too

https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-and-remove-drivers-to-an-offline-windows-image
You can use DISM to install or remove driver packages in an offline Windows or Windows PE image. You can either add or remove the driver packages directly by using the command prompt, or apply an unattended answer file to a mounted .wim, .ffu, .vhd, or .vhdx file.
When you use DISM to install a driver package to an offline image, the driver package is added to the driver store. When the image boots, Plug and Play (PnP) runs and associates the driver packages in the store to the corresponding devices on the computer.

Mount a Windows image. For example:
Dism /Mount-Image /ImageFile:C:\test\images\install.wim /MountDir:C:\test\offline

To install all of the driver packages from a folder- Point to a folder that contains driver packages. To include all of the folder's subfolders, use the `/Recurse option:
Dism /Image:C:\test\offline /Add-Driver /Driver:c:\drivers /Recurse

Caution: Using /Recurse can be handy, but it's easy to bloat your image with it. Some driver packages include multiple .inf driver packages, which often share payload files from the same folder. 
During installation, each .inf driver package is expanded into a separate folder. Each individual folder has a copy of the payload files.

https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/infverif
InfVerif (InfVerif.exe) is a tool that you can use to test a driver INF file. Windows Drivers - Driver Technologies - Tools for Testing Drivers 

https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/signtool
SignTool (Signtool.exe) is a command-line CryptoAPI tool that digitally-signs files, verifies signatures in files, and time stamps files.

OSD TaskSeq step action "Apply Driver" uses this command:
"X:\WINDOWS\system32\dism.exe" /image:"C:" /windir:"WINDOWS" /apply-unattend:"C:\_SMSTaskSequence\PkgMgrTemp\drivers.xml" /logpath:"C:\_SMSTaskSequence\PkgMgrTemp\dism.log"

#>