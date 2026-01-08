# dotslash-files

Personal repository for "dotslash" configuration files, scripts, and per-project config used across my projects.

Purpose
- Centralize dotfiles, reusable scripts, templates, and per-project configuration.
- Make bootstrapping and sharing configuration across machines and projects easy and reproducible.

Recommended layout
- `home/` — files intended to be symlinked into $HOME (e.g. `.zshrc`, `.gitconfig`, `.config/`)
- `hosts/<hostname>/` — host-specific overrides and additions
- `projects/<project>/` — per-project configs, tooling snippets, and README for usage
- `bin/` — small executable helper scripts (add to PATH via symlink)
- `templates/` — config templates (eg. `.gitconfig.local.template`)
- `docs/` — additional documentation and notes
- `private/` — local-only secrets (should be gitignored; do not commit secrets)

Getting started (examples)

Clone the repo:

```bash
git clone git@github.com:<you>/dotslash-files.git ~/.dotslash
```

Apply your preferred management method (choose one):

- yadm (simple dotfile management):

```bash
yadm clone git@github.com:<you>/dotslash-files.git
```

- chezmoi (state-driven dotfile manager):

```bash
chezmoi init --apply git@github.com:<you>/dotslash-files.git
```

- GNU stow (symlink manager):

```bash
cd ~/.dotslash
stow home
```

- Manual (one-off symlink):

```bash
ln -s ~/.dotslash/home/.zshrc ~/.zshrc
```

Per-project usage
- Add this repo as a git submodule inside a project:

```bash
git submodule add git@github.com:<you>/dotslash-files.git .dots
```

- Keep per-project config in `projects/<project>/` and add a small setup script in the project to link or copy those files as needed.

Security and secrets
- Do NOT commit secrets (API keys, private keys, passwords).
- Use `.gitignore` to keep local-only files out of version control.
- For encrypted secrets consider tools like `git-crypt` or `sops`.

Contributing
- This is primarily a personal repository; for collaborative/public workflows, open an issue first, then a branch and PR.
- Keep changes focused and document why a change is needed.

License
- No license is specified in this repository by default. Add a `LICENSE` file if you want to make contents explicitly reusable under an open license.

Maintainer
- rmax

Notes
- If you want, I can add a `bootstrap` script, example configs, or a CONTRIBUTING guide.