import AutonomiaGuideAPI from '../autonomiaGuide';

// #895 — o transcritor decide o formato pela extensão: ela tem que bater com
// o áudio gravado (OGG no Chrome/Firefox, MP3 no Safari).
describe('#AutonomiaGuideAPI.transcrever', () => {
  const originalAxios = window.axios;
  const post = vi.fn(() => Promise.resolve());

  beforeEach(() => {
    window.axios = { post };
  });

  afterEach(() => {
    window.axios = originalAxios;
    post.mockClear();
  });

  const nomeEnviado = () => post.mock.calls[0][1].get('file').name;

  it.each([
    ['audio/ogg', 'voz.ogg'],
    ['audio/ogg;codecs=opus', 'voz.ogg'],
    ['audio/mp3', 'voz.mp3'],
    ['audio/mpeg', 'voz.mp3'],
    ['audio/mp4', 'voz.mp4'],
    ['audio/webm', 'voz.webm'],
    ['', 'voz.webm'],
  ])('áudio %s sobe como %s', (tipo, nome) => {
    AutonomiaGuideAPI.transcrever(new Blob(['a'], { type: tipo }));

    expect(post.mock.calls[0][0]).toContain('/transcricao');
    expect(nomeEnviado()).toBe(nome);
  });
});
