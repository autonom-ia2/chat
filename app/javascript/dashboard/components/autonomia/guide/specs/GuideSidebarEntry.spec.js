import { nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import GuideSidebarEntry from '../GuideSidebarEntry.vue';

const disponivel = ref(true);
const uiSettingsRef = ref({ is_autonomia_guide_panel_open: false });
const updateUISettings = vi.fn(patch => {
  uiSettingsRef.value = { ...uiSettingsRef.value, ...patch };
});
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: uiSettingsRef, updateUISettings }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: disponivel.value }));
    }
    return ref(1);
  },
}));

const montar = (props = {}) =>
  mount(GuideSidebarEntry, {
    props,
    global: { mocks: { $t: key => key } },
  });
const intro = w => w.find('[data-guia-intro]');
const ponto = w => w.find('[data-guia-ponto]');

// #697 — entrada do Guia no pé da barra lateral (computador).
describe('GuideSidebarEntry', () => {
  beforeEach(() => {
    disponivel.value = true;
    uiSettingsRef.value = { is_autonomia_guide_panel_open: false };
    window.sessionStorage.clear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('não aparece quando a conta não tem o Guia', () => {
    disponivel.value = false;
    const wrapper = montar();
    expect(wrapper.find('[data-guia-abrir]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('mostra o rótulo com a barra aberta e só o ícone com ela recolhida', () => {
    const aberta = montar();
    expect(aberta.text()).toContain('AUTONOMIA_GUIDE.LAUNCHER_LABEL');
    aberta.unmount();

    const recolhida = montar({ isCollapsed: true });
    const botao = recolhida.get('[data-guia-abrir]');
    expect(botao.text()).not.toContain('AUTONOMIA_GUIDE.LAUNCHER_LABEL');
    expect(botao.attributes('aria-label')).toBe(
      'AUTONOMIA_GUIDE.LAUNCHER_LABEL'
    );
    recolhida.unmount();
  });

  it('na primeira vez mostra o balão e o ponto', () => {
    const wrapper = montar();
    expect(intro(wrapper).exists()).toBe(true);
    expect(ponto(wrapper).exists()).toBe(true);
    wrapper.unmount();
  });

  it('Entendi grava que viu e some; o ponto fica até abrir o Guia', async () => {
    const wrapper = montar();
    await wrapper.get('[data-guia-entendi]').trigger('click');
    expect(updateUISettings).toHaveBeenCalledWith({
      autonomia_guide_intro_seen: true,
    });
    expect(intro(wrapper).exists()).toBe(false);
    expect(ponto(wrapper).exists()).toBe(true);
    wrapper.unmount();
  });

  it('Depois esconde nesta sessão sem gravar nada', async () => {
    const wrapper = montar();
    await wrapper.get('[data-guia-depois]').trigger('click');
    expect(updateUISettings).not.toHaveBeenCalled();
    expect(intro(wrapper).exists()).toBe(false);
    wrapper.unmount();
    const deNovo = montar();
    expect(intro(deNovo).exists()).toBe(false);
    deNovo.unmount();
  });

  it('abrir o Guia apaga balão e ponto de vez e fecha os outros painéis', async () => {
    const wrapper = montar();
    await wrapper.get('[data-guia-abrir]').trigger('click');
    expect(updateUISettings).toHaveBeenCalledWith({
      is_autonomia_guide_panel_open: true,
      is_autonomia_copilot_panel_open: false,
      is_contact_sidebar_open: false,
      autonomia_guide_intro_seen: true,
      autonomia_guide_opened: true,
    });
    await nextTick();
    expect(intro(wrapper).exists()).toBe(false);
    expect(ponto(wrapper).exists()).toBe(false);
    expect(wrapper.get('[data-guia-abrir]').attributes('aria-expanded')).toBe(
      'true'
    );
    wrapper.unmount();
  });

  it('com o Guia aberto, clicar de novo fecha sem regravar as marcas', async () => {
    uiSettingsRef.value = {
      is_autonomia_guide_panel_open: true,
      autonomia_guide_intro_seen: true,
      autonomia_guide_opened: true,
    };
    const wrapper = montar();
    await wrapper.get('[data-guia-abrir]').trigger('click');
    expect(updateUISettings).toHaveBeenCalledWith({
      is_autonomia_guide_panel_open: false,
      is_autonomia_copilot_panel_open: false,
      is_contact_sidebar_open: false,
    });
    wrapper.unmount();
  });

  it('quando o painel fecha por fora, o foco volta para o botão', async () => {
    uiSettingsRef.value = {
      is_autonomia_guide_panel_open: true,
      autonomia_guide_opened: true,
    };
    const alvo = document.createElement('div');
    document.body.appendChild(alvo);
    const conectado = mount(GuideSidebarEntry, {
      attachTo: alvo,
      global: { mocks: { $t: key => key } },
    });

    uiSettingsRef.value = {
      ...uiSettingsRef.value,
      is_autonomia_guide_panel_open: false,
    };
    await nextTick();
    await nextTick();

    expect(document.activeElement).toBe(
      conectado.get('[data-guia-abrir]').element
    );
    conectado.unmount();
    alvo.remove();
  });

  it('quem já conhece o Guia não vê balão nem ponto', () => {
    uiSettingsRef.value = {
      is_autonomia_guide_panel_open: false,
      autonomia_guide_intro_seen: true,
      autonomia_guide_opened: true,
    };
    const wrapper = montar();
    expect(intro(wrapper).exists()).toBe(false);
    expect(ponto(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });
});
