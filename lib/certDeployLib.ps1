. "$PSScriptRoot\sessions.ps1"

function Install-WebServerCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$target, 
        [Parameter(Mandatory=$true)]
        [string]$subject, 
        [Parameter(Mandatory=$true)]
        [string]$SANs, 
        [Parameter(Mandatory=$true)]
        [string]$name,

        [string]$TemplateName="webserver",
        [switch]$KeyExportable
    )

    $sessions = Get-PoCSessions -NeededHosts @('CA',$target) -UserName "SECLAB\Administrator"
    $pssCa = $sessions['CA']
    $pssTarget = $sessions[$target]

    if(-not (Test-Path C:\temp)){ mkdir C:\temp }

    Invoke-Command -Session $pssCa -ScriptBlock { if(-not (Test-Path C:\temp)){ mkdir C:\temp } }
    Invoke-Command -Session $pssTarget -ScriptBlock { if(-not (Test-Path C:\temp)){ mkdir C:\temp } }

    "Creating Cert-Request" | Write-Verbose
    Invoke-Command -Session $pssTarget -ScriptBlock {
        $exportable = if($using:KeyExportable){ "TRUE" }else{ "FALSE" }

    $inf = @"
[Version] 
Signature="`$Windows NT`$"

[NewRequest] 
Subject = "$($using:subject)"       ; For a wildcard use "CN=*.CONTOSO.COM" for example 
Exportable = $exportable            ; Private key is not exportable 
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
%szOID_SUBJECT_ALT_NAME2% = "{text}$($using:SANs)" 
%szOID_ENHANCED_KEY_USAGE% = "{text}%szOID_PKIX_KP_SERVER_AUTH%,%szOID_PKIX_KP_CLIENT_AUTH%"

"@

    $inf | Out-File "C:\temp\$($using:name).inf"
    
    cd C:\temp
    rm "$($using:name).req" -ErrorAction SilentlyContinue

    Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-new", "$($using:name).inf", "$($using:name).req") 
    }

    # transfer and submit requests
    "Transfering Cert-Request to CA" | Write-Verbose
    Copy-Item -Path C:\temp\$name.req -Destination C:\temp\ -FromSession $pssTarget
    Copy-Item -Path C:\temp\$name.req -Destination C:\temp\ -ToSession $pssCa

    "Submitting Cert-Request to CA" | Write-Verbose
    Invoke-Command -Session $pssCa -ScriptBlock {
        cd C:\temp
        rm "$($using:name).cer" -ErrorAction SilentlyContinue
        rm "$($using:name).rsp" -ErrorAction SilentlyContinue
        if(-not (Test-Path -Path "ca.cer")){
            Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-ca.cert", "ca.cer")
        }
        Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-config", "`"ca.corp.seclab.test\SECLAB RootCA`"", "-attrib", "CertificateTemplate:$($using:TemplateName)", "-submit", "$($using:name).req", "$($using:name).cer")
    }

    "Transfering Cert to Server" | Write-Verbose
    Copy-Item -Path C:\Temp\ca.cer -Destination C:\temp -FromSession $pssCa
    Copy-Item -Path C:\Temp\$name.cer -Destination C:\temp -FromSession $pssCa
    Copy-Item -Path C:\temp\ca.cer -Destination C:\temp -ToSession $pssTarget
    Copy-Item -Path C:\temp\$name.cer -Destination C:\temp -ToSession $pssTarget

    # install certificates
    "Installing Cert on Server" | Write-Verbose
    Invoke-Command -Session $pssTarget -ScriptBlock {
        cd C:\temp
        Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-addstore", "Root", "ca.cer")
        Start-Process -FilePath "certreq.exe" -Wait -NoNewWindow -WorkingDirectory C:\temp -ArgumentList @("-accept", "$($using:name).cer")
    }
}