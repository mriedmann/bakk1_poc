# https://technet.microsoft.com/en-us/library/dn383662(v=ws.11).aspx

. "$PSScriptRoot\..\lib\sessions.ps1"
. "$PSScriptRoot\..\lib\certDeployLib.ps1"

$ErrorActionPreference = "Stop"

# create sessions
$sessions = Get-PoCSessions -NeededHosts WAP
$pssWap = $sessions['WAP']

###### Handle Certificates

@([PSCustomObject]@{
    Name="WAP-AppCert"
    Subject="CN=*.SECLAB.TEST"
    SANs="dns=*.seclab.test"
},[PSCustomObject]@{
    Name="WAP-FSProxyCert"
    Subject="CN=FS.SECLAB.TEST"
    SANs="dns=fs.seclab.test&dns=enterpriseregistration.seclab.test"
}) | %{
    Install-WebServerCertificate -target 'WAP' -name $_.Name -subject $_.Subject -SANs $_.SANs -Verbose
}

###### Install WAP

Invoke-Command -Session $pssWap -ScriptBlock {
    Install-WindowsFeature Web-Application-Proxy -IncludeManagementTools
}

Invoke-Command -Session $pssWap -ScriptBlock {
    $fsCert = Get-ChildItem "Cert:\LocalMachine\My" -DnsName "fs.seclab.test" | select -First 1
    Install-WebApplicationProxy –CertificateThumbprint ($fsCert.Thumbprint) -FederationServiceName fs.seclab.test
}