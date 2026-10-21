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

Alpine 3.24 ships BusyBox 1.37.0, which contains the vulnerable applet. As of February 2026, no upstream fix exists — Alpine has not patched this in any version (including edge), and only a mailing list patch is available upstream.

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

**Status:** Fixed — Alpine 3.23 ships curl 8.22.0

Alpine 3.21 shipped curl 8.14.1, which contained 7 vulnerabilities (6 MEDIUM, 1 LOW) fixed in curl 8.18.0, and the base image used to pull curl from Alpine edge to work around it. Since the move to Alpine 3.23 (October 2026) the stock `curl` package is 8.22.0 (unchanged on 3.24), so the edge override has been removed.

| CVE | Severity | Description |
|-----|----------|-------------|
| CVE-2025-14017 | MEDIUM | Multi-threaded LDAPS TLS option corruption |
| CVE-2025-13034 | MEDIUM | Pinned public key verification bypass (QUIC/GnuTLS) |
| CVE-2025-15079 | MEDIUM | SCP/SFTP known_hosts bypass |
| CVE-2025-14819 | MEDIUM | TLS CA store cache corruption on handle reuse |
| CVE-2025-14524 | MEDIUM | OAuth2 bearer token leakage on cross-protocol redirect |
| CVE-2025-10966 | MEDIUM | wolfSSH SFTP host verification missing |
| CVE-2025-15224 | LOW | SCP/SFTP public key auth bypass via SSH agent |

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**References:**

- [curl security advisories](https://curl.se/docs/security.html)
- [Alpine Security Tracker — curl](https://security.alpinelinux.org/package/curl)

### CVE-2025-47273, CVE-2026-59890 — setuptools Path Traversal and MANIFEST.in Exclusion Bypass

**Status:** Fixed — setuptools upgraded to >= 83.0.0 in base image

CVE-2025-47273 is a path traversal in setuptools' `PackageIndex.download()` (fixed in 78.1.1). CVE-2026-59890 is a MANIFEST.in exclusion bypass when building a source distribution (fixed in 83.0.0). Alpine 3.24's `py3-setuptools` ships 82.0.1, which is still affected by the latter.

Setuptools is present only as a dependency of the `supervisor` APK package. Neither vulnerable code path is exercised at runtime, but setuptools is upgraded at build time via pip to eliminate the scanner findings.

Earlier images on Alpine 3.21 had to cap the upgrade below 81 because supervisor 4.2.5 imported `pkg_resources`, which setuptools 81 removed. Alpine 3.23 and 3.24 ship supervisor 4.3.0, which loads entry points through `importlib.metadata`, so the cap has been dropped.

**Affected images:** `adamrollogi/base`, `adamrollogi/php`, `adamrollogi/php-nginx`

**References:**

- [NVD: CVE-2025-47273](https://nvd.nist.gov/vuln/detail/CVE-2025-47273)
- [GHSA-5rjg-fvgr-3xxf](https://github.com/advisories/GHSA-5rjg-fvgr-3xxf)
- [NVD: CVE-2026-59890](https://nvd.nist.gov/vuln/detail/CVE-2026-59890)

### CVE-2026-40200, CVE-2026-6042 — musl Vulnerabilities

**Status:** Fixed — base image runs `apk upgrade` before installing packages

The pinned `alpine:3.21` digest shipped `musl-utils` 1.2.5-r9, which Trivy flagged for CVE-2026-40200 (HIGH, arbitrary code execution via stack-based overflow) and CVE-2026-6042 (MEDIUM, GB18030 decoder denial of service).

The php and php-nginx Dockerfiles already ran `apk upgrade`, so only the standalone base image was affected. The base Dockerfile now upgrades the installed Alpine packages before adding its own, so every published image receives Alpine security updates at build time regardless of how old the pinned digest is.

**Affected images:** `adamrollogi/base`

**References:**

- [NVD: CVE-2026-40200](https://nvd.nist.gov/vuln/detail/CVE-2026-40200)
- [Alpine Security Tracker — musl](https://security.alpinelinux.org/package/musl)
