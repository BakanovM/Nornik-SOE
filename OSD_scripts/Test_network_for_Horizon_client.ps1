# Скрипт тестирования качества сетевого подключения для Vmware Horizon клиента 
# Баканов Максим 2023-03

$ScriptName = "Test_network_for_Horizon_client.ps1"

# Имя хоста с учетем заглавных и строчных символов как выдает HostName.exe
$CompName = (Get-ItemProperty "HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters\" -Name "HostName").HostName 
echo "HostName: $CompName"

# Собираем инфу о сети: сетевые адаптеры, IP-адрес, профиль соединения
$NetAdapters = Get-NetAdapter -physical | where status -eq 'up' # https://devblogs.microsoft.com/scripting/using-powershell-to-find-connected-network-adapters/
$IPv4_addr = Get-NetIPAddress -Type Unicast -AddressFamily IPv4 | ? PrefixOrigin -ne "WellKnown"
$NetRoutes_to_GW = Get-NetRoute | ? DestinationPrefix -eq '0.0.0.0/0'
$Net_conn_profiles = Get-NetConnectionProfile # https://stackoverflow.com/questions/33283848/determining-internet-connection-using-powershell

if ($DebugPreference -eq "Continue") { # При включенном отладочном режиме отображаем дополнительную инфу
$NetAdapters | select ifIndex, Name, InterfaceDescription, LinkSpeed, MacAddress | FT -Au
$IPv4_addr | select @{n="if";e={ $_.InterfaceIndex}}, @{n="IPv4 address";e={"$($_.IPAddress)/$($_.PrefixLength) $($_.PrefixOrigin)"}}
$NetRoutes_to_GW | select @{n="if";e={ $_.InterfaceIndex}}, NextHop, RouteMetric, InterfaceMetric, TypeOfRoute, Protocol | FT -Au 
$Net_conn_profiles | select @{n="if";e={$_.InterfaceIndex}}, Name, InterfaceAlias, NetworkCategory, @{n="IPv4Connect";e={$_.IPv4Connectivity}} | FT -Au
}
echo "All info about network on this system:"
foreach($NAdap in $NetAdapters) {
    $ifI = $NAdap.ifIndex; 
    $IPv4 = $IPv4_addr | ? InterfaceIndex -eq $ifI
    $ConnProfile = $Net_conn_profiles | ? InterfaceIndex -eq $ifI
    New-Object –TypeName PSObject –Property ([ordered]@{
        if_Index = $NAdap.ifIndex;
        If_Name = $NAdap.Name;
        InterfaceDescription = $NAdap.InterfaceDescription;
        LinkSpeed = $NAdap.LinkSpeed;
        MacAddress = $NAdap.MacAddress;
        IPv4_address = "$($IPv4.IPAddress)/$($IPv4.PrefixLength) $($IPv4.PrefixOrigin)";
        NextHop = ($NetRoutes_to_GW | ? InterfaceIndex -eq $ifI) | select -ExpandProperty NextHop
        NetworkCategory = $ConnProfile.NetworkCategory;
        IPv4Connect = $ConnProfile.IPv4Connectivity;
        ConnProfile = $ConnProfile.Name;
    })
}

# По IPv4 адресу шлюза Horizon можно определить находимся ли мы в КСПД или во внешнем интернете
if ((Resolve-DnsName "HV.nornik.ru" -Type A).IPAddress -contains "172.16.66.200") {
    echo "Detected internal IPv4 address in corp network.`n"
} else { echo "IPv4 address of HV.nornik.ru is outside of corp network.`n" }

# How to Get My Public IP Address Using PoSh - https://woshub.com/get-external-ip-powershell/
echo "Detecting Public Internet IP address:"
$PublicIP_services = "ipinfo.io/ip", "ifconfig.me/ip", "icanhazip.com", "ident.me" # "smart-ip.net/myip" # services that contain only the ip address (in the form of plain-text)
$PublicIP_services | % { Write-Progress $_; echo ( (Invoke-WebRequest -URI ("http://" + $_) -UseBasicParsing).Content.Trim() + " - request to '$_'" ) }

$Public_IP_Addr = (Invoke-WebRequest -URI ("http://" + $PublicIP_services[0]) -UseBasicParsing).Content.Trim()
$IRM = Invoke-RestMethod -Uri ('http://ipinfo.io/'+$Public_IP_Addr) -UseBasicParsing

$Inet_Provider = $IRM.org; if ($Inet_Provider -match "^AS\d+ (.+)") { $Inet_Provider = $Matches[1] }
echo "for IPv4 address $Public_IP_Addr the Geo Location (City) is '$($IRM.city)', internet provider is '$Inet_Provider'"

$Company_Horizon_Servers = "HV", "hvgw01", "hvgw02", "hvgw03", "hvgw11", "hvgw12", "hvgw13", "hvsp", "hvspgw01", "hvspgw02", "hvspgw11", "hvspgw12"

$Company_Horizon_Servers | % { $HostName = "$_.nornik.ru"
    try { 
        $DNS_resolve = Resolve-DnsName $HostName -EA Stop 
        try {
            Test-Connection $HostName -Count 1 -EA Stop | Out-Null
            $pings = Test-Connection $HostName -Count 3
            $NetConn_result = ""
            443, 8443 | % {
                $NetConn = Test-NetConnection $HostName -port $_ -WarningAction SilentlyContinue
                if ($NetConn.TcpTestSucceeded) { $NetConn_result += ([string]$_ + ":Yes, ") } else { $NetConn_result += ([string]$_ + ":NO!, ") }
            }
            $IPv4 = $pings[0].IPV4Address.IPAddressToString # $DNS_resolve.IP4Address
            echo "$HostName ($IPv4) : ping is $([string]($pings.ResponseTime)) ms, test socket connection - $NetConn_result"

        } catch { $Error[0].Exception.Message }
    }
    catch { $Error[0].Exception.Message }
}

# https://www.cyberdrain.com/monitoring-with-powershell-monitoring-internet-speeds/
# https://www.joakimnordin.com/is-it-possible-to-check-the-internet-performance-at-a-clients-network-using-powershell/  https://github.com/JoakimNordin/Speedtest/blob/master/speedtest.ps1
$URI_start = "https://www.speedtest.net/apps/cli" # Адрес странички, с которой начинаем поиск ссылки на закачку программы
try { 
    $IWR = IWR $URI_start -UseBasicParsing # может с первого раза не загрузиться
    $IWR.Links | % { if ($_.outerHTML -match '<a class=\".+" href=\"(.+)\">Download for Windows</a>') { $URI_to_utility = $Matches[1] } }
    echo "from Web page '$URI_start' we use download link: $URI_to_utility"
    # на момент 2023-03 было "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
} catch { 
    $Error[1].Exception.Message; $Error[1].ErrorDetails.Message 
}


Return

# Цифровая подпись с использованием сертификата сохраненного для админ учетки в CertMgr.msc -> Current User -> Personal -> Certificates
$Cert = Get-ChildItem cert:\CurrentUser\My –CodeSigningCert | Sort NotAfter | select -Last 1 # ? { $_.EnhancedKeyUsageList.FriendlyName -eq "Code Signing" } | 
Set-AuthenticodeSignature -FilePath $ScriptName -Certificate $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.sectigo.com"
<#
https://winitpro.ru/index.php/2016/11/17/kak-podpisat-skript-powershell-sertifikatom/
У командлета Set-AuthenticodeSignature есть специальный параметр TimestampServer, в котором указывается URL адрес Timestamp службы. 
Если этот параметр оставить пустым, то PS скрипт перестанет запускаться после истечения срока действия сертификата. Например -TimestampServer "http://timestamp.verisign.com/scripts/timstamp.dll" .

https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-authenticodesignature
This cmdlet adds an Authenticode signature to any file that supports Subject Interface Package (SIP).
In a PowerShell script file, the signature takes the form of a block of text that indicates the end of the instructions that are executed in the script. If there is a signature in the file when this cmdlet runs, that signature is removed.
-TimestampServer uses the specified time stamp server to add a time stamp to the signature. Type the URL of the time stamp server as a string. The URL must start with https:// or http://.
The time stamp represents the exact time that the certificate was added to the file. A time stamp prevents the script from failing if the certificate expires because users and programs can verify that the certificate was valid at the time of signing.
-HashAlgorithm specifies the hashing algorithm that Windows uses to compute the digital signature for the file. for PoSh 7.3, the default is SHA256, which is the Windows default hashing algorithm. For earlier versions, the default is SHA1.
you will need to know the URL of Sectigo's timestamping server "http://timestamp.sectigo.com", see https://sectigo.com/resource-library/time-stamping-server
#>

# SIG # Begin signature block
# MIIgIgYJKoZIhvcNAQcCoIIgEzCCIA8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDVtmftpGvBlhGo
# 1NPhQPDKDEvtG6zvlHCanuqMed++6aCCGgswggV2MIIDXqADAgECAhM4AAAACtrJ
# SITaigLjAAEAAAAKMA0GCSqGSIb3DQEBCwUAMBUxEzARBgNVBAMTCk5OLVJvb3Qt
# Q0EwHhcNMTcwMTExMTIzOTQ5WhcNMzcwMTA5MTQxOTQ0WjBVMRIwEAYKCZImiZPy
# LGQBGRYCcnUxFzAVBgoJkiaJk/IsZAEZFgdub3JuaWNrMRMwEQYKCZImiZPyLGQB
# GRYDbnByMREwDwYDVQQDEwhOTi1IUS1DQTCCASIwDQYJKoZIhvcNAQEBBQADggEP
# ADCCAQoCggEBANed1zSzoLSR0ikQhtk5brJs/3rOIBfRtTdjojH/9FpeJ2m9tgUB
# 6hK1DHk6mSVmY9JrSXuEYZoA1r877O//M9bhwQ670f2csmBn0mM+PEgL7FP2sBRb
# UC7/cGsWBmGe85D4yaG0PwIEQDCykhhXzJ3dt5Oo+rnTA+/BqrKggNcdjtPg8MYp
# KHHKsKJGbJYUg6NWpIehCIA+Q4Q0FXPcLnAKyolR/DXb3O6+oQCEHTZagNSkuEpj
# XfT+Ieh5IIhD/PD6aoJ8opf9CQb6XAmfPIYLT1Xppa8eOaX1dD6esifGK3DwHkAm
# 15aFn8iAAvUfmkU0hMcSr+g61iAg27BPas0CAwEAAaOCAX0wggF5MBAGCSsGAQQB
# gjcVAQQDAgECMCMGCSsGAQQBgjcVAgQWBBTm2dsEo4J+XB3vJ8ci9kFxo1LnNzAd
# BgNVHQ4EFgQUEBNStjX2FBU4RXenePFnjq01OSAwPwYDVR0gBDgwNjA0BgRVHSAA
# MCwwKgYIKwYBBQUHAgEWHmh0dHA6Ly9wa2kubm9ybmlrLnJ1L0NQUy5odG1sADAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBQTKBG+BwuyVH6OKxvFRabJFfYBQjA0BgNVHR8E
# LTArMCmgJ6AlhiNodHRwOi8vcGtpLm5vcm5pay5ydS9OTi1Sb290LUNBLmNybDBQ
# BggrBgEFBQcBAQREMEIwQAYIKwYBBQUHMAKGNGh0dHA6Ly9wa2kubm9ybmlrLnJ1
# L1ZNU0hRUk9PVENBMDFfTk4tUm9vdC1DQSgxKS5jcnQwDQYJKoZIhvcNAQELBQAD
# ggIBAFyTDI+IIRDHYfSH9LBihzjzDh/UlRU4q59Lg1kCQ/vVJhqHE+0uFQSeoFyy
# lQPq/8apmIRj21TIwFDoYa0NyUnw5YNfvf8KUAplzy08SutuYkdCCf7RpptW2rCG
# zWKfL9YeEjWhAJH3lL/zxb0ajtXCj4H0NgFmAIwpZMWIInGwr6QC6O39RuvhLSGR
# TNi4bcJyJPm3Fjsi9X+B76mxSsZtJRPCDT9V1C7Wy8KNxojprWi80zCfbMz7pyS8
# ZWrCKksyfICvCUWO+P/3B6dmEOwHl6ZIvJv5iYEp+Tk4aVRYpqNCH4cwHeXB081l
# auQXAsv1OFbwNLXWnK2ytXanmggcvjI5Ql8FohOUy3rJweXlXmRGIUSz13nWur1J
# FD/nMZTk+UNIZewRfmEq3S8Nv47vt2GfM0Hk+hOH6tmYoJrqrzWCbC23Oc29bFDA
# 9HLyQaoXaZeXcC0Us3t1s1smQL6WOBnyL4qmWH2uUi93pZGl3aeyxGUcxX9YhdA+
# 721cMgY6qbO8NytuQEJ2r82QuUaLHTvsyuhQtGOKUsL5cL9bjhvH09K+NUKHZMpw
# Tv2U4otQJZH21dilsQL79FH4C9SW8ohJETec9NKkEkwy9fDI441opO+WXjWNPeJz
# tbtNj4Ko2KcTikVng4ItlcaIkl7/huaOUc+wX9mH8N299lOOMIIGpDCCBYygAwIB
# AgITRgAHcWeWKzFvXdW+SAACAAdxZzANBgkqhkiG9w0BAQsFADBVMRIwEAYKCZIm
# iZPyLGQBGRYCcnUxFzAVBgoJkiaJk/IsZAEZFgdub3JuaWNrMRMwEQYKCZImiZPy
# LGQBGRYDbnByMREwDwYDVQQDEwhOTi1IUS1DQTAeFw0yMzAzMjIxNjIxMDNaFw0y
# NTAzMjExNjIxMDNaMIGXMRIwEAYKCZImiZPyLGQBGRYCcnUxFzAVBgoJkiaJk/Is
# ZAEZFgdub3JuaWNrMRMwEQYKCZImiZPyLGQBGRYDbnByMQwwCgYDVQQLEwNTU0Mx
# DDAKBgNVBAsTA1NBUjEPMA0GA1UECxMGQWRtaW5zMSYwJAYDVQQDDB3QkdCw0LrQ
# sNC90L7QsiDQnC7QoS4gLSBhZG1pbjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBAMJ9KiWaz9EXElr93nqqjf0/msT13eY9ghbYZiZlSDgip3CFl0ZPBuwl
# STcEe+mcUPkHrjOu592NoYnJtQvc52E6MhC/QmXWoqTwjjZhbho5SXOuH9ddvbyR
# 4DL5J+n8MKPm8GNy9SoMPEozKPkdRCgQtuRjbRRWxaJPrFg81GgfyDNQECAfw6e8
# DSOlj6gjz0Zwpu3zlh/y9iHu9MUUQcZJIsBj0XMo1TwT4JSKYBEcQwHN0pW6yzsr
# LoNqLQ9lOXOvrC693TnmqhAKRjUbv3Ng6Kb6mr/tSFQqSJ1COuFdn6SlJRY4gs/b
# WRl5OURMbBysZ2FeS0aTisJJRjhb9xUCAwEAAaOCAygwggMkMDwGCSsGAQQBgjcV
# BwQvMC0GJSsGAQQBgjcVCIPy8jiB7MpigcWLOoaP3xODra8zRoXG83O9xDYCAWQC
# AQgwEwYDVR0lBAwwCgYIKwYBBQUHAwMwCwYDVR0PBAQDAgeAMBsGCSsGAQQBgjcV
# CgQOMAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYEFEanCyHnCAE63V4QY6t2UzB77Yk2
# MB8GA1UdIwQYMBaAFBATUrY19hQVOEV3p3jxZ46tNTkgMIHwBgNVHR8EgegwgeUw
# geKggd+ggdyGgbZsZGFwOi8vL0NOPU5OLUhRLUNBLENOPU5OUEtJLENOPUNEUCxD
# Tj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1
# cmF0aW9uLERDPWFkcm9vdCxEQz1ub3JuaWNrLERDPXJ1P2NlcnRpZmljYXRlUmV2
# b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2lu
# dIYhaHR0cDovL3BraS5ub3JuaWsucnUvTk4tSFEtQ0EuY3JsMIIBHgYIKwYBBQUH
# AQEEggEQMIIBDDCBsAYIKwYBBQUHMAKGgaNsZGFwOi8vL0NOPU5OLUhRLUNBLENO
# PUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1D
# b25maWd1cmF0aW9uLERDPWFkcm9vdCxEQz1ub3JuaWNrLERDPXJ1P2NBQ2VydGlm
# aWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MDAG
# CCsGAQUFBzAChiRodHRwOi8vcGtpLm5vcm5pay5ydS9OTi1IUS1DQSgyKS5jcnQw
# JQYIKwYBBQUHMAGGGWh0dHA6Ly9wa2kubm9ybmlrLnJ1L29jc3AwUAYJKwYBBAGC
# NxkCBEMwQaA/BgorBgEEAYI3GQIBoDEEL1MtMS01LTIxLTE0Mjc0OTMyODctMjg5
# MjA3NDEzNC0yODMzODAzMTgtMTU2MDMyMA0GCSqGSIb3DQEBCwUAA4IBAQB1KymT
# W5srQchDgUnV6HHGeB9h4Mn2Idn5OsIohpXocLzsH/QR0AvxR1FP2PNo5p4toDe8
# PE5HhcqMmjp7TTvxryURN5nOltvTrNhZTWLs3zKSk/O2PTSS8i2tWd1okncnzOcS
# LwKqIaeH9TLmkMAX4NHkLTg7LFnXzHoIOVp6BNCGVJVjOk1Om1x7XA4XdfKtQV4/
# XeB0RMf6ZvUcAlZmPT5r2sVVEGR7GpwTv9lGK8G8Rar6zAyBc4TA8B/2hrVzf4HN
# 7OLXFNMme3e2Z7QUZZF5zn4/gNWKpe1sC7U4uUEQxVdSKa6Tzdxlk0fqf9y9RU7n
# lQSmRobnA1SJDj2UMIIG7DCCBNSgAwIBAgIQMA9vrN1mmHR8qUY2p3gtuTANBgkq
# hkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkx
# FDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5l
# dHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBSU0EgQ2VydGlmaWNhdGlvbiBBdXRo
# b3JpdHkwHhcNMTkwNTAyMDAwMDAwWhcNMzgwMTE4MjM1OTU5WjB9MQswCQYDVQQG
# EwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxm
# b3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJTAjBgNVBAMTHFNlY3RpZ28g
# UlNBIFRpbWUgU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDIGwGv2Sx+iJl9AZg/IJC9nIAhVJO5z6A+U++zWsB21hoEpc5Hg7XrxMxJ
# NMvzRWW5+adkFiYJ+9UyUnkuyWPCE5u2hj8BBZJmbyGr1XEQeYf0RirNxFrJ29dd
# SU1yVg/cyeNTmDoqHvzOWEnTv/M5u7mkI0Ks0BXDf56iXNc48RaycNOjxN+zxXKs
# Lgp3/A2UUrf8H5VzJD0BKLwPDU+zkQGObp0ndVXRFzs0IXuXAZSvf4DP0REKV4TJ
# f1bgvUacgr6Unb+0ILBgfrhN9Q0/29DqhYyKVnHRLZRMyIw80xSinL0m/9NTIMdg
# aZtYClT0Bef9Maz5yIUXx7gpGaQpL0bj3duRX58/Nj4OMGcrRrc1r5a+2kxgzKi7
# nw0U1BjEMJh0giHPYla1IXMSHv2qyghYh3ekFesZVf/QOVQtJu5FGjpvzdeE8Nfw
# KMVPZIMC1Pvi3vG8Aij0bdonigbSlofe6GsO8Ft96XZpkyAcSpcsdxkrk5WYnJee
# 647BeFbGRCXfBhKaBi2fA179g6JTZ8qx+o2hZMmIklnLqEbAyfKm/31X2xJ2+opB
# JNQb/HKlFKLUrUMcpEmLQTkUAx4p+hulIq6lw02C0I3aa7fb9xhAV3PwcaP7Sn1F
# NsH3jYL6uckNU4B9+rY5WDLvbxhQiddPnTO9GrWdod6VQXqngwIDAQABo4IBWjCC
# AVYwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYDVR0OBBYEFBqh
# +GEZIA/DQXdFKI7RNV8GEgRVMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAG
# AQH/AgEAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBQ
# BgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRy
# dXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwdgYIKwYBBQUHAQEEajBo
# MD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0
# UlNBQWRkVHJ1c3RDQS5jcnQwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIBAG1UgaUzXRbhtVOBkXXfA3oyCy0l
# hBGysNsqfSoF9bw7J/RaoLlJWZApbGHLtVDb4n35nwDvQMOt0+LkVvlYQc/xQuUQ
# ff+wdB+PxlwJ+TNe6qAcJlhc87QRD9XVw+K81Vh4v0h24URnbY+wQxAPjeT5OGK/
# EwHFhaNMxcyyUzCVpNb0llYIuM1cfwGWvnJSajtCN3wWeDmTk5SbsdyybUFtZ83J
# b5A9f0VywRsj1sJVhGbks8VmBvbz1kteraMrQoohkv6ob1olcGKBc2NeoLvY3NdK
# 0z2vgwY4Eh0khy3k/ALWPncEvAQ2ted3y5wujSMYuaPCRx3wXdahc1cFaJqnyTdl
# Hb7qvNhCg0MFpYumCf/RoZSmTqo9CfUFbLfSZFrYKiLCS53xOV5M3kg9mzSWmglf
# jv33sVKRzj+J9hyhtal1H3G/W0NdZT1QgW6r8NDT/LKzH7aZlib0PHmLXGTMze4n
# muWgwAxyh8FuTVrTHurwROYybxzrF06Uw3hlIDsPQaof6aFBnf6xuKBlKjTg3qj5
# PObBMLvAoGMs/FwWAKjQxH/qEZ0eBsambTJdtDgJK0kHqv3sMNrxpy/Pt/360KOE
# 2See+wFmd7lWEOEgbsausfm2usg1XTN2jvF8IAwqd661ogKGuinutFoAsYyr4/kK
# yVRd1LlqdJ69SK6YMIIG9TCCBN2gAwIBAgIQOUwl4XygbSeoZeI72R0i1DANBgkq
# hkiG9w0BAQwFADB9MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5j
# aGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0
# ZWQxJTAjBgNVBAMTHFNlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgQ0EwHhcNMjMw
# NTAzMDAwMDAwWhcNMzQwODAyMjM1OTU5WjBqMQswCQYDVQQGEwJHQjETMBEGA1UE
# CBMKTWFuY2hlc3RlcjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQD
# DCNTZWN0aWdvIFJTQSBUaW1lIFN0YW1waW5nIFNpZ25lciAjNDCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAKSTKFJLzyeHdqQpHJk4wOcO1NEc7GjLAWTk
# is13sHFlgryf/Iu7u5WY+yURjlqICWYRFFiyuiJb5vYy8V0twHqiDuDgVmTtoeWB
# IHIgZEFsx8MI+vN9Xe8hmsJ+1yzDuhGYHvzTIAhCs1+/f4hYMqsws9iMepZKGRNc
# rPznq+kcFi6wsDiVSs+FUKtnAyWhuzjpD2+pWpqRKBM1uR/zPeEkyGuxmegN77tN
# 5T2MVAOR0Pwtz1UzOHoJHAfRIuBjhqe+/dKDcxIUm5pMCUa9NLzhS1B7cuBb/Rm7
# HzxqGXtuuy1EKr48TMysigSTxleGoHM2K4GX+hubfoiH2FJ5if5udzfXu1Cf+hgl
# TxPyXnypsSBaKaujQod34PRMAkjdWKVTpqOg7RmWZRUpxe0zMCXmloOBmvZgZpBY
# B4DNQnWs+7SR0MXdAUBqtqgQ7vaNereeda/TpUsYoQyfV7BeJUeRdM11EtGcb+Re
# DZvsdSbu/tP1ki9ShejaRFEqoswAyodmQ6MbAO+itZadYq0nC/IbSsnDlEI3iCCE
# qIeuw7ojcnv4VO/4ayewhfWnQ4XYKzl021p3AtGk+vXNnD3MH65R0Hts2B0tEUJT
# cXTC5TWqLVIS2SXP8NPQkUMS1zJ9mGzjd0HI/x8kVO9urcY+VXvxXIc6ZPFgSwVP
# 77kv7AkTAgMBAAGjggGCMIIBfjAfBgNVHSMEGDAWgBQaofhhGSAPw0F3RSiO0TVf
# BhIEVTAdBgNVHQ4EFgQUAw8xyJEqk71j89FdTaQ0D9KVARgwDgYDVR0PAQH/BAQD
# AgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0g
# BEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0
# aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEQGA1UdHwQ9MDswOaA3oDWGM2h0dHA6Ly9j
# cmwuc2VjdGlnby5jb20vU2VjdGlnb1JTQVRpbWVTdGFtcGluZ0NBLmNybDB0Bggr
# BgEFBQcBAQRoMGYwPwYIKwYBBQUHMAKGM2h0dHA6Ly9jcnQuc2VjdGlnby5jb20v
# U2VjdGlnb1JTQVRpbWVTdGFtcGluZ0NBLmNydDAjBggrBgEFBQcwAYYXaHR0cDov
# L29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAEybZVj64HnP7xXD
# Mm3eM5Hrd1ji673LSjx13n6UbcMixwSV32VpYRMM9gye9YkgXsGHxwMkysel8Cbf
# +PgxZQ3g621RV6aMhFIIRhwqwt7y2opF87739i7Efu347Wi/elZI6WHlmjl3vL66
# kWSIdf9dhRY0J9Ipy//tLdr/vpMM7G2iDczD8W69IZEaIwBSrZfUYngqhHmo1z2s
# IY9wwyR5OpfxDaOjW1PYqwC6WPs1gE9fKHFsGV7Cg3KQruDG2PKZ++q0kmV8B3w1
# RB2tWBhrYvvebMQKqWzTIUZw3C+NdUwjwkHQepY7w0vdzZImdHZcN6CaJJ5OX07T
# jw/lE09ZRGVLQ2TPSPhnZ7lNv8wNsTow0KE9SK16ZeTs3+AB8LMqSjmswaT5qX01
# 0DJAoLEZKhghssh9BXEaSyc2quCYHIN158d+S4RDzUP7kJd2KhKsQMFwW5kKQPqA
# bZRhe8huuchnZyRcUI0BIN4H9wHU+C4RzZ2D5fjKJRxEPSflsIZHKgsbhHZ9e2hP
# jbf3E7TtoC3ucw/ZELqdmSx813UfjxDElOZ+JOWVSoiMJ9aFZh35rmR2kehI/shV
# Cu0pwx/eOKbAFPsyPfipg2I2yMO+AIccq/pKQhyJA9z1XHxw2V14Tu6fXiDmCWp8
# KwijSPUV/ARP380hHHrl9Y4a1LlAMYIFbTCCBWkCAQEwbDBVMRIwEAYKCZImiZPy
# LGQBGRYCcnUxFzAVBgoJkiaJk/IsZAEZFgdub3JuaWNrMRMwEQYKCZImiZPyLGQB
# GRYDbnByMREwDwYDVQQDEwhOTi1IUS1DQQITRgAHcWeWKzFvXdW+SAACAAdxZzAN
# BglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqG
# SIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3
# AgEVMC8GCSqGSIb3DQEJBDEiBCDJhIk2zcHrh+Wt6gREc3ZpLRK2r7v6AT6cpLjm
# yTnYKDANBgkqhkiG9w0BAQEFAASCAQBDlO474F/zyd2Tr+sZUnV0mtC9+r2gJ1tL
# tB4pnWzuqFmT62HRnXX5P8JcXgEyx0E5g8vHtzYEu+zInp401QtXrfZGqQPRYP38
# XwWfYkkyu6E+ik0dcQ93lc06y1NpeqeaCj4KmWTqtmF9xgqwVXox7txYHnsnew2E
# B/Jpkyi6aGNpzU/3Ta3vMMHe1sB5WdValxzlHciT8RmvjWeY2MlM6suqa7Wsdul2
# 8SLJaWuhhw7hcuQ0LdjwU/xF+j0FdMuWFr9msa+Xxm7oC+DmFnV22RAFzqPy3uwE
# cY2lhN06X+FAJcPG4lK8LHdlhuxHswqG1YkB/4sXuf1Jg+lqAbxIoYIDSzCCA0cG
# CSqGSIb3DQEJBjGCAzgwggM0AgEBMIGRMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQI
# ExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGDAWBgNVBAoT
# D1NlY3RpZ28gTGltaXRlZDElMCMGA1UEAxMcU2VjdGlnbyBSU0EgVGltZSBTdGFt
# cGluZyBDQQIQOUwl4XygbSeoZeI72R0i1DANBglghkgBZQMEAgIFAKB5MBgGCSqG
# SIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTIzMDkwNzExMDEz
# OFowPwYJKoZIhvcNAQkEMTIEMPwnb71secKdsnxbp7gOy3MoW1+xrHjYI4P7A2Co
# Wo5AG1tqQ+NZi4mduDN8dhUDgzANBgkqhkiG9w0BAQEFAASCAgBGsuaXH0Cb4dLg
# 0IF3JQkiaHaI5u1o2JWG37GnXeOkl2YfC9KPSSXVkSFHVvaED3Tc7v7MfxT05isR
# bAa36ovwXXSMKroEbWuze5UVs8ZnPo2rI6anUZiQZrQ5I/zES04bE/x9Opx2XdkU
# UWg7EY+p1tbHLFVNGoIj4ZfH63W3Q4mxnISkizOjvkoif7JvXY/IW2wHrudYVXcr
# tW7Vx20CdEGmIHpu1NBleQoeyi9UsUsNIOJ3T6peP5p7/GYKXFPredgoeXC/+tTC
# oHwKDY5fq6U+qsX9JRXnUzYWGn9ZX7jkWgObyh9KeI2C7kmXzcZ3Y0E3tvI7li1K
# FESVcJnxE/k2FYH5tfrPQczWYQfntw1hf+QZk3ubfpOkjRWm/hUe8rwQ5tCIuHNm
# ZnWzX9xOKXtSi4lt6S4ZOqihXs/ZWFyhqwiUJFl8sTTemdM6T3OA4B8iaXI56aO7
# W8gH+Mfno8uCUggR+H0Ul5g4pJNjUxNyAVzZEbh83VP8MCK7/rEkK9wAatVvWlrn
# CsZ1doO3Hd5fD269AOSTrInAhtQFWAMZbKvaSvh1zPdWYv38YQzYz2qoAyY2Demh
# plxSgPGtCDcrSCtbEhSr9AVpICN4jH2eVZ6BHJ8M5xAOh6wiXXiKlKyGfKbFB5vv
# 7hk1QJQeyKLN/JIOO//+hH5kjOPojA==
# SIG # End signature block
