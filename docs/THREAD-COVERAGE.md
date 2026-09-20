# Thread coverage

The bundled library contains 4 packs, 37 designations, and 74 gender-specific
profiles. It focuses on common US straight-thread families that are absent from
the inspected Fusion stock library and can be represented faithfully by
Fusion's cylindrical `ThreadData` XML.

## Included

### GHT — 1 designation

- 3/4-11.5 NH (GHT)

This is the common US garden-hose connection. It seals on a washer. The NHR
thin-wall rolled/forming variant is not offered as a modeled solid thread.

### NPSH — 10 designations

- 1/2-14 and 3/4-14 NPSH
- 1, 1 1/4, 1 1/2, and 2-11.5 NPSH
- 2 1/2, 3, 3 1/2, and 4-8 NPSH

This is the complete NPSH series in ASME B1.20.7.

### NH/NST — 11 designations

- 3/4-8 and 1-8 NH
- 1 1/2-9 NH
- 2 1/2-7.5 NH
- 3-6 and 3 1/2-6 NH
- 4, 4 1/2, 5, 6, and 8-4 NH

This is the complete national fire-hose series in NFPA 1960:2024. Local fire
departments can use nonstandard threads, so life-safety parts require AHJ and
gauge verification.

### NPSM — 15 designations

- 1/8-27 NPSM
- 1/4-18 and 3/8-18 NPSM
- 1/2-14 and 3/4-14 NPSM
- 1, 1 1/4, 1 1/2, and 2-11.5 NPSM
- 2 1/2, 3, 3 1/2, 4, 5, and 6-8 NPSM

This is the complete NPSM series in ASME B1.20.1.

## Deliberately not duplicated

Fusion's stock `ANSI Unified Screw Threads` file already covers the Unified
geometry used by many JIC/AN flare, SAE O-ring boss, ORFS, tripod, microphone,
camera, and RF connector threads. Separate packs with the same geometry would
only create confusing duplicate menu entries.

## Not representable as ordinary ThreadData

- NPT and NPTF are tapered.
- NPTR is tapered.

Fusion's legacy XML describes a thread on a cylindrical face. A straight XML
approximation would have the wrong diameter along its length and is unsafe to
label as one of these tapered standards.

## Candidates awaiting stronger verification

Schrader/ISO tire-valve and faucet-aerator threads are common gaps.
[ISO 4570](https://www.iso.org/standard/30078.html) dimensions are verified,
but its permitted valve variants still need Fusion modeling and
interoperability tests. Faucet threads still need current B1.1 tolerance
calculations; neither family will be added from nominal size and pitch alone.
