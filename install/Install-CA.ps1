Add-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools

Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -ValidityPeriod 5 -CACommonName "SECLAB RootCA2" -HashAlgorithmName "SHA256"

Add-WindowsFeature web-webserver, web-static-content -IncludeManagementTools

if(-not (Test-Path C:\inetpub\wwwroot\crld)){ mkdir C:\inetpub\wwwroot\crld }
if(-not (Test-Path C:\inetpub\wwwroot\ca)){ mkdir C:\inetpub\wwwroot\ca }

Get-CACrlDistributionPoint | Remove-CACrlDistributionPoint

Add-CACrlDistributionPoint -Uri "C:\inetpub\wwwroot\crld\<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -PublishToServer -PublishDeltaToServer
Add-CACrlDistributionPoint -Uri "http://ca.seclab.test/crld/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl" -AddToCrlIdp -AddToCertificateCdp -AddToFreshestCrl

Get-CAAuthorityInformationAccess | Remove-CAAuthorityInformationAccess

Add-CAAuthorityInformationAccess -uri "C:\inetpub\wwwroot\ca\<CAName><CertificateName>.crt"
Add-CAAuthorityInformationAccess -Uri "http://ca.seclab.test/ca/<CAName><CertificateName>.crt" -AddToCertificateAia

Start-Process -FilePath "certutil.exe" -Wait -NoNewWindow -ArgumentList @("-ca.cert", "`"C:\inetpub\wwwroot\ca\SECLAB RootCA2.crt`"")