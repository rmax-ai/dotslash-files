# Website Prompt: DotSlash Files Repository

## Objective
Create a marketing/informational website for the `dotslash-files` project that clearly explains what DotSlash is, how this repository organizes manifest files, and how developers can interact with the utilities and installer scripts described in the repository.

## Audience
1. Developers who want to publish or consume DotSlash manifests.
2. Operators evaluating DotSlash for reproducible tool distribution.
3. Contributors who may extend the installer, shim, or test suite.

## Required Sections
1. **Hero Summary**
   - Project name and tagline (DotSlash wrappers for reproducible tooling).
   - One-sentence description of the benefits (small manifests, remote fetching, security via hashes).
2. **How DotSlash Works**
   - Mention the shebang (`#!/usr/bin/env dotslash`) and JSON manifest structure.
   - Include the typical execution flow: inspect, fetch, verify, cache, exec (based on docs/dotslash-reference.md).  
3. **Repository Overview**
   - Explain that this repo stores DotSlash manifests and highlight key directories (`bin/`, `scripts/`, `tests/`, docs).  
   - Mention the shim, sandbox, doctor, installer scripts with short descriptions drawn from README and docs/dotslash-install-plan.md.
4. **CLI Usage Highlights**
   - Summaries of quick commands (parse, fetch, run, sha256) and mention `dotslash-install` behavior (installer, interactive/CI flows).  
5. **Installer Proposal Summary**
   - Describe features from docs/dotslash-install-plan: install dir resolution, interactive fuzzy selection, wrapper creation, PATH handling, flags, exit codes, tests.
6. **Security & Best Practices**
   - Emphasize hash verification, caches, and no script execution. Mention guidance from docs/dotslash-reference and README best practices.  
7. **Getting Involved**
   - Steps for contributors (add manifest, validate with dotslash, open PR). Mention tests (shim/install/bin). Provide `make shim-tests`, `make bin-tests`, `make install-tests` usage rules (AGENTS).  
8. **Footer with Links**
   - Link to official DotSlash site, docs in repo, tests, trackers.

## Tone & Deliverables
- Tone: concise, confident, technical but approachable.
- Use callouts for commands and code (inline code formatting).  
- Highlight automation (safety, caching) and testing guidance.
- Mention directories and scripts as navigation aids (e.g., `scripts/dotslash-install`).
- Ensure accessibility: use headings, bullet lists, summary boxes.

## Optional Enhancements
- Suggest embedding diagrams or terminal callouts (hero screenshot placeholders) showing `dotslash` fetching flow.
- Provide a comparison table between storing binaries vs DotSlash manifests.
Use this prompt to brief a website generator/AI copywriter.
