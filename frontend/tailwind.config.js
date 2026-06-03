export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg:                    '#fafdfe',
        panel:                 '#ffffff',
        'surface-container':   '#e8f7f9',
        primary:               '#006874',
        'primary-container':   '#97f0ff',
        'on-primary':          '#ffffff',
        'on-primary-container':'#001f24',
        'on-surface':          '#191c1d',
        'on-surface-variant':  '#3f484a',
        outline:               '#6f797a',
        'outline-variant':     '#dbe4e6',
        tertiary:              '#2e7d32',
        warning:               '#e65100',
        error:                 '#b71c1c',
      },
    },
  },
  plugins: [],
};
