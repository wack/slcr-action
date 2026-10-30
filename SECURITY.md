# Security Policy

## Supported versions

Security fixes go into `trunk` and ship in the next release. The major
version tag (such as `v1`) then moves to that release. Only the latest
release of the current major version is supported.

## Reporting a vulnerability

**Please don't report security vulnerabilities in public issues,
discussions, or pull requests.**

Report them privately in one of two ways:

- Email **security@wack.run**.
- Use GitHub's
  [private vulnerability reporting](https://github.com/wack/slcr-action/security/advisories/new).

Please include:

- The action's version (the ref in your `uses:` line).
- A description of the issue and its impact.
- Steps to reproduce it, ideally a minimal workflow.

A vulnerability in the slcr CLI itself belongs to
[wack/slcr](https://github.com/wack/slcr/security/policy).

## What to expect

- We'll acknowledge your report within **3 business days**.
- We'll send an initial assessment within **10 business days**. It will say
  whether we consider the report a vulnerability and how severe it is.
- We'll keep you updated as we work on a fix, and tell you when it ships.
- We'll credit you in the advisory, unless you'd rather stay anonymous.
