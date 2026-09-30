module.exports = {
  content: [__dirname + '/index.html', __dirname + '/mockup.js', __dirname + '/assets/email-demo.html'],
  theme: {
    extend: {
      colors: { n: {
        background: '#F6F8FC', surface: '#FFFFFF', ink: '#20252D', muted: '#647083', line: '#E3E8F0',
        blue: '#1D6EE3', navy: '#0D2344', tint: '#EDF5FF', green: '#237555', amber: '#926016'
      } },
      fontFamily: { sans: ['-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'] }
    }
  },
  plugins: []
};
