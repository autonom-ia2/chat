import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import MaisDoWhatsapp from '../mais/MaisDoWhatsapp.vue';

const CLOUD = {
  id: 1,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
};

const montar = ({ conversa = {} } = {}) => {
  const store = createStore({
    getters: { getSelectedChat: () => conversa },
  });
  const i18n = createI18n({ legacy: false, locale: 'en', missingWarn: false });
  return mount(MaisDoWhatsapp, {
    props: { caixa: CLOUD, enviar: vi.fn() },
    global: {
      plugins: [store, i18n],
      stubs: { JanelaDoMais: true, Icon: true },
    },
  });
};

const abrirMenu = async wrapper => {
  await wrapper.find('[data-mais-do-whatsapp]').trigger('click');
};

describe('MaisDoWhatsapp: Documento e Fotos e vídeos (#1702)', () => {
  it('Fotos e vídeos abre o seletor do anexo só com foto e vídeo', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);
    await wrapper.find('[data-item="fotos_e_videos"]').trigger('click');
    expect(wrapper.emitted('anexar')).toEqual([['image/*,video/*']]);
    expect(wrapper.emitted('documentos')).toBeUndefined();
  });

  it('Documento abre um seletor sem filtro e manda os arquivos como documento', async () => {
    const wrapper = montar();
    const seletor = wrapper.find('[data-seletor-de-documento]');
    expect(seletor.attributes('accept')).toBeUndefined();
    expect(seletor.attributes('multiple')).toBeDefined();
    const clicar = vi.spyOn(seletor.element, 'click');

    await abrirMenu(wrapper);
    await wrapper.find('[data-item="documento"]').trigger('click');
    expect(clicar).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('anexar')).toBeUndefined();

    const foto = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });
    Object.defineProperty(seletor.element, 'files', { value: [foto] });
    await seletor.trigger('change');
    expect(wrapper.emitted('documentos')).toEqual([[[foto]]]);
  });

  it('no número reserva (só texto) Documento e Fotos e vídeos somem', async () => {
    const wrapper = montar({ conversa: { whatsapp_api_reply: true } });
    await abrirMenu(wrapper);
    expect(wrapper.find('[data-item="documento"]').exists()).toBe(false);
    expect(wrapper.find('[data-item="fotos_e_videos"]').exists()).toBe(false);
  });
});
