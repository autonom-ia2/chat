import { mount, flushPromises } from '@vue/test-utils';
import GuideVoz from '../GuideVoz.vue';

// #895 — o player de voz do Guia: 44px, barra por teclado, velocidade e um
// áudio por vez. O jsdom não toca áudio: play/pause são espiões.
const montar = (props = {}) =>
  mount(GuideVoz, {
    props: { src: 'blob:voz', duracao: 12, ...props },
    attachTo: document.body,
    global: {
      mocks: {
        $t: (key, valores) => {
          if (key === 'AUTONOMIA_GUIDE.VOICE.TIME') {
            return `${valores.atual} / ${valores.total}`;
          }
          return valores ? `${key}:${JSON.stringify(valores)}` : key;
        },
      },
    },
  });

const botao = (wrapper, chave) => wrapper.find(`button[aria-label="${chave}"]`);
const barra = wrapper => wrapper.find('input[type="range"]');
const velocidade = wrapper => wrapper.findAll('button').at(-1);

describe('GuideVoz', () => {
  let play;
  let pause;
  const montados = [];
  const novo = props => {
    const wrapper = montar(props);
    montados.push(wrapper);
    return wrapper;
  };

  beforeEach(() => {
    play = vi
      .spyOn(HTMLMediaElement.prototype, 'play')
      .mockImplementation(() => Promise.resolve());
    pause = vi
      .spyOn(HTMLMediaElement.prototype, 'pause')
      .mockImplementation(() => {});
  });

  afterEach(() => {
    montados.splice(0).forEach(wrapper => wrapper.unmount());
    vi.restoreAllMocks();
  });

  it('mostra o tempo decorrido e o total, com a duração da gravação', () => {
    const wrapper = novo();

    expect(wrapper.text()).toContain('0:00 / 0:12');
    expect(barra(wrapper).attributes('max')).toBe('12');
  });

  it('o play redondo toca e vira pausa', async () => {
    const wrapper = novo();

    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.PLAY').trigger('click');
    await flushPromises();

    expect(play).toHaveBeenCalledOnce();
    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.PAUSE').trigger('click');
    expect(pause).toHaveBeenCalled();
    expect(botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.PLAY').exists()).toBe(true);
  });

  it('um áudio por vez: tocar outro pausa o primeiro', async () => {
    const primeiro = novo();
    const segundo = novo();

    await botao(primeiro, 'AUTONOMIA_GUIDE.VOICE.PLAY').trigger('click');
    await flushPromises();
    await botao(segundo, 'AUTONOMIA_GUIDE.VOICE.PLAY').trigger('click');
    await flushPromises();

    expect(botao(primeiro, 'AUTONOMIA_GUIDE.VOICE.PLAY').exists()).toBe(true);
    expect(botao(segundo, 'AUTONOMIA_GUIDE.VOICE.PAUSE').exists()).toBe(true);
  });

  it('a barra é um slider com nome e valor falado', () => {
    const wrapper = novo();

    expect(barra(wrapper).attributes('aria-label')).toBe(
      'AUTONOMIA_GUIDE.VOICE.POSITION'
    );
    expect(barra(wrapper).attributes('aria-valuetext')).toBe(
      'AUTONOMIA_GUIDE.VOICE.POSITION_VALUE:{"atual":"0:00","total":"0:12"}'
    );
  });

  it('tocar ou arrastar a barra leva o áudio até aquele ponto', async () => {
    const wrapper = novo();
    const audio = wrapper.find('audio').element;

    await barra(wrapper).setValue(7);

    expect(audio.currentTime).toBe(7);
    expect(wrapper.text()).toContain('0:07 / 0:12');
  });

  it('as setas andam 5 segundos, sem passar do começo nem do fim', async () => {
    const wrapper = novo();
    const audio = wrapper.find('audio').element;

    await barra(wrapper).trigger('keydown', { key: 'ArrowRight' });
    expect(audio.currentTime).toBe(5);
    await barra(wrapper).trigger('keydown', { key: 'ArrowRight' });
    await barra(wrapper).trigger('keydown', { key: 'ArrowRight' });
    expect(audio.currentTime).toBe(12);
    await barra(wrapper).trigger('keydown', { key: 'ArrowLeft' });
    expect(audio.currentTime).toBe(7);
    expect(barra(wrapper).attributes('aria-valuetext')).toContain('0:07');
  });

  it('a velocidade alterna 1× → 1,5× → 2× → 1×, como no WhatsApp', async () => {
    const wrapper = novo();
    const audio = wrapper.find('audio').element;

    expect(velocidade(wrapper).text()).toContain('SPEED_1');
    await velocidade(wrapper).trigger('click');
    expect(velocidade(wrapper).text()).toContain('SPEED_1_5');
    expect(audio.playbackRate).toBe(1.5);
    await velocidade(wrapper).trigger('click');
    expect(velocidade(wrapper).text()).toContain('SPEED_2');
    expect(audio.playbackRate).toBe(2);
    await velocidade(wrapper).trigger('click');
    expect(audio.playbackRate).toBe(1);
  });

  it('usa a duração do arquivo quando o navegador a conhece', async () => {
    const wrapper = novo({ duracao: 3 });
    const audio = wrapper.find('audio').element;
    Object.defineProperty(audio, 'duration', { value: 65, configurable: true });

    await wrapper.find('audio').trigger('loadedmetadata');

    expect(wrapper.text()).toContain('0:00 / 1:05');
  });

  it('ignora a duração "infinita" de áudio gravado e fica com a medida', async () => {
    const wrapper = novo({ duracao: 9 });
    const audio = wrapper.find('audio').element;
    Object.defineProperty(audio, 'duration', {
      value: Infinity,
      configurable: true,
    });

    await wrapper.find('audio').trigger('loadedmetadata');

    expect(wrapper.text()).toContain('0:00 / 0:09');
  });

  it('ao terminar, volta ao começo e ao play', async () => {
    const wrapper = novo();
    await botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.PLAY').trigger('click');
    await flushPromises();

    await wrapper.find('audio').trigger('ended');

    expect(botao(wrapper, 'AUTONOMIA_GUIDE.VOICE.PLAY').exists()).toBe(true);
    expect(wrapper.text()).toContain('0:00 / 0:12');
  });
});
