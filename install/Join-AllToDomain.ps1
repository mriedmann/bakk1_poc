. "$PSScriptRoot\..\lib\sessions.ps1"

$sessions = (Get-PoCSessions -NeededHosts DC,CA,ADFS,RDS).Values

$sessions | %{
    Invoke-Command -Session $_ -ScriptBlock {
        if((gwmi win32_computersystem).partofdomain -eq $false) {
            Add-Computer -DomainName "SECLAB" -Restart
        }
    }
}