# Fusion 360 Thread File-Based Library

A small, dependency-free Windows CLI for installing and maintaining local
custom thread definitions in Autodesk Fusion. It provides a free, auditable
workflow for the legacy `ThreadData` XML format and does not require Fusion's
Hub Thread Library.

The first bundled pack is **US garden hose, 3/4-11.5 NH**, with male and female
definitions.

> This is an independent community project. It is not affiliated with or
> endorsed by Autodesk. Autodesk Fusion is a trademark of Autodesk, Inc.

## Why a manager is useful

Fusion stores legacy custom XML in a build-specific directory such as:

```text
%LOCALAPPDATA%\Autodesk\webdeploy\production\<build-id>\
  Fusion\Server\Fusion\Configuration\ThreadData
```

The opaque build directory changes during Fusion updates, and Autodesk notes
that manual changes there are lost. This tool discovers the running or newest
valid deployment, installs versioned packs, and keeps receipts and backups
outside Fusion's replaceable application directory.

## Requirements

- Windows 10 or 11
- Autodesk Fusion installed normally for one user, or deployed under Program
  Files in a lab
- Windows PowerShell 5.1 or PowerShell 7+
- No administrator rights for a normal per-user Fusion installation

## Quick start

Download or clone the repository, open PowerShell in its folder, then run:

```powershell
.\fusion-threads.cmd status
.\fusion-threads.cmd install -DryRun
.\fusion-threads.cmd install
```

Restart Fusion after installing. In the Thread or Hole command, select:

```text
US Garden Hose Thread (GHT) > 3/4-11.5 NH (GHT)
```

The `.cmd` launcher selects PowerShell 7 when available and otherwise uses the
Windows PowerShell 5.1 already included with Windows.

## Commands

| Command | Purpose |
| --- | --- |
| `help` | Show command help and examples. |
| `list` | List the packs contained in this checkout. |
| `validate` | Validate every manifest and thread XML file. |
| `discover` | List every valid local Fusion deployment. |
| `status` | Show the selected Fusion deployment and installed state. |
| `install` | Install all packs, or a pack selected with `-Pack`. |
| `update` | Safely bring managed files to the checked-out pack version. |
| `repair` | Restore missing files after Fusion creates a new deployment. |
| `uninstall` | Remove managed files and restore any replaced original. |

Useful options:

```powershell
# One pack only
.\fusion-threads.cmd install -Pack us.asme-b1.20.7.garden-hose

# Preview without touching either Fusion or manager state
.\fusion-threads.cmd update -DryRun

# Operate on every valid Fusion deployment still present
.\fusion-threads.cmd install -AllInstallations

# Use an exact target for a portable or unusual installation
.\fusion-threads.cmd install -ThreadDataPath 'D:\Fusion\...\ThreadData'

# Back up and replace an unmanaged or locally modified collision
.\fusion-threads.cmd install -Force

# Explicitly adopt a byte-identical file that was copied manually
.\fusion-threads.cmd install -AdoptExisting
```

## Discovery

The manager validates candidates by requiring both `Fusion360.exe` and the
exact `Fusion\Server\Fusion\Configuration\ThreadData` directory. It checks:

1. An explicit `-ThreadDataPath`.
2. The executable path of a running `Fusion360.exe` process.
3. Per-user deployments under `%LOCALAPPDATA%\Autodesk\webdeploy\production`.
4. Lab deployments under `%ProgramFiles%\Autodesk\webdeploy\production`.

The running deployment wins; otherwise the executable modified most recently
is selected. `-AllInstallations` opts into changing all valid deployments.
Folders that only contain an Autodesk launcher or an incomplete update are
ignored.

## File and conflict policy

The manager never edits an Autodesk XML file in place.

| Existing destination | Default action |
| --- | --- |
| Missing | Add the pack file. |
| Byte-identical but unmanaged | Stop. Use `-AdoptExisting`; it is backed up first. |
| Previously managed and unchanged | Back it up, then update it. |
| Previously managed but locally edited | Stop. Use `-Force` to back up and replace it. |
| Unmanaged and different | Stop. Use `-Force` to back up and replace it. |

Receipts and backups live under:

```text
%LOCALAPPDATA%\FusionThreadManager
```

If a forced install replaced an unmanaged file, uninstall restores that exact
original. If a managed file was later edited, uninstall stops unless `-Force`
is supplied; forced uninstall backs up the edit before removing it.

## Pack organization

Repository folders provide the hierarchy that Fusion's flat destination lacks:

```text
packs/<region>/<standard>/<family>/
```

Each independently versioned folder contains a `pack.json`, one or more XML
files, sources, and usage notes. This makes US, Japanese, metric, pipe, hose,
and other future collections easy to browse without inventing definitions that
have not been verified.

See [Adding a thread pack](docs/ADDING-A-PACK.md) to contribute another
standard.

## Garden-hose modeling note

For the bundled female GHT profile, Fusion cuts out to a 1.0725 in
(27.2415 mm) root diameter. A 24.5-24.6 mm starting socket and a roughly 35 mm
outside-diameter collar provide robust modeling geometry. A thin wall or a
cylindrical face continuing into a Y-junction can cause Fusion's Boolean
operation to fail independently of the XML.

## Project status

This is an initial Windows MVP. The installer and conflict behavior are tested
without touching a real Fusion installation. Additional thread packs should be
added only with authoritative dimensional sources and physical or gauge-fit
testing where practical.

## Autodesk references

- [Custom thread location and latest-build requirement](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Custom-threads-not-showing-in-Fusion.html)
- [Fusion thread library and legacy XML update behavior](https://help.autodesk.com/cloudhelp/ENU/Fusion-Model/files/SLD-MANAGE-THREADS-LIBRARY.htm)

## License

[MIT](LICENSE)
