import { nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import GuiaNoCabecalho from '../GuiaNoCabecalho.vue';

// #3192 — no celular, na conversa aberta, o Guia mora no cabeçalho.
const uiSettingsRef = ref({ is_autonomia_guide_panel_open: false });
const updateUISettings = vi.fn(patch => {
  uiSettingsRef.value = { ...uiSettingsRef.value, ...patch };
});
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: uiSettingsRef, updateUISettings }),
}));
const rota = { name: 'inbox_conversation', meta: {}, query: {} };
vi.mock('vue-router', () => ({ useRoute: () => rota }));
const disponivel = ref(true);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: disponivel.value }));
    }
    return ref(1);
  },
}));

const montar = (opcoes = {}) => mount(GuiaNoCabecalho, opcoes);

describe('GuiaNoCabecalho (#3192)', () => {
  beforeEach(() => {
    uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
    disponivel.value = true;
    rota.meta = {};
  });

  afterEach(() => vi.clearAllMocks());

  it('só aparece no celular, com o nome escrito', () => {
    const wrapper = montar();
    const caixa = wrapper.get('[data-guia-cabecalho]');
    expect(caixa.classes()).toContain('md:hidden');
    expect(caixa.text()).toContain('AUTONOMIA_GUIDE.CONVERSATION_BUTTON');
    expect(wrapper.get('button').attributes('aria-label')).toBe(
      'AUTONOMIA_GUIDE.LAUNCHER_LABEL'
    );
    wrapper.unmount();
  });

  it('abre o Guia', async () => {
    const wrapper = montar();
    await wrapper.get('button').trigger('click');
    expect(updateUISettings).toHaveBeenCalledWith(
      expect.objectContaining({ is_autonomia_guide_panel_open: true })
    );
    wrapper.unmount();
  });

  it('mostra o ponto até a primeira abertura', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-guia-ponto]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('não aparece sem Guia na conta nem com o painel aberto', () => {
    disponivel.value = false;
    const semGuia = montar();
    expect(semGuia.find('[data-guia-cabecalho]').exists()).toBe(false);
    semGuia.unmount();

    disponivel.value = true;
    uiSettingsRef.value = { is_autonomia_guide_panel_open: true };
    const aberto = montar();
    expect(aberto.find('[data-guia-cabecalho]').exists()).toBe(false);
    aberto.unmount();
  });

  it('voltar a aparecer sem o painel fechar não rouba o foco', async () => {
    disponivel.value = false;
    const outro = document.createElement('button');
    document.body.appendChild(outro);
    const wrapper = montar({ attachTo: document.body });
    outro.focus();

    disponivel.value = true;
    await nextTick();
    await nextTick();
    expect(wrapper.find('[data-guia-cabecalho]').exists()).toBe(true);
    expect(document.activeElement).toBe(outro);
    wrapper.unmount();
    outro.remove();
  });

  it('fechar o painel devolve o foco ao botão', async () => {
    uiSettingsRef.value = { is_autonomia_guide_panel_open: true };
    const wrapper = montar({ attachTo: document.body });
    uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
    await nextTick();
    await nextTick();
    expect(document.activeElement).toBe(wrapper.get('button').element);
    wrapper.unmount();
  });
});
