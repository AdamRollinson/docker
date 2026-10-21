export default defineAppConfig({
  ui: {
    colors: {
      primary: 'blue',
      neutral: 'slate'
    },
    footer: {
      slots: {
        root: 'border-t border-default',
        left: 'text-sm text-muted'
      }
    }
  },
  seo: {
    siteName: 'Rollogi Docker Images'
  },
  header: {
    title: 'Rollogi Docker Images',
    to: '/',
    logo: {
      alt: '',
      light: '',
      dark: ''
    },
    search: true,
    colorMode: true,
    links: [{
      'icon': 'i-simple-icons-docker',
      'to': 'https://hub.docker.com/u/adamrollogi',
      'target': '_blank',
      'aria-label': 'Docker Hub'
    }, {
      'icon': 'i-simple-icons-github',
      'to': 'https://github.com/AdamRollinson/docker',
      'target': '_blank',
      'aria-label': 'GitHub'
    }]
  },
  footer: {
    credits: `MIT licensed • © ${new Date().getFullYear()} Rollogi`,
    colorMode: false,
    links: [{
      'icon': 'i-simple-icons-docker',
      'to': 'https://hub.docker.com/u/adamrollogi',
      'target': '_blank',
      'aria-label': 'Docker Hub'
    }, {
      'icon': 'i-simple-icons-github',
      'to': 'https://github.com/AdamRollinson/docker',
      'target': '_blank',
      'aria-label': 'GitHub'
    }]
  },
  toc: {
    title: 'On this page',
    bottom: {
      title: 'Links',
      edit: 'https://github.com/AdamRollinson/docker/edit/main/docs/content',
      links: [{
        icon: 'i-simple-icons-docker',
        label: 'Images on Docker Hub',
        to: 'https://hub.docker.com/u/adamrollogi',
        target: '_blank'
      }, {
        icon: 'i-lucide-bug',
        label: 'Report an issue',
        to: 'https://github.com/AdamRollinson/docker/issues/new',
        target: '_blank'
      }]
    }
  }
})
