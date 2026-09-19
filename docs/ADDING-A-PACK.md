# Adding a thread pack

Packs are grouped by region, standard, and thread family:

```text
packs/
  us/
    asme-b1.20.7/
      garden-hose/
        pack.json
        US-Garden-Hose-GHT.xml
        README.md
```

Use a separate folder and manifest for each independently installable family.
Do not add an unverified definition merely to fill a country or standards
folder.

## Manifest

Each `pack.json` uses schema version 1:

```json
{
  "schemaVersion": 1,
  "id": "region.standard.family",
  "name": "Human-readable name",
  "version": "1.0.0",
  "region": "US",
  "standard": "Standards designation",
  "description": "What this pack adds.",
  "fusionCompatibility": {
    "format": "legacy-thread-data-xml",
    "testedProductVersions": ["2705.1.15"]
  },
  "references": ["https://authoritative.example/reference"],
  "files": [
    {
      "source": "Definition.xml",
      "destination": "Unique-Definition.xml",
      "sha256": "64-lowercase-hex-characters"
    }
  ]
}
```

Rules enforced by `fusion-threads validate`:

- IDs contain lowercase letters, digits, dots, or hyphens.
- Versions use semantic `major.minor.patch` form.
- Source paths cannot escape their pack directory.
- Destinations are plain, unique `.xml` filenames without subdirectories.
- Source hashes must match the lowercase SHA-256 declared in the manifest.
- XML uses a `ThreadType` root with unique `Name` and `CustomName` values.
- Every designation has TPI or pitch, and at least one internal or external
  thread with ordered major, pitch, and minor diameters.

## Versioning

Increment the pack version whenever an installed XML file changes:

- Patch: correction that preserves intended compatibility.
- Minor: new designation or size.
- Major: incompatible renaming or dimensional behavior.

An update replaces only a file recorded as managed and unchanged since the
last install. A byte-identical unmanaged file requires `-AdoptExisting`.
Unknown or locally modified content requires `-Force`. All are backed up
before the manager assumes ownership or replaces content.

## Evidence and licensing

Cite primary or authoritative sources in both the manifest and pack README.
Dimensions and names may be facts, but standards publications and vendor XML
files can be copyrighted. Do not copy standards prose, tables, or Autodesk's
bundled definitions into this repository without permission.

## Test

```powershell
./fusion-threads.cmd validate
pwsh -NoProfile -File ./tests/Run-Tests.ps1
```

Also test external and internal modeled threads in Fusion. Record the tested
Fusion product version in the pack manifest.
