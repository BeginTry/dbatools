$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'AccessToken', 'ApplicationIntent', 'AzureUnsupported', 'BatchSeparator', 'ClientName', 'ConnectTimeout', 'EncryptConnection', 'FailoverPartner', 'LockTimeout', 'MaxPoolSize', 'MinPoolSize', 'MinimumVersion', 'MultipleActiveResultSets', 'MultiSubnetFailover', 'NetworkProtocol', 'NonPooledConnection', 'PacketSize', 'PooledConnectionLifetime', 'SqlExecutionModes', 'StatementTimeout', 'TrustServerCertificate', 'WorkstationId', 'AppendConnectionString', 'SqlConnectionOnly', 'DisableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    if ($env:azuredbpasswd) {
        Context "Connect to Azure" {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($script:azuresqldblogin, $securePassword)

            It "Should login to Azure" {
                $s = Connect-DbaInstance -SqlInstance $script:azureserver -SqlCredential $cred -Database test
                $s.Name | Should -match $script:azureserver
                $s.DatabaseEngineType | Should -Be 'SqlAzureDatabase'
            }
        }
    }

    Context "connection is properly made" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1 -ApplicationIntent ReadOnly

        It "returns the proper name" {
            $server.Name -eq $script:instance1 | Should Be $true
        }

        It "returns more than one database" {
            $server.Databases.Name.Count -gt 0 | Should Be $true
        }

        It "returns the connection with ApplicationIntent of ReadOnly" {
            $server.ConnectionContext.ConnectionString -match "ApplicationIntent=ReadOnly" | Should Be $true
        }

        It "sets StatementTimeout to 0" {
            $server = Connect-DbaInstance -SqlInstance $script:instance1 -StatementTimeout 0

            $server.ConnectionContext.StatementTimeout | Should Be 0
        }

        It "sets connectioncontext parameters that are provided" {
            $params = @{
                'BatchSeparator'           = 'GO'
                'ConnectTimeout'           = 1
                'Database'                 = 'master'
                'LockTimeout'              = 1
                'MaxPoolSize'              = 20
                'MinPoolSize'              = 1
                'NetworkProtocol'          = 'TcpIp'
                'PacketSize'               = 4096
                'PooledConnectionLifetime' = 600
                'WorkstationId'            = 'MadeUpServer'
                'SqlExecutionModes'        = 'ExecuteSql'
                'StatementTimeout'         = 0
            }

            $server = Connect-DbaInstance -SqlInstance $script:instance1 @params

            foreach ($param in $params.GetEnumerator()) {
                if ($param.Key -eq 'Database') {
                    $propName = 'DatabaseName'
                } else {
                    $propName = $param.Key
                }

                $server.ConnectionContext.$propName | Should Be $param.Value
            }
        }
    }
}