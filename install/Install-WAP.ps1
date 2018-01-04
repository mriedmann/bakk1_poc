# https://technet.microsoft.com/en-us/library/dn383662(v=ws.11).aspx

$ErrorActionPreference = "Stop"

# create sessions
$pssDc = New-PSSession -ComputerName "10.0.0.10" -Credential (Get-Credential -UserName "SECLAB\Administrator" -Message "DC Creds")
$pssWap = New-PSSession -ComputerName "10.10.10.10" -Credential (Get-Credential -UserName "Administrator" -Message "WAP Creds")

# env setup
if(-not (Test-Path ..\temp)){ mkdir ..\temp }

###### Handle Certificates

# create and transfer requests
$certConf = @([PSCustomObject]@{
    Name="WAP-AppCert"
    Subject="CN=*.SECLAB.TEST"
    SANs="dns=*.seclab.test"
},[PSCustomObject]@{
    Name="WAP-FSProxyCert"
    Subject="CN=FS.SECLAB.TEST"
    SANs="dns=fs.seclab.test&dns=enterpriseregistration.seclab.test"
})

$certNames = $certConf | select -ExpandProperty Name

$certConf | %{

$subject = $_.Subject
$SANs = $_.SANs
$name = $_.Name

$inf = @"
[Version] 
Signature="`$Windows NT`$"

[NewRequest] 
Subject = "$subject"   ; For a wildcard use "CN=*.CONTOSO.COM" for example 
Exportable = FALSE                  ; Private key is not exportable 
KeyLength = 2048                    ; Common key sizes: 512, 1024, 2048, 4096, 8192, 16384 
KeySpec = 1                         ; AT_KEYEXCHANGE 
KeyUsage = 0xA0                     ; Digital Signature, Key Encipherment 
MachineKeySet = True                ; The key belongs to the local computer account 
ProviderName = "Microsoft RSA SChannel Cryptographic Provider" 
ProviderType = 12 
SMIME = FALSE 
RequestType = CMC

[Strings] 
szOID_SUBJECT_ALT_NAME2 = "2.5.29.17" 
szOID_ENHANCED_KEY_USAGE = "2.5.29.37" 
szOID_PKIX_KP_SERVER_AUTH = "1.3.6.1.5.5.7.3.1" 
szOID_PKIX_KP_CLIENT_AUTH = "1.3.6.1.5.5.7.3.2"

[Extensions] 
%szOID_SUBJECT_ALT_NAME2% = "{text}$SANs" 
%szOID_ENHANCED_KEY_USAGE% = "{text}%szOID_PKIX_KP_SERVER_AUTH%,%szOID_PKIX_KP_CLIENT_AUTH%"

"@

$inf | Out-File "..\temp\$name.inf"
}

Invoke-Command -Session $pssWap -ScriptBlock { if(-not (Test-Path C:\temp)){ mkdir C:\temp } }
Copy-Item -Path ..\temp\*.inf -Destination C:\temp\ -ToSession $pssWap
Invoke-Command -Session $pssWap -ScriptBlock {
    cd C:\temp
    rm *.req

    $using:certNames | % {
        Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-new", "$_.inf", "$_.req") 
    }
}
Copy-Item -Path C:\Temp\*.req -Destination ..\temp -FromSession $pssWap

# transfer and submit requests
Invoke-Command -Session $pssDc -ScriptBlock { if(-not (Test-Path C:\temp)){ mkdir C:\temp } }
Copy-Item -Path ..\temp\*.req -Destination C:\temp\ -ToSession $pssDc
Invoke-Command -Session $pssDc -ScriptBlock {
    cd C:\temp
    rm *.cer
    rm *.rsp
    Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-ca.cert", "ca.cer")
    $using:certNames | % {
        Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-config", "`"DC01.corp.seclab.test\SECLAB RootCA`"", "-attrib", "CertificateTemplate:webserver", "–submit", "$_.req", "$_.cer")
    }
}
Copy-Item -Path C:\Temp\*.cer -Destination ..\temp -FromSession $pssDc

# transfer and install certificates
Copy-Item -Path ..\temp\*.cer -Destination C:\temp\ -ToSession $pssWap
Invoke-Command -Session $pssWap -ScriptBlock {
    cd C:\temp
    Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-addstore", "Root", "ca.cer")
    $using:certNames | % {
        Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("–accept", "$_.cer")
    }
}

###### Install WAP

Invoke-Command -Session $pssWap -ScriptBlock {
    Install-WindowsFeature Web-Application-Proxy -IncludeManagementTools
}

Invoke-Command -Session $pssWap -ScriptBlock {
    $fsCert = Get-ChildItem Cert:\LocalMachine\My | ?{ $_.Subject -like "*=fs.seclab.test*" } | select -First 1
    Install-WebApplicationProxy –CertificateThumbprint ($fsCert.Thumbprint) -FederationServiceName fs.seclab.test
    Restart-Computer
}

###### Configure WebApplication

Invoke-Command -Session $pssWap -ScriptBlock {
    $appCert = Get-ChildItem Cert:\LocalMachine\My | ?{ $_.Subject -match ".*=\*\.seclab\.test" } | select -First 1

    Add-WebApplicationProxyApplication `
        -BackendServerUrl 'https://rdg.seclab.test' `
        -ExternalCertificateThumbprint $appCert.Thumbprint `
        -EnableHTTPRedirect:$true `
        -ExternalUrl 'https://rdg.seclab.test' `
        -Name 'RDS' `
        -ExternalPreAuthentication ADFS `
        -ADFSRelyingPartyName 'RDS'
    
    Get-WebApplicationProxyApplication | Set-WebApplicationProxyApplication -DisableHttpOnlyCookieProtection:$true
}