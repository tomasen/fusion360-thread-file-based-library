[CmdletBinding()]
param(
    [ValidateSet('auto', 'powershell', 'pwsh')]
    [string] $ChildEngine = 'auto'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $repositoryRoot 'install.ps1'
$assetName = 'fusion360-thread-file-based-library-windows.zip'
$checksumName = $assetName + '.sha256'
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

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Fusion Thread Bootstrap Tests {0}" -f [guid]::NewGuid().ToString('N'))
$releaseRoot = Join-Path $testRoot 'Release'
$payloadRoot = Join-Path $testRoot 'Payload'
$installRoot = Join-Path $testRoot 'Install Tést & Manager'
$stateRoot = Join-Path $testRoot 'Manager State'
$archivePath = Join-Path $releaseRoot $assetName
$checksumPath = Join-Path $releaseRoot $checksumName
$script:passed = 0

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

function New-TestRelease {
    param(
        [Parameter(Mandatory = $true)][string] $Archive,
        [Parameter(Mandatory = $true)][string] $Checksum,
        [switch] $InvalidChecksum
    )

    if (Test-Path -LiteralPath $Archive) {
        Remove-Item -LiteralPath $Archive -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $payloadRoot,
        $Archive,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
    $hash = if ($InvalidChecksum) { '0' * 64 } else { (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant() }
    [System.IO.File]::WriteAllText(
        $Checksum,
        "$hash  $assetName`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function New-TraversalRelease {
    param(
        [Parameter(Mandatory = $true)][string] $Archive,
        [Parameter(Mandatory = $true)][string] $Checksum
    )

    if (Test-Path -LiteralPath $Archive) {
        Remove-Item -LiteralPath $Archive -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($Archive, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry('../escaped.txt')
        $writer = New-Object System.IO.StreamWriter($entry.Open())
        try {
            $writer.Write('unsafe')
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
    $hash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText(
        $Checksum,
        "$hash  $assetName`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Invoke-BootstrapFile {
    param(
        [Parameter(Mandatory = $true)][string] $Target,
        [string] $Archive = $archivePath,
        [string] $Checksum = $checksumPath,
        [switch] $InstallPacks,
        [string] $ThreadDataPath,
        [string] $ManagerStateRoot
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $bootstrapPath,
        '-InstallRoot', $Target,
        '-ArchivePath', $Archive,
        '-ChecksumPath', $Checksum,
        '-SkipPathUpdate'
    )
    if ($InstallPacks) {
        $arguments += @('-ThreadDataPath', $ThreadDataPath, '-StateRoot', $ManagerStateRoot)
    }
    else {
        $arguments += '-SkipPackInstall'
    }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $engine @arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    }
}

New-Item -ItemType Directory -Path $releaseRoot, $payloadRoot, $stateRoot -Force | Out-Null
foreach ($name in @('fusion-threads.ps1', 'fusion-threads.cmd', 'src', 'packs')) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $name) -Destination $payloadRoot -Recurse -Force
}
[System.IO.File]::WriteAllText((Join-Path $stateRoot 'sentinel.txt'), 'preserve me')

try {
    New-TestRelease -Archive $archivePath -Checksum $checksumPath

    Invoke-TestCase 'bootstrap installs a verified release without touching manager state' {
        $result = Invoke-BootstrapFile -Target $installRoot
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'fusion-threads.ps1') -PathType Leaf) 'Installed CLI is missing.'
        Assert-True (Test-Path -LiteralPath (Join-Path $installRoot '.fusion-thread-manager-install.json') -PathType Leaf) 'Install ownership marker is missing.'
        Assert-Equal 'preserve me' ([System.IO.File]::ReadAllText((Join-Path $stateRoot 'sentinel.txt'))) 'Bootstrap changed external manager state.'
        Assert-True ($result.Output -match 'Skipped Fusion thread-pack installation') 'Expected skip confirmation.'
    }

    Invoke-TestCase 'bootstrap atomically replaces its owned install root' {
        [System.IO.File]::WriteAllText((Join-Path $installRoot 'stale.txt'), 'remove on update')
        $result = Invoke-BootstrapFile -Target $installRoot
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $installRoot 'stale.txt'))) 'Update retained a stale manager file.'
        Assert-Equal 'preserve me' ([System.IO.File]::ReadAllText((Join-Path $stateRoot 'sentinel.txt'))) 'Update changed external manager state.'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $testRoot -Directory -Filter '.FusionThreadManager-*-*').Count 'Update left a staging or previous-version directory.'
    }

    Invoke-TestCase 'dynamic scriptblock execution does not require PSScriptRoot' {
        $dynamicInstall = Join-Path $testRoot 'Dynamic Script Install'
        $source = [System.IO.File]::ReadAllText($bootstrapPath)
        $scriptBlock = [scriptblock]::Create($source)
        $output = & $scriptBlock -InstallRoot $dynamicInstall -ArchivePath $archivePath -ChecksumPath $checksumPath -SkipPackInstall -SkipPathUpdate 2>&1
        Assert-True (Test-Path -LiteralPath (Join-Path $dynamicInstall 'fusion-threads.cmd') -PathType Leaf) (($output | Out-String) + ' Dynamic install failed.')
    }

    Invoke-TestCase 'bootstrap invokes the installed CLI to install thread packs' {
        $packInstallRoot = Join-Path $testRoot 'Pack Install Manager'
        $threadData = Join-Path $testRoot 'Temporary Fusion\ThreadData'
        $packState = Join-Path $testRoot 'Pack Install State'
        New-Item -ItemType Directory -Path $threadData | Out-Null
        $result = Invoke-BootstrapFile -Target $packInstallRoot -InstallPacks -ThreadDataPath $threadData -ManagerStateRoot $packState
        Assert-Equal 0 $result.ExitCode $result.Output
        Assert-True (Test-Path -LiteralPath (Join-Path $threadData 'US-Garden-Hose-GHT.xml') -PathType Leaf) 'Installed CLI did not copy the thread XML.'
        $expectedPackCount = @(Get-ChildItem -LiteralPath (Join-Path $payloadRoot 'packs') -Filter 'pack.json' -File -Recurse).Count
        Assert-Equal $expectedPackCount @(Get-ChildItem -LiteralPath (Join-Path $packState 'receipts') -Filter '*.json' -File -Recurse).Count 'Installed CLI did not create one receipt per pack.'
    }

    Invoke-TestCase 'manager remains installed when thread-pack installation fails' {
        $managerOnlyRoot = Join-Path $testRoot 'Manager Survives Pack Failure'
        $missingThreadData = Join-Path $testRoot 'Missing Fusion\ThreadData'
        $failedPackState = Join-Path $testRoot 'Failed Pack State'
        $result = Invoke-BootstrapFile -Target $managerOnlyRoot -InstallPacks -ThreadDataPath $missingThreadData -ManagerStateRoot $failedPackState
        Assert-True ($result.ExitCode -ne 0) 'Missing ThreadData path unexpectedly succeeded.'
        Assert-True ($result.Output -match 'manager remains installed') 'Expected the partial-success explanation.'
        Assert-True (Test-Path -LiteralPath (Join-Path $managerOnlyRoot 'fusion-threads.ps1') -PathType Leaf) 'Pack failure removed the installed manager.'
        Assert-True (-not (Test-Path -LiteralPath $failedPackState)) 'Pack failure created manager state unexpectedly.'
    }

    Invoke-TestCase 'checksum mismatch fails without creating an install root' {
        $badInstall = Join-Path $testRoot 'Bad Checksum Install'
        New-TestRelease -Archive $archivePath -Checksum $checksumPath -InvalidChecksum
        $result = Invoke-BootstrapFile -Target $badInstall
        Assert-True ($result.ExitCode -ne 0) 'Checksum mismatch unexpectedly succeeded.'
        Assert-True ($result.Output -match 'SHA-256 verification failed') 'Expected checksum failure explanation.'
        Assert-True (-not (Test-Path -LiteralPath $badInstall)) 'Checksum failure created an install root.'
    }

    Invoke-TestCase 'path traversal entry is rejected and cannot escape extraction' {
        $traversalInstall = Join-Path $testRoot 'Traversal Install'
        $escapedPath = Join-Path $testRoot 'escaped.txt'
        New-TraversalRelease -Archive $archivePath -Checksum $checksumPath
        $result = Invoke-BootstrapFile -Target $traversalInstall
        Assert-True ($result.ExitCode -ne 0) 'Traversal archive unexpectedly succeeded.'
        Assert-True ($result.Output -match 'unsafe path') 'Expected unsafe-path explanation.'
        Assert-True (-not (Test-Path -LiteralPath $traversalInstall)) 'Traversal failure created an install root.'
        Assert-True (-not (Test-Path -LiteralPath $escapedPath)) 'Traversal archive wrote outside extraction root.'
    }

    Invoke-TestCase 'non-empty unowned install root is preserved' {
        New-TestRelease -Archive $archivePath -Checksum $checksumPath
        $unownedRoot = Join-Path $testRoot 'Unowned Install'
        New-Item -ItemType Directory -Path $unownedRoot | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $unownedRoot 'user.txt'), 'keep me')
        $result = Invoke-BootstrapFile -Target $unownedRoot
        Assert-True ($result.ExitCode -ne 0) 'Bootstrap replaced an unowned directory.'
        Assert-True ($result.Output -match 'Refusing to replace non-empty unowned') 'Expected ownership failure explanation.'
        Assert-Equal 'keep me' ([System.IO.File]::ReadAllText((Join-Path $unownedRoot 'user.txt'))) 'Bootstrap changed an unowned directory.'
    }

    Write-Host "`n$script:passed bootstrap tests passed using $engineCommand."
}
finally {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot) -like 'Fusion Thread Bootstrap Tests *') {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
