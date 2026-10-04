import { ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';

// #935 — a bolinha com o número de avisos novos (AC-I11): conta pela API e pelo
// ActionCable, mostra no botão do Guia e, ao abrir, traz os avisos para a conversa
// e marca como vistos. O estado dos avisos é do módulo, então cada teste importa
// tudo de novo (`vi.resetModules`).

const papel = ref('administrator');
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'getCurrentRole') return papel;
    if (getter === 'getCurrentAccountId') return ref(1);
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    return ref(() => true);
  },
}));
const uiSettings = ref({ is_autonomia_guide_panel_open: false });
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings: vi.fn() }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) => (params ? `${chave}:${params.count}` : chave),
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home', meta: {} }),
  useRouter: () => ({ resolve: () => ({ matched: [{}] }), push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/centralDeAjuda', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: { capitulos: [] } })) },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: {
    avisos: vi.fn(),
    marcarAviso: vi.fn(() => Promise.resolve({})),
    conversaAtual: vi.fn(() => Promise.resolve({ data: {} })),
    chat: vi.fn(),
    resposta: vi.fn(),
  },
}));

const turnoDeAviso = (id, texto) => ({
  pedido_id: `aviso-${id}`,
  pergunta: '',
  status: 'done',
  resposta: texto,
  navegacoes: [],
  artigos: [],
  aviso_id: id,
  criado_em: '2026-10-04T10:00:00Z',
});

const carregarModulos = async () => {
  vi.resetModules();
  const API = (await import('dashboard/api/autonomiaGuide')).default;
  const { emitter } = await import('shared/helpers/mitt');
  const { BUS_EVENTS } = await import('shared/constants/busEvents');
  const { useAvisosDoGuia } = await import('../useAvisosDoGuia');
  return { API, emitter, BUS_EVENTS, useAvisosDoGuia };
};

const comDoisNovos = API =>
  API.avisos.mockResolvedValue({
    data: { avisos: [{ id: 7 }, { id: 8 }], novos: 2 },
  });

describe('avisos do Guia', () => {
  beforeEach(() => {
    papel.value = 'administrator';
    uiSettings.value = { is_autonomia_guide_panel_open: false };
    vi.clearAllMocks();
  });

  describe('GuideDot', () => {
    it('sem número é o ponto; com número mostra a contagem, até 9+', async () => {
      const GuideDot = (await import('../GuideDot.vue')).default;

      expect(mount(GuideDot).find('[data-guia-numero]').exists()).toBe(false);
      expect(mount(GuideDot, { props: { numero: 2 } }).text()).toBe('2');
      expect(mount(GuideDot, { props: { numero: 12 } }).text()).toBe('9+');
    });
  });

  describe('useAvisosDoGuia', () => {
    it('o administrador recebe a contagem dos novos, uma busca só', async () => {
      const { API, useAvisosDoGuia } = await carregarModulos();
      comDoisNovos(API);
      const avisos = useAvisosDoGuia();

      await avisos.carregar();
      await avisos.carregar();

      expect(API.avisos).toHaveBeenCalledTimes(1);
      expect(API.avisos).toHaveBeenCalledWith('novo');
      expect(avisos.quantidade.value).toBe(2);
    });

    it('agente comum não busca aviso nenhum', async () => {
      papel.value = 'agent';
      const { API, useAvisosDoGuia } = await carregarModulos();
      const avisos = useAvisosDoGuia();

      await avisos.carregar();

      expect(API.avisos).not.toHaveBeenCalled();
      expect(avisos.quantidade.value).toBe(0);
    });

    it('o aviso que chega pelo ActionCable sobe o número sem recarregar', async () => {
      const { API, emitter, BUS_EVENTS, useAvisosDoGuia } =
        await carregarModulos();
      comDoisNovos(API);
      const avisos = useAvisosDoGuia();
      await avisos.carregar();

      emitter.emit(BUS_EVENTS.GUIDE_AVISO_CREATED, { id: 9, account_id: 1 });
      emitter.emit(BUS_EVENTS.GUIDE_AVISO_CREATED, { id: 9, account_id: 1 });

      expect(avisos.quantidade.value).toBe(3);
    });

    it('marcar como vistos zera e avisa o servidor de cada um', async () => {
      const { API, useAvisosDoGuia } = await carregarModulos();
      comDoisNovos(API);
      const avisos = useAvisosDoGuia();
      await avisos.carregar();

      await avisos.marcarVistos();

      expect(avisos.quantidade.value).toBe(0);
      expect(API.marcarAviso.mock.calls).toEqual([
        [7, 'visto'],
        [8, 'visto'],
      ]);
    });
  });

  describe('botão do Guia', () => {
    it('com 2 avisos novos, a bolinha mostra 2 e o nome do botão diz quantos', async () => {
      const { API } = await carregarModulos();
      comDoisNovos(API);
      const Launcher = (await import('../AutonomiaGuideLauncher.vue')).default;

      const wrapper = mount(Launcher, { global: { mocks: { $t: k => k } } });
      await flushPromises();

      expect(wrapper.get('[data-guia-numero]').text()).toBe('2');
      expect(wrapper.get('[data-guia-abrir]').attributes('aria-label')).toBe(
        'AUTONOMIA_GUIDE.AVISOS.LAUNCHER_LABEL:2'
      );
      wrapper.unmount();
    });

    it('na barra lateral também', async () => {
      const { API } = await carregarModulos();
      comDoisNovos(API);
      const Entrada = (await import('../GuideSidebarEntry.vue')).default;

      const wrapper = mount(Entrada, {
        global: {
          mocks: { $t: k => k },
          stubs: { TeleportWithDirection: true },
        },
      });
      await flushPromises();

      expect(wrapper.get('[data-guia-numero]').text()).toBe('2');
      expect(wrapper.get('[data-guia-abrir]').attributes('aria-label')).toBe(
        'AUTONOMIA_GUIDE.AVISOS.LAUNCHER_LABEL:2'
      );
      wrapper.unmount();
    });
  });

  describe('painel', () => {
    it('ao abrir, os 2 avisos aparecem como turnos do Guia e viram vistos', async () => {
      const { API, useAvisosDoGuia } = await carregarModulos();
      comDoisNovos(API);
      API.conversaAtual.mockResolvedValue({
        data: {
          id: 3,
          titulo: 'Avisos',
          turnos: [
            turnoDeAviso(7, 'Conexão caída: 1 agora.'),
            turnoDeAviso(8, 'Automação: 41 agora.'),
          ],
        },
      });
      const avisos = useAvisosDoGuia();
      await avisos.carregar();
      uiSettings.value = { is_autonomia_guide_panel_open: true };
      const Container = (await import('../AutonomiaGuideContainer.vue'))
        .default;

      const wrapper = mount(Container, {
        attachTo: document.body,
        global: {
          mocks: { $t: k => k },
          directives: { onClickOutside: {}, dompurifyHtml: {} },
        },
      });
      await flushPromises();
      await nextTick();

      expect(API.conversaAtual).toHaveBeenCalled();
      expect(wrapper.findAll('[data-aviso]')).toHaveLength(2);
      // O aviso é fala do Guia: nenhum balão de pergunta vazio.
      const { useAutonomiaGuideStore } = await import(
        'dashboard/store/modules/autonomiaGuide'
      );
      expect(
        useAutonomiaGuideStore().messages.map(m => [m.message_type, m.aviso])
      ).toEqual([
        ['assistant', { id: 7 }],
        ['assistant', { id: 8 }],
      ]);
      expect(API.marcarAviso).toHaveBeenCalledWith(7, 'visto');
      expect(API.marcarAviso).toHaveBeenCalledWith(8, 'visto');
      expect(avisos.quantidade.value).toBe(0);
      wrapper.unmount();
    });
  });
});
