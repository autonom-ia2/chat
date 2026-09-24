import { computed, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import {
  isFixedPanelOpen,
  useFixedPanelPresence,
} from 'dashboard/composables/useFixedPanelState';
import AutonomiaGuideLauncher from '../AutonomiaGuideLauncher.vue';

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
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    return ref(1); // getCurrentAccountId
  },
}));

// Um painel fixo qualquer (a própria CrmCardDrawer, entre outros) chamaria
// `useFixedPanelPresence` assim; um componente hospedeiro descartável evita
// depender da CrmCardDrawer real (com seu próprio store/API) só para este teste.
const PainelFixo = {
  props: { aberto: { type: Boolean, default: false } },
  setup(props) {
    useFixedPanelPresence(computed(() => props.aberto));
    return () => null;
  },
};

const mountLauncher = () =>
  mount(AutonomiaGuideLauncher, {
    global: { mocks: { $t: key => key } },
  });

describe('AutonomiaGuideLauncher', () => {
  beforeEach(() => {
    uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
    window.sessionStorage.clear();
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

  // #646 — a gaveta do card do CRM (CrmCardDrawer) ocupa o mesmo canto; o
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
