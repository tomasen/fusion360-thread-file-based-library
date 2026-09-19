# US garden-hose thread pack

This pack adds **3/4-11.5 NH**, the common straight US garden-hose thread, with
both external and internal definitions. The connection seals at a washer, not
at the thread flanks.

## Modeled dimensions

| Property | External | Internal |
| --- | ---: | ---: |
| Major diameter | 1.0540 in | 1.0725 in |
| Pitch diameter | 1.00175 in | 1.02025 in |
| Minor diameter | 0.9495 in | 0.9680 in |

The profile uses 11.5 TPI, a 60-degree included angle, and nominal size 0.75 in.
The internal tap-drill hint is 31/32 in (0.96875 in).

These values are intended for solid modeled or printed **NH** parts. **NHR** is
the thin-wall rolled/forming variant; it is not the name for a female thread.

For a modeled female thread, provide uninterrupted material beyond the
1.0725 in (27.2415 mm) root diameter. A 35 mm outside-diameter collar is a
practical starting point. Thin or intersecting walls can make Fusion's Boolean
thread operation fail even when the XML is valid.

## References

- [ASME B1.20.7 overview](https://www.asme.org/codes-standards/find-codes-standards/b1-20-7-hose-coupling-screw-threads)
- [USDA dimensional tables](https://www.fs.usda.gov/t-d/programs/fire/documents/5100_190c.pdf)
- [DLA NH/NHR manufacturing guidance](https://landandmaritimeapps.dla.mil/Downloads/MilSpec/Docs/A-A-59614/aa59614ss5.pdf)

This repository does not reproduce the ASME standard. Verify dimensions and
fit for safety-critical or production use.
