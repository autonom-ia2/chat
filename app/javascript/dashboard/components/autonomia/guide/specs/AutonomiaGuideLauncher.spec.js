import { computed, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import {
  isFixedPanelOpen,
  useFixedPanelPresence,
} from 'dashboard/composables/useFixedPanelState';
import AutonomiaGuideLauncher from '../AutonomiaGuideLauncher.vue';
import { useOcuparCantoDaBolinha } from '../cantoDaBolinha';

const uiSettingsRef = ref({ is_autonomia_guide_panel_open: false });
const updateUISettings = vi.fn(patch => {
  uiSettingsRef.value = { ...uiSettingsRef.value, ...patch };
});
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: uiSettingsRef,
    updateUISettings,
  }),
}));
const rota = { name: 'home', meta: {}, query: {} };
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    if (getter === 'accounts/isFeatureEnabledonAccount') {
      return ref(() => false);
    }
    return ref(1); // getCurrentAccountId
  },
}));

// Um painel fixo qualquer (a própria gaveta do card, CardGaveta, entre outros) chamaria
// `useFixedPanelPresence` assim; um componente hospedeiro descartável evita
// depender da CardGaveta real (com seu próprio store/API) só para este teste.
const PainelFixo = {
  props: { aberto: { type: Boolean, default: false } },
  setup(props) {
    useFixedPanelPresence(computed(() => props.aberto));
    return () => null;
  },
};

const TelaComEnviar = {
  props: { ocupado: { type: Object, required: true } },
  setup(props) {
    useOcuparCantoDaBolinha(props.ocupado);
    return () => null;
  },
};

const mountLauncher = (opcoes = {}) =>
  mount(AutonomiaGuideLauncher, {
    global: { mocks: { $t: key => key } },
    ...opcoes,
  });

describe('AutonomiaGuideLauncher', () => {
  beforeEach(() => {
    uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
    window.sessionStorage.clear();
    Object.assign(rota, { name: 'home', meta: {}, query: {} });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('sits at the default corner offset when no fixed panel is open', () => {
    const wrapper = mountLauncher();

    expect(wrapper.find('.fixed').classes()).toContain('bottom-4');
    expect(wrapper.find('.fixed').classes()).not.toContain('bottom-24');

    wrapper.unmount();
  });

  // #646 — a gaveta do card do CRM (CardGaveta) ocupa o mesmo canto; o
  // lançador precisa subir para não cobrir o rodapé Cancelar/Salvar dela.
  it('rises above the footer while a fixed panel is open', async () => {
    const launcher = mountLauncher();
    const painel = mount(PainelFixo, { props: { aberto: true } });
    await nextTick();

    expect(isFixedPanelOpen.value).toBe(true);
    expect(launcher.find('.fixed').classes()).toContain('bottom-24');
    expect(launcher.find('.fixed').classes()).not.toContain('bottom-4');

    launcher.unmount();
    painel.unmount();
  });

  it('returns to the default offset once the fixed panel closes', async () => {
    const launcher = mountLauncher();
    const painel = mount(PainelFixo, { props: { aberto: true } });
    await nextTick();
    expect(launcher.find('.fixed').classes()).toContain('bottom-24');

    await painel.setProps({ aberto: false });
    await nextTick();

    expect(isFixedPanelOpen.value).toBe(false);
    expect(launcher.find('.fixed').classes()).toContain('bottom-4');

    launcher.unmount();
    painel.unmount();
  });

  // Dois painéis podem se sobrepor (ex.: um abre por cima do outro); fechar
  // só um não pode apagar o sinal de que o outro ainda está aberto.
  it('stays raised while a second fixed panel is still open', async () => {
    const launcher = mountLauncher();
    const painelA = mount(PainelFixo, { props: { aberto: true } });
    const painelB = mount(PainelFixo, { props: { aberto: true } });
    await nextTick();

    await painelA.setProps({ aberto: false });
    await nextTick();

    expect(isFixedPanelOpen.value).toBe(true);
    expect(launcher.find('.fixed').classes()).toContain('bottom-24');

    launcher.unmount();
    painelA.unmount();
    painelB.unmount();
  });

  // #697 — no computador a entrada é a da barra lateral; aqui fica só a bolinha do celular.
  describe('bolinha do celular', () => {
    it('só aparece em tela pequena', () => {
      const wrapper = mountLauncher();
      expect(wrapper.find('.fixed').classes()).toContain('md:hidden');
      wrapper.unmount();
    });

    it('tem nome acessível e nenhum balão', () => {
      const wrapper = mountLauncher();
      expect(wrapper.get('[data-guia-abrir]').attributes('aria-label')).toBe(
        'AUTONOMIA_GUIDE.LAUNCHER_LABEL'
      );
      expect(wrapper.find('[data-guia-intro]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('mostra o ponto até a primeira abertura', () => {
      const wrapper = mountLauncher();
      expect(wrapper.find('[data-guia-ponto]').exists()).toBe(true);
      wrapper.unmount();
      uiSettingsRef.value = {
        is_autonomia_guide_panel_open: false,
        autonomia_guide_opened: true,
      };
      const depois = mountLauncher();
      expect(depois.find('[data-guia-ponto]').exists()).toBe(false);
      depois.unmount();
    });

    // #3192 — no celular a bolinha cobria o botão de enviar.
    it('some na conversa aberta', () => {
      rota.name = 'inbox_conversation';
      const wrapper = mountLauncher();
      expect(wrapper.find('[data-guia-abrir]').exists()).toBe(false);
      wrapper.unmount();
    });

    it('some enquanto uma tela avisa que o canto é dela (criação de agente)', async () => {
      const wrapper = mountLauncher();
      const ocupado = ref(true);
      const tela = mount(TelaComEnviar, { props: { ocupado } });
      await nextTick();
      expect(wrapper.find('[data-guia-abrir]').exists()).toBe(false);

      tela.unmount();
      await nextTick();
      expect(wrapper.find('[data-guia-abrir]').exists()).toBe(true);
      wrapper.unmount();
    });

    // A bolinha volta ao sair da tela, com o painel fechado: o foco fica onde
    // a pessoa estava.
    it('voltar a aparecer por troca de tela não rouba o foco', async () => {
      const outro = document.createElement('button');
      document.body.appendChild(outro);
      const tela = mount(TelaComEnviar, { props: { ocupado: ref(true) } });
      const wrapper = mountLauncher({ attachTo: document.body });
      outro.focus();

      tela.unmount();
      await nextTick();
      await nextTick();
      expect(wrapper.find('[data-guia-abrir]').exists()).toBe(true);
      expect(document.activeElement).toBe(outro);
      wrapper.unmount();
      outro.remove();
    });

    it('fechar o painel devolve o foco à bolinha', async () => {
      uiSettingsRef.value = { is_autonomia_guide_panel_open: true };
      const wrapper = mountLauncher({ attachTo: document.body });
      uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
      await nextTick();
      await nextTick();
      expect(document.activeElement).toBe(
        wrapper.get('[data-guia-abrir]').element
      );
      wrapper.unmount();
    });

    it('abrir o Guia grava que a pessoa já conhece', async () => {
      const wrapper = mountLauncher();
      await wrapper.get('[data-guia-abrir]').trigger('click');
      expect(updateUISettings).toHaveBeenCalledWith(
        expect.objectContaining({
          is_autonomia_guide_panel_open: true,
          autonomia_guide_intro_seen: true,
          autonomia_guide_opened: true,
        })
      );
      wrapper.unmount();
    });
  });
});
