[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\FusionThreadManager'),
    [string[]] $Pack,
    [Alias('TargetThreadDataPath')]
    [string] $ThreadDataPath,
    [switch] $AllInstallations,
    [switch] $SkipPackInstall,
    [string] $StateRoot,

    # These options support offline installs and isolated automated tests.
    [string] $ArchivePath,
    [string] $ChecksumPath,
    [switch] $SkipPathUpdate,
    [string] $ReleaseBaseUrl = 'https://github.com/tomasen/fusion360-thread-file-based-library/releases/latest/download'
)

# Keep the implementation in a child scope. When this file is run with
# `irm <raw-url> | iex`, helper functions and preference variables should not
# leak into the caller's session.
& {
    param([hashtable] $Options)

    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'

    $productId = 'fusion360-thread-file-based-library'
    $archiveName = 'fusion360-thread-file-based-library-windows.zip'
    $checksumName = 'fusion360-thread-file-based-library-windows.zip.sha256'
    $markerName = '.fusion-thread-manager-install.json'
    $maximumEntryCount = 4096
    $maximumEntryBytes = 128MB
    $maximumExpandedBytes = 256MB

    function Get-BootstrapFullPath {
        param([Parameter(Mandatory = $true)][string] $Path)

        $expanded = [Environment]::ExpandEnvironmentVariables($Path)
        return [System.IO.Path]::GetFullPath($expanded)
    }

    function Test-BootstrapChildPath {
        param(
            [Parameter(Mandatory = $true)][string] $Parent,
            [Parameter(Mandatory = $true)][string] $Candidate
        )

        $parentFull = Get-BootstrapFullPath $Parent
        $candidateFull = Get-BootstrapFullPath $Candidate
        $prefix = $parentFull.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        return $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
    }

    function Remove-BootstrapDirectory {
        param(
            [Parameter(Mandatory = $true)][string] $Parent,
            [Parameter(Mandatory = $true)][string] $Path,
            [Parameter(Mandatory = $true)][string] $LeafPrefix
        )

        $full = Get-BootstrapFullPath $Path
        if (-not (Test-BootstrapChildPath $Parent $full)) {
            throw "Refusing to remove a path outside its expected parent: $full"
        }
        if (-not (Split-Path -Leaf $full).StartsWith($LeafPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an unexpected directory: $full"
        }
        if (Test-Path -LiteralPath $full) {
            Remove-Item -LiteralPath $full -Recurse -Force
        }
    }

    function Copy-BootstrapArtifact {
        param(
            [string] $LocalPath,
            [Parameter(Mandatory = $true)][string] $Uri,
            [Parameter(Mandatory = $true)][string] $Destination
        )

        if (-not [string]::IsNullOrWhiteSpace($LocalPath)) {
            $source = Get-BootstrapFullPath $LocalPath
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Local bootstrap artifact not found: $source"
            }
            Copy-Item -LiteralPath $source -Destination $Destination
            return
        }

        Write-Host "Downloading $Uri"
        $previousProtocol = [System.Net.ServicePointManager]::SecurityProtocol
        $client = New-Object System.Net.WebClient
        try {
            if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'Tls12') {
                [System.Net.ServicePointManager]::SecurityProtocol =
                    $previousProtocol -bor [System.Net.SecurityProtocolType]::Tls12
            }
            $client.Headers['User-Agent'] = 'FusionThreadManager-Bootstrap'
            $client.DownloadFile([uri] $Uri, $Destination)
        }
        finally {
            $client.Dispose()
            [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        }
    }

    function Assert-BootstrapChecksum {
        param(
            [Parameter(Mandatory = $true)][string] $Archive,
            [Parameter(Mandatory = $true)][string] $ChecksumFile
        )

        $checksumText = [System.IO.File]::ReadAllText($ChecksumFile).Trim().TrimStart([char] 0xFEFF)
        $lines = @($checksumText -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -ne 1 -or $lines[0] -notmatch '^([0-9A-Fa-f]{64})(?:[ \t]+\*?([^\r\n]+))?$') {
            throw "Invalid checksum file format. Expected one SHA-256 line in '$ChecksumFile'."
        }

        $expected = $Matches[1].ToLowerInvariant()
        $declaredName = [string] $Matches[2]
        if (-not [string]::IsNullOrWhiteSpace($declaredName)) {
            $declaredName = $declaredName.Trim()
            if ([System.IO.Path]::GetFileName($declaredName) -ne $declaredName -or
                $declaredName -ne $archiveName) {
                throw "Checksum file names an unexpected archive: $declaredName"
            }
        }

        $actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "SHA-256 verification failed for '$archiveName'. Expected $expected; found $actual."
        }
        Write-Host "Verified SHA-256: $actual"
    }

    function Expand-BootstrapArchiveSafely {
        param(
            [Parameter(Mandatory = $true)][string] $Archive,
            [Parameter(Mandatory = $true)][string] $Destination
        )

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        New-Item -ItemType Directory -Path $Destination | Out-Null
        $destinationFull = Get-BootstrapFullPath $Destination
        $destinationPrefix = $destinationFull.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ) + [System.IO.Path]::DirectorySeparatorChar
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $expandedTotal = [int64] 0
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Archive)
        try {
            if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt $maximumEntryCount) {
                throw "Release archive has an invalid entry count: $($zip.Entries.Count)"
            }

            foreach ($entry in $zip.Entries) {
                $entryName = ([string] $entry.FullName).Replace('\', '/')
                if ([string]::IsNullOrWhiteSpace($entryName) -or
                    $entryName.StartsWith('/') -or
                    $entryName.StartsWith('//') -or
                    $entryName -match '^[A-Za-z]:' -or
                    $entryName.IndexOf([char] 0) -ge 0) {
                    throw "Release archive contains an unsafe path: '$entryName'"
                }

                $isDirectory = $entryName.EndsWith('/')
                $trimmedName = $entryName.TrimEnd('/')
                $segments = @($trimmedName -split '/')
                if ($segments.Count -eq 0) {
                    throw "Release archive contains an empty path."
                }
                foreach ($segment in $segments) {
                    $isReservedDeviceName = $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]|CONIN\$|CONOUT\$)(?:\..*)?$'
                    if ([string]::IsNullOrWhiteSpace($segment) -or
                        $segment -eq '.' -or
                        $segment -eq '..' -or
                        $segment.EndsWith('.') -or
                        $segment.EndsWith(' ') -or
                        $isReservedDeviceName -or
                        $segment.Contains(':') -or
                        $segment.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                        throw "Release archive contains an unsafe path: '$entryName'"
                    }
                }

                $relativePath = [string]::Join([System.IO.Path]::DirectorySeparatorChar, $segments)
                if (-not $seen.Add($relativePath)) {
                    throw "Release archive contains duplicate paths: '$entryName'"
                }
                $outputPath = Get-BootstrapFullPath (Join-Path $destinationFull $relativePath)
                if (-not $outputPath.StartsWith($destinationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Release archive path escapes the extraction directory: '$entryName'"
                }

                $unixFileType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
                $dosAttributes = ($entry.ExternalAttributes -band 0xFFFF)
                if ($unixFileType -eq 0xA000 -or
                    (($dosAttributes -band [int] [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
                    throw "Release archive contains a link or reparse point: '$entryName'"
                }

                if ($isDirectory) {
                    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
                    continue
                }
                if ([int64] $entry.Length -gt $maximumEntryBytes) {
                    throw "Release archive entry is too large: '$entryName'"
                }

                $outputDirectory = Split-Path -Parent $outputPath
                New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
                $inputStream = $entry.Open()
                $outputStream = New-Object System.IO.FileStream(
                    $outputPath,
                    [System.IO.FileMode]::CreateNew,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )
                try {
                    $buffer = New-Object byte[] 81920
                    $entryTotal = [int64] 0
                    while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $entryTotal += $read
                        $expandedTotal += $read
                        if ($entryTotal -gt $maximumEntryBytes -or $expandedTotal -gt $maximumExpandedBytes) {
                            throw "Release archive exceeds the safe expanded-size limit."
                        }
                        $outputStream.Write($buffer, 0, $read)
                    }
                }
                finally {
                    $outputStream.Dispose()
                    $inputStream.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }

    function Get-BootstrapPayloadRoot {
        param([Parameter(Mandatory = $true)][string] $ExtractionRoot)

        $candidates = @($ExtractionRoot)
        $topLevel = @(Get-ChildItem -LiteralPath $ExtractionRoot -Force)
        if ($topLevel.Count -eq 1 -and $topLevel[0].PSIsContainer) {
            $candidates += $topLevel[0].FullName
        }

        foreach ($candidate in $candidates) {
            $requiredFiles = @(
                (Join-Path $candidate 'fusion-threads.ps1'),
                (Join-Path $candidate 'fusion-threads.cmd'),
                (Join-Path $candidate 'src\FusionThreadManager.psm1')
            )
            $filesPresent = @($requiredFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -eq $requiredFiles.Count
            $packsRoot = Join-Path $candidate 'packs'
            $packCount = if (Test-Path -LiteralPath $packsRoot -PathType Container) {
                @(Get-ChildItem -LiteralPath $packsRoot -Filter 'pack.json' -File -Recurse).Count
            }
            else {
                0
            }
            if ($filesPresent -and $packCount -gt 0) {
                return (Get-BootstrapFullPath $candidate)
            }
        }
        throw 'Release archive does not contain a valid Fusion Thread Manager payload.'
    }

    function Get-BootstrapPowerShell {
        foreach ($commandName in @('powershell.exe', 'pwsh.exe')) {
            $command = Get-Command $commandName -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                return $command.Source
            }
        }
        throw 'PowerShell is required to validate and run Fusion Thread Manager.'
    }

    function Invoke-BootstrapCli {
        param(
            [Parameter(Mandatory = $true)][string] $Engine,
            [Parameter(Mandatory = $true)][string] $CliPath,
            [Parameter(Mandatory = $true)][string[]] $Arguments,
            [Parameter(Mandatory = $true)][string] $FailureMessage
        )

        $processArguments = @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $CliPath
        ) + $Arguments
        $previousErrorAction = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 converts native stderr into non-terminating
            # ErrorRecord objects. Capture it without letting the bootstrap's
            # Stop preference preempt the explicit exit-code check below.
            $ErrorActionPreference = 'Continue'
            $output = @(& $Engine @processArguments 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorAction
        }
        foreach ($line in $output) {
            Write-Host ([string] $line)
        }
        if ($exitCode -ne 0) {
            throw "$FailureMessage (exit code $exitCode)"
        }
    }

    function Assert-BootstrapOwnedInstall {
        param([Parameter(Mandatory = $true)][string] $Target)

        if (-not (Test-Path -LiteralPath $Target)) {
            return
        }
        if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
            throw "InstallRoot is not a directory: $Target"
        }
        $children = @(Get-ChildItem -LiteralPath $Target -Force)
        if ($children.Count -eq 0) {
            return
        }

        $markerPath = Join-Path $Target $markerName
        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw "Refusing to replace non-empty unowned InstallRoot '$Target'. Choose another -InstallRoot or remove it manually."
        }
        try {
            $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Install ownership marker is unreadable: $markerPath"
        }
        if ([string] $marker.productId -ne $productId) {
            throw "InstallRoot belongs to a different product: $Target"
        }
    }

    function Install-BootstrapPayload {
        param(
            [Parameter(Mandatory = $true)][string] $PayloadRoot,
            [Parameter(Mandatory = $true)][string] $Target,
            [Parameter(Mandatory = $true)][string] $Engine
        )

        $targetFull = Get-BootstrapFullPath $Target
        $driveRoot = [System.IO.Path]::GetPathRoot($targetFull)
        if ($targetFull.TrimEnd('\', '/') -eq $driveRoot.TrimEnd('\', '/')) {
            throw "InstallRoot cannot be a drive root: $targetFull"
        }

        $targetParent = Split-Path -Parent $targetFull
        if ([string]::IsNullOrWhiteSpace($targetParent)) {
            throw "InstallRoot requires a parent directory: $targetFull"
        }
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Assert-BootstrapOwnedInstall $targetFull

        $token = [guid]::NewGuid().ToString('N')
        $stage = Join-Path $targetParent ('.FusionThreadManager-stage-' + $token)
        $old = Join-Path $targetParent ('.FusionThreadManager-old-' + $token)
        $oldMoved = $false
        $newMoved = $false
        try {
            New-Item -ItemType Directory -Path $stage | Out-Null
            foreach ($item in @(Get-ChildItem -LiteralPath $PayloadRoot -Force)) {
                Copy-Item -LiteralPath $item.FullName -Destination $stage -Recurse -Force
            }

            $versionPath = Join-Path $stage 'VERSION'
            $installedVersion = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
                [System.IO.File]::ReadAllText($versionPath).Trim()
            }
            else {
                'unknown'
            }
            $marker = [ordered]@{
                schemaVersion = 1
                productId = $productId
                version = $installedVersion
                installedAtUtc = [DateTime]::UtcNow.ToString('o')
                source = $Options.ReleaseBaseUrl
            }
            $markerJson = $marker | ConvertTo-Json
            [System.IO.File]::WriteAllText(
                (Join-Path $stage $markerName),
                $markerJson + [Environment]::NewLine,
                (New-Object System.Text.UTF8Encoding($false))
            )

            Invoke-BootstrapCli -Engine $Engine -CliPath (Join-Path $stage 'fusion-threads.ps1') -Arguments @('validate') -FailureMessage 'Downloaded manager validation failed'

            if (Test-Path -LiteralPath $targetFull) {
                Move-Item -LiteralPath $targetFull -Destination $old
                $oldMoved = $true
            }
            try {
                Move-Item -LiteralPath $stage -Destination $targetFull
                $newMoved = $true
            }
            catch {
                if ($oldMoved -and -not (Test-Path -LiteralPath $targetFull)) {
                    Move-Item -LiteralPath $old -Destination $targetFull
                    $oldMoved = $false
                }
                throw
            }

            if ($oldMoved -and (Test-Path -LiteralPath $old)) {
                try {
                    Remove-BootstrapDirectory -Parent $targetParent -Path $old -LeafPrefix '.FusionThreadManager-old-'
                    $oldMoved = $false
                }
                catch {
                    Write-Warning "The update succeeded, but the previous manager directory could not be removed: $old"
                }
            }
        }
        finally {
            if (-not $newMoved -and (Test-Path -LiteralPath $stage)) {
                Remove-BootstrapDirectory -Parent $targetParent -Path $stage -LeafPrefix '.FusionThreadManager-stage-'
            }
        }

        return $targetFull
    }

    function Add-BootstrapUserPath {
        param([Parameter(Mandatory = $true)][string] $Directory)

        $directoryFull = Get-BootstrapFullPath $Directory
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $entries = @([string] $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $alreadyPresent = $false
        foreach ($entry in $entries) {
            try {
                $entryFull = Get-BootstrapFullPath $entry.Trim()
                if ($entryFull.TrimEnd('\') -eq $directoryFull.TrimEnd('\')) {
                    $alreadyPresent = $true
                    break
                }
            }
            catch {
                # Preserve malformed or provider-style PATH entries without treating them as a match.
            }
        }
        if (-not $alreadyPresent) {
            $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                $directoryFull
            }
            else {
                $userPath.TrimEnd(';') + ';' + $directoryFull
            }
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
            Write-Host "Added to the user PATH: $directoryFull"
        }

        $processEntries = @([string] $env:Path -split ';')
        if (-not @($processEntries | Where-Object {
                    try { (Get-BootstrapFullPath $_).TrimEnd('\') -eq $directoryFull.TrimEnd('\') }
                    catch { $false }
                })) {
            $env:Path = ([string] $env:Path).TrimEnd(';') + ';' + $directoryFull
        }
    }

    $localArchiveProvided = -not [string]::IsNullOrWhiteSpace([string] $Options.ArchivePath)
    $localChecksumProvided = -not [string]::IsNullOrWhiteSpace([string] $Options.ChecksumPath)
    if ($localArchiveProvided -ne $localChecksumProvided) {
        throw '-ArchivePath and -ChecksumPath must be supplied together.'
    }

    $temporaryParent = Get-BootstrapFullPath ([System.IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $temporaryParent ('FusionThreadManagerBootstrap-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $downloadedArchive = Join-Path $temporaryRoot $archiveName
        $downloadedChecksum = Join-Path $temporaryRoot $checksumName
        $releaseBase = ([string] $Options.ReleaseBaseUrl).TrimEnd('/')
        Copy-BootstrapArtifact -LocalPath $Options.ArchivePath -Uri ($releaseBase + '/' + $archiveName) -Destination $downloadedArchive
        Copy-BootstrapArtifact -LocalPath $Options.ChecksumPath -Uri ($releaseBase + '/' + $checksumName) -Destination $downloadedChecksum
        Assert-BootstrapChecksum -Archive $downloadedArchive -ChecksumFile $downloadedChecksum

        $extractionRoot = Join-Path $temporaryRoot 'extracted'
        Expand-BootstrapArchiveSafely -Archive $downloadedArchive -Destination $extractionRoot
        $payloadRoot = Get-BootstrapPayloadRoot $extractionRoot
        $engine = Get-BootstrapPowerShell
        $installedRoot = Install-BootstrapPayload -PayloadRoot $payloadRoot -Target $Options.InstallRoot -Engine $engine
        Write-Host "Installed Fusion Thread Manager to: $installedRoot"

        if (-not [bool] $Options.SkipPathUpdate) {
            try {
                Add-BootstrapUserPath $installedRoot
            }
            catch {
                Write-Warning "The manager was installed, but its directory could not be added to the user PATH: $($_.Exception.Message)"
            }
        }

        if ([bool] $Options.SkipPackInstall) {
            Write-Host 'Skipped Fusion thread-pack installation. Run fusion-threads install when ready.'
            return
        }

        $cliArguments = @('install')
        $requestedPacks = @($Options.Pack | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) })
        if ($requestedPacks.Count -gt 0) {
            $cliArguments += @('-Pack', ($requestedPacks -join ','))
        }
        if (-not [string]::IsNullOrWhiteSpace([string] $Options.ThreadDataPath)) {
            $cliArguments += @('-ThreadDataPath', [string] $Options.ThreadDataPath)
        }
        if ([bool] $Options.AllInstallations) {
            $cliArguments += '-AllInstallations'
        }
        if (-not [string]::IsNullOrWhiteSpace([string] $Options.StateRoot)) {
            $cliArguments += @('-StateRoot', [string] $Options.StateRoot)
        }

        try {
            Invoke-BootstrapCli -Engine $engine -CliPath (Join-Path $installedRoot 'fusion-threads.ps1') -Arguments $cliArguments -FailureMessage 'Thread-pack installation failed'
        }
        catch {
            throw "The manager remains installed at '$installedRoot', but thread-pack installation failed. $($_.Exception.Message)"
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-BootstrapDirectory -Parent $temporaryParent -Path $temporaryRoot -LeafPrefix 'FusionThreadManagerBootstrap-'
        }
    }
} @{
    InstallRoot = $InstallRoot
    Pack = @($Pack)
    ThreadDataPath = $ThreadDataPath
    AllInstallations = [bool] $AllInstallations
    SkipPackInstall = [bool] $SkipPackInstall
    StateRoot = $StateRoot
    ArchivePath = $ArchivePath
    ChecksumPath = $ChecksumPath
    SkipPathUpdate = [bool] $SkipPathUpdate
    ReleaseBaseUrl = $ReleaseBaseUrl
}
