$PrimaryScript=@"
DECLARE @LS_BackupJobId	AS uniqueidentifier 
DECLARE @LS_PrimaryId	AS uniqueidentifier 
DECLARE @SP_Add_RetCode	As int 


EXEC @SP_Add_RetCode = master.dbo.sp_add_log_shipping_primary_database 
		@database = N'<DatabaseName>' 
		,@backup_directory = N'\\nas01.lesa.net\sqlbackups\<ServerFolder>\<DatabaseName>' 
		,@backup_share = N'\\nas01.lesa.net\sqlbackups\<ServerFolder>\<DatabaseName>'  
		,@backup_job_name = N'LSBackup_<DatabaseName>' 
		,@backup_retention_period = 7200
		,@backup_compression = 2
		,@backup_threshold = <BackupThreshold> 
		,@threshold_alert_enabled = 1
		,@history_retention_period = 5760 
		,@backup_job_id = @LS_BackupJobId OUTPUT 
		,@primary_id = @LS_PrimaryId OUTPUT 
		,@overwrite = 1 


IF (@@ERROR = 0 AND @SP_Add_RetCode = 0) 
BEGIN 

DECLARE @LS_BackUpScheduleUID	As uniqueidentifier 
DECLARE @LS_BackUpScheduleID	AS int 


EXEC msdb.dbo.sp_add_schedule 
		@schedule_name =N'LSBackupSchedule_<PrimaryServerName>' 
		,@enabled = 1 
		,@freq_type = 4 
		,@freq_interval = 1 
		,@freq_subday_type = 4 
		,@freq_subday_interval = <BackupInterval> 
		,@freq_recurrence_factor = 0 
		,@active_start_date = 20180608 
		,@active_end_date = 99991231 
		,@active_start_time = <StartTime>
		,@active_end_time = <EndTime>
		,@schedule_uid = @LS_BackUpScheduleUID OUTPUT 
		,@schedule_id = @LS_BackUpScheduleID OUTPUT 

EXEC msdb.dbo.sp_attach_schedule 
		@job_id = @LS_BackupJobId 
		,@schedule_id = @LS_BackUpScheduleID  

EXEC msdb.dbo.sp_update_job 
		@job_id = @LS_BackupJobId 
		,@enabled = 1 


END 


EXEC master.dbo.sp_add_log_shipping_alert_job 

EXEC master.dbo.sp_add_log_shipping_primary_secondary 
		@primary_database = N'<DatabaseName>' 
		,@secondary_server = N'<SecondaryServerName>' 
		,@secondary_database = N'<DatabaseName>' 
		,@overwrite = 1 
"@


$SecondaryScript=@"

DECLARE @LS_Secondary__CopyJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__RestoreJobId	AS uniqueidentifier 
DECLARE @LS_Secondary__SecondaryId	AS uniqueidentifier 
DECLARE @LS_Add_RetCode	As int 


EXEC @LS_Add_RetCode = master.dbo.sp_add_log_shipping_secondary_primary 
		@primary_server = N'<PrimaryServerName>' 
		,@primary_database = N'<DatabaseName>' 
		,@backup_source_directory = N'\\nas01.lesa.net\sqlbackups\<ServerFolder>\<DatabaseName>' 
		,@backup_destination_directory = N'\\nas01.lesa.net\sqlbackups\<ServerFolder>\<DatabaseName>' 
		,@copy_job_name = N'LSCopy_<PrimaryServerName>_<DatabaseName>' 
		,@restore_job_name = N'LSRestore_<PrimaryServerName>_<DatabaseName>' 
		,@file_retention_period = 7200 
		,@overwrite = 1 
		,@copy_job_id = @LS_Secondary__CopyJobId OUTPUT 
		,@restore_job_id = @LS_Secondary__RestoreJobId OUTPUT 
		,@secondary_id = @LS_Secondary__SecondaryId OUTPUT 

IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 


    DECLARE @LS_SecondaryRestoreJobScheduleUID	As uniqueidentifier 
    DECLARE @LS_SecondaryRestoreJobScheduleID	AS int 


    EXEC msdb.dbo.sp_add_schedule 
		    @schedule_name =N'DefaultRestoreJobSchedule' 
		    ,@enabled = 1 
		    ,@freq_type = 4 -- Daily
		    ,@freq_interval = 1 -- No interval used
		    ,@freq_subday_type = 4 -- Every N number of minutes
		    ,@freq_subday_interval = <RestoreInterval> -- N
		    ,@freq_recurrence_factor = 0
		    ,@active_start_date = 20170516 
		    ,@active_end_date = 99991231 
		    ,@active_start_time = <StartTime> 
		    ,@active_end_time = <Endtime> 
		    ,@schedule_uid = @LS_SecondaryRestoreJobScheduleUID OUTPUT 
		    ,@schedule_id = @LS_SecondaryRestoreJobScheduleID OUTPUT 

    EXEC msdb.dbo.sp_attach_schedule 
		    @job_id = @LS_Secondary__RestoreJobId 
		    ,@schedule_id = @LS_SecondaryRestoreJobScheduleID  


END 


DECLARE @LS_Add_RetCode2	As int 


IF (@@ERROR = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

    EXEC @LS_Add_RetCode2 = master.dbo.sp_add_log_shipping_secondary_database 
		    @secondary_database = N'<DatabaseName>' 
		    ,@primary_server = N'<PrimaryServerName>' 
		    ,@primary_database = N'<DatabaseName>' 
		    ,@restore_delay = 2
		    ,@restore_mode = 1 
		    ,@disconnect_users	= 1 
		    ,@restore_threshold = <RestoreThreshold>   
		    ,@threshold_alert_enabled = 1
		    ,@history_retention_period	= 5760 
		    ,@overwrite = 1 

END 


IF (@@error = 0 AND @LS_Add_RetCode = 0) 
BEGIN 

    -- Disable copy job
      EXEC msdb.dbo.sp_update_job
            @job_id = @LS_Secondary__CopyJobId 
            ,@enabled=0

    EXEC msdb.dbo.sp_update_job 
		    @job_id = @LS_Secondary__RestoreJobId 
		    ,@enabled = 1 
    
    --EXEC msdb.dbo.sp_delete_job 
    --      @job_name='LSAlert_<SecondaryServerSimpleName>'

END 


-- End Script to be run at Secondary --

"@


#.SYNOPSIS
#    Sets up log shipping for a database from a given primary server to a given secondary server.  This is a system function, so users are not expected to run it.
#
#.Description
#    This script will configure log shipping for one database on a primary server to a given
#    secondary server.  Assumes at least one full backup has been made of the database.
#    Typically run when setting up a new server.  Used by other log-shipping related functions.
#
#.EXAMPLE
#    Add-LogShipping -PrimaryServerName ProdSQL03.ss911.net -SecondaryServerName StandbySQL03.ss911.net -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName ServiceDesk -BackupThreshold 60 -RestoreThreshold 180
#
#    Sets up log shipping for the database ServiceDesk located on ProdSQL03.ss911.net so that it log ships 
#    to the server standbysql03.ss911.net.  A backup job will be created on ProdSQL03 that performs a
#    transaction log backup every 15 minutes.  A restore job will be created on StandbySQL03 that restores 
#    transaction log backups every 60 minutes.  The job starts at midnight and ends one minute before midnight,
#    which means it runs all day long.  If 60 minutes passes without a successful backup, the operator will
#    be notified.  If 3 hours passes without a successful restore the operator will be notified.
function Add-LogShipping {

    param (
        #The primary server name on which the database is located
        [string]$PrimaryServerName,
        #The server upon which backups will be restored, in read-only mode
        [string]$SecondaryServerName,
        #The name of the database to be log shipped
        [string]$DatabaseName,
        #How often transaction log backups will be performed on the primary server, in minutes
        [int]$BackupInterval,
        #How often transaction log restores will be performed on the standby server, in minutes
        [int]$RestoreInterval,
        #Time of day when the backups will begin running.  Ex: "010000" = 1:00am.  Ex: "223000" = 10:30pm.
        [int]$StartTime,
        #Time of day when the backups will end.  Ex: "010000" = 1:00am.  Ex: "223000" = 10:30pm.
        [int]$EndTime,
        #How far backups can get behind before an operator is alerted, in minutes.
        [int]$BackupThreshold,
        #How far restores can get behind before an operator is alerted, in minutes.
        [int]$RestoreThreshold,
        #Don't perform any restores.  Good for reconfiguring log shipping.
        [switch]$NoRestore
    )

$Restore=@"
alter database <DatabaseName> set single_user with rollback after 30 seconds
go
restore database <DatabaseName> from disk=N'\\nas01.lesa.net\sqlbackups\<ServerFolder>\<DatabaseName>\<LastFullBackup>' 
with file = 1, replace, standby = N'<LogFilePath><DatabaseName>_undo.bak'
"@


    if ($PrimaryServerName -match "\w+" ) {
        $ServerFolder = $matches[0]
    } else { 
        write-warning "Invalid Primary Server"
        return;
    }

    if ($SecondaryServerName -match "\w+") {
        $SecondaryServerSimpleName = $matches[0] 
    } else {
        Write-Warning "Invalid Secondary Server"
        return;
    }

    $PrimaryScript = $PrimaryScript -replace "<PrimaryServerName>", $PrimaryServerName
    $PrimaryScript = $PrimaryScript -replace "<SecondaryServerName>", $SecondaryServerName
    $PrimaryScript = $PrimaryScript -replace "<DatabaseName>", $DatabaseName
    $PrimaryScript = $PrimaryScript -replace "<ServerFolder>", $ServerFolder
    $PrimaryScript = $PrimaryScript -replace "<SecondaryServerSimpleName>", $SecondaryServerSimpleName
    $PrimaryScript = $PrimaryScript -replace "<BackupInterval>", $BackupInterval
    $PrimaryScript = $PrimaryScript -replace "<StartTime>", $StartTime
    $PrimaryScript = $PrimaryScript -replace "<EndTime>", $EndTime
    $PrimaryScript = $PrimaryScript -replace "<BackupThreshold>", $BackupThreshold
    $PrimaryScript = $PrimaryScript -replace "<RestoreThreshold>", $RestoreThreshold

    $SecondaryScript = $SecondaryScript -replace "<PrimaryServerName>", $PrimaryServerName
    $SecondaryScript = $SecondaryScript -replace "<SecondaryServerName>", $SecondaryServerName
    $SecondaryScript = $SecondaryScript -replace "<DatabaseName>", $DatabaseName
    $SecondaryScript = $SecondaryScript -replace "<ServerFolder>", $ServerFolder
    $SecondaryScript = $SecondaryScript -replace "<SecondaryServerSimpleName>", $SecondaryServerSimpleName
    $SecondaryScript = $SecondaryScript -replace "<RestoreInterval>", $RestoreInterval
    $SecondaryScript = $SecondaryScript -replace "<StartTime>", $StartTime
    $SecondaryScript = $SecondaryScript -replace "<EndTime>", $EndTime
    $SecondaryScript = $SecondaryScript -replace "<BackupThreshold>", $BackupThreshold
    $SecondaryScript = $SecondaryScript -replace "<RestoreThreshold>", $RestoreThreshold

    if (-not $NoRestore)
    {
        # Obtain secondary server default database file and log file paths
        $Paths = invoke-sqlcmd -ServerInstance $SecondaryServerName -Database master -Query "select Data = serverproperty('InstanceDefaultDataPath'), [Log] = serverproperty('InstanceDefaultLogPath')"
        set-location c:\

        # Obtain primary server data and log file names
        $physicalfiles = Invoke-Sqlcmd -ServerInstance $PrimaryServerName -query "select name, data_space_id from sys.master_files where database_id = db_id('$DatabaseName')"
        set-location c:\

        foreach ($file in $physicalfiles)
        {
            if ($file.data_space_id -eq 0) { $Restore += ", move '$($file.name)' to '$($Paths.Log)$($file.name).ldf'" }
            if ($file.data_space_id -eq 1) { $Restore += ", move '$($file.name)' to '$($Paths.Data)$($file.name).mdf'" }
            if ($file.data_space_id -gt 1) { $Restore += ", move '$($file.name)' to '$($Paths.Data)$($file.name).ndf'" }
        }

        $LastFullBackup = Get-ChildItem -path "\\nas01.lesa.net\sqlbackups\$ServerFolder\$DataBaseName" -filter "*.bak" | sort-object creationtime -Descending | select-object -first 1
        if ($null -eq $LastFullBackup) { throw [System.IO.FileNotFoundException] "Full backup not found" }

        $Restore = $Restore -replace "<DatabaseName>", $DatabaseName
        $Restore = $Restore -replace "<ServerFolder>", $ServerFolder
        $Restore = $Restore -replace "<DataFilePath>", $Paths.Data
        $Restore = $Restore -replace "<LogFilePath>", $Paths.Log
        $Restore = $Restore -replace "<LastFullBackup>", $LastFullBackup.Name

        # Initial database restore to secondary in standby mode
        write-host "Restoring database backup $LastFullBackup onto $SecondaryServerName"
        & sqlcmd -S $SecondaryServerName -E -Q $Restore
    }

    # Configure log shipping on Primary
    write-host "Configuring log shipping on $PrimaryServerName"
    invoke-sqlcmd -ServerInstance $PrimaryServerName -Query $PrimaryScript
    
    # Configure log shipping on Standby
    write-host "Configuring log shipping on $SecondaryServerName"
    invoke-sqlcmd -ServerInstance $SecondaryServerName -Query $SecondaryScript
    set-location c:\
}

function Remove-LogShipping
{
    param ([string]$PrimaryServer, [string]$SecondaryServer, [string]$DatabaseName)

    write-host "Removing Log Shipping for $PrimaryServer/$DatabaseName"

    $sql = "exec sp_delete_log_shipping_secondary_database @secondary_database='{0}'" -f $DatabaseName
    Invoke-Sqlcmd -ServerInstance $SecondaryServer -Database master -Query $sql

    $sql = "exec sp_delete_log_shipping_secondary_primary @primary_server='{0}', @primary_database='{1}'" -f $PrimaryServer, $DatabaseName
    Invoke-Sqlcmd -ServerInstance $SecondaryServer -Database master -Query $sql

    $sql = "exec sp_delete_log_shipping_primary_secondary @primary_database='{0}', @secondary_server='{1}', @secondary_database='{2}'" -f $DatabaseName, $SecondaryServer, $DatabaseName
    invoke-sqlcmd -ServerInstance $PrimaryServer -Database master -Query $sql

    $sql = "exec sp_delete_log_shipping_primary_database @database='{0}'" -f $DatabaseName
    invoke-sqlcmd -ServerInstance $PrimaryServer -Database master -Query $sql
    set-location c:\
}

#.SYNOPSIS
#    Sets up log shipping for all database on the SQLMain production primary server.
#    Assumes full backups have already been performed
#    Assumes primary server is up and running and has all databases available
#
#.Description
#    This script will enumerate databases on SQL-Main and add log shipping for each database on StandbySQL03.
#
#.EXAMPLE
#    Add-SQLMainLogShipping
#
#    Sets up log shipping for all databases on ProdSQL03 (SQL-Main) 
function Add-SQLMainLogShipping
{

    $Databases = invoke-sqlcmd -ServerInstance ProdSQL03.ss911.net -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Add-LogShipping -PrimaryServerName ProdSQL03.ss911.net -SecondaryServerName StandbySQL03.ss911.net -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180
    }

}

#.SYNOPSIS
#    Sets up log shipping for all database on the SQL Warehouse production primary server.
#    Assumes full backups have already been performed
#    Assumes primary server is up and running and has all databases available
#
#.Description
#    This script will enumerate databases on SQL-SQLWarehouse and add log shipping for each database on StandbySQL02.
#
#.EXAMPLE
#    Add-SQLWarehouseLogShipping
#
#    Sets up log shipping for all databases on ProdSQL03 (SQL-Main) 
function Add-SQLWarehouseLogShipping
{

    $Databases = invoke-sqlcmd -ServerInstance ProdSQL02.ss911.net -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Add-LogShipping -PrimaryServerName ProdSQL02.ss911.net -SecondaryServerName StandbySQL02.ss911.net -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180
    }

}

#.SYNOPSIS
#    Sets up log shipping for all database on the SQL WebRMS production primary server.
#    Assumes full backups have already been performed
#    Assumes primary server is up and running and has all databases available
#
#.Description
#    This script will enumerate databases on SQL-WebRMSLogShipping and add log shipping for each database on StandbySQL01.
#
#.EXAMPLE
#    Add-SQLWebRMSLogShipping
#
#    Sets up log shipping for all databases on ProdSQL03 (SQL-Main) 
function Add-SQLWebRMSLogShipping
{

    $Databases = invoke-sqlcmd -ServerInstance ProdSQL01.ss911.net -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb','netrms')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Add-LogShipping -PrimaryServerName prodsql01.ss911.net -SecondaryServerName StandbySQL01.ss911.net -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180
    }

    # Set up log shipping for NetRMS so it backs up every 5 minutes
    Add-LogShipping -PrimaryServerName prodsql01.ss911.net -SecondaryServerName StandbySQL01.ss911.net -BackupInterval 5 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName NetRMS -BackupThreshold 60 -RestoreThreshold 180

}

<#
.Synopsis
    Resets the log shipping for any one database on the SQL-Main server
    Assumes primary server is up and running and the database is available

.Description
    Resets the log shipping for any one database by removing the log shipping configuration, backing up the database, restoring to the secondary, and re-establishing log shipping.
    Uses the Remove-LogShipping and Add-LogShipping functions

.Example
    Reset-SQLMainLogShipping -DatabaseName Pawn

.Parameter DatabaseName

    The database that will be reset

#>
function Reset-SQLMainLogShipping {
    
    param ([Parameter(Mandatory=$true)][string]$DatabaseName)

    $PrimaryServer='ProdSQL03.ss911.net'
    $SecondaryServer='StandbySQL03.ss911.net'

    if ($PrimaryServer -match "\w+") {
        $ServerName = $matches[0] 
    } 

    $Now = get-date -Format "yyyy_MM_dd_hhmmss"

    Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $DatabaseName

    $SQL = "backup database [{0}] to disk='\\nas01.lesa.net\sqlbackups\{1}\{0}\{0}_backup_{2}.bak'" -f $DatabaseName, $ServerName, $Now
    & sqlcmd -S $PrimaryServer -E -Q $SQL

    Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $DatabaseName -BackupThreshold 60 -RestoreThreshold 180 

}


<#
.Synopsis
    Resets the log shipping for any one database on the SQL-Warehouse server
    Assumes primary server is up and running and the database is available

.Description
    Resets the log shipping for any one database by removing the log shipping configuration, backing up the database, restoring to the secondary, and re-establishing log shipping.
    Uses the Remove-LogShipping and Add-LogShipping functions

.Example
    Reset-SQLWarehouseLogShipping -DatabaseName CAD_LESA

.Parameter DatabaseName

    The database that will be reset

#>
function Reset-SQLWarehouseLogShipping {

    param ([string]$DatabaseName)

    $PrimaryServer='ProdSQL02.ss911.net'
    $SecondaryServer='StandbySQL02.ss911.net'

    if ($PrimaryServer -match "\w+") {
        $ServerName = $matches[0] 
    }

    $Now = get-date -Format "yyyy_MM_dd_hhmmss"

    Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $DatabaseName

    $SQL = "backup database [{0}] to disk='\\nas01.lesa.net\sqlbackups\{1}\{0}\{0}_backup_{2}.bak'" -f $DatabaseName, $ServerName, $Now
    & sqlcmd -S $PrimaryServer -E -Q $SQL

    Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $DatabaseName -BackupThreshold 60 -RestoreThreshold 180 

}

<#
.Synopsis
    Resets the log shipping for any one database on the SQL-WebRMS server
    Assumes primary server is up and running and the database is available

.Description
    Resets the log shipping for any one database by removing the log shipping configuration, backing up the database, restoring to the secondary, and re-establishing log shipping.
    Uses the Remove-LogShipping and Add-LogShipping functions

.Example
    Reset-SQLWebRMSLogShipping -DatabaseName NetRMS

.Example
    Reset-SQLWebRMSLogShipping -DatabaseName CA

.Parameter DatabaseName

    The database that will be reset

#>
function Reset-SQLWebRMSLogShipping {

    param ([string]$DatabaseName)

    $PrimaryServer='ProdSQL01.ss911.net'
    $SecondaryServer='StandbySQL01.ss911.net'

    if ($PrimaryServer -match "\w+") {
        $ServerName = $matches[0] 
    }

    $Now = get-date -Format "yyyy_MM_dd_hhmmss"

    Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $DatabaseName

    $SQL = "backup database [{0}] to disk='\\nas01.lesa.net\sqlbackups\{1}\{0}\{0}_backup_{2}.bak'" -f $DatabaseName, $ServerName, $Now
    & sqlcmd -S $PrimaryServer -E -Q $SQL

    if ($DatabaseName -eq "NetRMS") {
        Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 5 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $DatabaseName -BackupThreshold 60 -RestoreThreshold 180 
    } else {
        Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $DatabaseName -BackupThreshold 60 -RestoreThreshold 180 
    }
}


# 
# Reconfigure functions
#
# Purpoase: To modify the log shipping parameters for a given server.  Restores last full backup of the primary databases to the standby without creating a new backups, 
# and restores all subsequent transaction log backups to the standby.
#

function ReconfigureSQLMainLogShipping
{

    $PrimaryServer='ProdSQL03.ss911.net'
    $SecondaryServer='StandbySQL03.ss911.net'

    $Databases = invoke-sqlcmd -ServerInstance $PrimaryServer -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $Database.Name
        Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180 -NoRestore
    }

}


function ReconfigureSQLWebRMSLogShipping
{

    $PrimaryServer='ProdSQL01.ss911.net'
    $SecondaryServer='StandbySQL01.ss911.net'

    $Databases = invoke-sqlcmd -ServerInstance $PrimaryServer -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb','NetRMS')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $Database.Name
        Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180 -NoRestore
    }

    Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName NetRMS
    Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 5 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName NetRMS -BackupThreshold 60 -RestoreThreshold 180 -NoRestore

}

function ReconfigureSQLWarehouseLogShipping
{

    $PrimaryServer='ProdSQL02.ss911.net'
    $SecondaryServer='StandbySQL02.ss911.net'

    $Databases = invoke-sqlcmd -ServerInstance $PrimaryServer -Database master -query "select Name from sysdatabases where name not in ('master','tempdb','model','msdb')"
    set-location c:\

    foreach ($Database in $Databases)
    {
        Remove-LogShipping -PrimaryServer $PrimaryServer -SecondaryServer $SecondaryServer -DatabaseName $Database.Name
        Add-LogShipping -PrimaryServerName $PrimaryServer -SecondaryServerName $SecondaryServer -BackupInterval 15 -RestoreInterval 60 -StartTime "000000" -EndTime "235900" -DatabaseName $Database.Name -BackupThreshold 60 -RestoreThreshold 180 -NoRestore
    }

}

function Reset-AllSQLMainLogShipping {

    $List = invoke-sqlcmd -ServerInstance standbysql03.ss911.net -Database master -Query 'exec sp_help_log_shipping_monitor'
    set-location c:\

    $List | Where-Object {$_.time_since_last_restore -gt $_.restore_threshold} | ForEach-Object {
        write-host "----------------------------------------------------------------------------------------"
        write-host ("Resetting Log Shipping for {0}" -f $_.Database_Name)
        write-host ""
        Reset-SQLMainLogShipping -DatabaseName $_.Database_Name
    }
}    

function Reset-AllSQLWarehouseLogShipping {

    $List = invoke-sqlcmd -ServerInstance standbysql02.ss911.net -Database master -Query 'exec sp_help_log_shipping_monitor'
    set-location c:\

    $List | Where-Object {$_.time_since_last_restore -gt $_.restore_threshold} | ForEach-Object {
        write-host "----------------------------------------------------------------------------------------"
        write-host ("Resetting Log Shipping for {0}" -f $_.Database_Name)
        write-host ""
        Reset-SQLWarehouseLogShipping -DatabaseName $_.Database_Name
    }
}    

function Reset-AllSQLWebRMSLogShipping {

    $List = invoke-sqlcmd -ServerInstance standbysql01.ss911.net -Database master -Query 'exec sp_help_log_shipping_monitor'
    set-location c:\

    $List | Where-Object {$_.time_since_last_restore -gt $_.restore_threshold} | ForEach-Object {
        write-host "----------------------------------------------------------------------------------------"
        write-host ("Resetting Log Shipping for {0}" -f $_.Database_Name)
        write-host ""
        Reset-SQLWebRMSLogShipping -DatabaseName $_.Database_Name    }
}    

function Reset-LogShipping {

    Invoke-Command -computername sqlxfer.lesa.net -ScriptBlock { Start-ScheduledTask -TaskName "Reset Log Shipping" }

}

# Requires sqlcmd.exe
function Backup-Database {
    param (
        [string]$ServerName,
        [string]$DatabaseName
    )

    # Separate the host name from the domain name.  Use just the hostname or server name for the backup destination path
    if ($ServerName -match "\w+") {
    
        $ServerName = $Matches[0]
    
        $Now = get-date -Format "yyyy_MM_dd_hhmmss"

        $SQL = "backup database [{0}] to disk='\\nas01.lesa.net\sqlbackups\{1}\{0}\{0}_backup_{2}.bak'" -f $DatabaseName, $ServerName, $Now
        & sqlcmd -S $ServerName -E -Q $SQL
    }
    else {
        write-warning "Invalid Server Name"
    }

}


