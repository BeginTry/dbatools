function Install-DbaInstance {
    <#
    .SYNOPSIS

        This function will help you to quickly install a SQL Server instance.

    .DESCRIPTION

        This function will help you to quickly install a SQL Server instance on one or many computers.
        Some of the things this function will do for you:
        * Add your login as an admin to the new instance
        * Search for SQL Server installations in the specified file repository
        * Generate SA password if needed
        * Install specific features using 'Default' and 'All' templates or cherry-pick the ones you need
        * Set number of tempdb files based on number of cores (SQL2016+)
        * Activate .Net 3.5 feature for SQL2012/2014
        * Restart the machine if needed after the installation is done

        Fully customizable installation parameters allow you to:
        * Use existing Configuration.ini files for the installation
        * Define service account credentials using native Powershell syntax
        * Override any configurations by using -Configuration switch
        * Change the TCP port after the installation is done
        * Enable 'Perform volume maintenance tasks' for the SQL Server account

        Note that the dowloaded installation media must be extracted and available to the server where the installation runs.

    .PARAMETER SqlInstance
        The target computer and, optionally, a new instance name and a port number.
        Use one of the following generic formats:
        Server1
        Server2\Instance1
        Server1\Alpha:1533, Server2\Omega:1566
        "ServerName\NewInstanceName,1534"

        You can also define instance name and port using -InstanceName and -Port parameters.
    .PARAMETER SaCredential
        Securely provide the password for the sa account when using mixed mode authentication.

    .PARAMETER Credential
        Used when executing installs against remote servers

    .PARAMETER ConfigurationFile
        The path to the custom Configuration.ini file.

    .PARAMETER Configuration
        A hashtable with custom configuration items that you want to use during the installation.
        Overrides all other parameters.
        For example, to define a custom server collation you can use the following parameter:
        PS> Install-DbaInstance -Version 2017 -Configuration @{ SQLCOLLATION = 'Latin1_General_BIN' }

        Full list of parameters can be found here: https://docs.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt#Install

    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        If the protocol fails to establish a connection

        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host
          to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.

    .PARAMETER Version
        SQL Server version you wish to install.

    .PARAMETER InstanceName
        Name of the SQL Server instance to install. Overrides the instance name specified in -SqlInstance.

    .PARAMETER Feature
        Features to install. Templates like "Default" and "All" can be used to setup a predefined set of components.

    .PARAMETER InstancePath
        Specifies a nondefault installation directory for instance-specific components.

    .PARAMETER DataPath
        Path to the Data folder.

    .PARAMETER LogPath
        Path to the Log folder.

    .PARAMETER TempPath
        Path to the TempDB folder.

    .PARAMETER BackupPath
        Path to the Backup folder.

    .PARAMETER AdminAccount
        One or more members of the sysadmin group. Uses UserName from the -Credential parameter if specified, or current Windows user by default.

    .PARAMETER Port
        After successful installation, changes SQL Server TCP port to this value. Overrides the port specified in -SqlInstance.

    .PARAMETER ProductID
        Product ID, or simply, serial number of your SQL Server installation, which will determine which version to install.
        If the PID is already built into the installation media, can be ignored.

    .PARAMETER EngineCredential
        Service account of the SQL Server Database Engine

    .PARAMETER AgentCredential
        Service account of the SQL Server Agent

    .PARAMETER ISCredential
        Service account of the Integration Services

    .PARAMETER RSCredential
        Service account of the Reporting Services

    .PARAMETER FTCredential
        Service account of the Full-Text catalog service

    .PARAMETER PBEngineCredential
        Service account of the PolyBase service

    .PARAMETER Path
        Path to the folder(s) with SQL Server installation media downloaded. It will be scanned recursively for a corresponding setup.exe.
        Path should be available from the remote server.
        If a setup.exe file is missing in the repository, the installation will fail.
        Consider setting the following configuration if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\installations'`

    .PARAMETER PerformVolumeMaintenanceTasks
        Allow SQL Server service account to perform Volume Maintenance tasks.

    .PARAMETER SaveConfiguration
        Save installation configuration file in a custom location. Will not be preserved otherwise.

    .PARAMETER Throttle
        Maximum number of computers updated in parallel. Once reached, the update operations will queue up.
        Default: 50

    .PARAMETER Restart
        Restart computer automatically if a restart is required before or after the installation.

    .PARAMETER DotNetPath
        Path to the .Net 3.5 installation folder (Windows installation media) for offline installations. Might be required for SQL2012/2014

    .PARAMETER AuthenticationMode
        Chooses between Mixed and Windows authentication.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Install
        Author: Reitse Eskens (@2meterDBA), Kirill Kravtsov (@nvarscar)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .Example
        C:\PS> Install-DbaInstance -Feature All

        Install a default SQL Server instance and run the installation enabling all features with the default settings. Automatically generates configuration.ini

    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017\sqlexpress, server01 -Version 2017 -Feature Default

        Install a named SQL Server instance named sqlexpress on the remote machine, sql2017, and a default instance on server01. Automatically generates configuration.ini

    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017 -ConfigurationFile C:\temp\configuration.ini

        Install a default named SQL Server instance on the remote machine, sql2017 and use the local configuration.ini

    .Example
        C:\PS> Install-DbaInstance -InstancePath G:\SQLServer

        Run the installation with default settings apart from the application volume, this will be redirected to G:\SQLServer.

    .Example
        C:\PS> Install-DbaInstance -Version 2016 -InstancePath D:\Root -DataPath E: -LogPath L: -PerformVolumeMaintenanceTasks -AdminAccount MyDomain\SvcSqlServer

        Install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
        permissions are granted and the domain account SvcSqlServer will be used as the service account for SqlServer.

       #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Alias('ComputerName')]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017")]
        [string]$Version,
        [string]$InstanceName,
        [PSCredential]$SaCredential,
        [PSCredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [parameter(ValueFromPipeline)]
        [Alias("FilePath")]
        [object]$ConfigurationFile,
        [hashtable]$Configuration,
        [string]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerSetup'),
        [ValidateSet("Default", "All", "Engine", "Tools", "Replication", "FullText", "DataQuality", "PolyBase", "MachineLearning", "AnalysisServices",
            "ReportingServices", "ReportingForSharepoint", "SharepointAddin", "IntegrationServices", "MasterDataServices", "PythonPackages", "RPackages",
            "ReplayController", "ReplayClient", "SDK", "BIDS", "SSMS")]
        [string]$Feature = "Default",
        [ValidateSet("Windows", "Mixed")]
        [string]$AuthenticationMode = "Windows",
        [string]$InstancePath,
        [string]$DataPath,
        [string]$LogPath,
        [string]$TempPath,
        [string]$BackupPath,
        [string[]]$AdminAccount,
        [int]$Port,
        [int]$Throttle,
        [Alias('PID')]
        [string]$ProductID,
        [pscredential]$EngineCredential,
        [pscredential]$AgentCredential,
        [pscredential]$ASCredential,
        [pscredential]$ISCredential,
        [pscredential]$RSCredential,
        [pscredential]$FTCredential,
        [pscredential]$PBEngineCredential,
        [string]$SaveConfiguration,
        [string]$DotNetPath,
        [switch]$PerformVolumeMaintenanceTasks,
        [switch]$Restart,
        [switch]$EnableException
    )
    begin {
        Function Read-IniFile {
            # Reads an ini file from a disk and returns a hashtable with a corresponding structure
            Param (
                $Path
            )
            #Collect config entries from the ini file
            Write-Message -Level Verbose -Message "Reading Ini file from $Path"
            $config = @{}
            switch -regex -file $Path {
                #Comment
                '^#.*' { break }
                #Section
                "^\[(.+)\]\s*$" {
                    $section = $matches[1]
                    $config.$section = @{}
                    break
                }
                #Item
                "\s*(.+)=(.+)\s*" {
                    $name, $value = $matches[1..2]
                    $config.$section.$name = $value
                    break
                }
            }
            return $config
        }
        Function Write-IniFile {
            # Writes a hashtable into a file in a format of an ini file
            Param (
                [hashtable]$Content,
                $Path
            )
            Write-Message -Level Verbose -Message "Writing Ini file to $Path"
            $output = @()
            foreach ($key in $Content.Keys) {
                $output += "[$key]"
                if ($Content.$key -is [hashtable]) {
                    foreach ($sectionKey in $Content.$key.Keys) {
                        $output += "$sectionKey=`"$($Content.$key.$sectionKey -join ',')`""
                    }
                }
            }
            Set-Content -Path $Path -Value $output -Force
        }
        Function Update-ServiceCredential {
            # updates a service account entry and returns the password as a command line argument
            Param (
                $Node,
                [pscredential]$Credential,
                [string]$AccountName,
                [string]$PasswordName = $AccountName.Replace('SVCACCOUNT', 'SVCPASSWORD')
            )
            if ($Credential) {
                if ($AccountName) {
                    $Node.$AccountName = $Credential.UserName
                }
                if ($Credential.Password.Length -gt 0) {
                    return "/$PasswordName=`"" + $Credential.GetNetworkCredential().Password + '"'
                }
            }
        }
        Function Get-SqlInstallSummary {
            # Reads Summary.txt from the SQL Server Installation Log folder
            Param (
                [DbaInstanceParameter]$ComputerName,
                [pscredential]$Credential,
                [parameter(Mandatory)]
                [version]$Version
            )
            $getSummary = {
                Param (
                    [parameter(Mandatory)]
                    [version]$Version
                )
                $versionNumber = "$($Version.Major)$($Version.Minor)".Substring(0, 3)
                $path = "$env:ProgramFiles\Microsoft SQL Server\$versionNumber\Setup Bootstrap\Log\Summary.txt"
                if (Test-Path $path) {
                    return Get-Content -Path $path
                }
            }
            $params = @{
                ComputerName = $ComputerName.ComputerName
                Credential   = $Credential
                ScriptBlock  = $getSummary
                ArgumentList = @($Version.ToString())
                ErrorAction  = 'Stop'
                Raw          = $true
            }
            return Invoke-Command2 @params
        }
        # defining local vars
        $notifiedCredentials = $false
        $notifiedUnsecure = $false
        $pathIsNetwork = $Path | Foreach-Object -Begin { $o = @() } -Process { $o += $_ -like '\\*'} -End { $o -contains $true }

        # read component names
        $components = Get-Content -Path $Script:PSModuleRoot\bin\dbatools-sqlinstallationcomponents.json -Raw | ConvertFrom-Json
    }
    process {
        # getting a numeric version for further comparison
        $canonicVersion = (Get-DbaBuildReference -MajorVersion $Version).BuildLevel
        if (-not $canonicVersion) {
            Stop-Function -Message "Version $Version was not found in the build reference database"
            return
        }

        # build feature list
        $featureList = @()
        foreach ($f in $Feature) {
            $featureDef = $components | Where-Object Name -contains $f
            foreach ($fd in $featureDef) {
                if (($fd.MinimumVersion -and $canonicVersion -lt [version]$fd.MinimumVersion) -or ($fd.MaximumVersion -and $canonicVersion -gt [version]$fd.MaximumVersion)) {
                    # exclude Default and All
                    if ($f -notin 'Default', 'All') {
                        Stop-Function -Message "Feature $f($($fd.Feature)) is not supported on SQL$Version"
                        return
                    }
                } else {
                    $featureList += $fd.Feature
                }
            }
        }

        # auto generate a random password if mixed is chosen and a credential is not provided
        if ($AuthenticationMode -eq "Mixed" -and -not $SaCredential) {
            $secpasswd = Get-RandomPassword -Length 15
            $SaCredential = New-Object System.Management.Automation.PSCredential ("sa", $secpasswd)
        }

        # turn the configuration file into an object so we can access it various ways
        if ($ConfigurationFile) {
            try {
                $ConfigurationFile = Get-Item -Path $ConfigurationFile -ErrorAction Stop
            } catch {
                Stop-Function -Message "Configuration file not found" -ErrorRecord $_
                return
            }
        }

        $actionPlan = @()
        foreach ($computer in $SqlInstance) {
            # Test elevated console
            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            # notify about credentials once
            if (-not $computer.IsLocalHost -and -not $notifiedCredentials -and -not $Credential -and $pathIsNetwork) {
                Write-Message -Level Warning -Message "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder"
                $notifiedCredentials = $true
            }
            # resolve names
            $resolvedName = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential
            $fullComputerName = $resolvedName.FullComputerName
            # test if the restart is needed
            $restartNeeded = Test-PendingReboot -ComputerName $fullComputerName -Credential $Credential
            if ($restartNeeded -and (-not $Restart -or $computer.IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$computer is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            # Attempt to configure CredSSP for the remote host when credentials are defined
            if ($Credential -and -not ([DbaInstanceParameter]$computer).IsLocalHost -and $Authentication -eq 'Credssp') {
                Write-Message -Level Verbose -Message "Attempting to configure CredSSP for remote connections"
                Initialize-CredSSP -ComputerName $fullComputerName -Credential $Credential -EnableException $false
                # Verify remote connection and confirm using unsecure credentials
                try {
                    $secureProtocol = Invoke-Command2 -ComputerName $fullComputerName -Credential $Credential -Authentication $Authentication -ScriptBlock { $true } -Raw
                } catch {
                    $secureProtocol = $false
                }
                # only ask once about using unsecure protocol
                if (-not $secureProtocol -and -not $notifiedUnsecure) {
                    if ($PSCmdlet.ShouldProcess($fullComputerName, "Primary protocol ($Authentication) failed, sending credentials via potentially unsecure protocol")) {
                        $notifiedUnsecure = $true
                    } else {
                        Stop-Function -Message "Failed to connect to $fullComputerName through $Authentication protocol. No actions will be performed on that computer." -Continue
                    }
                }
            }
            # find installation file
            Write-Message -Level Verbose -Message "Looking for installation files in $($Path) on remote machine into $fullComputerName"
            $findSetupParams = @{
                ComputerName   = $fullComputerName
                Credential     = $Credential
                Authentication = $Authentication
                Version        = $canonicVersion
                Path           = $Path
            }
            $setupFile = Find-SqlServerSetup @findSetupParams
            if (-not $setupFile) {
                Stop-Function -Message "Failed to find setup file for SQL$Version in $Path on $fullComputerName" -Continue
            }
            $instance = if ($InstanceName) { $InstanceName } else { $computer.InstanceName }
            $portNumber = if ($Port) { $Port } else { $computer.Port }
            $mainKey = if ($canonicVersion -gt '11.0') { "OPTIONS" } else { "SQLSERVER2008" }
            if (Test-Bound -ParameterName ConfigurationFile) {
                try {
                    $config = Read-IniFile -Path $ConfigurationFile
                } catch {
                    Stop-Function -Message "Failed to read config file $ConfigurationFile" -ErrorRecord $_
                }
            } else {
                # determine a default user to assign sqladmin permissions
                if ($Credential) {
                    $defaultAdminAccount = $Credential.UserName
                } else {
                    if ($env:USERDOMAIN) {
                        $defaultAdminAccount = "$env:USERDOMAIN\$env:USERNAME"
                    } else {
                        if ($computer.IsLocalHost) {
                            $defaultAdminAccount = "$($resolvedName.ComputerName)\$env:USERNAME"
                        } else {
                            $defaultAdminAccount = $env:USERNAME
                        }
                    }
                }
                # determine browser startup
                if ($instance -eq 'MSSQLSERVER') { $browserStartup = 'Manual' }
                else { $browserStartup = 'Automatic' }
                # build generic config based on parameters
                $config = @{
                    $mainKey = @{
                        ACTION                = "Install"
                        AGTSVCSTARTUPTYPE     = "Automatic"
                        ASCOLLATION           = "Latin1_General_CI_AS"
                        BROWSERSVCSTARTUPTYPE = $browserStartup
                        ENABLERANU            = "False"
                        ERRORREPORTING        = "False"
                        FEATURES              = $featureList
                        FILESTREAMLEVEL       = "0"
                        HELP                  = "False"
                        INDICATEPROGRESS      = "False"
                        INSTANCEID            = $instance
                        INSTANCENAME          = $instance
                        ISSVCSTARTUPTYPE      = "Automatic"
                        QUIET                 = "True"
                        QUIETSIMPLE           = "False"
                        RSINSTALLMODE         = "DefaultNativeMode"
                        RSSVCSTARTUPTYPE      = "Automatic"
                        SQLCOLLATION          = "SQL_Latin1_General_CP1_CI_AS"
                        SQLSVCSTARTUPTYPE     = "Automatic"
                        SQLSYSADMINACCOUNTS   = $defaultAdminAccount
                        SQMREPORTING          = "False"
                        TCPENABLED            = "1"
                        UPDATEENABLED         = "False"
                        X86                   = "False"
                    }
                }
            }
            $configNode = $config.$mainKey
            if (-not $configNode) {
                Stop-Function -Message "Incorrect configuration file. Main node $mainKey not found."
                return
            }
            $execParams = @()
            # version-specific stuff
            if ($canonicVersion -gt '10.0') {
                $execParams += '/IACCEPTSQLSERVERLICENSETERMS'
            }
            # activate .Net 3.5 if missing - only needed on 2012 and 2014
            if ($canonicVersion -ge '11.0' -and $canonicVersion -le '12.0' ) {
                if (-Not (Get-WindowsFeature NET-Framework-Core| Where-Object $_.InstallState -eq 'Installed')) {
                    Write-Message -Level Verbose -Message "Installing .Net Framework 3.5 (NET-Framework-Core)"
                    $dotNetParams = @{ Name = 'NET-Framework-Core' }
                    if ($DotNetPath) { $dotNetParams += @{ Source = $DotNetPath }
                    }
                    try {
                        $dotNetResults = Install-WindowsFeature @DotNetPath -ErrorAction Stop
                    } catch {
                        Stop-Function -Message ".Net3.5 installation returned failure" -ErrorRecord $_
                    }
                    if (-Not $dotNetResults.Success) {
                        Write-Message -Level Warning -Message ".Net3.5 installation was unsuccessful"
                    }
                }
            }
            if ($canonicVersion -ge '13.0') {
                # configure the number of cores
                $cores = Get-DbaCmObject -ComputerName $fullComputerName -Credential $Credential -ClassName Win32_processor | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum
                if ($cores -gt 8) {
                    $cores = 8
                }
                $configNode.SQLTEMPDBFILECOUNT = $cores
            }
            # Apply custom configuration keys if provided
            if ($Configuration) {
                foreach ($key in $Configuration.Keys) {
                    $configNode.$key = [string]$Configuration.$key
                    if ($key -eq 'UpdateSource' -and $Configuration.Keys -notcontains 'UPDATEENABLED') {
                        #enable updates since now we have a source
                        $configNode.UPDATEENABLED = "True"
                    }
                }
            }

            # Now apply credentials
            $execParams += Update-ServiceCredential -Node $configNode -Credential $EngineCredential -AccountName SQLSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $AgentCredential -AccountName AGTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ASCredential -AccountName ASSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $ISCredential -AccountName ISSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $RSCredential -AccountName RSSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $FTCredential -AccountName FTSVCACCOUNT
            $execParams += Update-ServiceCredential -Node $configNode -Credential $PBEngineCredential -AccountName PBENGSVCACCOUNT -PasswordName PBDMSSVCPASSWORD
            $execParams += Update-ServiceCredential -Credential $SaCredential -PasswordName SAPWD
            # And root folders and other variables
            if (Test-Bound -ParameterName InstancePath) {
                $configNode.INSTANCEDIR = $InstancePath
            }
            if (Test-Bound -ParameterName DataPath) {
                $configNode.SQLUSERDBDIR = $DataPath
            }
            if (Test-Bound -ParameterName LogPath) {
                $configNode.SQLUSERDBLOGDIR = $LogPath
            }
            if (Test-Bound -ParameterName TempPath) {
                $configNode.SQLTEMPDBDIR = $TempPath
            }
            if (Test-Bound -ParameterName BackupPath) {
                $configNode.SQLBACKUPDIR = $BackupPath
            }
            if (Test-Bound -ParameterName AdminAccount) {
                $configNode.SQLSYSADMINACCOUNTS = $AdminAccount
            }
            # PID
            if (Test-Bound -ParameterName ProductID) {
                $configNode.PID = $ProductID
            }
            # Authentication
            if ($AuthenticationMode -eq 'Mixed') {
                $configNode.SECURITYMODE = "SQL"
            }

            # save config file
            $tempdir = Get-DbatoolsConfigValue -FullName path.dbatoolstemp
            $configFile = "$tempdir\Configuration_$($fullComputerName)_$instance_$version.ini"
            try {
                Write-IniFile -Content $config -Path $configFile
            } catch {
                Stop-Function -Message "Failed to write config file to $configFile" -ErrorRecord $_
            }
            $execParams += "/CONFIGURATIONFILE=`"$configFile`""
            if ($PSCmdlet.ShouldProcess($fullComputerName, "Install $Version from $setupFile")) {
                $actionPlan += [pscustomobject]@{
                    ComputerName      = $fullComputerName
                    InstanceName      = $instance
                    Port              = $portNumber
                    InstallationPath  = $setupFile
                    ConfigurationPath = $configFile
                    ArgumentList      = $execParams
                    RestartNeeded     = $restartNeeded
                }
            }
        }

        $installAction = {
            $output = [pscustomobject]@{
                ComputerName = $_.ComputerName
                Version      = $Version
                Build        = $currentVersion.Build
                SACredential = $null
                Successful   = $false
                Restarted    = $false
                InstanceName = $_.InstanceName
                Installer    = $_.InstallationPath
                Port         = $null
                Notes        = @()
                ExitCode     = $null
                Log          = $null
            }
            $restartParams = @{
                ComputerName = $_.ComputerName
                ErrorAction  = 'Stop'
                For          = 'WinRM'
                Wait         = $true
                Force        = $true
            }
            if ($Credential) {
                $restartParams.Credential = $Credential
            }
            if ($_.RestartNeeded -and $Restart) {
                # Restart the computer prior to doing anything
                #Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Restarting computer $($computer) due to pending restart"
                Write-Message -Level Verbose "Restarting computer $($_.ComputerName) due to pending restart" -FunctionName Update-DbaInstance
                try {
                    $null = Restart-Computer @restartParams
                    $output.Restarted = $true
                } catch {
                    Stop-Function -Message "Failed to restart computer" -ErrorRecord $_ -FunctionName Update-DbaInstance
                }
            }
            $sessionParams = @{
                ComputerName = $_.ComputerName
                ErrorAction  = "Stop"
            }
            if ($Credential) { $sessionParams.Credential = $Credential }
            # save config if needed
            if ($SaveConfiguration) {
                try {
                    $null = Copy-Item $_.ConfigurationPath -Destination $SaveConfiguration -ErrorAction Stop
                } catch {
                    $msg = "Could not save configuration file to $SaveConfiguration"
                    Write-Message -Level Warning -Message $msg
                    $output.Notes += $msg
                }
            }
            try {
                # need to figure out where to store the config file
                $session = New-PSSession @sessionParams
                $chosenPath = Invoke-Command -Session $session -ScriptBlock { (Get-Item ([System.IO.Path]::GetTempPath())).FullName } -ErrorAction Stop
                $remoteConfig = Join-DbaPath $chosenPath (Split-Path $_.ConfigurationPath -Leaf)
                Write-Message -Level Verbose -Message "Copying $($_.ConfigurationPath) to remote machine into $chosenPath"
                Copy-Item -Path $_.ConfigurationPath -Destination $remoteConfig -ToSession $session -Force -ErrorAction Stop
                $session | Remove-PSSession
            } catch {
                $msg = "Failed to copy file $($_.ConfigurationPath) to the remote session with $($_.ComputerName)"
                Stop-Function -Message $msg -ErrorRecord $_ -FunctionName Update-DbaInstance
                $output.Notes += $msg
            }
            Write-Message -Level Verbose -Message "Setup starting from $($_.InstallationPath)"
            $execParams = @{
                ComputerName   = $_.ComputerName
                ErrorAction    = 'Stop'
                Authentication = $Authentication
            }
            if ($Credential) {
                $execParams.Credential = $Credential
            } else {
                if (Test-Bound -Not Authentication) {
                    # Use Default authentication instead of CredSSP when Authentication is not specified and Credential is null
                    $execParams.Authentication = "Default"
                }
            }
            try {
                $installResult = Invoke-Program @execParams -Path $_.InstallationPath -ArgumentList $_.ArgumentList -Fallback
                $output.ExitCode = $updateResult.ExitCode
                $output.SACredential = $SaCredential
                # Get setup log summary contents
                try {
                    $output.Log = Get-SqlInstallSummary -ComputerName $_.ComputerName -Credential $Credential -Version $canonicVersion
                } catch {
                    $msg = "Could not get the contents of the summary file from $($_.ComputerName). 'Log' property will be empty | $($_.Exception.Message)"
                    $output.Notes += $msg
                }
                if ($installResult.Successful) {
                    $output.Successful = $true
                } else {
                    $msg = "Installation failed with exit code $($installResult.ExitCode). Expand 'Log' property to find more details."
                    $output.Notes += $msg
                    Stop-Function -Message $msg -FunctionName Update-DbaInstance
                    return $output
                }
            } catch {
                Stop-Function -Message "Installation failed" -ErrorRecord $_ -FunctionName Update-DbaInstance
                $output.Notes += $_.Exception.Message
                return $output
            } finally {
                ## Cleanup temp
                $null = Invoke-Command2 @sessionParams -ScriptBlock {
                    if ($args[0] -like '*\Configuration_*.ini' -and (Test-Path $args[0])) {
                        Remove-Item -LiteralPath $args[0] -ErrorAction Stop
                    }
                } -Raw -ArgumentList $setupFile
                # cleanup config file
                Remove-Item $_.ConfigurationPath
            }

            # perform volume maintenance tasks if requested
            if ($PerformVolumeMaintenanceTasks) {
                Set-DbaPrivilege -ComputerName $_.ComputerName -Credential $Credential -Type IFI -EnableException:$EnableException
            }
            # change port after the installation
            if ($_.Port) {
                Set-DbaTcpPort -SqlInstance "$($_.ComputerName)\$($_.InstanceName)" -Credential $Credential -Port $_.Port -EnableException:$EnableException
            }
            # restart if necessary
            if ($installResult.ExitCode -eq 3010 -or (Test-PendingReboot -ComputerName $_.ComputerName -Credential $Credential)) {
                if ($Restart) {
                    # Restart the computer
                    #Write-ProgressHelper -ExcludePercent -Activity $activity -Message "Restarting computer $($computer) and waiting for it to come back online"
                    Write-Message -Level Verbose -Message "Restarting computer $($_.ComputerName) and waiting for it to come back online" -FunctionName Install-DbaInstance
                    try {
                        $null = Restart-Computer @restartParams
                        $output.Restarted = $true
                    } catch {
                        Stop-Function -Message "Failed to restart computer $($_.ComputerName)" -ErrorRecord $_ -FunctionName Install-DbaInstance
                        return $output
                    }
                } else {
                    $output.Notes += "Restart is required for computer $($_.ComputerName) to finish the installation of SQL$Version"
                }
            }
            return $output
        }
        $outputHandler = {
            $_ | Select-DefaultView -Property ComputerName, Version, Successful, InstanceName, Installer, Notes
            if ($_.Successful -eq $false) {
                Write-Message -Level Warning -Message "Installation failed: $($_.Notes -join ' | ')"
            }
        }
        # check how many computers we are looking at and decide upon parallelism
        if ($actionPlan.Count -eq 1) {
            $actionPlan | ForEach-Object -Process $installAction | ForEach-Object -Process $outputHandler
        } elseif ($actionPlan.Count -ge 2) {
            $actionPlan | Invoke-Parallel -ImportModules -ImportVariables -ScriptBlock $installAction -Throttle $Throttle | ForEach-Object -Process $outputHandler
        }
    }
}