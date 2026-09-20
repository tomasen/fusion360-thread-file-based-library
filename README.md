# Fusion 360 Thread File-Based Library

Fusion's free plan does not include the managed Thread Library, and copying
custom thread files by hand is tedious. This project installs, updates, and
removes organized `ThreadData` XML packs with one PowerShell command.

## Install without cloning

Close Fusion, open PowerShell, and run:

```powershell
irm 'https://raw.githubusercontent.com/tomasen/fusion360-thread-file-based-library/main/install.ps1' | iex
```

Restart Fusion when it finishes. Run the same command later to update.

## Included threads

- GHT: 1 designation
- NPSH: 10
- NH/NST fire hose: 11
- NPSM: 15

That is **37 designations / 74 male and female profiles**. See
[thread coverage](docs/THREAD-COVERAGE.md) for the exact sizes. NPT/NPTF are
not included because tapered threads cannot be modeled correctly with Fusion's
cylindrical `ThreadData` format.

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

The manager leaves Autodesk's stock XML alone and keeps recoverable backups in
`%LOCALAPPDATA%\FusionThreadManager`.

[Usage](docs/USAGE.md) · [Add a pack](docs/ADDING-A-PACK.md)

Check fit with mating hardware before production use.

## License

[MIT](LICENSE)
