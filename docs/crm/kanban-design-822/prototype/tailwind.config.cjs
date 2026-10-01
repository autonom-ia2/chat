module.exports = {
  content: [__dirname + '/index.html', __dirname + '/app.js'],
  theme: {
    extend: {
      fontFamily: { inter: ['Inter', 'system-ui', 'sans-serif'] },
      colors: {
        // Product tokens: _next-colors.scss and branded Sidebar.vue.
        navy: '#0b3265',
        sidebar: '#0b1e3f',
        brand: '#2781f6',
      },
    },
  },
};
