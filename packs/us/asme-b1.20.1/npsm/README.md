# NPSM straight pipe thread pack

This pack adds all 15 **NPSM** sizes from 1/8-27 through 6-8, with external
and internal modeled profiles. NPSM is a straight, free-fitting mechanical
pipe thread; it does not seal on the thread flanks. Use the joint's specified
gasket, O-ring, or other seal.

The XML uses the midpoint of each published diameter tolerance. Where the
standard leaves an external minor or internal major diameter to the commercial
die or tap, the profile is calculated from the standard truncation shown in
the NPSM thread form. No tap-drill value is invented.

## References

- [ASME B1.20.1 overview](https://www.asme.org/codes-standards/find-codes-standards/b1201-pipe-threads-general-purpose-inch)
- [NBS Handbook H28 (1957), Part II](https://nvlpubs.nist.gov/nistpubs/Legacy/hb/nbshandbook28supp1957pt2.pdf), Table VII.6

This is not NPT. NPT and NPTF are tapered and cannot be represented correctly
by Fusion's cylindrical `ThreadData` XML format.
