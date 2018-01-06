. "$PSScriptRoot\..\lib\sessions.ps1"
. "$PSScriptRoot\..\lib\certDeployLib.ps1"

$ErrorActionPreference = "Stop"

# create sessions
$sessions = Get-PoCSessions -NeededHosts DC,CA,RDS -UserName "SECLAB\Administrator"
$pssDc = $sessions['DC']
$pssCa = $sessions['CA']
$pssRds = $sessions['RDS']

Invoke-Command -Session $pssDc -ScriptBlock {
    If(-not (Get-DnsServerResourceRecord -Name rdg -ZoneName seclab.test -ErrorAction SilentlyContinue)){
        Add-DnsServerResourceRecordA -Name rdg -ZoneName seclab.test -IPv4Address 10.0.0.40
    }
}

$certs = Invoke-Command -Session $pssRds -ScriptBlock { Get-ChildItem -Path Cert:\LocalMachine\My -DnsName "rdg.seclab.test" | ? Issuer -ne "CN=rdg.seclab.test" }
if(-not $certs){
    Install-WebServerCertificate -target RDS -subject "CN=rdg.seclab.test" -SANs "dns=rdg.seclab.test&dns=rds.corp.seclab.test" -name "rdg-web" -TemplateName "exportablewebserver" -KeyExportable -Verbose
}

Invoke-Command -Session $pssRds -ScriptBlock {
    $cert = Get-ChildItem -Path Cert:\LocalMachine\My -DnsName "rdg.seclab.test" | ? Issuer -ne "CN=rdg.seclab.test" | select -First 1
    $pfxPassword = (Read-Host -AsSecureString -Prompt "Enter PFX export password")
    Export-PfxCertificate -Cert $cert -FilePath C:\temp\rds.pfx -Password $pfxPassword
}


