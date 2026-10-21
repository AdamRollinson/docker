# Rollogi Docker Images documentation

Documentation site for the `adamrollogi/base`, `php`, `php-nginx` and `php-nginx-dev` images. Built with Nuxt 4, Nuxt UI and Nuxt Content, generated statically and served by Cloudflare Pages.

## Local development

```bash
pnpm install
pnpm dev        # http://localhost:3000
pnpm check      # eslint + vue-tsc
pnpm generate   # static build to .output/public
pnpm preview    # serve the static build
```

Content lives in `content/`. Folder and file name prefixes (`1.`, `2.`, ...) set the navigation order; `.navigation.yml` files name the sections.

## Deploying to Cloudflare Pages

Connect the repository in the Cloudflare dashboard with these settings:

| Setting | Value |
|---------|-------|
| Production branch | `main` |
| Root directory | `docs` |
| Build command | `pnpm generate` |
| Build output directory | `.output/public` |
| Environment variable | `NUXT_PUBLIC_SITE_URL=https://docker.rollogi.co.uk` |

Every push to `main` deploys production; every pull request gets a preview URL. Nitro detects Cloudflare Pages automatically, so no preset configuration is needed.

Under **Settings, Builds, Build watch paths** set the include path to `docs/*` so that commits touching only the Dockerfiles do not trigger a docs deploy. The reverse is already handled: the image build workflow ignores pushes that only change `docs/**` or Markdown files.

## Structure

```
app/            Vue app shell, layout, header, footer, OG image component
content/        Markdown pages (the documentation itself)
public/         Static assets
nuxt.config.ts  Modules, site URL, llms.txt sections, prerender options
app/app.config.ts  Colours, header and footer links, table of contents links
```
