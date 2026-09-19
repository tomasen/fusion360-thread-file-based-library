Set-StrictMode -Version 2.0

$script:ToolName = 'Fusion Thread Manager'
$script:ToolVersion = '0.1.0'

function Write-FtmInfo {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "[info] $Message"
}

function Write-FtmWarning {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Warning $Message
}

function Get-FtmDefaultStateRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not available. Pass -StateRoot explicitly.'
    }

    return Join-Path $env:LOCALAPPDATA 'FusionThreadManager'
}

function Get-FtmFullPath {
    param([Parameter(Mandatory = $true)][string] $Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-FtmFileHash {
    param([Parameter(Mandatory = $true)][string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($stream)
        return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-FtmStringHash {
    param([Parameter(Mandatory = $true)][string] $Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $digest = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Read-FtmJson {
    param([Parameter(Mandatory = $true)][string] $Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-FtmJsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)] $Value
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $json = $Value | ConvertTo-Json -Depth 12
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, $encoding)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Copy-FtmFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    $temporary = "$Destination.$([guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $Source -Destination $temporary -Force
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

function Test-FtmChildPath {
    param(
        [Parameter(Mandatory = $true)][string] $Parent,
        [Parameter(Mandatory = $true)][string] $Child
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $parentFull = (Get-FtmFullPath $Parent).TrimEnd($separator) + $separator
    $childFull = Get-FtmFullPath (Join-Path $Parent $Child)
    return $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-FtmPathWithin {
    param(
        [Parameter(Mandatory = $true)][string] $Parent,
        [Parameter(Mandatory = $true)][string] $Candidate
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $parentFull = (Get-FtmFullPath $Parent).TrimEnd($separator) + $separator
    $candidateFull = Get-FtmFullPath $Candidate
    return $candidateFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-FtmSafeXmlDocument {
    param([Parameter(Mandatory = $true)][string] $Path)

    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    try {
        $document.Load($reader)
        return $document
    }
    finally {
        $reader.Dispose()
    }
}

function ConvertTo-FtmNumber {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Description
    )

    $value = 0.0
    $style = [System.Globalization.NumberStyles]::Float
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($Text, $style, $culture, [ref] $value)) {
        throw "$Description must be a decimal number; found '$Text'."
    }
    if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) {
        throw "$Description must be finite; found '$Text'."
    }
    return $value
}

function Test-FtmThreadXml {
    param([Parameter(Mandatory = $true)][string] $Path)

    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $document = Get-FtmSafeXmlDocument $Path
    }
    catch {
        $errors.Add("Invalid XML: $($_.Exception.Message)")
        return $errors.ToArray()
    }

    $root = $document.DocumentElement
    if ($null -eq $root -or $root.LocalName -ne 'ThreadType') {
        $errors.Add('Root element must be ThreadType.')
        return $errors.ToArray()
    }

    foreach ($nodeName in @('Name', 'CustomName', 'Unit', 'Angle')) {
        $node = $root.SelectSingleNode("./$nodeName")
        if ($null -eq $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) {
            $errors.Add("Missing required ThreadType/$nodeName value.")
        }
    }

    $unitNode = $root.SelectSingleNode('./Unit')
    if ($null -ne $unitNode -and $unitNode.InnerText -notin @('in', 'mm')) {
        $errors.Add("Unit must be 'in' or 'mm'.")
    }
    $angleNode = $root.SelectSingleNode('./Angle')
    if ($null -ne $angleNode) {
        try {
            $angle = ConvertTo-FtmNumber $angleNode.InnerText 'Angle'
            if ($angle -le 0 -or $angle -ge 180) {
                $errors.Add('Angle must be greater than 0 and less than 180 degrees.')
            }
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
    }

    foreach ($threadSize in @($root.SelectNodes('./ThreadSize'))) {
        $sizeNode = $threadSize.SelectSingleNode('./Size')
        if ($null -eq $sizeNode) {
            $errors.Add('Each ThreadSize requires Size.')
        }
        else {
            try {
                if ((ConvertTo-FtmNumber $sizeNode.InnerText 'ThreadSize/Size') -le 0) {
                    $errors.Add('ThreadSize/Size must be greater than zero.')
                }
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }

    $designations = @($root.SelectNodes('./ThreadSize/Designation'))
    if ($designations.Count -eq 0) {
        $errors.Add('At least one ThreadSize/Designation is required.')
        return $errors.ToArray()
    }

    foreach ($designation in $designations) {
        $labelNode = $designation.SelectSingleNode('./ThreadDesignation')
        $label = if ($null -ne $labelNode) { $labelNode.InnerText } else { '<unnamed>' }
        $tpiNode = $designation.SelectSingleNode('./TPI')
        $pitchNode = $designation.SelectSingleNode('./Pitch')
        foreach ($requiredDesignationNode in @('ThreadDesignation', 'CTD')) {
            $requiredNode = $designation.SelectSingleNode("./$requiredDesignationNode")
            if ($null -eq $requiredNode -or [string]::IsNullOrWhiteSpace($requiredNode.InnerText)) {
                $errors.Add("Designation '$label' requires $requiredDesignationNode.")
            }
        }
        if ($null -eq $tpiNode -and $null -eq $pitchNode) {
            $errors.Add("Designation '$label' requires TPI or Pitch.")
        }
        elseif ($null -ne $tpiNode -and $null -ne $pitchNode) {
            $errors.Add("Designation '$label' must use either TPI or Pitch, not both.")
        }
        else {
            try {
                $pitchValue = if ($null -ne $tpiNode) {
                    ConvertTo-FtmNumber $tpiNode.InnerText "TPI for '$label'"
                }
                else {
                    ConvertTo-FtmNumber $pitchNode.InnerText "Pitch for '$label'"
                }
                if ($pitchValue -le 0) {
                    $errors.Add("TPI/Pitch for '$label' must be greater than zero.")
                }
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }

        $threads = @($designation.SelectNodes('./Thread'))
        if ($threads.Count -eq 0) {
            $errors.Add("Designation '$label' requires at least one Thread block.")
            continue
        }

        foreach ($thread in $threads) {
            $genderNode = $thread.SelectSingleNode('./Gender')
            $gender = if ($null -ne $genderNode) { $genderNode.InnerText.ToLowerInvariant() } else { '' }
            if ($gender -notin @('external', 'internal')) {
                $errors.Add("Designation '$label' has invalid or missing Gender '$gender'.")
            }
            $classNode = $thread.SelectSingleNode('./Class')
            if ($null -eq $classNode -or [string]::IsNullOrWhiteSpace($classNode.InnerText)) {
                $errors.Add("Designation '$label'/$gender requires Class.")
            }

            try {
                $majorNode = $thread.SelectSingleNode('./MajorDia')
                $pitchDiameterNode = $thread.SelectSingleNode('./PitchDia')
                $minorNode = $thread.SelectSingleNode('./MinorDia')
                if ($null -eq $majorNode -or $null -eq $pitchDiameterNode -or $null -eq $minorNode) {
                    throw "Designation '$label'/$gender requires MajorDia, PitchDia, and MinorDia."
                }

                $major = ConvertTo-FtmNumber $majorNode.InnerText "MajorDia for '$label'/$gender"
                $pitchDiameter = ConvertTo-FtmNumber $pitchDiameterNode.InnerText "PitchDia for '$label'/$gender"
                $minor = ConvertTo-FtmNumber $minorNode.InnerText "MinorDia for '$label'/$gender"
                if ($major -lt $pitchDiameter -or $pitchDiameter -lt $minor -or $minor -le 0) {
                    $errors.Add("Diameter order for '$label'/$gender must be MajorDia >= PitchDia >= MinorDia > 0.")
                }
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }

    return $errors.ToArray()
}

function Get-FtmPackDefinitions {
    param([Parameter(Mandatory = $true)][string] $RepositoryRoot)

    $packsRoot = Join-Path $RepositoryRoot 'packs'
    if (-not (Test-Path -LiteralPath $packsRoot -PathType Container)) {
        throw "Pack folder not found: $packsRoot"
    }

    $manifestFiles = @(Get-ChildItem -LiteralPath $packsRoot -Filter 'pack.json' -File -Recurse)
    if ($manifestFiles.Count -eq 0) {
        throw "No pack.json manifests were found under $packsRoot"
    }

    $seenIds = @{}
    $seenNames = @{}
    $seenDestinations = @{}
    $packs = New-Object System.Collections.Generic.List[object]

    foreach ($manifestFile in $manifestFiles) {
        $manifest = Read-FtmJson $manifestFile.FullName
        $errors = New-Object System.Collections.Generic.List[string]

        if ($manifest.schemaVersion -ne 1) {
            $errors.Add('schemaVersion must be 1.')
        }
        if ([string]::IsNullOrWhiteSpace([string] $manifest.id) -or
            ([string] $manifest.id) -notmatch '^[a-z0-9][a-z0-9.-]*$') {
            $errors.Add('id must contain lowercase letters, digits, dots, or hyphens.')
        }
        if ([string]::IsNullOrWhiteSpace([string] $manifest.name)) {
            $errors.Add('name is required.')
        }
        if (([string] $manifest.version) -notmatch '^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$') {
            $errors.Add('version must use semantic major.minor.patch form.')
        }
        $compatibilityProperty = $manifest.PSObject.Properties['fusionCompatibility']
        if ($null -ne $compatibilityProperty) {
            $compatibility = $compatibilityProperty.Value
            $formatProperty = $compatibility.PSObject.Properties['format']
            if ($null -eq $formatProperty -or [string]::IsNullOrWhiteSpace([string] $formatProperty.Value)) {
                $errors.Add('fusionCompatibility.format is required when fusionCompatibility is present.')
            }
            $testedProperty = $compatibility.PSObject.Properties['testedProductVersions']
            if ($null -eq $testedProperty -or @($testedProperty.Value).Count -eq 0) {
                $errors.Add('fusionCompatibility.testedProductVersions requires at least one version.')
            }
            else {
                foreach ($testedVersion in @($testedProperty.Value)) {
                    if ([string]::IsNullOrWhiteSpace([string] $testedVersion)) {
                        $errors.Add('fusionCompatibility.testedProductVersions cannot contain an empty value.')
                    }
                }
            }
        }
        if ($seenIds.ContainsKey([string] $manifest.id)) {
            $errors.Add("Duplicate pack id '$($manifest.id)'.")
        }
        else {
            $seenIds[[string] $manifest.id] = $manifestFile.FullName
        }

        $fileEntries = @($manifest.files)
        if ($fileEntries.Count -eq 0) {
            $errors.Add('files must contain at least one entry.')
        }

        $resolvedFiles = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $fileEntries) {
            $sourceRelative = [string] $entry.source
            $destinationName = [string] $entry.destination
            if ([string]::IsNullOrWhiteSpace($sourceRelative)) {
                $errors.Add('Each file entry requires source.')
                continue
            }
            if (-not (Test-FtmChildPath $manifestFile.DirectoryName $sourceRelative)) {
                $errors.Add("Source escapes the pack folder: $sourceRelative")
                continue
            }

            $sourceFull = Get-FtmFullPath (Join-Path $manifestFile.DirectoryName $sourceRelative)
            if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) {
                $errors.Add("Source file does not exist: $sourceRelative")
                continue
            }
            $declaredHash = ([string] $entry.sha256).ToLowerInvariant()
            if ($declaredHash -notmatch '^[0-9a-f]{64}$') {
                $errors.Add("File '$sourceRelative' requires a lowercase SHA-256 value.")
            }
            else {
                $actualHash = Get-FtmFileHash $sourceFull
                if ($declaredHash -ne $actualHash) {
                    $errors.Add("SHA-256 mismatch for '$sourceRelative'. Expected $declaredHash; found $actualHash.")
                }
            }
            if ([string]::IsNullOrWhiteSpace($destinationName) -or
                [System.IO.Path]::GetFileName($destinationName) -ne $destinationName -or
                [System.IO.Path]::GetExtension($destinationName).ToLowerInvariant() -ne '.xml') {
                $errors.Add("Destination must be a plain .xml filename: $destinationName")
                continue
            }
            if ($seenDestinations.ContainsKey($destinationName.ToLowerInvariant())) {
                $errors.Add("Destination '$destinationName' is also owned by another pack.")
            }
            else {
                $seenDestinations[$destinationName.ToLowerInvariant()] = [string] $manifest.id
            }

            $xmlErrors = @(Test-FtmThreadXml $sourceFull)
            foreach ($xmlError in $xmlErrors) {
                $errors.Add("${sourceRelative}: $xmlError")
            }

            try {
                $xmlDocument = Get-FtmSafeXmlDocument $sourceFull
                $threadName = $xmlDocument.DocumentElement.SelectSingleNode('./Name').InnerText
                $customName = $xmlDocument.DocumentElement.SelectSingleNode('./CustomName').InnerText
                foreach ($name in @($threadName, $customName)) {
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $key = $name.ToLowerInvariant()
                        if ($seenNames.ContainsKey($key) -and $seenNames[$key] -ne $sourceFull) {
                            $errors.Add("Thread Name/CustomName '$name' is duplicated in another XML file.")
                        }
                        else {
                            $seenNames[$key] = $sourceFull
                        }
                    }
                }
            }
            catch {
                # The XML parser error is already reported above.
            }

            $resolvedFiles.Add([pscustomobject]@{
                SourceRelative = $sourceRelative
                SourceFull = $sourceFull
                DestinationName = $destinationName
            })
        }

        $packs.Add([pscustomobject]@{
            Id = [string] $manifest.id
            Name = [string] $manifest.name
            Version = [string] $manifest.version
            Region = [string] $manifest.region
            Standard = [string] $manifest.standard
            Manifest = $manifest
            ManifestPath = $manifestFile.FullName
            Files = $resolvedFiles.ToArray()
            ValidationErrors = $errors.ToArray()
        })
    }

    return @($packs.ToArray() | Sort-Object Id)
}

function Assert-FtmPacksValid {
    param([Parameter(Mandatory = $true)][object[]] $Packs)

    $messages = New-Object System.Collections.Generic.List[string]
    foreach ($pack in $Packs) {
        foreach ($errorMessage in @($pack.ValidationErrors)) {
            $messages.Add("$($pack.ManifestPath): $errorMessage")
        }
    }
    if ($messages.Count -gt 0) {
        throw "Pack validation failed:`n - $($messages -join "`n - ")"
    }
}

function Resolve-FtmPacks {
    param(
        [Parameter(Mandatory = $true)][object[]] $AllPacks,
        [string[]] $RequestedIds
    )

    $expandedIds = @($RequestedIds | ForEach-Object { @([string] $_ -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($expandedIds.Count -eq 0 -or $expandedIds -contains 'all') {
        return @($AllPacks)
    }

    $selected = New-Object System.Collections.Generic.List[object]
    $seenRequested = @{}
    foreach ($requestedId in $expandedIds) {
        $requestedKey = $requestedId.ToLowerInvariant()
        if ($seenRequested.ContainsKey($requestedKey)) {
            throw "Pack '$requestedId' was selected more than once."
        }
        $seenRequested[$requestedKey] = $true
        $match = @($AllPacks | Where-Object { $_.Id -eq $requestedId })
        if ($match.Count -eq 0) {
            $available = ($AllPacks | ForEach-Object { $_.Id }) -join ', '
            throw "Unknown pack '$requestedId'. Available packs: $available"
        }
        $selected.Add($match[0])
    }
    return $selected.ToArray()
}

function Get-FtmFusionCandidateFromExecutable {
    param(
        [Parameter(Mandatory = $true)][string] $ExecutablePath,
        [bool] $IsRunning
    )

    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        return $null
    }

    $root = Split-Path -Parent $ExecutablePath
    $threadData = Join-Path $root 'Fusion\Server\Fusion\Configuration\ThreadData'
    if (-not (Test-Path -LiteralPath $threadData -PathType Container)) {
        return $null
    }

    $file = Get-Item -LiteralPath $ExecutablePath
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath)
    $productVersion = [string] $versionInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($productVersion)) {
        $productVersion = [string] $versionInfo.FileVersion
    }
    $versionSort = [version] '0.0'
    $versionMatch = [regex]::Match($productVersion, '\d+(?:\.\d+){1,3}')
    if ($versionMatch.Success) {
        try {
            $versionSort = [version] $versionMatch.Value
        }
        catch {
            $versionSort = [version] '0.0'
        }
    }

    $normalizedThreadData = Get-FtmFullPath $threadData
    return [pscustomobject]@{
        Id = (Get-FtmStringHash $normalizedThreadData.ToLowerInvariant()).Substring(0, 16)
        Kind = 'fusion'
        Root = Get-FtmFullPath $root
        ExecutablePath = Get-FtmFullPath $ExecutablePath
        ThreadDataPath = $normalizedThreadData
        ProductVersion = $productVersion
        VersionSort = $versionSort
        ExecutableLastWriteUtc = $file.LastWriteTimeUtc
        IsRunning = $IsRunning
    }
}

function Get-FtmFusionInstallations {
    param(
        [string] $ThreadDataPath,
        [switch] $AllInstallations
    )

    if (-not [string]::IsNullOrWhiteSpace($ThreadDataPath)) {
        $full = Get-FtmFullPath $ThreadDataPath
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            throw "ThreadData override does not exist: $full"
        }
        return @([pscustomobject]@{
            Id = (Get-FtmStringHash $full.ToLowerInvariant()).Substring(0, 16)
            Kind = 'override'
            Root = Split-Path -Parent $full
            ExecutablePath = $null
            ThreadDataPath = $full
            ProductVersion = 'unknown (path override)'
            VersionSort = [version] '0.0'
            ExecutableLastWriteUtc = [datetime]::MinValue
            IsRunning = $false
        })
    }

    $runningPaths = @{}
    try {
        foreach ($process in @(Get-Process -Name 'Fusion360' -ErrorAction SilentlyContinue)) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($process.Path)) {
                    $runningPaths[(Get-FtmFullPath $process.Path).ToLowerInvariant()] = $true
                }
            }
            catch {
                # A protected process path should not prevent filesystem discovery.
            }
        }
    }
    catch {
        # Process discovery is an optimization, not a requirement.
    }

    $executables = @{}
    foreach ($runningPath in $runningPaths.Keys) {
        $executables[$runningPath] = $runningPath
    }

    $productionRoots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $productionRoots.Add((Join-Path $env:LOCALAPPDATA 'Autodesk\webdeploy\production'))
        $productionRoots.Add((Join-Path $env:LOCALAPPDATA 'Autodesk\Autodesk Fusion 360\webdeploy\production'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $productionRoots.Add((Join-Path $env:ProgramFiles 'Autodesk\webdeploy\production'))
    }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $productionRoots.Add((Join-Path $programFilesX86 'Autodesk\webdeploy\production'))
    }

    foreach ($productionRoot in @($productionRoots.ToArray() | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $productionRoot -PathType Container)) {
            continue
        }
        foreach ($versionDirectory in @(Get-ChildItem -LiteralPath $productionRoot -Directory -ErrorAction SilentlyContinue)) {
            $executable = Join-Path $versionDirectory.FullName 'Fusion360.exe'
            if (Test-Path -LiteralPath $executable -PathType Leaf) {
                $fullExecutable = Get-FtmFullPath $executable
                $executables[$fullExecutable.ToLowerInvariant()] = $fullExecutable
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($executableKey in $executables.Keys) {
        $executablePath = [string] $executables[$executableKey]
        $candidate = Get-FtmFusionCandidateFromExecutable $executablePath $runningPaths.ContainsKey($executableKey)
        if ($null -ne $candidate) {
            $candidates.Add($candidate)
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No valid Fusion installation was found. Expected Fusion360.exe and Fusion\Server\Fusion\Configuration\ThreadData under %LOCALAPPDATA%\Autodesk\webdeploy\production (or a lab installation under Program Files). Install Fusion first, or pass -ThreadDataPath explicitly."
    }

    $sorted = @($candidates.ToArray() | Sort-Object `
        @{ Expression = { $_.IsRunning }; Descending = $true }, `
        @{ Expression = { $_.VersionSort }; Descending = $true }, `
        @{ Expression = { $_.ExecutableLastWriteUtc }; Descending = $true })

    if ($AllInstallations) {
        return $sorted
    }
    return @($sorted[0])
}

function Get-FtmReceiptPath {
    param(
        [Parameter(Mandatory = $true)][string] $StateRoot,
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack
    )

    return Join-Path $StateRoot ("receipts\{0}\{1}.json" -f $Target.Id, $Pack.Id)
}

function Get-FtmRequiredProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Missing required property '$Name'."
    }
    return $property.Value
}

function Assert-FtmReceiptValid {
    param(
        [Parameter(Mandatory = $true)] $Receipt,
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack,
        [Parameter(Mandatory = $true)][string] $StateRoot
    )

    try {
        if ((Get-FtmRequiredProperty $Receipt 'schemaVersion') -ne 1) {
            throw 'schemaVersion must be 1.'
        }
        if ([string] (Get-FtmRequiredProperty $Receipt 'targetId') -ne $Target.Id) {
            throw 'targetId does not match the selected Fusion deployment.'
        }
        if ([string] (Get-FtmRequiredProperty $Receipt 'packId') -ne $Pack.Id) {
            throw 'packId does not match the selected pack.'
        }
        $receiptTarget = Get-FtmFullPath ([string] (Get-FtmRequiredProperty $Receipt 'threadDataPath'))
        if (-not $receiptTarget.Equals((Get-FtmFullPath $Target.ThreadDataPath), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'threadDataPath does not match the selected Fusion deployment.'
        }

        $receiptFiles = @((Get-FtmRequiredProperty $Receipt 'files'))
        foreach ($entry in $receiptFiles) {
            $destinationName = [string] (Get-FtmRequiredProperty $entry 'destinationName')
            if ([System.IO.Path]::GetFileName($destinationName) -ne $destinationName -or
                [System.IO.Path]::GetExtension($destinationName).ToLowerInvariant() -ne '.xml') {
                throw "Unsafe destinationName '$destinationName'."
            }
            $installedHash = [string] (Get-FtmRequiredProperty $entry 'installedSha256')
            if ($installedHash -notmatch '^[0-9a-f]{64}$') {
                throw "Invalid installedSha256 for '$destinationName'."
            }

            $originalProperty = $entry.PSObject.Properties['originalBackup']
            $originalBackup = if ($null -ne $originalProperty) { [string] $originalProperty.Value } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($originalBackup)) {
                if (-not (Test-FtmPathWithin $StateRoot $originalBackup)) {
                    throw "Original backup for '$destinationName' is outside StateRoot."
                }
                $originalHashProperty = $entry.PSObject.Properties['originalBackupSha256']
                if ($null -eq $originalHashProperty -or ([string] $originalHashProperty.Value) -notmatch '^[0-9a-f]{64}$') {
                    throw "Missing or invalid originalBackupSha256 for '$destinationName'."
                }
                if (-not (Test-Path -LiteralPath $originalBackup -PathType Leaf)) {
                    throw "Required original backup is missing for '$destinationName': $originalBackup"
                }
                $actualOriginalHash = Get-FtmFileHash $originalBackup
                if ($actualOriginalHash -ne [string] $originalHashProperty.Value) {
                    throw "Required original backup hash mismatch for '$destinationName'."
                }
            }

            $lastBackupProperty = $entry.PSObject.Properties['lastBackup']
            if ($null -ne $lastBackupProperty -and
                -not [string]::IsNullOrWhiteSpace([string] $lastBackupProperty.Value) -and
                -not (Test-FtmPathWithin $StateRoot ([string] $lastBackupProperty.Value))) {
                throw "lastBackup for '$destinationName' is outside StateRoot."
            }
        }
    }
    catch {
        throw "Invalid or unsafe receipt '$Path': $($_.Exception.Message)"
    }
}

function Read-FtmReceipt {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack,
        [Parameter(Mandatory = $true)][string] $StateRoot
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $receipt = Read-FtmJson $Path
    }
    catch {
        throw "Invalid receipt JSON '$Path': $($_.Exception.Message)"
    }
    Assert-FtmReceiptValid $receipt $Path $Target $Pack $StateRoot
    return $receipt
}

function Get-FtmPriorFileEntry {
    param(
        $Receipt,
        [Parameter(Mandatory = $true)][string] $DestinationName
    )

    if ($null -eq $Receipt) {
        return $null
    }
    return @($Receipt.files | Where-Object { $_.destinationName -eq $DestinationName } | Select-Object -First 1)[0]
}

function New-FtmInstallPlan {
    param(
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack,
        [Parameter(Mandatory = $true)][string] $StateRoot
    )

    $receiptPath = Get-FtmReceiptPath $StateRoot $Target $Pack
    $receipt = Read-FtmReceipt $receiptPath $Target $Pack $StateRoot
    $items = New-Object System.Collections.Generic.List[object]
    $currentDestinations = @{}
    $staleItems = New-Object System.Collections.Generic.List[object]

    foreach ($file in @($Pack.Files)) {
        $currentDestinations[$file.DestinationName.ToLowerInvariant()] = $true
        $destination = Join-Path $Target.ThreadDataPath $file.DestinationName
        $sourceHash = Get-FtmFileHash $file.SourceFull
        $exists = Test-Path -LiteralPath $destination -PathType Leaf
        $existingHash = if ($exists) { Get-FtmFileHash $destination } else { $null }
        $priorEntry = Get-FtmPriorFileEntry $receipt $file.DestinationName

        if (-not $exists) {
            $action = 'Add'
        }
        elseif ($existingHash -eq $sourceHash -and $null -ne $priorEntry) {
            $action = 'NoChange'
        }
        elseif ($existingHash -eq $sourceHash) {
            $action = 'IdenticalUnmanaged'
        }
        elseif ($null -ne $priorEntry -and $existingHash -eq [string] $priorEntry.installedSha256) {
            $action = 'UpdateManaged'
        }
        elseif ($null -ne $priorEntry) {
            $action = 'ConflictModified'
        }
        else {
            $action = 'ConflictUnmanaged'
        }

        $items.Add([pscustomobject]@{
            SourceFull = $file.SourceFull
            SourceRelative = $file.SourceRelative
            SourceHash = $sourceHash
            DestinationName = $file.DestinationName
            Destination = $destination
            ExistingHash = $existingHash
            Action = $action
            PriorEntry = $priorEntry
        })
    }

    if ($null -ne $receipt) {
        foreach ($priorEntry in @($receipt.files)) {
            $destinationName = [string] $priorEntry.destinationName
            if ($currentDestinations.ContainsKey($destinationName.ToLowerInvariant())) {
                continue
            }
            $destination = Join-Path $Target.ThreadDataPath $destinationName
            $exists = Test-Path -LiteralPath $destination -PathType Leaf
            $existingHash = if ($exists) { Get-FtmFileHash $destination } else { $null }
            if (-not $exists) {
                $action = 'StaleMissing'
            }
            elseif ($existingHash -eq [string] $priorEntry.installedSha256) {
                $action = 'RemoveStaleManaged'
            }
            else {
                $action = 'ConflictModifiedStale'
            }
            $staleItems.Add([pscustomobject]@{
                DestinationName = $destinationName
                Destination = $destination
                ExistingHash = $existingHash
                Action = $action
                PriorEntry = $priorEntry
            })
        }
    }

    return [pscustomobject]@{
        Target = $Target
        Pack = $Pack
        Receipt = $receipt
        ReceiptPath = $receiptPath
        Items = $items.ToArray()
        StaleItems = $staleItems.ToArray()
    }
}

function Assert-FtmPlannedFileState {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        $ExpectedHash
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    if ([string]::IsNullOrWhiteSpace([string] $ExpectedHash)) {
        if ($exists) {
            throw "Destination changed after planning (a file appeared): $Path"
        }
        return
    }
    if (-not $exists) {
        throw "Destination changed after planning (file is missing): $Path"
    }
    $actualHash = Get-FtmFileHash $Path
    if ($actualHash -ne [string] $ExpectedHash) {
        throw "Destination changed after planning (hash mismatch): $Path"
    }
}

function Get-FtmBackupPath {
    param(
        [Parameter(Mandatory = $true)][string] $StateRoot,
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack,
        [Parameter(Mandatory = $true)][string] $DestinationName,
        [Parameter(Mandatory = $true)][string] $OperationStamp
    )

    $backupDirectory = Join-Path $StateRoot ("backups\{0}\{1}\{2}" -f $Target.Id, $Pack.Id, $OperationStamp)
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }
    return Join-Path $backupDirectory $DestinationName
}

function Invoke-FtmInstallPlan {
    param(
        [Parameter(Mandatory = $true)] $Plan,
        [Parameter(Mandatory = $true)][string] $StateRoot,
        [switch] $DryRun
    )

    $target = $Plan.Target
    $pack = $Plan.Pack
    $operationStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $verbs = @{}

    foreach ($item in @($Plan.Items)) {
        $verbs[$item.DestinationName.ToLowerInvariant()] = switch ($item.Action) {
            'Add' { 'install' }
            'NoChange' { 'keep identical' }
            'IdenticalUnmanaged' { 'adopt identical pre-existing' }
            'UpdateManaged' { 'update' }
            'ConflictModified' { 'replace locally modified' }
            'ConflictUnmanaged' { 'replace unmanaged' }
        }
    }

    if ($DryRun) {
        foreach ($item in @($Plan.Items)) {
            Write-Host "[dry-run] $($verbs[$item.DestinationName.ToLowerInvariant()]) $($item.Destination)"
        }
        foreach ($staleItem in @($Plan.StaleItems)) {
            Write-Host "[dry-run] remove obsolete managed file $($staleItem.Destination)"
        }
        return
    }

    $allNoChange = @($Plan.Items | Where-Object { $_.Action -ne 'NoChange' }).Count -eq 0
    $samePackVersion = $null -ne $Plan.Receipt -and [string] $Plan.Receipt.packVersion -eq $pack.Version
    if ($allNoChange -and @($Plan.StaleItems).Count -eq 0 -and $samePackVersion) {
        foreach ($item in @($Plan.Items)) {
            Write-FtmInfo "$($pack.Id): keep identical '$($item.DestinationName)'"
        }
        return
    }

    foreach ($item in @($Plan.Items)) {
        Assert-FtmPlannedFileState $item.Destination $item.ExistingHash
    }
    foreach ($staleItem in @($Plan.StaleItems)) {
        Assert-FtmPlannedFileState $staleItem.Destination $staleItem.ExistingHash
    }

    $operationBackups = @{}
    foreach ($item in @($Plan.Items)) {
        if ($item.Action -ne 'NoChange' -and -not [string]::IsNullOrWhiteSpace([string] $item.ExistingHash)) {
            $backup = Get-FtmBackupPath $StateRoot $target $pack $item.DestinationName $operationStamp
            Copy-Item -LiteralPath $item.Destination -Destination $backup -Force
            if ((Get-FtmFileHash $backup) -ne $item.ExistingHash) {
                throw "Backup verification failed for '$($item.Destination)'."
            }
            $operationBackups[$item.Destination.ToLowerInvariant()] = $backup
        }
    }
    foreach ($staleItem in @($Plan.StaleItems)) {
        if (-not [string]::IsNullOrWhiteSpace([string] $staleItem.ExistingHash)) {
            $backup = Get-FtmBackupPath $StateRoot $target $pack $staleItem.DestinationName $operationStamp
            Copy-Item -LiteralPath $staleItem.Destination -Destination $backup -Force
            if ((Get-FtmFileHash $backup) -ne $staleItem.ExistingHash) {
                throw "Backup verification failed for '$($staleItem.Destination)'."
            }
            $operationBackups[$staleItem.Destination.ToLowerInvariant()] = $backup
        }
    }

    $rollbackEntries = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Plan.Items | Where-Object { $_.Action -notin @('NoChange', 'IdenticalUnmanaged') })) {
        $rollbackEntries.Add([pscustomobject]@{
            Destination = $item.Destination
            Existed = -not [string]::IsNullOrWhiteSpace([string] $item.ExistingHash)
            Backup = $operationBackups[$item.Destination.ToLowerInvariant()]
        })
    }
    foreach ($staleItem in @($Plan.StaleItems)) {
        $rollbackEntries.Add([pscustomobject]@{
            Destination = $staleItem.Destination
            Existed = -not [string]::IsNullOrWhiteSpace([string] $staleItem.ExistingHash)
            Backup = $operationBackups[$staleItem.Destination.ToLowerInvariant()]
        })
    }

    try {
        $receiptFiles = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($Plan.Items)) {
            $originalBackup = $null
            $originalBackupHash = $null
            $lastBackup = $null
            if ($null -ne $item.PriorEntry) {
                if ($null -ne $item.PriorEntry.PSObject.Properties['originalBackup'] -and
                    -not [string]::IsNullOrWhiteSpace([string] $item.PriorEntry.originalBackup)) {
                    $originalBackup = [string] $item.PriorEntry.originalBackup
                    $originalBackupHash = [string] $item.PriorEntry.originalBackupSha256
                }
                if ($null -ne $item.PriorEntry.PSObject.Properties['lastBackup'] -and
                    -not [string]::IsNullOrWhiteSpace([string] $item.PriorEntry.lastBackup)) {
                    $lastBackup = [string] $item.PriorEntry.lastBackup
                }
            }

            $backupKey = $item.Destination.ToLowerInvariant()
            if ($operationBackups.ContainsKey($backupKey)) {
                $lastBackup = [string] $operationBackups[$backupKey]
                if ($item.Action -in @('ConflictUnmanaged', 'IdenticalUnmanaged') -and [string]::IsNullOrWhiteSpace($originalBackup)) {
                    $originalBackup = $lastBackup
                    $originalBackupHash = $item.ExistingHash
                }
            }

            if ($item.Action -notin @('NoChange', 'IdenticalUnmanaged')) {
                Assert-FtmPlannedFileState $item.Destination $item.ExistingHash
                Copy-FtmFileAtomic $item.SourceFull $item.Destination
                if ((Get-FtmFileHash $item.Destination) -ne $item.SourceHash) {
                    throw "Installed-file verification failed for '$($item.Destination)'."
                }
            }
            else {
                Assert-FtmPlannedFileState $item.Destination $item.ExistingHash
            }

            $receiptFiles.Add([pscustomobject]@{
                source = $item.SourceRelative
                destinationName = $item.DestinationName
                installedSha256 = $item.SourceHash
                originalBackup = $originalBackup
                originalBackupSha256 = $originalBackupHash
                lastBackup = $lastBackup
            })
            Write-FtmInfo "$($pack.Id): $($verbs[$item.DestinationName.ToLowerInvariant()]) '$($item.DestinationName)'"
        }

        foreach ($staleItem in @($Plan.StaleItems)) {
            Assert-FtmPlannedFileState $staleItem.Destination $staleItem.ExistingHash
            if (Test-Path -LiteralPath $staleItem.Destination -PathType Leaf) {
                Remove-Item -LiteralPath $staleItem.Destination -Force
            }
            $originalBackup = [string] $staleItem.PriorEntry.originalBackup
            if (-not [string]::IsNullOrWhiteSpace($originalBackup)) {
                Copy-FtmFileAtomic $originalBackup $staleItem.Destination
                Write-FtmInfo "$($pack.Id): removed obsolete file and restored pre-existing '$($staleItem.DestinationName)'"
            }
            else {
                Write-FtmInfo "$($pack.Id): removed obsolete managed '$($staleItem.DestinationName)'"
            }
        }

        $receipt = [pscustomobject]@{
            schemaVersion = 1
            toolVersion = $script:ToolVersion
            packId = $pack.Id
            packVersion = $pack.Version
            installedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            targetId = $target.Id
            threadDataPath = $target.ThreadDataPath
            fusionExecutable = $target.ExecutablePath
            fusionProductVersion = $target.ProductVersion
            files = $receiptFiles.ToArray()
        }
        Write-FtmJsonAtomic $Plan.ReceiptPath $receipt
    }
    catch {
        $originalError = $_
        $entries = $rollbackEntries.ToArray()
        for ($index = $entries.Count - 1; $index -ge 0; $index--) {
            $rollback = $entries[$index]
            try {
                if ($rollback.Existed) {
                    Copy-FtmFileAtomic $rollback.Backup $rollback.Destination
                }
                elseif (Test-Path -LiteralPath $rollback.Destination -PathType Leaf) {
                    Remove-Item -LiteralPath $rollback.Destination -Force
                }
            }
            catch {
                Write-FtmWarning "Rollback failed for '$($rollback.Destination)': $($_.Exception.Message)"
            }
        }
        throw $originalError
    }
}

function New-FtmUninstallPlan {
    param(
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)] $Pack,
        [Parameter(Mandatory = $true)][string] $StateRoot
    )

    $receiptPath = Get-FtmReceiptPath $StateRoot $Target $Pack
    $receipt = Read-FtmReceipt $receiptPath $Target $Pack $StateRoot
    if ($null -eq $receipt) {
        return [pscustomobject]@{
            Target = $Target
            Pack = $Pack
            Receipt = $null
            ReceiptPath = $receiptPath
            Items = @()
        }
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($receipt.files)) {
        $destinationName = [string] $entry.destinationName
        if ([System.IO.Path]::GetFileName($destinationName) -ne $destinationName) {
            throw "Unsafe destination in receipt '$receiptPath': $destinationName"
        }
        $destination = Join-Path $Target.ThreadDataPath $destinationName
        $exists = Test-Path -LiteralPath $destination -PathType Leaf
        $currentHash = if ($exists) { Get-FtmFileHash $destination } else { $null }
        if (-not $exists) {
            $action = 'AlreadyMissing'
        }
        elseif ($currentHash -eq [string] $entry.installedSha256) {
            $action = 'RemoveManaged'
        }
        else {
            $action = 'ConflictModified'
        }
        $items.Add([pscustomobject]@{
            DestinationName = $destinationName
            Destination = $destination
            CurrentHash = $currentHash
            Action = $action
            ReceiptEntry = $entry
        })
    }

    return [pscustomobject]@{
        Target = $Target
        Pack = $Pack
        Receipt = $receipt
        ReceiptPath = $receiptPath
        Items = $items.ToArray()
    }
}

function Invoke-FtmUninstallPlan {
    param(
        [Parameter(Mandatory = $true)] $Plan,
        [Parameter(Mandatory = $true)][string] $StateRoot,
        [switch] $DryRun
    )

    if ($null -eq $Plan.Receipt) {
        Write-FtmInfo "$($Plan.Pack.Id): not managed in '$($Plan.Target.ThreadDataPath)'"
        return
    }

    $operationStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-uninstall-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    if ($DryRun) {
        foreach ($item in @($Plan.Items)) {
            $originalBackup = [string] $item.ReceiptEntry.originalBackup
            $actionText = if (-not [string]::IsNullOrWhiteSpace($originalBackup)) { 'remove and restore original' } else { 'remove' }
            Write-Host "[dry-run] $actionText $($item.Destination)"
        }
        return
    }

    foreach ($item in @($Plan.Items)) {
        Assert-FtmPlannedFileState $item.Destination $item.CurrentHash
    }

    $operationBackups = @{}
    foreach ($item in @($Plan.Items)) {
        if (-not [string]::IsNullOrWhiteSpace([string] $item.CurrentHash)) {
            $backup = Get-FtmBackupPath $StateRoot $Plan.Target $Plan.Pack $item.DestinationName $operationStamp
            Copy-Item -LiteralPath $item.Destination -Destination $backup -Force
            if ((Get-FtmFileHash $backup) -ne $item.CurrentHash) {
                throw "Backup verification failed for '$($item.Destination)'."
            }
            $operationBackups[$item.Destination.ToLowerInvariant()] = $backup
        }
    }

    $rollbackEntries = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Plan.Items)) {
        $originalBackup = [string] $item.ReceiptEntry.originalBackup
        if (-not [string]::IsNullOrWhiteSpace([string] $item.CurrentHash) -or
            -not [string]::IsNullOrWhiteSpace($originalBackup)) {
            $rollbackEntries.Add([pscustomobject]@{
                Destination = $item.Destination
                Existed = -not [string]::IsNullOrWhiteSpace([string] $item.CurrentHash)
                Backup = $operationBackups[$item.Destination.ToLowerInvariant()]
            })
        }
    }

    try {
        foreach ($item in @($Plan.Items)) {
            Assert-FtmPlannedFileState $item.Destination $item.CurrentHash
            $originalBackup = [string] $item.ReceiptEntry.originalBackup

            if ($item.Action -eq 'ConflictModified' -and -not [string]::IsNullOrWhiteSpace([string] $item.CurrentHash)) {
                Write-FtmWarning "Backed up locally modified file before forced uninstall: $($operationBackups[$item.Destination.ToLowerInvariant()])"
            }
            if (Test-Path -LiteralPath $item.Destination -PathType Leaf) {
                Remove-Item -LiteralPath $item.Destination -Force
            }
            if (-not [string]::IsNullOrWhiteSpace($originalBackup)) {
                Copy-FtmFileAtomic $originalBackup $item.Destination
                if ((Get-FtmFileHash $item.Destination) -ne [string] $item.ReceiptEntry.originalBackupSha256) {
                    throw "Restored-file verification failed for '$($item.Destination)'."
                }
                Write-FtmInfo "$($Plan.Pack.Id): restored pre-existing '$($item.DestinationName)'"
            }
            else {
                Write-FtmInfo "$($Plan.Pack.Id): removed '$($item.DestinationName)'"
            }
        }

        if (Test-Path -LiteralPath $Plan.ReceiptPath -PathType Leaf) {
            Remove-Item -LiteralPath $Plan.ReceiptPath -Force
        }
    }
    catch {
        $originalError = $_
        $entries = $rollbackEntries.ToArray()
        for ($index = $entries.Count - 1; $index -ge 0; $index--) {
            $rollback = $entries[$index]
            try {
                if ($rollback.Existed) {
                    Copy-FtmFileAtomic $rollback.Backup $rollback.Destination
                }
                elseif (Test-Path -LiteralPath $rollback.Destination -PathType Leaf) {
                    Remove-Item -LiteralPath $rollback.Destination -Force
                }
            }
            catch {
                Write-FtmWarning "Rollback failed for '$($rollback.Destination)': $($_.Exception.Message)"
            }
        }
        throw $originalError
    }
}

function Show-FtmStatus {
    param(
        [Parameter(Mandatory = $true)][object[]] $Targets,
        [Parameter(Mandatory = $true)][object[]] $Packs,
        [Parameter(Mandatory = $true)][string] $StateRoot
    )

    foreach ($target in $Targets) {
        Write-Host ''
        Write-Host "Fusion: $($target.ProductVersion)"
        Write-Host "ThreadData: $($target.ThreadDataPath)"
        foreach ($pack in $Packs) {
            $receiptPath = Get-FtmReceiptPath $StateRoot $target $pack
            $receipt = Read-FtmReceipt $receiptPath $target $pack $StateRoot
            foreach ($file in @($pack.Files)) {
                $destination = Join-Path $target.ThreadDataPath $file.DestinationName
                $sourceHash = Get-FtmFileHash $file.SourceFull
                $exists = Test-Path -LiteralPath $destination -PathType Leaf
                $currentHash = if ($exists) { Get-FtmFileHash $destination } else { $null }
                $entry = Get-FtmPriorFileEntry $receipt $file.DestinationName

                if (-not $exists -and $null -eq $entry) {
                    $status = 'not installed'
                }
                elseif (-not $exists) {
                    $status = 'managed file missing'
                }
                elseif ($currentHash -eq $sourceHash -and $null -ne $entry) {
                    $status = 'current'
                }
                elseif ($currentHash -eq $sourceHash) {
                    $status = 'identical file present (not yet managed)'
                }
                elseif ($null -ne $entry -and $currentHash -eq [string] $entry.installedSha256) {
                    $status = "update available (installed pack $($receipt.packVersion))"
                }
                elseif ($null -ne $entry) {
                    $status = 'locally modified'
                }
                else {
                    $status = 'unmanaged conflict'
                }
                Write-Host ("  {0} {1}: {2}" -f $pack.Id, $pack.Version, $status)
            }
        }
    }
}

function Write-FtmCompatibilityWarnings {
    param(
        [Parameter(Mandatory = $true)][object[]] $Targets,
        [Parameter(Mandatory = $true)][object[]] $Packs
    )

    foreach ($target in $Targets) {
        if ($target.Kind -ne 'fusion' -or [string]::IsNullOrWhiteSpace($target.ProductVersion)) {
            continue
        }
        foreach ($pack in $Packs) {
            $compatibilityProperty = $pack.Manifest.PSObject.Properties['fusionCompatibility']
            if ($null -eq $compatibilityProperty) {
                continue
            }
            $testedProperty = $compatibilityProperty.Value.PSObject.Properties['testedProductVersions']
            if ($null -eq $testedProperty) {
                continue
            }
            $testedVersions = @($testedProperty.Value | ForEach-Object { [string] $_ })
            if ($testedVersions -notcontains $target.ProductVersion) {
                Write-FtmWarning "Pack '$($pack.Id)' has not yet been recorded as tested with Fusion $($target.ProductVersion). The legacy ThreadData XML folder is present, so the operation may continue; use -DryRun first and verify in Fusion."
            }
        }
    }
}

function Show-FtmHelp {
    $helpText = @"
$script:ToolName $script:ToolVersion

Usage:
  .\fusion-threads.cmd <command> [options]

Commands:
  install      Install all bundled packs, or packs selected with -Pack.
  update       Same safe operation as install; replaces older managed files.
  repair       Restore missing pack files after a Fusion update.
  uninstall    Remove managed files and restore pre-existing files if needed.
  discover     List every valid Fusion deployment found on this computer.
  status       Show Fusion discovery and per-pack state.
  list         List bundled packs.
  validate     Validate every pack manifest and XML definition.
  help         Show this help.

Options:
  -Pack <id>                 Select one or more pack IDs (default: all).
  -ThreadDataPath <path>     Override automatic Fusion discovery.
  -AllInstallations          Operate on every valid local Fusion build.
  -DryRun                    Print the plan without changing files or state.
  -AdoptExisting             Manage a byte-identical pre-existing file.
  -Force                     Back up and replace/remove a conflicting file.
  -StateRoot <path>          Override receipt and backup storage.

Examples:
  .\fusion-threads.cmd status
  .\fusion-threads.cmd install -DryRun
  .\fusion-threads.cmd install
  .\fusion-threads.cmd install -AdoptExisting
  .\fusion-threads.cmd update -Pack us.asme-b1.20.7.garden-hose
  .\fusion-threads.cmd uninstall
"@
    Write-Host $helpText
}

function Invoke-FusionThreadManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $RepositoryRoot,
        [ValidateSet('discover', 'install', 'update', 'repair', 'uninstall', 'status', 'list', 'validate', 'help')]
        [string] $Command = 'help',
        [string[]] $Pack,
        [string] $ThreadDataPath,
        [switch] $AllInstallations,
        [switch] $AdoptExisting,
        [switch] $Force,
        [switch] $DryRun,
        [string] $StateRoot
    )

    $RepositoryRoot = Get-FtmFullPath $RepositoryRoot
    $allPacks = @(Get-FtmPackDefinitions $RepositoryRoot)

    if ($Command -eq 'help') {
        Show-FtmHelp
        return
    }

    if ($Command -eq 'validate') {
        Assert-FtmPacksValid $allPacks
        foreach ($validPack in $allPacks) {
            Write-Host "[valid] $($validPack.Id) $($validPack.Version)"
        }
        return
    }

    Assert-FtmPacksValid $allPacks
    $selectedPacks = @(Resolve-FtmPacks $allPacks $Pack)

    if ($Command -eq 'list') {
        foreach ($selectedPack in $selectedPacks) {
            Write-Host ("{0}  {1}  {2}" -f $selectedPack.Id, $selectedPack.Version, $selectedPack.Name)
        }
        return
    }

    if ($Command -eq 'discover') {
        $discoveredTargets = @(Get-FtmFusionInstallations -ThreadDataPath $ThreadDataPath -AllInstallations)
        foreach ($discoveredTarget in $discoveredTargets) {
            $runningText = if ($discoveredTarget.IsRunning) { ' running' } else { '' }
            Write-Host ("{0}{1}`n  {2}" -f $discoveredTarget.ProductVersion, $runningText, $discoveredTarget.ThreadDataPath)
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $StateRoot = Get-FtmDefaultStateRoot
    }
    $StateRoot = Get-FtmFullPath $StateRoot
    $targets = @(Get-FtmFusionInstallations -ThreadDataPath $ThreadDataPath -AllInstallations:$AllInstallations)
    Write-FtmCompatibilityWarnings $targets $selectedPacks

    foreach ($target in $targets) {
        $runningText = if ($target.IsRunning) { ' (running)' } else { '' }
        Write-FtmInfo "Using Fusion $($target.ProductVersion)$runningText at '$($target.ThreadDataPath)'"
    }

    if ($Command -eq 'status') {
        Show-FtmStatus $targets $selectedPacks $StateRoot
        return
    }

    if ($Command -in @('install', 'update', 'repair')) {
        $plans = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            foreach ($selectedPack in $selectedPacks) {
                $plans.Add((New-FtmInstallPlan $target $selectedPack $StateRoot))
            }
        }

        $replacementConflicts = @($plans | ForEach-Object { @($_.Items) + @($_.StaleItems) } | Where-Object { $_.Action -in @('ConflictModified', 'ConflictUnmanaged', 'ConflictModifiedStale') })
        $adoptionConflicts = @($plans | ForEach-Object { $_.Items } | Where-Object { $_.Action -eq 'IdenticalUnmanaged' })
        if ($replacementConflicts.Count -gt 0 -and -not $Force) {
            foreach ($conflict in $replacementConflicts) {
                Write-FtmWarning "$($conflict.Action): $($conflict.Destination)"
            }
            throw 'No files were changed. Re-run with -Force to back up and replace conflicts.'
        }
        if ($adoptionConflicts.Count -gt 0 -and -not $AdoptExisting -and -not $Force) {
            foreach ($conflict in $adoptionConflicts) {
                Write-FtmWarning "Identical unmanaged file: $($conflict.Destination)"
            }
            throw 'No files were changed. Re-run with -AdoptExisting to back up and explicitly manage identical files.'
        }

        foreach ($plan in $plans) {
            Invoke-FtmInstallPlan $plan $StateRoot -DryRun:$DryRun
        }

        if (-not $DryRun -and @(Get-Process -Name 'Fusion360' -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-FtmWarning 'Fusion is running. Restart Fusion before looking for newly installed or updated thread definitions.'
        }
        return
    }

    if ($Command -eq 'uninstall') {
        $plans = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            foreach ($selectedPack in $selectedPacks) {
                $plans.Add((New-FtmUninstallPlan $target $selectedPack $StateRoot))
            }
        }

        $conflicts = @($plans | ForEach-Object { $_.Items } | Where-Object { $_.Action -eq 'ConflictModified' })
        if ($conflicts.Count -gt 0 -and -not $Force) {
            foreach ($conflict in $conflicts) {
                Write-FtmWarning "Locally modified managed file: $($conflict.Destination)"
            }
            throw 'No files were changed. Re-run with -Force to back up and remove modified managed files.'
        }

        foreach ($plan in $plans) {
            Invoke-FtmUninstallPlan $plan $StateRoot -DryRun:$DryRun
        }

        if (-not $DryRun -and @(Get-Process -Name 'Fusion360' -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-FtmWarning 'Fusion is running. Restart Fusion to refresh its thread definitions.'
        }
        return
    }

    throw "Unsupported command '$Command'."
}

Export-ModuleMember -Function Invoke-FusionThreadManager
