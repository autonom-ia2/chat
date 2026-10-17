import { mount } from '@vue/test-utils';
import { computed, defineComponent, h, nextTick, reactive, ref } from 'vue';
import { hasPermissions } from 'dashboard/helper/permissionsHelper';
import { routes as rotasDoInicio } from 'dashboard/routes/dashboard/settings/inicio/inicio.routes';
import ForkSidebarNav from '../fork/ForkSidebarNav.vue';

// Menu lateral novo (#1617): item da tela aberta marcado, gaveta do celular com foco preso e Esc,
// e Configurações para quem só cuida da IA do CRM.

const rota = reactive({
  path: '/crm_kanban_index',
  name: 'crm_kanban_index',
  fullPath: '/crm_kanban_index',
  params: {},
});
const estado = { chaves: ['administrator'] };
const larguras = vi.hoisted(() => ({ salva: 240, atual: null }));

// Permissão de cada tela; settings_inicio vem da rota real.
const META = {
  settings_inicio: rotasDoInicio[0].meta.permissions,
  crm_kanban_index: ['administrator', 'agent'],
  home: ['administrator', 'agent'],
  conversation_mentions: ['administrator', 'agent'],
  central_de_ajuda: ['administrator', 'agent', 'crm_manage_ai'],
  crm_handoff_settings_index: ['administrator', 'crm_manage_ai'],
  crm_calendar_index: ['administrator', 'agent'],
  settings_booking: ['administrator', 'agent'],
  agent_reports_index: ['administrator', 'agent'],
  conversation_reports: ['administrator', 'agent'],
};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: {} }) }));
vi.mock('dashboard/composables/store', async () => {
  const { ref: valor } = await import('vue');
  return { useMapGetter: () => valor(false) };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name, params: {} }) }),
}));
vi.mock('dashboard/composables/useBrandedSidebar', () => ({
  useBrandedSidebar: () => ({ brandedColor: ref('') }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ sidebar_width: larguras.salva }),
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useOnboardingTrail', () => ({
  useOnboardingTrail: () => {
    const passos = ref([]);
    return {
      passos,
      total: computed(() => 0),
      carregar: vi.fn(),
    };
  },
}));
vi.mock('../provider', async () => {
  const { ref: valor } = await import('vue');
  return {
    useSidebarContext: () => {
      larguras.atual = valor(larguras.salva);
      return {
        isAllowed: to => hasPermissions(META[to.name] || [], estado.chaves),
        resolvePath: to => `/${to.name}`,
        isCollapsed: valor(false),
        sidebarWidth: larguras.atual,
      };
    },
    usePopoverState: () => ({}),
  };
});

// RouterLink de mentira: `custom` entrega href e navigate ao slot, como o de verdade.
const RouterLink = defineComponent({
  props: { to: { type: Object, required: true }, custom: Boolean },
  setup(props, { slots, attrs }) {
    return () =>
      props.custom
        ? slots.default({ href: `/${props.to.name}`, navigate: () => {} })
        : h('a', { ...attrs, href: `/${props.to.name}` }, slots.default?.());
  },
});

const folha = (name, rotaDaFolha) => ({
  name,
  label: name,
  to: { name: rotaDaFolha },
});
const ITENS = [
  {
    name: 'Conversation',
    label: 'Conversas',
    icon: 'i-lucide-message-circle',
    children: [
      folha('All', 'home'),
      folha('Mentions', 'conversation_mentions'),
    ],
  },
  {
    name: 'CRM',
    label: 'CRM',
    icon: 'i-lucide-kanban-square',
    children: [
      folha('CRM Kanban', 'crm_kanban_index'),
      {
        name: 'CRM Scheduling',
        label: 'Agendamento',
        children: [
          folha('CRM Calendar', 'crm_calendar_index'),
          folha('CRM Booking', 'settings_booking'),
        ],
      },
    ],
  },
  {
    name: 'Reports',
    label: 'Relatórios',
    icon: 'i-lucide-chart-spline',
    children: [
      folha('Report Overview', 'agent_reports_index'),
      folha('Report Conversation', 'conversation_reports'),
    ],
  },
  { ...folha('CentralDeAjuda', 'central_de_ajuda'), icon: 'i-lucide-x' },
  {
    name: 'Settings',
    label: 'Configurações',
    children: [folha('Settings CRM Handoff', 'crm_handoff_settings_index')],
  },
];

const montar = () => {
  const fechar = vi.fn();
  const gaveta = ref(false);
  const wrapper = mount(
    defineComponent({
      setup: () => () =>
        h('aside', [
          h(ForkSidebarNav, {
            itens: ITENS,
            onFechar: fechar,
            gavetaAberta: gaveta.value,
          }),
        ]),
    }),
    {
      attachTo: document.body,
      global: { components: { RouterLink }, stubs: { transition: true } },
    }
  );
  return { wrapper, fechar, gaveta };
};

describe('ForkSidebarNav', () => {
  afterEach(() => {
    document.body.innerHTML = '';
    estado.chaves = ['administrator'];
  });

  it('marca só a tela aberta com aria-current e mostra os grupos do layout', () => {
    const { wrapper } = montar();
    const marcados = wrapper.findAll('[aria-current="page"]');
    expect(marcados).toHaveLength(1);
    expect(marcados[0].attributes('data-menu-item')).toBe('CRM');
    expect(wrapper.findAll('h2').map(titulo => titulo.text())).toEqual([
      'FORK_SIDEBAR.GRUPOS.ATENDER',
      'FORK_SIDEBAR.GRUPOS.ACOMPANHAR',
      'FORK_SIDEBAR.GRUPOS.RESULTADOS',
    ]);
  });

  it('gaveta do celular: Esc fecha, e o Tab no último volta ao primeiro', async () => {
    const { fechar, gaveta } = montar();
    gaveta.value = true;
    await nextTick();
    await nextTick();

    const focaveis = [
      ...document.querySelectorAll('aside a[href], aside button'),
    ];
    expect(document.activeElement).toBe(focaveis[0]);
    expect(focaveis[0].hasAttribute('data-fechar-gaveta')).toBe(true);

    focaveis.at(-1).focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Tab', bubbles: true })
    );
    expect(document.activeElement).toBe(focaveis[0]);

    focaveis[0].focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey: true,
        bubbles: true,
      })
    );
    expect(document.activeElement).toBe(focaveis.at(-1));

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(fechar).toHaveBeenCalledTimes(1);
  });

  it('gaveta fechada: Esc não faz nada', () => {
    const { fechar } = montar();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(fechar).not.toHaveBeenCalled();
  });

  it('função só com crm_manage_ai continua vendo Configurações no rodapé', () => {
    estado.chaves = ['crm_manage_ai'];
    rota.path = '/central_de_ajuda';
    rota.name = 'central_de_ajuda';
    const { wrapper } = montar();
    const rodape = wrapper.find('[data-menu-rodape]');
    expect(
      rodape
        .findAll('[data-menu-item]')
        .map(item => item.attributes('data-menu-item'))
    ).toEqual(['CentralDeAjuda', 'Settings']);
    rota.path = '/crm_kanban_index';
    rota.name = 'crm_kanban_index';
  });

  it('largura: 256px sem escolha ou com os 200px do upstream; a escolhida pela pessoa fica', () => {
    larguras.salva = 200;
    montar();
    expect(larguras.atual.value).toBe(256);
    larguras.salva = 300;
    montar();
    expect(larguras.atual.value).toBe(300);
    larguras.salva = 240;
  });

  describe('abrir e fechar grupo (#1661: nascem fechados, abrem só no clique)', () => {
    const irPara = async nome => {
      rota.path = `/${nome}`;
      rota.name = nome;
      rota.fullPath = `/${nome}`;
      await nextTick();
      await nextTick();
    };
    const botao = (wrapper, nome) =>
      wrapper.find(`button[data-menu-item="${nome}"]`);
    const aberto = (wrapper, nome) =>
      botao(wrapper, nome).attributes('aria-expanded');

    afterEach(async () => {
      await irPara('crm_kanban_index');
    });

    it('(a)(e) o grupo da tela atual nasce FECHADO e realçado; clicar abre e clicar de novo fecha (#1661)', async () => {
      await irPara('home');
      const { wrapper } = montar();
      await nextTick();
      expect(aberto(wrapper, 'Conversation')).toBe('false');
      expect(botao(wrapper, 'Conversation').classes()).toContain(
        'bg-n-blue-3/70'
      );
      await botao(wrapper, 'Conversation').trigger('click');
      expect(aberto(wrapper, 'Conversation')).toBe('true');
      await botao(wrapper, 'Conversation').trigger('click');
      expect(aberto(wrapper, 'Conversation')).toBe('false');
    });

    it('(b) navegar para outra tela do mesmo grupo não abre sozinho', async () => {
      await irPara('home');
      const { wrapper } = montar();
      await nextTick();
      await irPara('conversation_mentions');
      expect(aberto(wrapper, 'Conversation')).toBe('false');
    });

    it('(c) um aberto por vez: abrir outro grupo fecha o anterior', async () => {
      await irPara('home');
      const { wrapper } = montar();
      await nextTick();
      await botao(wrapper, 'Conversation').trigger('click');
      await botao(wrapper, 'Reports').trigger('click');
      expect(aberto(wrapper, 'Reports')).toBe('true');
      expect(aberto(wrapper, 'Conversation')).toBe('false');
    });

    it('(d) Agenda continua fechada na tela filha até o clique', async () => {
      await irPara('crm_calendar_index');
      const { wrapper } = montar();
      await nextTick();
      expect(aberto(wrapper, 'Agenda')).toBe('false');
      await botao(wrapper, 'Agenda').trigger('click');
      expect(aberto(wrapper, 'Agenda')).toBe('true');
    });
  });
});

// #1781: o menu não rola sozinho na troca de tela, e a borda avisa quando há itens fora da área visível.
describe('ForkSidebarNav: rolagem (#1781)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  const medidas = (el, { topo, altura = 400, total = 1000 }) => {
    Object.defineProperty(el, 'clientHeight', {
      value: altura,
      configurable: true,
    });
    Object.defineProperty(el, 'scrollHeight', {
      value: total,
      configurable: true,
    });
    el.scrollTop = topo;
    el.dispatchEvent(new Event('scroll'));
  };

  it('trocar de tela não rola o menu', async () => {
    const rolar = vi.fn();
    Element.prototype.scrollIntoView = rolar;
    montar();
    rota.name = 'crm_calendar_index';
    rota.fullPath = '/crm_calendar_index';
    await nextTick();
    await nextTick();
    expect(rolar).not.toHaveBeenCalled();
    rota.name = 'crm_kanban_index';
    rota.fullPath = '/crm_kanban_index';
    delete Element.prototype.scrollIntoView;
  });

  it('setas e esmaecido aparecem e somem conforme a rolagem; clicar rola uma tela', async () => {
    const { wrapper } = montar();
    const nav = wrapper.find('nav').element;
    nav.scrollBy = vi.fn();
    const ver = seletor => wrapper.find(seletor).exists();

    medidas(nav, { topo: 0, total: 400 });
    await nextTick();
    expect(ver('[data-seta="acima"]') || ver('[data-seta="abaixo"]')).toBe(
      false
    );

    medidas(nav, { topo: 0 });
    await nextTick();
    expect(ver('[data-seta="acima"]')).toBe(false);
    expect(ver('[data-seta="abaixo"]')).toBe(true);
    expect(ver('[data-esmaecido-baixo]')).toBe(true);
    const baixo = wrapper.find('[data-seta="abaixo"]');
    expect(baixo.attributes('aria-label')).toBe('FORK_SIDEBAR.ROLAR_ABAIXO');
    expect(baixo.classes()).toContain('min-h-11');
    expect(baixo.text()).toBe('FORK_SIDEBAR.MAIS_ABAIXO');
    const esmaecido = wrapper.find('[data-esmaecido-baixo]');
    expect(esmaecido.attributes('aria-hidden')).toBe('true');
    expect(esmaecido.classes()).toContain('pointer-events-none');

    await baixo.trigger('click');
    expect(nav.scrollBy).toHaveBeenCalledWith({ top: 352, behavior: 'smooth' });

    medidas(nav, { topo: 300 });
    await nextTick();
    expect(ver('[data-seta="acima"]')).toBe(true);
    expect(ver('[data-seta="abaixo"]')).toBe(true);

    medidas(nav, { topo: 600 });
    await nextTick();
    expect(ver('[data-seta="acima"]')).toBe(true);
    expect(ver('[data-seta="abaixo"]')).toBe(false);
    expect(wrapper.find('[data-seta="acima"]').attributes('aria-label')).toBe(
      'FORK_SIDEBAR.ROLAR_ACIMA'
    );
    await wrapper.find('[data-seta="acima"]').trigger('click');
    expect(nav.scrollBy).toHaveBeenLastCalledWith({
      top: -352,
      behavior: 'smooth',
    });
  });
});
