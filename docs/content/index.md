---
seo:
  title: Rollogi Docker Images
  description: Multi-architecture PHP container images on Alpine Linux. Pinned PHP releases, hardened by default, with Nginx, PHP-FPM and Xdebug variants.
---

::u-page-hero{class="dark:bg-gradient-to-b from-neutral-900 to-neutral-950"}
---
orientation: horizontal
---
#top
:hero-background

#title
PHP containers that are [pinned, hardened and small]{.text-primary}.

#description
Alpine-based images for PHP 8.2 to 8.6 on amd64 and arm64. Every release is pinned, every image is scanned before it is published, and nothing runs as root unless you ask it to.

#links
  :::u-button
  ---
  to: /getting-started
  size: xl
  trailing-icon: i-lucide-arrow-right
  ---
  Get started
  :::

  :::u-button
  ---
  icon: i-simple-icons-docker
  color: neutral
  variant: outline
  size: xl
  to: https://hub.docker.com/u/adamrollogi
  target: _blank
  ---
  Docker Hub
  :::

#default
  :::prose-pre
  ---
  code: |
    docker run --rm -d -p 8080:8080 \
      -e NGINX_PORT=8080 \
      -v $(pwd):/var/www/html:ro \
      adamrollogi/php-nginx:8.4
  filename: Terminal
  ---

  ```bash [Terminal]
  docker run --rm -d -p 8080:8080 \
    -e NGINX_PORT=8080 \
    -v $(pwd):/var/www/html:ro \
    adamrollogi/php-nginx:8.4
  ```
  :::
::

::u-page-section{class="dark:bg-neutral-950"}
#title
Four images, one lineage

#description
Each image builds on the one before it, so behaviour is consistent from the CLI to the full web stack.

#features
  :::u-page-feature
  ---
  icon: i-lucide-box
  to: /images/base
  ---
  #title
  base

  #description
  Alpine 3.24 with tini, cron, bash, curl, git and the shared logging helpers. No Python, no process manager. The foundation for everything else.
  :::

  :::u-page-feature
  ---
  icon: i-simple-icons-php
  to: /images/php
  ---
  #title
  php

  #description
  PHP CLI with Composer and the extensions a modern framework needs. One tag per minor and one per exact release.
  :::

  :::u-page-feature
  ---
  icon: i-simple-icons-nginx
  to: /images/php-nginx
  ---
  #title
  php-nginx

  #description
  Nginx and PHP-FPM under one roof, with optional HTTPS, security headers, a health endpoint and per-service logs.
  :::

  :::u-page-feature
  ---
  icon: i-lucide-bug
  to: /images/php-nginx-dev
  ---
  #title
  php-nginx-dev

  #description
  The web stack plus Xdebug, visible errors and uncached assets, tuned for local development.
  :::

  :::u-page-feature
  ---
  icon: i-lucide-pin
  to: /getting-started/tags-and-versions
  ---
  #title
  Pinned releases

  #description
  The exact PHP release is pinned per minor and enforced at build time. New upstream releases are picked up automatically every four hours.
  :::

  :::u-page-feature
  ---
  icon: i-lucide-shield-check
  to: /security/hardening
  ---
  #title
  Hardened defaults

  #description
  Non-root, no setuid binaries, root-owned config, read-only rootfs support, and Trivy scans gating every publish.
  :::
::

::u-page-section{class="dark:bg-gradient-to-b from-neutral-950 to-neutral-900"}
  :::u-page-c-t-a
  ---
  links:
    - label: Read the quick start
      to: '/getting-started/quick-start'
      trailingIcon: i-lucide-arrow-right
    - label: View the source
      to: 'https://github.com/AdamRollinson/docker'
      target: _blank
      variant: subtle
      icon: i-simple-icons-github
  title: Everything is configured with environment variables
  description: No Dockerfile layering needed for the common cases. Set a variable, restart the container, done.
  class: dark:bg-neutral-950
  ---

  :stars-bg
  :::
::
