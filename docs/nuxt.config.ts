// https://nuxt.com/docs/api/configuration/nuxt-config
const siteUrl = process.env.NUXT_PUBLIC_SITE_URL || 'https://docker.rollogi.co.uk'

export default defineNuxtConfig({
  modules: [
    '@nuxt/eslint',
    '@nuxt/image',
    '@nuxt/ui',
    '@nuxt/content',
    'nuxt-og-image',
    'nuxt-llms'
  ],

  devtools: {
    enabled: true
  },

  css: ['~/assets/css/main.css'],

  site: {
    url: siteUrl,
    name: 'Rollogi Docker Images'
  },

  content: {
    build: {
      markdown: {
        toc: {
          searchDepth: 1
        }
      }
    },
    experimental: {
      sqliteConnector: 'native'
    }
  },

  experimental: {
    asyncContext: true
  },

  compatibilityDate: '2026-06-30',

  // Static output for Cloudflare Pages. autoSubfolderIndex=false matches Pages' route handling
  // (it serves /about.html for /about and redirects /about/index.html itself).
  nitro: {
    prerender: {
      autoSubfolderIndex: false
    }
  },

  eslint: {
    config: {
      stylistic: {
        commaDangle: 'never',
        braceStyle: '1tbs'
      }
    }
  },

  llms: {
    domain: siteUrl,
    title: 'Rollogi Docker Images',
    description: 'Multi-architecture PHP container images on Alpine Linux: base, php, php-nginx and php-nginx-dev.',
    full: {
      title: 'Rollogi Docker Images - Full Documentation',
      description: 'Complete documentation for the adamrollogi/base, php, php-nginx and php-nginx-dev images.'
    },
    sections: [
      { title: 'Getting Started', contentCollection: 'docs', contentFilters: [{ field: 'path', operator: 'LIKE', value: '/getting-started%' }] },
      { title: 'Images', contentCollection: 'docs', contentFilters: [{ field: 'path', operator: 'LIKE', value: '/images%' }] },
      { title: 'Configuration', contentCollection: 'docs', contentFilters: [{ field: 'path', operator: 'LIKE', value: '/configuration%' }] },
      { title: 'Security', contentCollection: 'docs', contentFilters: [{ field: 'path', operator: 'LIKE', value: '/security%' }] },
      { title: 'Releases', contentCollection: 'docs', contentFilters: [{ field: 'path', operator: 'LIKE', value: '/releases%' }] }
    ]
  },

  ogImage: {
    zeroRuntime: true
  },

  prerender: {
    routes: [
      '/'
    ],
    crawlLinks: true
  }
})
