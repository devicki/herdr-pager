# Contributing to herdr-pager

Thanks for helping. herdr-pager sends ntfy push notifications when agents finish or need you, and when commands end. Issues and pull requests are welcome, in English or Korean.

## Reporting a bug

Open an issue with the **Bug report** form. The versions it asks for and the exact steps matter most; the plugin log usually shows what went wrong: `herdr plugin log list --plugin devicki.pager`.

## Changing something

1. Fork the repository and make a branch.
2. Keep the change small and focused. Match the style around it: short functions, comments that say why.
3. Run the tests and make sure they pass:
   ```sh
   ./test.sh
   ```
   They need jq, curl and python3. It runs an isolated Herdr and a stand-in ntfy server, so nothing reaches a real one.
4. If you fix a bug, add a check to `test.sh` that fails without your fix.
5. Update `README.md` and `README.ko.md` together when behaviour or settings change. The English README is the main one; a Korean update can be a rough one, it will be polished.
6. Open a pull request and say what changed and how you tested it.

## Things to keep in mind

- macOS runs these scripts with `/bin/bash` 3.2. Check that they still parse there:
  ```sh
  for f in bin/herdr-pager test.sh; do docker run --rm -v "$PWD:/p:ro" bash:3.2 bash -n /p/$f; done
  ```
  In bash 3.2, a `case` inside `$( )` needs its patterns to start with `(`. Use BSD-compatible flags (no `sed -i`, no `\I`) and `stat -c %Y || stat -f %m`.
- Never paste an ntfy token, password or a real server address in an issue or a PR; the tests use a stand-in server.
- Messages exist in English and Korean (`word()` in bin/herdr-pager); add both for new wording.
- Keep `bin/herdr-pager` executable: scripts, cron and the shell hooks run it directly.

## Releases

The maintainer releases: bump `version` in `herdr-plugin.toml`, update the `--ref` in both READMEs, then tag `vX.Y.Z`. You do not need to bump versions in a pull request.
