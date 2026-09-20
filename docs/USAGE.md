# Usage and safety

## Requirements

- Windows 10 or 11
- Autodesk Fusion installed for one user or deployed under Program Files
- Windows PowerShell 5.1 or PowerShell 7+
- No administrator rights for a normal per-user Fusion installation

Close Fusion before changing its thread files. Restart it after installation,
update, repair, or uninstall.

## One-line install

```powershell
irm 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1' | iex
```

The bootstrap downloads the latest release ZIP and checksum, verifies SHA-256,
validates the contained packs, and installs the manager under:

```text
%LOCALAPPDATA%\Programs\FusionThreadManager
```

It then installs every bundled thread pack into the selected Fusion deployment
and adds the manager directory to the user's `PATH`. Manager state is separate:

```text
%LOCALAPPDATA%\FusionThreadManager
```

Re-running the bootstrap performs an atomic manager/library update and retains
that state.

## Inspect-first install

The short `irm | iex` command executes the current `main` branch bootstrap
before you can verify it. For an auditable install, download and inspect that
small script first:

```powershell
$url = 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1'
Invoke-WebRequest $url -OutFile .\install.ps1
Get-Content .\install.ps1
.\install.ps1
```

The bootstrap always verifies the downloaded release archive against its
published SHA-256 file. Pinning `install.ps1` to a reviewed release tag or
commit provides a stronger first-stage trust boundary than using `main`.

## CLI

| Command | Purpose |
| --- | --- |
| `help` | Show command help and examples. |
| `list` | List packs in the installed release. |
| `validate` | Validate manifests, hashes, and thread XML. |
| `discover` | List valid local Fusion deployments. |
| `status` | Show the selected deployment and installed state. |
| `install` | Install all packs or those selected by `-Pack`. |
| `update` | Make managed files match the installed release. |
| `repair` | Restore files after Fusion creates a new deployment. |
| `uninstall` | Remove managed files and restore replaced originals. |

Useful options:

```powershell
fusion-threads install -Pack us.asme-b1.20.7.garden-hose
fusion-threads update -DryRun
fusion-threads install -AllInstallations
fusion-threads install -ThreadDataPath 'D:\Fusion\...\ThreadData'
fusion-threads install -Force
fusion-threads install -AdoptExisting
```

`-Force` backs up a collision before replacing it. `-AdoptExisting` records a
byte-identical manually copied file so it can be managed without discarding its
pre-existing state.

## Fusion discovery

The manager requires both `Fusion360.exe` and the exact
`Fusion\Server\Fusion\Configuration\ThreadData` directory. It checks, in order:

1. An explicit `-ThreadDataPath`.
2. The executable path of a running Fusion process.
3. Per-user deployments under `%LOCALAPPDATA%\Autodesk\webdeploy\production`.
4. Lab deployments under `%ProgramFiles%\Autodesk\webdeploy\production`.

The running deployment wins; otherwise the newest valid executable is used.
`-AllInstallations` explicitly opts into changing every valid deployment.
Launcher-only and incomplete update folders are ignored.

## Conflict and recovery behavior

The manager never edits an Autodesk XML file in place.

| Destination state | Default behavior |
| --- | --- |
| Missing | Add the pack file and receipt. |
| Managed and identical | No change. |
| Managed but locally edited | Stop; `-Force` backs up and replaces it. |
| Unmanaged but byte-identical | Stop; `-AdoptExisting` backs up and adopts it. |
| Unmanaged and different | Stop; `-Force` backs up and replaces it. |

Uninstall removes a manager-created file only when its current hash still
matches the receipt. If a forced install replaced an unmanaged file, uninstall
restores the exact original. If required recovery data is missing, uninstall
stops instead of deleting the destination.

## Modeling notes

- A nominal pipe or hose size is not the physical face diameter. Select or
  create a cylindrical face near the modeled major/minor diameter in the pack.
- Female modeled threads require enough uninterrupted wall beyond the thread's
  major diameter. Intersections, thin walls, and downstream junctions can make
  Fusion's Boolean operation fail even when the XML is valid.
- GHT, NPSH, NH, and NPSM are straight threads and normally rely on a washer,
  gasket, O-ring, or other joint seal. They are not substitutes for NPT.

Autodesk references:

- [Custom thread location and latest-build requirement](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Custom-threads-not-showing-in-Fusion.html)
- [Fusion thread library and legacy XML update behavior](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/SLD-MANAGE-THREADS-LIBRARY.htm)
