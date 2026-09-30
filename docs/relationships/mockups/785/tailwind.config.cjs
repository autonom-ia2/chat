module.exports = {
  content: [__dirname + '/index.html', __dirname + '/mockup.js', __dirname + '/assets/*.html'],
  theme: { extend: { colors: { n: {
    background: '#F7F9FC', surface: '#FFFFFF', ink: '#20252D', muted: '#5E6978', line: '#E4E8EF',
    blue: '#2175EB', navy: '#0D2344', tint: '#EEF5FF', green: '#247451', amber: '#926016'
  } }, screens: { desk: '1280px' } } },
  plugins: []
};
