---

# DotSlash: Comprehensive Reference Guide

## 1. Core Concept

DotSlash files are **smart pointers**. Instead of storing a 100MB binary in Git, you store a 1KB text file. When executed, DotSlash fetches the correct binary for the user’s platform, verifies it, and runs it transparently.

## 2. File Anatomy

A DotSlash file is a **polyglot**. It starts with a shebang (`#!`) to tell the OS to use the DotSlash runner, but the content is formatted as **JSON**.

### Schema Reference

| Key | Type | Requirement | Description |
| --- | --- | --- | --- |
| `name` | String | **Required** | The name of the tool (for logging/errors). |
| `platforms` | Object | **Required** | Map of OS-Architecture keys to artifact definitions. |
| `size` | Integer | **Required** | Exact size of the remote file in bytes. |
| `hash` | String | **Required** | `sha256` or `blake3`. |
| `digest` | String | **Required** | The hex-encoded hash of the remote file. |
| `format` | String | Optional | `tar.gz`, `zip`, `zst`, `bz2`, `gz`, or `xz`. Use `null` or omit for raw binaries. |
| `path` | String | Optional | The internal path to the binary if the download is an archive. |
| `providers` | Array | **Required** | List of sources (URIs) where the file is hosted. |

---

## 3. Platform Keys

DotSlash detects the current machine's OS and CPU to look up the correct entry in the `platforms` object.

* **Linux:** `linux-x86_64`, `linux-aarch64`
* **macOS:** `macos-x86_64`, `macos-aarch64` (Apple Silicon)
* **Windows:** `windows-x86_64`

---

## 4. Provider Types

DotSlash allows multiple providers to ensure high availability.

### HTTP Provider

Fetches from a direct URL.

```json
{
  "type": "http",
  "url": "https://example.com/downloads/tool-v1.tar.gz"
}

```

### GitHub Release Provider

Specifically optimized for GitHub’s release infrastructure.

```json
{
  "type": "github-release",
  "owner": "facebook",
  "repo": "dotslash",
  "tag": "v1.0.0",
  "name": "dotslash-macos-aarch64.gz"
}

```

---

## 5. Caching and Execution Flow

1. **Invocation:** User runs `./bin/my-tool`.
2. **Lookup:** DotSlash reads the local file and identifies the current platform.
3. **Cache Check:** It checks `$DOTSLASH_CACHE` (defaulting to `~/.cache/dotslash`) for the `digest`.
4. **Fetch:** If missing, it downloads the artifact from the first available `provider`.
5. **Verify:** It confirms the `size` and `digest` match the config exactly.
6. **Decompress:** If a `format` is specified, it extracts the archive into the cache.
7. **Exec:** It uses the `execve` system call to replace the current process with the tool, passing all arguments (`$@`) along. **Performance overhead is negligible** after the first download.

---

## 6. Security Model

DotSlash is more secure than many global package managers because:

* **Content Addressing:** Binaries are verified by hash. Even if a download server is compromised, DotSlash will refuse to run a modified binary.
* **Read-Only Cache:** Downloaded tools are stored in a read-only local cache.
* **No "Pre-install" Scripts:** Unlike `npm` or `pip`, DotSlash does not run arbitrary lifecycle scripts. It only fetches and executes the specified binary.

---

## 7. Common Commands

If you have the `dotslash` CLI installed, use these helpers to avoid manual calculations:

* **Generate a hash/size entry:**
```bash
dotslash -- create-url-entry https://example.com/tool.zip

```


* **Check the version of the runner:**
```bash
dotslash --version

```



---

## 8. Best Practices

* **Commit to Git:** Always check your `.dotslash` files into your repository.
* **Include All Platforms:** Ensure you include at least `linux-x86_64`, `macos-x86_64`, and `macos-aarch64` so your whole team can work.
* **Use Mirrors:** List multiple URLs in the `providers` array if your team relies on an internal Artifactory mirror as well as public GitHub.

---
