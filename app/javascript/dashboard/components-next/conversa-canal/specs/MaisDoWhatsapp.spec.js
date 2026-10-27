import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import MaisDoWhatsapp from '../mais/MaisDoWhatsapp.vue';

const CLOUD = {
  id: 1,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
};

const montar = ({ conversa = {}, soArquivos = false } = {}) => {
  const store = createStore({
    getters: {
      getSelectedChat: () => conversa,
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => () => false,
    },
  });
  const i18n = createI18n({ legacy: false, locale: 'en', missingWarn: false });
  return mount(MaisDoWhatsapp, {
    props: { caixa: CLOUD, enviar: vi.fn(), soArquivos },
    global: {
      plugins: [store, i18n],
      stubs: { JanelaDoMais: true, Icon: true },
    },
  });
};

const abrirMenu = async wrapper => {
  await wrapper.find('[data-mais-do-whatsapp]').trigger('click');
};

const escolherArquivo = async (wrapper, item, arquivo) => {
  const seletor = wrapper.find(`[data-seletor="${item}"]`);
  const clicar = vi.spyOn(seletor.element, 'click');
  await abrirMenu(wrapper);
  await wrapper.find(`[data-item="${item}"]`).trigger('click');
  expect(clicar).toHaveBeenCalledTimes(1);
  Object.defineProperty(seletor.element, 'files', { value: [arquivo] });
  await seletor.trigger('change');
  return seletor;
};

describe('MaisDoWhatsapp: Documento e Fotos e vídeos (#1702)', () => {
  const foto = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });

  it('Fotos e vídeos tem seletor próprio só com foto e vídeo e manda como mídia', async () => {
    const wrapper = montar();
    const seletor = await escolherArquivo(wrapper, 'fotos_e_videos', foto);
    expect(seletor.attributes('accept')).toBe('image/*,video/*');
    expect(wrapper.emitted('arquivos')).toEqual([
      [{ arquivos: [foto], comoDocumento: false }],
    ]);
  });

  it('Documento tem seletor sem filtro e manda qualquer arquivo como documento', async () => {
    const wrapper = montar();
    const seletor = await escolherArquivo(wrapper, 'documento', foto);
    expect(seletor.attributes('accept')).toBeUndefined();
    expect(seletor.attributes('multiple')).toBeDefined();
    expect(wrapper.emitted('arquivos')).toEqual([
      [{ arquivos: [foto], comoDocumento: true }],
    ]);
  });

  it('o "+" não mexe no campo de anexo do Chatwoot', async () => {
    const campo = document.createElement('input');
    campo.id = 'conversationAttachment';
    campo.setAttribute('accept', 'image/*,audio/*,.pdf');
    document.body.appendChild(campo);
    await escolherArquivo(montar(), 'fotos_e_videos', foto);
    expect(campo.getAttribute('accept')).toBe('image/*,audio/*,.pdf');
    campo.remove();
  });

  it('antes de existir conversa (#2211), só Documento e Fotos e vídeos', async () => {
    const wrapper = montar({ soArquivos: true });
    await abrirMenu(wrapper);
    const itens = wrapper
      .findAll('[data-item]')
      .map(item => item.attributes('data-item'));
    expect(itens).toEqual(['documento', 'fotos_e_videos']);
  });

  it('no número reserva (só texto) Documento e Fotos e vídeos somem', async () => {
    const wrapper = montar({ conversa: { whatsapp_api_reply: true } });
    await abrirMenu(wrapper);
    expect(wrapper.find('[data-item="documento"]').exists()).toBe(false);
    expect(wrapper.find('[data-item="fotos_e_videos"]').exists()).toBe(false);
  });
});
