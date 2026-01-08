dotslash-files

This repository stores DOTSLASH wrapper files used across projects. A DOTSLASH file (commonly given a .ds extension) is a small script-like file that must begin with the shebang:

#!/usr/bin/env dotslash

and contain a JSON body that tells the dotslash runtime how to fetch and run the executable it represents. Any arguments passed on the dotslash command line after the DOTSLASH file are forwarded to the underlying executable.

Quick usage

- Run a DOTSLASH file:
  dotslash ./tool.ds -- <args>

- Validate / inspect a DOTSLASH file:
  dotslash --parse ./tool.ds

- Prepare (fetch) the executable without running it:
  dotslash --fetch ./tool.ds

- Compute checksums:
  dotslash --sha256 FILE
  dotslash --b3sum FILE

Example DOTSLASH file (illustrative)

#!/usr/bin/env dotslash
{
  "name": "mytool",
  "provider": { "http": "https://example.com/bin/mytool-<platform>.tar.gz" },
  "run": { "cmd": ["mytool"] }
}

Testing & validation

- Make the file executable:
  chmod +x ./tool.ds

- Validate JSON syntax (optional):
  jq . ./tool.ds

- Use dotslash --parse and dotslash --fetch to verify behaviour on your host.

Best practices

- Use the #!/usr/bin/env dotslash shebang and prefer a .ds extension for clarity.
- Avoid hardcoding platform-specific paths; use provider templates and runtime outputs instead (see --help for supported placeholders).
- Pin artifacts with checksums when possible and prefer stable, versioned downloads.

Repository organization

Store DOTSLASH files in a logical location (root, a tools/ directory, or a dedicated dots/ directory). Keep files small, well-documented, and executable.

References

- Local quick reference: /Users/rmax/docs/dotslash.md
- Official project: https://dotslash-cli.com

Contributing

1. Add your DOTSLASH file (make it executable).
2. Validate locally with dotslash --parse and dotslash --fetch.
3. Open a PR describing the tool, platforms supported (if any), and any checksums or verification steps.
