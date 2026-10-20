import { ref, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import JanelaDeEmojis from '../JanelaDeEmojis.vue';

// #1895 — a janela abre de dentro do popover da Nova conversa, mas vai para o body.
// Escolher um emoji ou apertar Esc nela não pode fechar a Nova conversa por baixo.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave, locale: ref('en') }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('@vueuse/core', async original => ({
  ...(await original()),
  useBreakpoints: () => ({ smaller: () => ref(false) }),
}));

const janela = () => document.querySelector('[data-janela-de-emojis]');

describe('JanelaDeEmojis dentro do popover', () => {
  let wrapper;

  beforeEach(async () => {
    wrapper = mount(Popover, {
      slots: {
        default: '<button data-test="abrir">Nova</button>',
        content: () => h(JanelaDeEmojis),
      },
      global: { stubs: { Icon: true } },
      attachTo: document.body,
    });
    await wrapper.find('[data-test="abrir"]').trigger('click');
    await flushPromises();
  });

  afterEach(() => {
    wrapper.unmount();
    document.body.innerHTML = '';
  });

  it('fica por cima do popover e se marca como sobreposta', () => {
    expect(janela()).not.toBeNull();
    expect(janela().hasAttribute('data-popover-content')).toBe(true);
    expect(janela().className).toContain('z-[10000]');
  });

  it('clicar num emoji não fecha o popover', async () => {
    const emoji = janela().querySelector('.grid button');
    emoji.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    emoji.click();
    await flushPromises();

    expect(wrapper.emitted('hide')).toBeUndefined();
  });

  it('Esc na busca da janela não fecha o popover', async () => {
    const campo = janela().querySelector('[data-buscar-emoji]');
    campo.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    await flushPromises();

    expect(wrapper.emitted('hide')).toBeUndefined();
  });
});
