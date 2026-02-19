# Security

## VEX Attestations

All CVE suppressions are maintained in a single consolidated OpenVEX document at [`.vex/openvex.json`](.vex/openvex.json). This file is attached as an attestation to every published image during CI builds, and can be used locally with `docker scout cves --vex-location .vex/`.

When adding new suppressions, add a statement to the existing `openvex.json` rather than creating per-CVE files.

## Known False Positives

### CVE-2023-27482 — Home Assistant Supervisor (does NOT affect these images)

**Status:** Suppressed via [OpenVEX](.vex/openvex.json)

Docker Scout flags CVE-2023-27482 against our images because the Alpine `supervisor` APK package shares a name with Home Assistant's Supervisor component. This is a **confirmed false positive**.

**Why it's a false positive:**

- CVE-2023-27482 is an authentication bypass in the **Home Assistant Supervisor** REST API (`homeassistant-supervisor`).
- Our images install `supervisor` from Alpine's APK repository, which is **supervisord** — the general-purpose process manager from [supervisord.org](http://supervisord.org).
- These are entirely different software projects that happen to share a package name.
- Zero Home Assistant code exists in any of our images.

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**References:**

- [NVD: CVE-2023-27482](https://nvd.nist.gov/vuln/detail/CVE-2023-27482)
- [Home Assistant Supervisor Advisory (GHSA-2j8f-6whh-frc8)](https://github.com/home-assistant/supervisor/security/advisories/GHSA-2j8f-6whh-frc8)
- [Wazuh false positive report (same root cause)](https://github.com/wazuh/wazuh/issues/23335)
- [Alpine Security Tracker — supervisor](https://security.alpinelinux.org/package/supervisor)

### CVE-2025-60876 — BusyBox wget Header Injection (not reachable in these images)

**Status:** Suppressed via [OpenVEX](.vex/openvex.json)

CVE-2025-60876 is an HTTP header injection vulnerability in BusyBox's `wget` applet (through 1.37.0). CR/LF and C0 control bytes in the HTTP request-target allow request line splitting. CVSS 6.5 MEDIUM.

Alpine 3.21 ships BusyBox 1.37.0, which contains the vulnerable applet. As of February 2026, no upstream fix exists — Alpine has not patched this in any version (including edge), and only a mailing list patch is available upstream.

**Why it's suppressed (not_affected / vulnerable_code_not_in_execute_path):**

- The base image installs the standalone `wget` package (APK: `wget`), which shadows the BusyBox `wget` applet in PATH.
- No entrypoint script, build step, or runtime process in any image layer invokes `wget` — all HTTP operations use `curl`.
- BusyBox cannot be removed as it provides Alpine's coreutils, but the vulnerable `wget` applet within it is never executed.

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**When to revisit:** If Alpine releases a patched BusyBox package (check `apk info busybox` or the [Alpine Security Tracker](https://security.alpinelinux.org/package/busybox)), the VEX suppression can be removed. Alternatively, if a future change introduces any use of BusyBox wget, the suppression must be re-evaluated.

**References:**

- [NVD: CVE-2025-60876](https://nvd.nist.gov/vuln/detail/CVE-2025-60876)
- [BusyBox mailing list patch](https://lists.busybox.net/pipermail/busybox-cvs/)
- [Alpine Security Tracker — busybox](https://security.alpinelinux.org/package/busybox)

### CVE-2025-14017, CVE-2025-13034, CVE-2025-15079, CVE-2025-14819, CVE-2025-14524, CVE-2025-10966, CVE-2025-15224 — libcurl Vulnerabilities

**Status:** Fixed — curl upgraded from Alpine edge (8.18.0+)

Alpine 3.21 ships curl 8.14.1, which contains 7 vulnerabilities (6 MEDIUM, 1 LOW) fixed in curl 8.18.0. Since Alpine 3.21's main repository does not yet carry the patched version, the base Dockerfile upgrades curl from the Alpine edge repository.

| CVE | Severity | Description |
|-----|----------|-------------|
| CVE-2025-14017 | MEDIUM | Multi-threaded LDAPS TLS option corruption |
| CVE-2025-13034 | MEDIUM | Pinned public key verification bypass (QUIC/GnuTLS) |
| CVE-2025-15079 | MEDIUM | SCP/SFTP known_hosts bypass |
| CVE-2025-14819 | MEDIUM | TLS CA store cache corruption on handle reuse |
| CVE-2025-14524 | MEDIUM | OAuth2 bearer token leakage on cross-protocol redirect |
| CVE-2025-10966 | MEDIUM | wolfSSH SFTP host verification missing |
| CVE-2025-15224 | LOW | SCP/SFTP public key auth bypass via SSH agent |

The `--repository` flag is scoped to a single `apk add` command and does not persist the edge repository, so other packages remain pinned to Alpine 3.21 stable.

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**When to revisit:** When Alpine 3.21 backports curl >= 8.18.0 to its main repository, the edge override can be removed from the Dockerfile.

**References:**

- [curl security advisories](https://curl.se/docs/security.html)
- [Alpine Security Tracker — curl](https://security.alpinelinux.org/package/curl)

### CVE-2025-47273 — setuptools Path Traversal

**Status:** Fixed — setuptools upgraded to >= 78.1.1 in base image

CVE-2025-47273 is a path traversal vulnerability in setuptools' `PackageIndex.download()` (all versions < 78.1.1). Alpine 3.21's `py3-setuptools` ships v69.0.0, which is vulnerable.

Setuptools is present as a transitive dependency of the `supervisor` APK package. While the vulnerable code path is never exercised at runtime, setuptools is upgraded at build time via pip to eliminate the scanner finding.

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**References:**

- [NVD: CVE-2025-47273](https://nvd.nist.gov/vuln/detail/CVE-2025-47273)
- [GHSA-5rjg-fvgr-3xxf](https://github.com/advisories/GHSA-5rjg-fvgr-3xxf)
