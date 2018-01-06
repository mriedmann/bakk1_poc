. "$PSScriptRoot\..\lib\sessions.ps1"

$ErrorActionPreference = "Stop"

# create sessions
$sessions = Get-PoCSessions -NeededHosts DC
$pssDc = $sessions['DC']

Invoke-Command -Session $pssDc -ScriptBlock {

install-windowsfeature AD-Domain-Services -includemanagementtools

Import-Module ADDSDeployment

if((gwmi win32_computersystem).partofdomain -eq $false) {
  Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "Win2012R2" `
    -DomainName "corp.seclab.test" `
    -DomainNetbiosName "SECLAB" `
    -ForestMode "Win2012R2" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true
}

}
