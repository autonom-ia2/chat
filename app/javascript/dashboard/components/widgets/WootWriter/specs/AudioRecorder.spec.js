import { mount, flushPromises } from '@vue/test-utils';
import AudioRecorder from '../AudioRecorder.vue';

// O gravador falso guarda os ouvintes para o teste disparar o fim da gravação.
const ouvintes = {};
let carregar;
vi.mock('wavesurfer.js', () => ({
  default: {
    create: () => ({
      plugins: [
        {
          on: (evento, fn) => {
            ouvintes[evento] = fn;
          },
          startRecording: () => Promise.resolve(),
          stopRecording: vi.fn(),
          stopMic: vi.fn(),
        },
      ],
      on: vi.fn(),
      load: (...args) => carregar(...args),
      destroy: vi.fn(),
    }),
  },
}));
vi.mock('wavesurfer.js/dist/plugins/record.js', () => ({
  default: { create: () => ({}) },
}));
vi.mock('../utils/audioConversionUtils', () => ({
  convertAudio: blob => Promise.resolve(blob),
}));

const abortado = () =>
  new DOMException('signal is aborted without reason', 'AbortError');

describe('AudioRecorder', () => {
  beforeAll(() => {
    globalThis.MediaRecorder = { isTypeSupported: () => true };
    URL.createObjectURL = () => 'blob:audio';
    URL.revokeObjectURL = () => {};
  });

  // #1702: a seta do WhatsApp para e envia; o gravador fecha antes da prévia carregar.
  it('fechar durante o carregamento da prévia não deixa erro solto', async () => {
    const soltos = [];
    const pegar = motivo => soltos.push(motivo);
    process.on('unhandledRejection', pegar);
    let rejeitar;
    carregar = () =>
      new Promise((_, r) => {
        rejeitar = r;
      });

    const wrapper = mount(AudioRecorder, {
      props: { audioRecordFormat: 'audio/ogg' },
    });
    await ouvintes['record-end'](new Blob(['x'], { type: 'audio/ogg' }));
    expect(wrapper.emitted('finishRecord')).toHaveLength(1);

    wrapper.unmount();
    rejeitar(abortado());
    await flushPromises();
    await new Promise(r => {
      setTimeout(r, 0);
    });
    process.off('unhandledRejection', pegar);

    expect(soltos).toEqual([]);
  });

  it('falha do carregamento com o gravador aberto continua aparecendo', async () => {
    const falha = new Error('arquivo ruim');
    carregar = () => Promise.reject(falha);
    const soltos = [];
    const pegar = motivo => soltos.push(motivo);
    process.on('unhandledRejection', pegar);

    const wrapper = mount(AudioRecorder, {
      props: { audioRecordFormat: 'audio/ogg' },
    });
    await ouvintes['record-end'](new Blob(['x'], { type: 'audio/ogg' }));
    await flushPromises();
    await new Promise(r => {
      setTimeout(r, 0);
    });
    process.off('unhandledRejection', pegar);
    wrapper.unmount();

    expect(soltos).toEqual([falha]);
  });
});
