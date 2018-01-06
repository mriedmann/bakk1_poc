. "$PSScriptRoot\..\lib\sessions.ps1"
. "$PSScriptRoot\..\lib\certDeployLib.ps1"

$ErrorActionPreference = "Stop"

# create sessions
$sessions = Get-PoCSessions -NeededHosts DC,CA,ADFS -UserName "SECLAB\Administrator"
$pssDc = $sessions['DC']
$pssCa = $sessions['CA']
$pssAdfs =  $sessions['ADFS']

Invoke-Command -Session $pssAdfs -ScriptBlock {
    Install-windowsfeature adfs-federation –IncludeManagementTools
}

Invoke-Command -Session $pssDc -ScriptBlock {
    if(-not (Get-KdsRootKey)) {
        Add-KdsRootKey –EffectiveTime (Get-Date).AddHours(-10)
    }

    try{
        Get-ADServiceAccount -Identity FsGmsa
    } catch {
        New-ADServiceAccount "FsGmsa" -DNSHostName "adfs.corp.seclab.test" -AccountExpirationDate $null -ServicePrincipalNames "http/fs.seclab.test"
    }

    if((Get-DnsServerZone | ?{ $_.ZoneName -eq "seclab.test" }) -eq $null){
        Add-DnsServerPrimaryZone -Name "seclab.test" -ReplicationScope "Forest"
    }
    Add-DnsServerResourceRecordA -Name "fs" -ZoneName "seclab.test" -IPv4Address "10.0.0.30"
}

Install-WebServerCertificate  -Target 'ADFS' -subject "CN=fs.seclab.test" -SANs "dns=fs.seclab.test&dns=certauth.fs.seclab.test" -name "adfs" -Verbose

Invoke-Command -Session $pssAdfs -ScriptBlock {

    # install adfs
    Import-Module ADFS

    $cert = Get-ChildItem -Path Cert:\LocalMachine\My -DnsName "fs.seclab.test"
    $fingerprint = $cert.Thumbprint

    # configure adfs
    Install-AdfsFarm -CertificateThumbprint:$fingerprint -FederationServiceDisplayName:"SECLAB" -FederationServiceName:"fs.seclab.test" -GroupServiceAccountIdentifier:"SECLAB\FsGmsa`$" -OverwriteConfiguration -Credential (Get-Credential -UserName "SECLAB\Administrator" -Message "SECLAB Domain Admin Account")
}