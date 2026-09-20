# Security policy

Please report a path-traversal, arbitrary-file overwrite/removal, XML parsing,
or backup-restoration vulnerability through [GitHub private vulnerability
reporting](https://github.com/tomasen/fusion360-thread-file-based-library/security/advisories/new)
before opening a public issue.

The manager treats pack content as untrusted input: source paths must remain
inside their pack, destinations must be plain XML filenames, DTD processing is
disabled, and destination conflicts stop by default. Even so, review a pack
before using `-Force`, particularly when it came from an untrusted fork.

The README offers `irm <raw-main-url> | iex` as a convenience path. It cannot
verify the first-stage script before execution, and `main` is mutable. The
bootstrap does verify the release ZIP against its published SHA-256 file, but a
compromised account could replace both. For a stronger trust boundary, inspect
`install.ps1` first and pin its URL to a reviewed release tag or commit.
