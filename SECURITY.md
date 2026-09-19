# Security policy

Please report a path-traversal, arbitrary-file overwrite/removal, XML parsing,
or backup-restoration vulnerability through [GitHub private vulnerability
reporting](https://github.com/tomasen/fusion360-thread-file-based-library/security/advisories/new)
before opening a public issue.

The manager treats pack content as untrusted input: source paths must remain
inside their pack, destinations must be plain XML filenames, DTD processing is
disabled, and destination conflicts stop by default. Even so, review a pack
before using `-Force`, particularly when it came from an untrusted fork.

Do not use remote `Invoke-Expression` installation commands for this project.
Download or clone a versioned release, inspect it, and run the local launcher.
