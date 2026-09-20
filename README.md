# Fusion 360 Thread File-Based Library

Free, auditable Fusion `ThreadData` XML packs plus a Windows installer that
finds the current Fusion deployment, installs safely, and survives Fusion
version-folder changes. No Hub Thread Library is required.

## Install without cloning

Close Fusion, open PowerShell, and run:

```powershell
irm 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1' | iex
```

Restart Fusion. The installer also adds `fusion-threads` to your user `PATH`.
Re-run the same command later to update the manager and bundled packs.

Piping a mutable web script to `iex` is convenient but cannot be verified
before execution. The [inspect-first method](docs/USAGE.md#inspect-first-install)
lets you review the bootstrap before it downloads and verifies the release.

## Included threads

| Fusion thread type | Standard | Designations |
| --- | --- | ---: |
| US Garden Hose Thread (GHT) | ASME B1.20.7 | 1 |
| US Straight Hose Thread (NPSH) | ASME B1.20.7 | 10 |
| US National Fire Hose Thread (NH/NST) | NFPA 1960:2024 | 11 |
| US Straight Pipe Thread (NPSM) | ASME B1.20.1 | 15 |
| **Total** | **4 packs** | **37** |

Every designation includes both external (male) and internal (female)
geometry: **74 modeled profiles**. See the exact sizes and scope decisions in
[thread coverage](docs/THREAD-COVERAGE.md).

NPT and NPTF are intentionally absent: they are tapered, while Fusion's legacy
`ThreadData` format models cylindrical threads. Adding them as ordinary XML
would make the wrong geometry.

## Commands

```powershell
fusion-threads status
fusion-threads list
fusion-threads install -DryRun
fusion-threads repair
fusion-threads uninstall
```

Install or remove one pack with `-Pack`, for example:

```powershell
fusion-threads install -Pack us.asme-b1.20.7.garden-hose
fusion-threads uninstall -Pack us.asme-b1.20.7.garden-hose
```

The manager never edits Autodesk's stock XML. Conflicts stop by default;
receipts and recoverable backups are stored in
`%LOCALAPPDATA%\FusionThreadManager`.

More detail: [usage and safety](docs/USAGE.md) ·
[add a pack](docs/ADDING-A-PACK.md) · [security](SECURITY.md)

This independent community project is not affiliated with Autodesk. Verify
fit with gauges or mating hardware before production, pressure, or life-safety
use.

## License

[MIT](LICENSE)
