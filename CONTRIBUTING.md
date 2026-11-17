# Contributing to Stretch the Mac

Contributions adding support for additional Synaptics `VMM53xx` dock board IDs, verified firmware revisions, multi-monitor resolutions, or window-snapping test cases are welcome.

## Ground Rules

- Read and follow [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) in all issues, pull requests, commit messages, and discussions.
- Review [`LEGAL.md`](LEGAL.md) before submitting protocol or hardware-interoperability changes:
  - Include `SPDX-License-Identifier: MIT` at the top of every source file and script.
  - Never commit or upload proprietary firmware binaries (`.bin`, `.dfu`, `.exe`), decompiled vendor code, verbatim hexadecimal OEM firmware dumps, or screenshots of proprietary OEM applications. Always use structural register descriptions and `<REDACTED_OEM_BYTES>`.
  - Preserve the strict volatile-SRAM write allowlist (`0x1740` and event queue `0x0368..0x0387` / `0x04A1`); never add SPI flash write or erase operations.
- Do not include personal data, private network addresses, monitor serial numbers, host hardware serial numbers, or local user paths in code, tests, logs, or fixtures.
- Report security vulnerabilities privately via [`SECURITY.md`](SECURITY.md) rather than public issues.

## Pull Request Workflow

1. Create a focused topic branch from `main` (`feat/...`, `fix/...`, `docs/...`, `chore/...`, `ci/...`).
2. Keep commits atomic, use Conventional Commit headers (`feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, `test:`), and sign all commits (`git config commit.gpgsign true`).
3. Run the local build, self-test, and syntax verification suite before opening a pull request:

```bash
make clean && make test
./dist/dockctl --help
python3 lenovo_40an_vmm5322_split.py --help
```

4. Open a pull request against `main` summarizing the problem, root cause or design choice, and verification output. All pull requests are licensed under the MIT License ([`LICENSE`](LICENSE)) and squash-merge onto `main` once `ci` and `security` checks pass.
