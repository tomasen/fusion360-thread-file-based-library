# Contributing

Contributions are welcome, especially well-sourced thread definitions that are
missing from Fusion's built-in library.

Before opening a pull request:

1. Read [Adding a thread pack](docs/ADDING-A-PACK.md).
2. Cite a primary or authoritative dimensional source.
3. Do not copy proprietary standards text or Autodesk's bundled XML files.
4. Run `./fusion-threads.cmd validate`.
5. Run `pwsh -NoProfile -File ./tests/Run-Tests.ps1`.
6. State which Fusion version and physical fit, if any, you tested.

Keep unrelated thread families in separate pack folders so users can install
and remove them independently.
