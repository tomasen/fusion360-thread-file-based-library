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

Use one folder and manifest per independently installable family.

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

`fusion-threads validate` checks that:

- IDs and versions have the expected format.
- Paths stay inside the pack and destinations are unique XML filenames.
- Declared SHA-256 hashes match.
- XML names are unique and thread diameters are ordered correctly.
- Every designation has a pitch/TPI and at least one profile.

## Versioning

Increment the pack version whenever its XML changes:

- Patch: correction that preserves intended compatibility.
- Minor: new designation or size.
- Major: incompatible renaming or dimensional behavior.

Use authoritative dimensional sources in `pack.json` and the pack README.
Record derived values, but do not copy standards prose, tables, or Autodesk's
bundled XML.

## Test

```powershell
./fusion-threads.cmd validate
pwsh -NoProfile -File ./tests/Run-Tests.ps1
```

Also model both profiles in Fusion and record the tested product version.
