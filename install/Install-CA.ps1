. "$PSScriptRoot\..\lib\sessions.ps1"
. "$PSScriptRoot\..\lib\certDeployLib.ps1"

$ErrorActionPreference = "Stop"

# create sessions
$sessions = Get-PoCSessions -NeededHosts DC,CA
$pssDc = $sessions['DC']
$pssCa = $sessions['CA']

Invoke-Command -Session $pssCa -ScriptBlock {
    # install CA
    Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools

    # configure CA
    Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName "SECLAB RootCA" -HashAlgorithmName "SHA256" -Credential (Get-Credential -UserName "SECLAB\Administrator" -Message "Domain Administrator Credentials") -Confirm:$false

    # install iis for CRL/AIA publishing
    Add-WindowsFeature web-webserver, web-static-content -IncludeManagementTools

    # create hosting dirs
    if(-not (Test-Path C:\inetpub\wwwroot\crld)){ mkdir C:\inetpub\wwwroot\crld }
    if(-not (Test-Path C:\inetpub\wwwroot\ca)){ mkdir C:\inetpub\wwwroot\ca }

    # configure CLR/AIA
    Get-CACrlDistributionPoint | Remove-CACrlDistributionPoint  -Confirm:$false

    Add-CACrlDistributionPoint -Uri "C:\inetpub\wwwroot\crld\<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -PublishToServer -PublishDeltaToServer
    Add-CACrlDistributionPoint -Uri "http://ca.seclab.test/crld/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -AddToCrlIdp -AddToCertificateCdp -AddToFreshestCrl

    Get-CAAuthorityInformationAccess | Remove-CAAuthorityInformationAccess  -Confirm:$false

    Add-CAAuthorityInformationAccess -Uri "http://ca.seclab.test/ca/<CAName><CertificateName>.crt" -AddToCertificateAia

    # export ca cert to AIA location
    Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -ArgumentList @("-ca.cert", "`"C:\inetpub\wwwroot\ca\SECLAB RootCA.crt`"")

    # copy crl-files to cdp. only once because republishing works
    Copy-Item C:\Windows\System32\CertSrv\CertEnroll\*.crl C:\inetpub\wwwroot\crld\

    # remove double-escaping protection to be able deliver delta-crl files
    C:\windows\system32\inetsrv\appcmd set config "Default Web Site" -section:system.webServer/security/requestFiltering -allowDoubleEscaping:true
}

Invoke-Command -Session $pssDc -ScriptBlock {
    if((Get-DnsServerZone | ?{ $_.ZoneName -eq "seclab.test" }) -eq $null){
        Add-DnsServerPrimaryZone -Name "seclab.test" -ReplicationScope "Forest"
    }
    Add-DnsServerResourceRecordA -Name "ca" -ZoneName "seclab.test" -IPv4Address "10.0.0.20"
}