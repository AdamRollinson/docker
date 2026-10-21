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

## Structure

```
app/            Vue app shell, layout, header, footer, OG image component
content/        Markdown pages (the documentation itself)
public/         Static assets
nuxt.config.ts  Modules, site URL, llms.txt sections, static preset and prerender options
wrangler.jsonc  Cloudflare Workers static-assets deployment config
app/app.config.ts  Colours, header and footer links, table of contents links
```
