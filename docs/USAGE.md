# Usage

## Requirements

- Windows 10 or 11
- Autodesk Fusion installed for one user or deployed under Program Files
- Windows PowerShell 5.1 or PowerShell 7+
- No administrator rights for a normal per-user installation

Close Fusion before changing its thread files. Restart it after installation,
update, repair, or uninstall.

## One-line install

```powershell
irm 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1' | iex
```

The bootstrap verifies the release checksum, installs the manager under
`%LOCALAPPDATA%\Programs\FusionThreadManager`, installs the bundled packs, and
adds `fusion-threads` to your user `PATH`. Its receipts and backups live in
`%LOCALAPPDATA%\FusionThreadManager`.

Run the command again to update.

## Inspect-first install

To review the bootstrap before running it:

```powershell
$url = 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1'
Invoke-WebRequest $url -OutFile .\install.ps1
Get-Content .\install.ps1
.\install.ps1
```

For a fixed bootstrap, replace `main` in the URL with a release tag or commit.

## CLI

```text
fusion-threads list       List available packs
fusion-threads status     Show Fusion and installed state
fusion-threads install    Install packs
fusion-threads update     Update managed files
fusion-threads repair     Reinstall after a Fusion update
fusion-threads uninstall  Remove packs and restore replaced files
fusion-threads validate   Validate manifests, hashes, and XML
fusion-threads discover   List Fusion installations
```

Useful options:

```powershell
fusion-threads install -Pack us.asme-b1.20.7.garden-hose
fusion-threads update -DryRun
fusion-threads install -AllInstallations
fusion-threads install -ThreadDataPath 'D:\Fusion\...\ThreadData'
fusion-threads install -Force
fusion-threads install -AdoptExisting
```

`-Force` backs up a collision before replacing it. `-AdoptExisting` takes over
a byte-identical file that was copied manually.

## Fusion discovery

The manager checks an explicit `-ThreadDataPath`, a running Fusion process,
per-user webdeploy folders, and lab deployments. The running deployment wins;
otherwise it uses the newest valid installation. Use `-AllInstallations` to
target every valid installation.

## Conflicts and recovery

New files are added without modifying Autodesk's stock XML. Unknown or edited
files stop the operation unless you use `-Force`, which backs them up first.
Uninstall restores replaced files and refuses to delete anything it cannot
verify from its receipt.

## Modeling notes

- A nominal pipe or hose size is not the physical face diameter. Select or
  create a cylindrical face near the modeled major/minor diameter in the pack.
- Female threads need uninterrupted wall beyond the major diameter. Thin or
  intersecting walls can make Fusion's Boolean operation fail.
- GHT, NPSH, NH, and NPSM are straight threads and normally rely on a washer,
  gasket, O-ring, or other joint seal. They are not substitutes for NPT.

References:

- [Custom thread location and latest-build requirement](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Custom-threads-not-showing-in-Fusion.html)
- [Fusion thread library and legacy XML update behavior](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/SLD-MANAGE-THREADS-LIBRARY.htm)
