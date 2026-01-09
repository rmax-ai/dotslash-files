# dotslash-files

This repository stores [DotSlash](https://dotslash-cli.com) wrapper files used across projects. A DotSlash file (commonly given a .dotslash extension) is a small script-like file that must begin with the shebang:

```bash
#!/usr/bin/env dotslash
```

and contain a JSON body that tells the dotslash runtime how to fetch and run the executable it represents. Any arguments passed on the dotslash command line after the DotSlash file are forwarded to the underlying executable.

## Quick usage

- Run a DotSlash file:

```bash
dotslash ./tool.dotslash -- <args>
```

- Validate / inspect a DotSlash file:

```bash
dotslash -- parse ./tool.dotslash
```

- Prepare (fetch) the executable without running it:

```bash
dotslash -- fetch ./tool.dotslash
```

- Compute checksums:

```bash
dotslash -- sha256 FILE
dotslash -- b3sum FILE
```

## Example DotSlash file (illustrative)

```bash
#!/usr/bin/env dotslash
```

```json
{
  "name": "mytool",
  "provider": { "http": "https://example.com/bin/mytool-<platform>.tar.gz" },
  "run": { "cmd": ["mytool"] }
}
```

## Testing & validation

- Make the file executable:

```bash
chmod +x ./tool.dotslash
```

- Validate JSON syntax (optional):

```bash
jq . ./tool.dotslash
```

- Use `dotslash -- parse` and `dotslash -- fetch` to verify behaviour on your host.

## Best practices

- Use the `#!/usr/bin/env dotslash` shebang and prefer a `.dotslash` extension for clarity.
- Avoid hardcoding platform-specific paths; use provider templates and runtime outputs instead (see `--help` for supported placeholders).
- Pin artifacts with checksums when possible and prefer stable, versioned downloads.
- For deployment, you can rename a `.dotslash` file to the target binary name and place it in a directory on your `PATH` (for example, `node-v24.0.0.dotslash` -> `~/bin/node`). After moving the file, ensure it is executable (for example: `chmod +x ~/bin/node`).

## Repository organization

Store DotSlash files in a logical location (root, a `tools/` directory, or a dedicated `dots/` directory). Keep files small, well-documented, and executable.

## References

- Official project: [dotslash-cli.com](https://dotslash-cli.com)

## Contributing

1. Add your DotSlash file (make it executable).
2. Validate locally with `dotslash -- parse` and `dotslash -- fetch`.
3. Open a PR describing the tool, platforms supported (if any), and any checksums or verification steps.
