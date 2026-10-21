# Rollogi Docker Images documentation

Documentation site for the `adamrollogi/base`, `php`, `php-nginx` and `php-nginx-dev` images. Built with Nuxt 4, Nuxt UI and Nuxt Content, generated statically and served from Cloudflare Workers as static assets.

## Local development

```bash
pnpm install
pnpm dev        # http://localhost:3000
pnpm check      # eslint + vue-tsc
pnpm generate   # static build to .output/public
pnpm preview    # serve the static build
```

Content lives in `content/`. Folder and file name prefixes (`1.`, `2.`, ...) set the navigation order; `.navigation.yml` files name the sections.

## Deploying to Cloudflare Workers

The site is deployed as a static-assets Worker: `wrangler.jsonc` points the `assets` directory at `.output/public` and defines no Worker script, so Cloudflare serves the files directly. `nuxt.config.ts` pins the Nitro preset to `static` so Cloudflare's build environment cannot switch it to the server preset.

Connect the repository in the Cloudflare dashboard (Workers & Pages, Create, Workers, Import a repository) with these settings:

| Setting | Value |
|---------|-------|
| Production branch | `main` |
| Root directory | `docs` |
| Build command | `pnpm generate` |
| Deploy command | `npx wrangler deploy` |
| Build variables | `NUXT_PUBLIC_SITE_URL=https://docker.rollogi.co.uk`, `NODE_VERSION=24`, `PNPM_VERSION=12.14.0` |

Under **Settings, Build, Build watch paths** set the include path to `docs/*` so that commits touching only the Dockerfiles do not trigger a docs deploy. The reverse is already handled: the image build workflow ignores pushes that only change `docs/**` or Markdown files.

Add the custom domain under **Settings, Domains & Routes**; when the zone is on the same Cloudflare account the DNS record is created automatically.

Non-production branches get preview URLs when "Builds for non-production branches" is enabled in the Worker's build settings.

To deploy from a machine with wrangler logged in: `pnpm generate && pnpm deploy`.

## Headers, caching, crawlers

Files in `public/` are copied into the output and picked up by Cloudflare:

| File | Purpose |
|------|---------|
| `public/_headers` | Browser caching and security headers. Hashed assets (`/_nuxt`, `/_fonts`, `/_og`) are `immutable` for a year; pages and text endpoints are `max-age=0, must-revalidate` so a deploy shows immediately. Adds `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy` and a Content-Security-Policy. Rules are merged, so the generic rule comes first and asset rules detach `Cache-Control` with `!` before setting their own. |
| `public/robots.txt` | Allows every crawler, including AI crawlers, points at `/llms.txt` and the sitemap, and hides build artefacts. |
| `public/.well-known/security.txt` | Vulnerability reporting contacts (RFC 9116). Update `Expires` yearly. |
| `sitemap.xml` | Generated at build time by `@nuxtjs/sitemap` from the prerendered pages (raw Markdown and OG images excluded). |

The CSP allows inline scripts and styles (Nuxt needs them) plus `wasm-unsafe-eval` and blob workers for the client-side search database. Any new external resource (fonts, images, embeds) needs a matching CSP source or it will be blocked.

No zone-level Cache Rules are needed: Workers static assets are content-addressed and served from Cloudflare's edge, and a "Cache everything" rule with a long edge TTL would only make HTML stale after deploys. Enable **Always Use HTTPS** and **HSTS** on the zone, and leave AI crawler blocking off so the `llms.txt` audience can read the site.

## Structure

```
app/            Vue app shell, layout, header, footer, OG image component
content/        Markdown pages (the documentation itself)
public/         Static assets
nuxt.config.ts  Modules, site URL, llms.txt sections, static preset and prerender options
wrangler.jsonc  Cloudflare Workers static-assets deployment config
app/app.config.ts  Colours, header and footer links, table of contents links
```
