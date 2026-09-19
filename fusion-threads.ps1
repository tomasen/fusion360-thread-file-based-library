[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('discover', 'install', 'update', 'repair', 'uninstall', 'status', 'list', 'validate', 'help')]
    [string] $Command = 'help',

    [string[]] $Pack,

    [Alias('TargetThreadDataPath')]
    [string] $ThreadDataPath,

    [switch] $AllInstallations,
    [switch] $AdoptExisting,
    [switch] $Force,
    [switch] $DryRun,

    # Primarily useful for portable installations and automated tests.
    [string] $StateRoot
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module (Join-Path $PSScriptRoot 'src\FusionThreadManager.psm1') -Force
    Invoke-FusionThreadManager @PSBoundParameters -RepositoryRoot $PSScriptRoot
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
