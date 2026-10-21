# Contributing to Mosaic

Thanks for helping. Mosaic is a small project; issues and focused pull
requests are welcome.

## Before you start

- Bugs and ideas: open an issue first for anything larger than a small fix.
- Security problems: follow [SECURITY.md](SECURITY.md), not a public issue.
- Read [AGENTS.md](AGENTS.md): it holds the code rules for people and coding
  agents alike, and [docs/architecture.md](docs/architecture.md).

## Set up

Clone the repository and symlink it in place of an installed copy:

```bash
git clone https://github.com/mateuspim/omarchy-mosaic.git
ln -s "$PWD/omarchy-mosaic" ~/.config/omarchy/plugins/pym.mosaic
omarchy-shell shell rescanPlugins && omarchy plugin enable pym.mosaic
omarchy-mosaic/scripts/dev-watch    # reload the widget on every save
```

Every saved file then runs in your shell. The
[development runbook](docs/runbooks/development.md) covers the git hooks,
throwaway test shells, and what not to run against your live tiles.

## Make a change

1. Branch from `master`.
2. Keep the change focused; update the [guide](docs/guide/) page or
   [spec](docs/specs/) it affects, and `CHANGELOG.md` under Unreleased.
3. Add or update tests. Run `npm test` (Node, Lua and Python 3) and
   `omarchy plugin validate .`.
4. Changing how tiles are launched or tiled? Re-run the
   [containment check](docs/runbooks/development.md#containment-check).
5. For panel changes, attach an offscreen render (`tests/preview.sh`, see
   the [development runbook](docs/runbooks/development.md)), never a desktop
   screenshot with personal data.
6. Changing the browser extension? Rename its worker script; see
   [ADR 10](docs/adr/0010-rename-the-extension-worker-on-every-change.md).
7. Durable design choice? Add an ADR under [docs/adr](docs/adr/README.md).

## Commit style

Plain imperative subject ("Add …", "Keep …"), under ~72 characters, and a
body that explains why.

## Pull request checklist

- [ ] Tests pass and `omarchy plugin validate .` exits 0
- [ ] Docs and CHANGELOG (Unreleased) updated
- [ ] No personal paths, stream URLs, device names, serials or addresses in
      tracked files

## License

By contributing you agree your work is released under the [MIT License](LICENSE).
