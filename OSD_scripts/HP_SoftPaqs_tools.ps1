# Проверяем совместимость всех HP SoftPaq CVA-файлов на совместимость с Win10 LTSC. Указание WT64=OEM не означает, что SoftPaq совместим с любыми Win10 LTSB/LTSC.
# Если указано WTIOT64_1809=OEM, то совместимо только c LTSC 2019. Если указано WTIOT64_21H2=OEM то совместимо с LTSC 2021.
# https://www.apharmony.com/software-sagacity/2014/08/multi-line-regular-expression-replace-in-powershell/
[IO.Directory]::SetCurrentDirectory((Convert-Path (Get-Location -PSProvider FileSystem)))
$CVA_No_LTSC = @(); $CVA_Info_array = @(); (Get-Item *.cva).BaseName | % { # "sp136077" | % {
    $File = [IO.File]::ReadAllText("$_.cva");  
    $WinVer = @("WTIOT64", "WTIOT64_1607", "WTIOT64_1809", "WTIOT64_21H2") | % { if ($File -match "(?ms)\[Operating Systems\].*?($_=OEM).*?\[.+\]") { $_ } }
    if ($File -match "(?ms)\[Software Title\].*?(US=(.+?))\r\n.*?\[.+\]") { $Soft_Title_US = $Matches[2] }
    if ($File -match "(?ms)\[General\].*?Version=(.+?)\r\n.*?Category=(.+?)\r\n.*?VendorName=(.*?)\r\n.*?VendorVersion=(.*?)\r\n.*?\[.+\]") { $CVA_ver = $Matches[1]; $Drv_category = $Matches[2]; $Vendor_Name = $Matches[3]; $Vendor_Ver = $Matches[4] }
    if ($File -match "(?ms)\[CVA File Information\].*?CVATimeStamp=(\d{4})(\d{2})(\d{2})T.*?\[.+\]") { $CVA_date = "$($Matches[1])-$($Matches[2])-$($Matches[3])"  } 
    $SilentInstall = "" # Этот параметр может отсутствовать или принимать значения "N/A" "NA" "No Need", "None"
    if ($File -match "(?ms)\[Install Execution\].*?(SilentInstall=(.+?))\r\n.*?\[.+\]") { $SilentInstall = $Matches[2] }
    if ($SilentInstall -match '"(N/A|NA|No Need|None)"') { $SilentInstall = "" }
#    if ($WinVer) {  } else { } # No any WTIOT64
    if ($WinVer -contains "WTIOT64" -or ($WinVer -contains "WTIOT64_1809" -AND $WinVer -contains "WTIOT64_21H2")) { 
        # Полная поддержка обоих ОС LTSC 1809 и 21H2
        Write-Host ("$_ " + [string]$WinVer) -NoNewline -Fore Green
    } elseif ($WinVer) { # Частичная поддержка LTSC
        $CVA_No_LTSC += $_
        Write-Host ("$_ " + [string]$WinVer) -NoNewline -Fore Yellow
    } else { # Отсутствие поддержки любых LTSC
        $CVA_No_LTSC += $_
        Write-Host "$_" -NoNewline -Fore Red 
    }
    Write-Host " $CVA_date $Soft_Title_US $SP_ver" -NoNewline
    if ($Vendor_Ver -and ($SP_ver -ne $Vendor_Ver)) { Write-Host ", $Vendor_Name $Vendor_Ver" -NoNewline}
    Write-Host  
    $SS = Select-String -Path "$_.html" -Pattern "EFFECTIVE DATE:\s+(.*?)<br" # учитываем два косяка HP разрабов - 1) иногда есть слитное начало SP123456EFFECTIVE DATE, 2) изредка дата заканчивается как <br>, а не <br/>
    if ($SS) { $Drv_Date = ([DateTime]($SS[0].Matches.Groups[1].Value)).ToString("yyyy-MM-dd") } else { $Drv_Date = "" }
    $CVA_Info_array += New-Object -TypeName PSObject -Property  ([ordered]@{ 
        "SoftPaq" = $_; "Drv_Date" = $Drv_Date; "CVA_date" = $CVA_date; "Drv_category" = $Drv_category; "Soft_Title_US" = $Soft_Title_US; "CVA_ver" = $CVA_ver; "Vendor_Ver" = $Vendor_Ver;  "Size" = [int]((Get-Item "$_.exe").Length / 1Mb);  "SilentInstall" = $SilentInstall
    } )
}
echo "Number of CVA files without full support of all our Win10 LTSC is $($CVA_No_LTSC.Count)"
$CVA_Info_array | sort Drv_category,Soft_Title_US,Drv_Date | Out-GridView # вся интересная инфа про HP SoftPaq из CVA и HTML файлов

# Из уже закачанных HP SoftPaq убираем все драйвера графики AMD NVidia и ПО диагностики
$HP_SP_exclude = $CVA_Info_array | ? { ($_.Drv_category -eq "Diagnostic") -or ($_.Drv_category -match "Driver-(Graphics|Display)" -and $_.Soft_Title_US -match "(AMD|NVidia) ") }
New-Item "!Exclude" -ItemType Directory -EA 0; $HP_SP_exclude | % { Move-Item "$($_.SoftPaq).*" -Dest "!Exclude" }

# в текущей папке отодвигаем в сторонку софтпаки из категории диагностики
(Get-Item *.cva).BaseName | % { if (Select-String -Path "$_.cva" -Pattern "Category=Diagnostic") { Move-Item "$_.*" -Dest "!Exclude" } }

# Оказывается среди не совместимых с автоматикой SSM есть софтпаки как без SilentInstall, так и с нормальным значением, со строкой тихой установки !
(Get-Item *.cva).BaseName | % { if (Select-String -Path "$_.cva" -Pattern "SSMCompliant=0") { $CVA_Info_array | where SoftPaq -eq $_ } } | Out-GridView


# Более простой способ отобрать исключаемые драйвера графики через простой анализ только Contents.CSV (даже не CVA файлов)
$Folder = "exclude_graphics_Nvidia_AMD"; New-Item $Folder -ItemType Directory
Import-Csv -Path ".repository\Contents.CSV" -Delimiter ',' -Encoding UTF8 | where Title -Match "(Nvidia|AMD|Intel2) .*(Video|Graphics)" |` #Out-GridView
% { Move-Item "$($_.SoftPaq).*" -Dest $Folder }


$CVA_No_LTSC = (Get-Item *.cva).Name | % { if ([IO.File]::ReadAllText($_) -notmatch '(?ms)\[Operating Systems\].*?(WTIOT64=OEM|WTIOT64_1809=OEM.+WTIOT64_21H2=OEM).*?\[.+\]') { $_ } }
# поиск обоих значений в любом порядке (?=.*WTIOT64_1809=OEM)(?=.*WTIOT64_21H2=OEM) - сильно замедляет работу RegEx. regular expression and in any order (?=  https://perlancar.wordpress.com/2018/10/05/matching-several-things-in-no-particular-order-using-a-single-regex/


# Исправляем CVA-файлы с метаданными о HP SoftPaq. В итоге, в разделе [Operating Systems] обязательно должен быть параметр WTIOT64=OEM
[IO.Directory]::SetCurrentDirectory((Convert-Path (Get-Location -PSProvider FileSystem)))
New-Item "orig_copy" -ItemType Directory -Force | Out-Null
(Get-Item "*.cva").BaseName | % {
# "sp136077" | % {
$FileBody = [IO.File]::ReadAllText("$_.cva")

if ($FileBody -notmatch '(?ms)(.*\[Operating Systems\])(.*?)(\[.+\].*)') # Выделяем в тексте начало и конец интересующего нас раздела
     { Write-Host "$_ not found section [OS]" -Fore Magenta  }
else { 
    $FileBody_Before = $Matches[1];  $OS_support = $Matches[2];  $FileBody_After = $Matches[3] 

    $WinVer = $OS_support -Split '\r\n' | % { if ($_ -match "(WTIOT64(_.{4})?)=OEM") { $Matches[1] } }
    # $WinVer = @("WTIOT64", "WTIOT64_1507","WTIOT64_1607","WTIOT64_1809","WTIOT64_21H2") | % { if ($OS_support -match "$_=OEM") { $_ } }; 

    # есть ли в списке поддерживаемых ОС обе наши LTSB/LTSC - предыдущая и актуальная ? 
#    if ($OS_support -match "(?ms)(WTIOT64=OEM|(?=.*WTIOT64_1809=OEM)(?=.*WTIOT64_21H2=OEM))") { # через regex
    if ($WinVer -contains "WTIOT64" -or ($WinVer -contains "WTIOT64_1809" -AND $WinVer -contains "WTIOT64_21H2")) { # через уже выявленные WTIOT64
        Write-Host "$_ supported OS. " -Fore Green -NoNewline 
        # (как вариант: любая, но не старой версии 1507 - "(WTIOT64(_(?!1507)\d{4})?)=OEM" - отказался из-за будущего перехода с 1607 на 1809 и далее) 
    } else {
        $FileBody = $FileBody_Before + "`r`nWTIOT64=OEM" + $OS_support + $FileBody_After 
        Move-Item "$_.cva" -Dest ".\orig_copy\$_.cva" # На всякий случай переносим оригинал
        [IO.File]::WriteAllText("$_.cva", $FileBody)
        Write-Host "$_ added WTIOT64 " -Fore Yellow -NoNewline 
    }
    Write-Host ([string]$WinVer)
}}


[IO.Directory]::SetCurrentDirectory((Convert-Path (Get-Location -PSProvider FileSystem)))
#(Get-Item *.cva).Name | % { 
"sp96129" | % {
    if ([IO.File]::ReadAllText($_) -match '(?ms)\[Software Title\].*?US=(.*System\s?BIOS.*\r).*?\[.+\]') { echo $_ ($_ + " " + $Matches[1] ) }
}

# Среди всех CVA-файлов распознаем обновления BIOS и отодвигаем их в сторонку
cd "C:\SOE\HP_SoftPaqs\Msk_vMsHqFs02\All"
[IO.Directory]::SetCurrentDirectory((Convert-Path (Get-Location -PSProvider FileSystem)))
New-Item "System_BIOS" -ItemType Directory | Out-Null
(Get-Item *.cva).BaseName | % { if ([IO.File]::ReadAllText("$_.cva") -match '(?ms)\[Software Title\].*?US=(.*System\s?BIOS.*?)(?:\r|\n).*?\[US\.Software Description]\r\n(.*?)(?:\r|\n)') 
    { echo "`n" $_ $Matches[1] $Matches[2]; Get-Item "$_.*" | Move-Item -Dest "System_BIOS"} }


# отбираем все HP SoftPaq файлы (трех типов - cva, exe, html) для моделей компьютеров по regex-шаблону и с помощью HardLinks создаем их копию в подпапочке
$Folder = "SanZ - HP 800 G3, 700 G1";  $Model_pattern = 'HP EliteDesk 800 G3 SFF|HP EliteDesk 700 G1 SFF'
$Folder = "HP 800 G6, КГМК Мончегорск"; $Model_pattern = 'HP EliteDesk 800 G6 Small Form Factor'
Enter-PSSession "vSrSSCcmDP01"
if (-Not (Test-Path $Folder)) { New-Item $Folder -ItemType Directory }
Get-Item "*.cva" | ? { Select-String -Path $_.FullName -Quiet -Pattern $Model_pattern } | % { Write-Progress $_.BaseName
    $File = $_; if (-Not (Test-Path "$Folder\$($File.BaseName).cva")) { 
        @("cva", "exe", "html") | % { New-Item -ItemType HardLink -Name "$Folder\$($File.BaseName).$_" -Value "$($File.DirectoryName)\$($File.BaseName).$_" } 
    }
}


# Разбор HTM-отчета утилиты HP SSM (её можно запускать с парметром /Report)
function ConvertTo-Encoding ([string]$From, [string]$To){ Begin { $encFrom = [System.Text.Encoding]::GetEncoding($from); $encTo = [System.Text.Encoding]::GetEncoding($to) }
	Process{ $bytes = $encTo.GetBytes($_); $bytes = [System.Text.Encoding]::Convert($encFrom, $encTo, $bytes); $encTo.GetString($bytes) }
} # Простенькая функция для перекодировки текста из одной кодировки в другую,  https://xaegr.wordpress.com/2007/01/24/decoder/
if ([IO.File]::ReadAllText((Get-Item *.htm).Name) -match '<h3.*(?ms)Possible Updates.*</h3>\s*<ul>(.+)</ul>.*<h3.*Updates Performed') { 
    $HP_SSM_report = $Matches[1]
    $HP_SSM_report -Split '\r\n' | % { if ($_ -match "<li>.*Update (\d+):\t\t(.*)\t\t(.+)\t\t - Version\: (.+) \((.+)\.CVA\)</li>") { 
        $Str = $Matches[3] # некорректно закодированный русский текст - UTF-8 не трактуется таковым
        # $Str | Out-File "file.txt" -Encoding default; $SoftPaq_title = Get-Content "file.txt" -Encoding UTF8 # другой вариант решения проблемы с кодировками
        $SoftPaq_title = $Str | ConvertTo-Encoding "UTF-8" ([System.Text.Encoding]::GetEncoding([cultureinfo]::CurrentCulture.TextInfo.ANSICodePage)).HeaderName # "windows-1251"
        echo ("{0:D2} {1} '{2}' {3}, {4}" -f [int]$Matches[1], $Matches[5], $SoftPaq_title, $Matches[4], $Matches[2])
        # Write-Debug ([string]($Matches.Values | select -SkipLast 1))
    } }
}
# https://docs.microsoft.com/ru-ru/dotnet/api/system.text.encoding
@('utf-7', 'utf-8', 'utf-16', 'utf-16BE', 'utf-32', 'utf-32BE', 'windows-1251', 'Windows-1252', 'IBM037', 'IBM437', 'IBM500', 'ASMO-708', 'DOS-720', 'ibm737', 'ibm775', 'ibm850', 'ibm852', 'IBM855', 'ibm857', 'IBM00858', 'IBM860', 'ibm861', 'DOS-862', 'IBM863', 'IBM864', 'IBM865', 'cp866', 'ibm869', 'IBM870', 'windows-874', 'cp875', 'shift_jis', 'gb2312', 'ks_c_5601-1987', 'big5', 'IBM1026', 'IBM01047', 'IBM01140', 'IBM01141', 'IBM01142', 'IBM01143', 'IBM01144', 'IBM01145', 'IBM01146', 'IBM01147', 'IBM01148', 'IBM01149', 'windows-1250', 'windows-1253', 'windows-1254', 'windows-1255', 'windows-1256', 'windows-1257', 'windows-1258', 'Johab', 'macintosh', 'x-mac-japanese', 'x-mac-chinesetrad', 'x-mac-korean', 'x-mac-arabic', 'x-mac-hebrew', 'x-mac-greek', 'x-mac-cyrillic', 'x-mac-chinesesimp', 'x-mac-romanian', 'x-mac-ukrainian', 'x-mac-thai', 'x-mac-ce', 'x-mac-icelandic', 'x-mac-turkish', 'x-mac-croatian', 'x-Chinese-CNS', 'x-cp20001', 'x-Chinese-Eten', 'x-cp20003', 'x-cp20004', 'x-cp20005', 'x-IA5', 'x-IA5-German', 'x-IA5-Swedish', 'x-IA5-Norwegian', 'us-ascii', 'x-cp20261', 'x-cp20269', 'IBM273', 'IBM277', 'IBM278', 'IBM280', 'IBM284', 'IBM285', 'IBM290', 'IBM297', 'IBM420', 'IBM423', 'IBM424', 'x-EBCDIC-KoreanExtended', 'IBM-Thai', 'koi8-r', 'IBM871', 'IBM880', 'IBM905', 'IBM00924', 'EUC-JP', 'x-cp20936', 'x-cp20949', 'cp1025', 'koi8-u', 'iso-8859-1', 'iso-8859-2', 'iso-8859-3', 'iso-8859-4', 'iso-8859-5', 'iso-8859-6', 'iso-8859-7', 'iso-8859-8', 'iso-8859-9', 'iso-8859-13', 'iso-8859-15', 'x-Europa', 'iso-8859-8-i', 'iso-2022-jp', 'csISO2022JP', 'iso-2022-jp', 'iso-2022-kr', 'x-cp50227', 'euc-jp', 'EUC-CN', 'euc-kr', 'hz-gb-2312', 'GB18030', 'x-iscii-de', 'x-iscii-be', 'x-iscii-ta', 'x-iscii-te', 'x-iscii-as', 'x-iscii-or', 'x-iscii-ka', 'x-iscii-ma', 'x-iscii-gu', 'x-iscii-pa')


# сравнение хэш-сумм реальных SoftPaq EXE-шников с инфой из CVA файлов, тест доступности для закачки из инета. При различии в хэшах - загрузка из инета EXE и HTML файлов в подпапочку Downloaded
New-Item "Downloaded" -ItemType Directory
[IO.Directory]::SetCurrentDirectory((Convert-Path (Get-Location -PSProvider FileSystem)))
# @("sp71616", "sp71704", "sp72908", "sp95757", "sp96325", "sp96865") | % { Get-Item "$_.cva" } | % {
Get-Item "sp*.cva" | % {
if ($_.BaseName -match "^SP(\d+)") {
    $SP = $Matches[1]; Write-Progress $SP
    $FileBody = [IO.File]::ReadAllText("sp$SP.cva")
    if ($FileBody -notmatch '(?ms)(.*\[SoftPaq\])(.*?)(\[.+\].*)') { Write-Error "in $SP.CVA Not found section [SoftPaq] !" } 
    else {
        $SP_Hash_from_CVA = $Matches[2];
        if ($SP_Hash_from_CVA -match "SoftPaqMD5=(.+)") { $SP_Hash_from_CVA = $Matches[1] } else { Write-Error "in $SP.CVA not found MD5 !" }
        if (!(Test-Path "sp$SP.exe")) { $Hash_status = "NO exe for cva" } else {
            $SP_Hash_real_EXE = (Get-FileHash "sp$SP.exe" -Alg MD5).Hash 
            if ($SP_Hash_from_CVA.Trim() -eq $SP_Hash_real_EXE) { $Hash_status = "hash same" } else { $Hash_status = "hash diff" }
        }
   $begin = $SP - ($SP-1)%500; $end = $Begin+500-1;  
#   $URL_no_ext = "http://ftp.hp.com/pub/softpaq/sp$Begin-$End/sp$SP";
   $URL_no_ext = "http://anonymous@ftp.hp.com/pub/softpaq/sp$Begin-$End/sp$SP"
   try { 
        $Web_Head = wget "$URL_no_ext.exe" -Method 'Head' -EA Stop; 
        $Status = "Web request for EXE: " + [string]$Web_Head.StatusCode
        if ($Hash_status -eq "hash diff") {
            wget "$URL_no_ext.html" -OutFile "Downloaded\sp$SP.html"
            wget "$URL_no_ext.exe"  -OutFile "Downloaded\sp$SP.exe"
        }
    }
   catch { $Status = $Error[0].Exception.Message }
   echo "sp$SP $URL_no_ext.exe $Hash_status, $Status" #  
    }
}}


# Докачка тех SoftPaq файлов, которые HP SDM не смог закачать из-за генерации неверного URL-имени закачиваемых SaftPaq-файлов. Список СофтПаков с ошибкой закачки берем из лога самого HP SDM.
Get-Content "C:\ProgramData\HP\HP SoftPaq Download Manager\SoftPaqDownloadManager.log" | % { 
if ($_ -match "Status: SoftPaq \[http://ftp\.hp\.com/pub/caps-softpaq/softpaq/sp\d+-\d+/sp(\d+)\.exe\] may exist. \[Return code: Moved Permanently\]") { $Matches[1] } } | select -Unique | % {
    $SP = $_; $begin = $SP - ($SP-1)%500; $end = $Begin+500-1;  $URL_no_ext = "http://ftp.hp.com/pub/softpaq/sp$Begin-$End/sp$SP";
    Write-Host "sp$SP " -NoNewline
    if ((Test-Path "sp$SP.exe") -and (Test-Path "sp$SP.cva") -and (Test-Path "sp$SP.html")) { Write-Host "already exist !" -Fore Cyan } else {
    # https://serverfault.com/questions/718165/powershell-download-via-http-using-proxy-and-checking-remote-file-size-fails-on
# $NetWebClient = New-Object System.Net.WebClient - для проверки существования файла по его URL-адресу
    # try { $data = $NetWebClient.OpenRead("$URL_no_ext.cva") | Out-Null;  $data.Close(); $NetWebClient.Dispose();  Write-Host "exist !" -Fore Green } catch { Write-Host "not found!" -Fore Red }
    Write-Host "downloading $URL_no_ext.exe " -NoNewline
    try { 
        if (-not (Test-Path "sp$SP.exe")) { wget "$URL_no_ext.exe" -OutFile "sp$SP.exe" }
        if (-not (Test-Path "sp$SP.cva")) { wget "$URL_no_ext.cva" -OutFile "sp$SP.cva"; Write-Host "sp$SP.cva " -NoNewline }
        if (-not (Test-Path "sp$SP.html")) { wget "$URL_no_ext.cva" -OutFile "sp$SP.htm"; Write-Host "sp$SP.html " -NoNewline  }
        Write-Host "Success !" -Fore Green
    } catch { Write-Host "Error wget!" -Fore Red }
}}

# Все драйвера графики Intel
Get-Item *.cva | Select-String -Pattern "=Intel .*Graphic\w? .*Driver"

# ищем HP SoftPaq у которых есть CVA, но отсутствует HTML 
$SoftPaqs = (Get-Item *.cva).BaseName | % { if ( (Test-Path "$_.cva") -and (-Not (Test-Path "$_.html")) ) { $_ } }

# очень полезный внутренний файл программы HP SDM - все метаданные про HP SoftPaq, про модели компов, какие софткпаки уже заменены более новыми версиями
$HP_SDM_ProductCatalog_file_name = "D:\HP_SoftPaqs\ProductCatalog.xml" # "C:\ProgramData\HP\HP SoftPaq Download Manager\ProductCatalog.xml"

# Например, имея список названий HP SoftPaq, можно загрузить его файлы CVA,EXE,HTML с интернет серверов HP
foreach ($SoftPaq in $SoftPaqs) {
    $pattern = "<ReleaseNotesUrl>(ftp://ftp\.hp\.com/pub/softpaq/sp\d+-\d+/$SoftPaq\.html)</ReleaseNotesUrl>"
    $SelStr = Select-String -Path $HP_SDM_ProductCatalog_file_name -Pattern $pattern | select -First 1
    $SoftPaq_ReleaseNotesUrl = $SelStr.Matches.Groups[1].Value -replace "^ftp://","https://"
    Write-Progress "downloading $SoftPaq_ReleaseNotesUrl"; Invoke-WebRequest -Uri $SoftPaq_ReleaseNotesUrl -OutFile "$SoftPaq.html" -UseBasicParsing 
}
[xml]$XML_HP_SDM_ProductCatalog = Get-Content $HP_SDM_ProductCatalog_file_name
$XMLProductLine = $XML_HP_SDM_ProductCatalog.NewDataSet.ProductCatalog.ProductLine
$All_ProductModels = $XMLProductLine | % { Write-Progress "Product Line '$($_.Name)'" ; $_.ProductFamily | select @{n="Name_Fam";e={$_.Name}} -Exp ProductModel }

# XML конфиг со списком всех моделей HP и поддерживаемых версий ОС, для который можно сохранить и загрузить софтпаки в HPIA
[xml]$XML_HPIA_config = Get-Content "D:\HP_SoftPaqs\HPIA\HPIA_config_for_all_models.config"
$XML_MyProductsList = $XML_HPIA_config.configuration.userSettings.'HP.ImageAssistant.ImagePal.Properties.Settings'.setting | where name -eq "MyProductsList"
$XML_ProductInfo = $XML_MyProductsList.value.ArrayOfProductInfo.ProductInfo

# Вот мы и добрались до списка моделей с указанием конкретной ОС как это было в конфиге HPIA
$HPIA_config_all_models = $XML_ProductInfo | select @{n="Comp_ProductName";e={$_.Name}}, ProductID, @{n="Platf";e={$All_ProductModels | where Name -eq $_.Name | select -Exp SystemID }},`
 @{n="OS_ver";e={$_.OSList.OSInfo.DisplayVersion}}, @{n="OS_rel";e={$_.OSList.OSInfo.ReleaseID}}, @{n="OSid";e={$_.OSList.OSInfo.SupportedOSID}}, @{n="OS_Name";e={$_.OSList.OSInfo.Name}}
$HPIA_config_all_models | Out-GridView

New-Item ".AddSoftware" -ItemType Directory -EA 0 # Эта папка используется не CMSL, а скриптом HPIA-Repository-Downloader для указания доп. софта по каждой модели
$HPIA_config_all_models | sort Comp_ProductName | % { 
    $OS_ver = $_.OS_ver
    Write-Host "Add-RepositoryFilter for Model = '$($_.Comp_ProductName)' and OS = '$($_.OS_Name)' -osver $OS_ver.  Platforms: " -NoNewline
    $_.platf -split ',' | % { 
        Write-Host "$_, " -NoNewline 
        Add-RepositoryFilter -Platform $_ -Os "Win10" -OsVer $OS_ver -Category Driver,Bios,Firmware # -PreferLTSC 
        # Copy-Item ".AddSoftware\AddOns_additional_software.txt" ".AddSoftware\$_"
    };  Write-Host
}
# Add-RepositoryFilter : Cannot validate argument on parameter 'OsVer'. The argument "20H2" does not belong to the set "1809,1903,1909,2004,2009,21H1,21H2,22H2" specified by the ValidateSet attribute. Supply an argument that is in the set and then try the command again.
Add-RepositoryFilter -Platform 8054 -Os "Win10" -OsVer "21H2" -PreferLTSC -Category Driver,Bios,Firmware # для модели 'HP EliteDesk 800 G2 Small Form Factor PC' в HPIA Edit My Product List есть максимум версия 20H2, которую не удется добавить через этот командлет CMSL


# $HP_SDM_ProductCatalog_as_text = Get-Content $HP_SDM_ProductCatalog_file_name # очень медленно читается большой файл
Test-Path "$SoftPaq.html"


# https://www.hp.com/us-en/solutions/client-management-solutions/download.html
# HP Client Management Script Library 1.6.10 2023-04-26  https://hpia.hpcloud.hp.com/downloads/cmsl/hp-cmsl-1.6.10.exe

# https://developers.hp.com/hp-client-management/blog/driver-injection-hp-image-assistant-and-hp-cmsl-in-memcm
# HP Image Assistant and the HP Client Management Script Library can team up to deliver intelligent and efficient installation of HP drivers, bios, and other HP software in a MEMCM. 
# CMSL is able to create and maintain offline, intranet hosted respositories. HPIA can then utilize these repositories during OSD tasks or for normal driver updates, potentially eliminating the need to install driverpacks, or as a supplement to make sure any drivers installed during driverpack injection are up to date during the imaging steps. 
$Net_path = "\\vMsHqMDT01\HP_SoftPaqs"

# 2020-03 https://www.configjon.com/installing-the-hp-client-management-script-library/
# 3 ways to install CMSL - Install using the executable installer provided by HP, Install directly from the PoSh gallery using Install-Module, Copy the CMSL module files into the PoSh modules directory
$P = Start-Process "D:\HPIA\hp-cmsl-1.6.10.exe" -Arg "/Silent" -PassThru -Wait
if ($P.ExitCode -ne 0) { echo "Error setup CMSL ! EXE-installator returns ExitCode=$($P.ExitCode) !" } 
Import-Module "HP.Repo", "HP.Softpaq"


# https://developers.hp.com/hp-client-management/doc/initialize-repository
# Initialize a directory to be used as a repository and create a .repository folder in the current directory, which contains the definition of the .repository and all its settings.
# After initializing a repository, you must add at least one filter to define the content that this repository will receive.
# If the directory already contains a repository, this command will fail. In order to un-initalize a directory, simple remove the .repository folder.
New-Item $Net_path -ItemType Directory
Set-Location $Net_path
Initialize-Repository
 
# Critical step, and required by HP Image Assistant – done once.  https://developers.hp.com/hp-client-management/doc/set-repositoryconfiguration
Set-RepositoryConfiguration -setting OfflineCacheMode -Cachevalue Enable
# Specifies the new value for the OnRemoteFileNotFound setting. The value must be either: 'Fail' (default), or 'LogAndContinue'.
Set-RepositoryConfiguration -Setting OnRemoteFileNotFound -Value LogAndContinue


# Add a filter per specified platform to the current repository  https://developers.hp.com/hp-client-management/doc/add-repositoryfilter
# This command adds a filter to a repository that was previously initialized by the Initialize-Repository command. A repository can contain one or more filters, and filtering will be the based on all the filters defined. 
# -Platform <String> - specifies the platform using its platform ID to include in this repository. A platform ID, a 4-digit hexadecimal number, can be obtained by executing the Get-HPDeviceProductID command. This parameter is mandatory.
# -PreferLTSC - If specified and if the data file exists, this command uses the LTSB/LTSC Reference file for the specified platform ID. If the data file does not exist, this command uses the regular Reference file for the specified platform.
Add-RepositoryFilter -Platform "8717" -Os "Win10" -OsVer "21H2" -PreferLTSC -Category Bios,Firmware,Driver # HP ProDesk 400 G7 Microtower PC

Add-RepositoryFilter -Platform "1998" -Os "Win10" -OsVer "1809" -Category Bios,Firmware,Driver # HP EliteDesk 700 G1 SFF

Add-RepositoryFilter -Platform "8054" -Os "Win10" -OsVer "2004" -Category Bios,Firmware,Driver # HP EliteDesk 800 G2 SFF
# -OsVer "2009". if "20H2" - Cannot validate argument on parameter 'OsVer'. The argument "20H2" does not belong to the set "1809,1903,1909,2004,2009,21H1,21H2,22H2" specified by the ValidateSet attribute.

Remove-RepositoryFilter -Platform "1998" -Yes

cd "D:\HPIA\HP_250_G8"; # 85F3 85F4 85F5 881D 881E is for "HP 250 G8 Notebook PC", this model exist in SDM and bot supported in HPIA
"85F3 85F4 85F5 881D 881E 899F" -split ' ' | % { Add-RepositoryFilter -Platform $_ -Os "Win10" -OsVer "21H2" -PreferLTSC -Category Bios,Firmware,Driver }

Get-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" # ограничения по продолжительности RDP сеанса

# Sync and remove/clean-up superseded Softpaqs from the Repository (run command from the repository folder)
# This Step should be repeated on a regular basis, perhaps weekly to maintain the catalog. A PoSh script with both commands can be used and run on a schedule. Make sure they are called from the Repository folder.
# Synchronizes the current repository and generates a report that includes information about the repository  https://developers.hp.com/hp-client-management/doc/invoke-repositorysync
# This command performs a synchronization on the current repository by downloading the latest SoftPaqs associated with the repository filters and creates a repository report in a format (default .CSV) set via the Set-RepositoryConfiguration command.
# This command may be scheduled via task manager to run on a schedule. You can define a notification email via the Set-RepositoryNotificationConfiguration command to receive any failure notifications during unattended operation.
# NOTE: if the Invoke-RepositorySync command fails to sync, the HP Image Assistant execution will also fail to install. Make sure there are no errors with the Step 4 commands
Invoke-RepositorySync -Verbose

# This command removes SoftPaqs from the current repository that are labeled as obsolete. These may be SoftPaqs that have been replaced by newer versions, or SoftPaqs that no longer match the active repository filters.
Invoke-RepositoryCleanup -Verbose


# принципиальная проблема неспособности инструмента HP SSM ставить драйверы из свежих HP SoftPaq. Причина этого в том что HP стали применять новый метод запаковки exe-шников HP SoftPaq, про который не знает древняя утилита HP SSM. FAR ArcLite:PE→7z method="LZMA2:24 BCJ" solid
$SSM_report_log = "\\NSA632557\C$\Setup\Logs\OSD\HP_SSM_report_eDebug_ssmtrace.log"; $SSM_report_log = "\\vSrSscCMDP01\D$\HP_SoftPaqs\Models\HP ZBook Studio G7 Mobile Workstation\HP SSM не смог распаковать новые версии SP\HP_SSM_report_eDebug_ssmtrace.log"
$SS_err = Select-String -Path $SSM_report_log -Pattern "EDebug Error \*{5}: (SP\d+)\.CVA: Installer path not found:"; $SS_err | % { $_.Matches.Groups[1].Value }
$SS_ok  = Select-String -Path $SSM_report_log -Pattern "\((SP\d+).CVA\): Install succeeded\."; $SS_ok | % { $_.Matches.Groups[1].Value } | sort

<# На случай проблемы самой утилиты SSMmain.exe "Out of memory" может потребоваться установка не из-под HP SSM. Пример - NVidia driver
PS C:\Setup\SP_NVidia> .\sp135753.exe /?
Usage: /s /e /f <target-path>
  /s - Un-package the package in silent mode (not showing user interaction UI)
  /f - Runtime switch that overrides the default target path specified in build time
  /e - Prevent execution of default executable file specified in build time.
       Only extracting the content files to target folder(Use this with /s /f)
.\sp135753.exe /s /f Extract


$P = Start "T:\sp135753.exe" -Arg "-s" -Wait -PassThru
RmDir /S /Q C:\SWSetup\SP135753\

из распакованного СофтПака запускается c:\SWSetup\SP135753\InstallCmdWrapper.exe, который вызывает инсталлятор:
Process Path = c:\SWSetup\SP135753\src\Driver\Driver\setup.exe
Command Line = ./driver/setup.exe  -s -n
Current Directory = C:\Program Files\NVIDIA Corporation\Installer2\CoreTemp.{21AD4B79-A789-4CB9-873B-07228825D1F8}\

#>

