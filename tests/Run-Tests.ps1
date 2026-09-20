[CmdletBinding()]
param(
    [ValidateSet('auto', 'powershell', 'pwsh')]
    [string] $ChildEngine = 'auto'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $repositoryRoot 'fusion-threads.ps1'
$gardenPackId = 'us.asme-b1.20.7.garden-hose'
$packXml = Join-Path $repositoryRoot 'packs\us\asme-b1.20.7\garden-hose\US-Garden-Hose-GHT.xml'
$engineCommand = switch ($ChildEngine) {
    'powershell' { 'powershell.exe' }
    'pwsh' { 'pwsh.exe' }
    default {
        if (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue) { 'powershell.exe' } else { 'pwsh.exe' }
    }
}
$engineInfo = Get-Command $engineCommand -ErrorAction SilentlyContinue
if ($null -eq $engineInfo) {
    throw "Requested child engine is unavailable: $engineCommand"
}
$engine = $engineInfo.Source

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Fusion Thread Manager Tests {0}" -f [guid]::NewGuid().ToString('N'))
$threadData = Join-Path $testRoot 'Tést & Fusion\ThreadData'
$stateRoot = Join-Path $testRoot 'Manager State'
$destination = Join-Path $threadData 'US-Garden-Hose-GHT.xml'
$script:passed = 0

function Invoke-TestCli {
    param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [string] $CommandPath = $cliPath
    )

    $allArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $CommandPath
    ) + $Arguments

    $quotedArguments = @($allArguments | ForEach-Object { '"' + ([string] $_).Replace('"', '\"') + '"' })
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $engine
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void] $process.Start()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    $combinedOutput = $standardOutput
    if (-not [string]::IsNullOrWhiteSpace($standardError)) {
        $combinedOutput += $standardError
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $combinedOutput
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool] $Condition,
        [Parameter(Mandatory = $true)][string] $Message
    )
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [Parameter(Mandatory = $true)][string] $Message
    )
    if ($Expected -ne $Actual) {
        throw "ASSERTION FAILED: $Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Body
    )
    & $Body
    $script:passed++
    Write-Host "[pass] $Name"
}

New-Item -ItemType Directory -Path $threadData -Force | Out-Null

try {
    Invoke-TestCase 'pack validation succeeds' {
        $result = Invoke-TestCli @('validate')
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True ($result.Output -match '\[valid\].*garden-hose') 'Expected valid pack output.'
    }

    Invoke-TestCase 'bundled library has four packs and 37 two-gender designations' {
        $manifests = @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'packs') -Filter 'pack.json' -File -Recurse)
        Assert-Equal 4 $manifests.Count 'Unexpected bundled pack count.'

        $xmlFiles = @($manifests | ForEach-Object {
            $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            foreach ($file in @($manifest.files)) {
                Join-Path $_.DirectoryName ([string] $file.source)
            }
        })
        $documents = @($xmlFiles | ForEach-Object { [xml] (Get-Content -LiteralPath $_ -Raw) })
        $designations = @($documents | ForEach-Object { $_.SelectNodes('/ThreadType/ThreadSize/Designation') })
        $threads = @($designations | ForEach-Object { $_.SelectNodes('./Thread') })

        Assert-Equal 37 $designations.Count 'Unexpected thread designation count.'
        Assert-Equal 74 $threads.Count 'Every designation should contain external and internal profiles.'
        foreach ($designation in $designations) {
            $genders = @($designation.SelectNodes('./Thread/Gender') | ForEach-Object { $_.InnerText })
            Assert-Equal 1 @($genders | Where-Object { $_ -eq 'external' }).Count "Missing or duplicate external profile for $($designation.ThreadDesignation)."
            Assert-Equal 1 @($genders | Where-Object { $_ -eq 'internal' }).Count "Missing or duplicate internal profile for $($designation.ThreadDesignation)."
        }
    }

    Invoke-TestCase 'duplicate pack selection is rejected' {
        $result = Invoke-TestCli @('list', '-Pack', "$gardenPackId,$gardenPackId")
        Assert-True ($result.ExitCode -ne 0) 'Duplicate pack selection unexpectedly succeeded.'
        Assert-True ($result.Output -match 'selected more than once') 'Expected duplicate-selection explanation.'
    }

    Invoke-TestCase 'dry-run performs no writes' {
        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot, '-DryRun')
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'Dry-run created the destination.'
        Assert-True (-not (Test-Path -LiteralPath $stateRoot)) 'Dry-run created manager state.'
    }

    Invoke-TestCase 'fresh install copies exact bytes and writes a receipt' {
        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (Test-Path -LiteralPath $destination -PathType Leaf) 'Installed XML is missing.'
        Assert-Equal (Get-FileHash -LiteralPath $packXml -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Installed bytes differ from pack bytes.'
        $receipts = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'receipts') -Filter '*.json' -File -Recurse)
        Assert-Equal 1 $receipts.Count 'Expected exactly one receipt.'
        $receipt = Get-Content -LiteralPath $receipts[0].FullName -Raw | ConvertFrom-Json
        Assert-Equal $gardenPackId $receipt.packId 'Wrong receipt pack id.'
        Assert-Equal '1.0.1' $receipt.packVersion 'Wrong receipt pack version.'
    }

    Invoke-TestCase 'repeat install is idempotent' {
        $beforeHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-Equal $beforeHash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Repeat install changed the file.'
        Assert-True ($result.Output -match 'keep identical') 'Expected no-change output.'
    }

    Invoke-TestCase 'modified managed file is protected by default' {
        [System.IO.File]::WriteAllText($destination, 'local modification')
        $result = Invoke-TestCli @('update', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-True ($result.ExitCode -ne 0) 'Update unexpectedly replaced a local modification.'
        Assert-Equal 'local modification' ([System.IO.File]::ReadAllText($destination)) 'Conflict path changed the modified file.'
    }

    Invoke-TestCase 'forced update backs up and replaces a modified managed file' {
        $result = Invoke-TestCli @('update', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot, '-Force')
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-Equal (Get-FileHash -LiteralPath $packXml -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Forced update did not install pack bytes.'
        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'backups') -Filter 'US-Garden-Hose-GHT.xml' -File -Recurse)
        Assert-True ($backupFiles.Count -ge 1) 'Forced update did not create a backup.'
        Assert-True (@($backupFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -eq 'local modification' }).Count -ge 1) 'Backup does not contain the local modification.'
    }

    Invoke-TestCase 'dry-run uninstall preserves files and state' {
        $result = Invoke-TestCli @('uninstall', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot, '-DryRun')
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (Test-Path -LiteralPath $destination -PathType Leaf) 'Dry-run uninstall removed the file.'
        $receiptCount = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'receipts') -Filter '*.json' -File -Recurse).Count
        Assert-True -Condition ($receiptCount -eq 1) -Message 'Dry-run uninstall removed the receipt.'
    }

    Invoke-TestCase 'normal uninstall removes a manager-created file' {
        $result = Invoke-TestCli @('uninstall', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (-not (Test-Path -LiteralPath $destination)) 'Uninstall left the managed file.'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'receipts') -Filter '*.json' -File -Recurse).Count 'Uninstall left a receipt.'
    }

    Invoke-TestCase 'identical unmanaged file requires explicit adoption and survives uninstall' {
        Copy-Item -LiteralPath $packXml -Destination $destination -Force
        $beforeHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash

        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-True ($result.ExitCode -ne 0) 'Install silently adopted an unmanaged identical file.'
        Assert-Equal $beforeHash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Conflict path changed the identical file.'

        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot, '-AdoptExisting')
        Assert-Equal 0 $result.ExitCode $result.Output
        $result = Invoke-TestCli @('uninstall', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (Test-Path -LiteralPath $destination -PathType Leaf) 'Uninstall removed a file that predated adoption.'
        Assert-Equal $beforeHash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Uninstall did not preserve the adopted original.'
        Remove-Item -LiteralPath $destination -Force
    }

    Invoke-TestCase 'pack update removes an obsolete managed filename' {
        $updateRoot = Join-Path $testRoot 'Rename Update'
        $updateThreadData = Join-Path $updateRoot 'ThreadData'
        $updateState = Join-Path $updateRoot 'State'
        $repositoryCopy = Join-Path $updateRoot 'Repository Copy'
        New-Item -ItemType Directory -Path $updateThreadData, $repositoryCopy -Force | Out-Null
        Copy-Item -Path (Join-Path $repositoryRoot '*') -Destination $repositoryCopy -Recurse -Force

        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $updateThreadData, '-StateRoot', $updateState)
        Assert-Equal 0 $result.ExitCode $result.Output
        $oldDestination = Join-Path $updateThreadData 'US-Garden-Hose-GHT.xml'
        Assert-True (Test-Path -LiteralPath $oldDestination -PathType Leaf) 'Version 1 destination is missing.'

        $copiedManifestPath = Join-Path $repositoryCopy 'packs\us\asme-b1.20.7\garden-hose\pack.json'
        $copiedManifest = Get-Content -LiteralPath $copiedManifestPath -Raw | ConvertFrom-Json
        $copiedManifest.version = '1.1.0'
        $copiedManifest.files[0].destination = 'US-Garden-Hose-GHT-v2.xml'
        $json = $copiedManifest | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($copiedManifestPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

        $copiedCli = Join-Path $repositoryCopy 'fusion-threads.ps1'
        $result = Invoke-TestCli -Arguments @('update', '-Pack', $gardenPackId, '-ThreadDataPath', $updateThreadData, '-StateRoot', $updateState) -CommandPath $copiedCli
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (-not (Test-Path -LiteralPath $oldDestination)) 'Update orphaned the old managed filename.'
        Assert-True (Test-Path -LiteralPath (Join-Path $updateThreadData 'US-Garden-Hose-GHT-v2.xml') -PathType Leaf) 'Updated destination is missing.'
    }

    Invoke-TestCase 'unmanaged conflict is protected by default' {
        [System.IO.File]::WriteAllText($destination, 'pre-existing file')
        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-True ($result.ExitCode -ne 0) 'Install unexpectedly replaced an unmanaged conflict.'
        Assert-Equal 'pre-existing file' ([System.IO.File]::ReadAllText($destination)) 'Conflict path changed the unmanaged file.'
    }

    Invoke-TestCase 'forced install plus uninstall restores unmanaged original' {
        $result = Invoke-TestCli @('install', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot, '-Force')
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-Equal (Get-FileHash -LiteralPath $packXml -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash 'Forced install did not install pack bytes.'

        $receiptFile = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'receipts') -Filter '*.json' -File -Recurse)[0]
        $receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
        $originalBackup = [string] $receipt.files[0].originalBackup
        $originalBytes = [System.IO.File]::ReadAllBytes($originalBackup)
        Remove-Item -LiteralPath $originalBackup -Force

        $result = Invoke-TestCli @('uninstall', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-True ($result.ExitCode -ne 0) 'Uninstall succeeded without its required original backup.'
        Assert-True (Test-Path -LiteralPath $destination -PathType Leaf) 'Unsafe uninstall removed the managed destination.'
        Assert-True (Test-Path -LiteralPath $receiptFile.FullName -PathType Leaf) 'Unsafe uninstall removed its receipt.'

        [System.IO.File]::WriteAllBytes($originalBackup, $originalBytes)
        $result = Invoke-TestCli @('uninstall', '-Pack', $gardenPackId, '-ThreadDataPath', $threadData, '-StateRoot', $stateRoot)
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-Equal 'pre-existing file' ([System.IO.File]::ReadAllText($destination)) 'Uninstall did not restore the original file.'
    }

    Write-Host "`n$script:passed integration tests passed using $engineCommand."
}
finally {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot) -like 'Fusion Thread Manager Tests *') {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Expected-failure cases launch child processes that intentionally return 1.
# Do not leak their native exit code after the test suite itself succeeds.
$global:LASTEXITCODE = 0
