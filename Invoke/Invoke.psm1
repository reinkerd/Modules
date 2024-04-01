Import-Module SQLServer
function InvokeSQL {
    param ([string]$Server, [string]$Database, [string]$Query)

    if ($Database.Length -eq 0) {
        Invoke-Sqlcmd -ServerInstance $Server -Query $Query -TrustServerCertificate -QueryTimeout 0
    } else {
        Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $Query -TrustServerCertificate -QueryTimeout 0
    }

}