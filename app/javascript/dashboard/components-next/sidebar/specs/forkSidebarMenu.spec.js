import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import Sidebar from '../Sidebar.vue';
import {
  FILHOS_CONHECIDOS,
  acharAtivo,
  nomesCitadosNoLayout,
  nomesDoTopoConhecidos,
  organizeForkMenu,
} from '../forkSidebarMenu';

// Menu lateral novo (#1617): a camada do fork só reorganiza a lista do Sidebar.vue. Item novo do Chatwoot sem
// lugar cai em "Outros" e o teste avisa; item do layout que sumiu do upstream, idem.

const t = chave => chave;
const accountScopedRoute = (name, params) => ({ name, params });
const ctx = { t, accountScopedRoute };

const folha = (name, rota = name) => ({
  name,
  label: name,
  to: { name: rota },
});
const nomes = lista => lista.map(item => item.name);

describe('organizeForkMenu', () => {
  const upstream = [
    { ...folha('FirstSteps', 'first_steps'), icon: 'i-lucide-list-checks' },
    { ...folha('Inbox', 'inbox_view'), icon: 'i-lucide-inbox' },
    {
      name: 'Conversation',
      label: 'Conversas',
      children: [folha('All', 'home'), folha('Participating', 'part')],
    },
    { name: 'Captain', label: 'Capitão', children: [folha('Overview')] },
    folha('Calls', 'calls_dashboard_index'),
    folha('Automacoes', 'automacoes_lista'),
    folha('Agents', 'autonomia_agents_index'),
    {
      name: 'Insurance',
      label: 'Cotação',
      children: [
        folha('Insurance Connections', 'ins_a'),
        folha('Insurance Agent', 'ins_b'),
      ],
    },
    {
      name: 'CRM',
      label: 'CRM',
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
        folha('CRM Dashboard', 'crm_dashboard_index'),
        folha('CRM SLA', 'crm_sla_index'),
      ],
    },
    {
      name: 'Financial',
      label: 'Financeiro',
      children: [folha('Subscription', 'autonomia_financial_subscription')],
    },
    {
      name: 'Reports',
      label: 'Relatórios',
      children: [folha('Reports Agent', 'agent_reports_index')],
    },
    folha('Relationships', 'relationships_home'),
    folha('CentralDeAjuda', 'central_de_ajuda'),
    {
      name: 'Settings',
      label: 'Configurações',
      children: [
        folha('Settings Agents', 'agent_list'),
        folha('Settings Billing', 'billing_settings_index'),
      ],
    },
  ];

  it('organiza conforme o layout: grupos, ordem, nomes e filhos que mudam de lugar', () => {
    const menu = organizeForkMenu(upstream, ctx);

    expect(nomes(menu.topo)).toEqual(['FirstSteps']);
    expect(menu.grupos.map(grupo => grupo.id)).toEqual([
      'ATENDER',
      'ACOMPANHAR',
      'CRESCER',
      'AUTOMATICO',
      'RESULTADOS',
    ]);
    const [atender, acompanhar, crescer, automatico, resultados] = menu.grupos;
    expect(nomes(atender.itens)).toEqual([
      'Conversation',
      'Inbox',
      'Calls',
      'Prazos',
    ]);
    expect(atender.itens[1].label).toBe('FORK_SIDEBAR.ITENS.NOTIFICACOES');
    expect(atender.itens[0].children[1].label).toBe(
      'FORK_SIDEBAR.ITENS.EM_QUE_PARTICIPO'
    );
    expect(atender.itens[3]).toMatchObject({
      label: 'FORK_SIDEBAR.ITENS.PRAZOS',
      to: { name: 'crm_sla_index' },
    });

    // CRM fica só com o Kanban e vira link direto; a Agenda junta o agendamento.
    expect(nomes(acompanhar.itens)).toEqual(['Relationships', 'CRM', 'Agenda']);
    expect(acompanhar.itens[1]).toMatchObject({
      to: { name: 'crm_kanban_index' },
    });
    expect(acompanhar.itens[1].children).toBeUndefined();
    expect(nomes(acompanhar.itens[2].children)).toEqual([
      'CRM Calendar',
      'CRM Booking',
    ]);

    // Cotação sem as abas; Capitão e Financeiro fora do menu.
    expect(nomes(crescer.itens)).toEqual(['Insurance']);
    expect(crescer.itens[0]).toMatchObject({ to: { name: 'ins_a' } });
    expect(crescer.itens[0].children).toBeUndefined();
    expect(nomes(automatico.itens)).toEqual(['Agents', 'Automacoes']);
    expect(automatico.itens[0].label).toBe('FORK_SIDEBAR.ITENS.AGENTES');

    // Relatórios ganham Funis; "Agentes" do relatório vira "Usuários".
    expect(nomes(resultados.itens[0].children)).toEqual([
      'Reports Agent',
      'CRM Dashboard',
    ]);
    expect(resultados.itens[0].children[0].label).toBe(
      'FORK_SIDEBAR.ITENS.USUARIOS'
    );
    expect(resultados.itens[0].children[1].label).toBe(
      'FORK_SIDEBAR.ITENS.FUNIS'
    );

    // Rodapé: Ajuda e Configurações, que abre a página de cartões e fica marcada nas telas que viraram cartão.
    expect(nomes(menu.rodape)).toEqual(['CentralDeAjuda', 'Settings']);
    const configuracoes = menu.rodape[1];
    expect(configuracoes.to).toEqual({ name: 'settings_inicio' });
    expect(configuracoes.children).toBeUndefined();
    expect(configuracoes.activeOn).toEqual(
      expect.arrayContaining([
        'settings_inicio',
        'agent_list',
        'autonomia_financial_subscription',
      ])
    );
    expect(configuracoes.activeOn).not.toContain('billing_settings_index');

    const todos = menu.grupos.flatMap(grupo => nomes(grupo.itens));
    expect(todos).not.toContain('Captain');
    expect(todos).not.toContain('Financial');
    expect(menu.configuracoesExtras).toEqual([]);
  });

  it('item desconhecido do Chatwoot vai para "Outros" e configuração nova vira cartão extra', () => {
    const novo = folha('Chatwoot Novidade', 'novidade');
    const menu = organizeForkMenu(
      [
        ...upstream.filter(item => item.name !== 'Settings'),
        novo,
        {
          name: 'Settings',
          label: 'Configurações',
          children: [folha('Settings Agents'), folha('Settings Coisa Nova')],
        },
      ],
      ctx
    );
    const outros = menu.grupos.at(-1);
    expect(outros.id).toBe('OUTROS');
    expect(outros.label).toBe('FORK_SIDEBAR.GRUPOS.OUTROS');
    expect(nomes(outros.itens)).toEqual(['Chatwoot Novidade']);
    expect(nomes(menu.configuracoesExtras)).toEqual(['Settings Coisa Nova']);
  });

  it('trilha concluída tira Primeiros passos do topo', () => {
    const menu = organizeForkMenu(upstream, { ...ctx, trilhaConcluida: true });
    expect(menu.topo).toEqual([]);
  });

  it('sem o agendamento novo, a Agenda é o Calendário direto, e sem Relacionamentos chegam Contatos e Empresas', () => {
    const semAgendamento = upstream
      .filter(item => item.name !== 'Relationships')
      .map(item =>
        item.name === 'CRM'
          ? {
              ...item,
              children: [
                folha('CRM Kanban', 'crm_kanban_index'),
                folha('CRM Calendar', 'crm_calendar_index'),
              ],
            }
          : item
      );
    const menu = organizeForkMenu(
      [
        ...semAgendamento,
        {
          name: 'Contacts',
          label: 'Contatos',
          children: [folha('All Contacts')],
        },
        {
          name: 'Companies',
          label: 'Empresas',
          children: [folha('All Companies')],
        },
      ],
      ctx
    );
    const acompanhar = menu.grupos.find(grupo => grupo.id === 'ACOMPANHAR');
    expect(nomes(acompanhar.itens)).toEqual([
      'Contacts',
      'Companies',
      'CRM',
      'Agenda',
    ]);
    expect(acompanhar.itens[3]).toMatchObject({
      label: 'FORK_SIDEBAR.ITENS.AGENDA',
      to: { name: 'crm_calendar_index' },
    });
  });

  it('acharAtivo prefere o caminho igual e depois o activeOn', () => {
    const menu = organizeForkMenu(upstream, ctx);
    const itens = [
      ...menu.topo,
      ...menu.grupos.flatMap(g => g.itens),
      ...menu.rodape,
    ];
    const caminho = to => `/${to.name}`;
    expect(
      acharAtivo(
        itens,
        { path: '/crm_sla_index', name: 'crm_sla_index' },
        caminho
      ).item.name
    ).toBe('Prazos');
    expect(
      acharAtivo(itens, { path: '/x', name: 'agent_list' }, caminho).item.name
    ).toBe('Settings');
  });
});

// Monta o Sidebar.vue de verdade, com as flags ligadas em várias combinações, e lê a lista que ele entrega ao
// menu novo. Falha quando um `name` do upstream não tem lugar no layout, ou quando o layout cita um nome que
// não existe mais.
const getters = {};
const estado = { relacionamentos: false };

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ fullPath: '/', params: {} }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => getters[key] || ref(() => 0),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
    isOnChatwootCloud: ref(false),
  }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: true }),
}));
vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => ref(''),
}));
vi.mock('dashboard/composables/useBrandedSidebar', () => ({
  useBrandedSidebar: () => ({ brandedColor: ref('') }),
}));
vi.mock('dashboard/composables/useRelationships', async () => {
  const { computed } = await import('vue');
  return {
    useRelationships: () => ({
      navigationEnabled: computed(() => estado.relacionamentos),
    }),
  };
});
vi.mock('dashboard/composables/useScrollActiveItemIntoView', () => ({
  useScrollActiveItemIntoView: vi.fn(),
}));
vi.mock('../provider', async () => {
  const { ref: valor } = await import('vue');
  return {
    provideSidebarContext: vi.fn(),
    usePopoverState: () => ({}),
    useSidebarContext: () => ({}),
    useSidebarResize: () => ({
      sidebarWidth: valor(200),
      isCollapsed: valor(false),
      setSidebarWidth: vi.fn(),
      saveWidth: vi.fn(),
      snapToCollapsed: vi.fn(),
      snapToExpanded: vi.fn(),
    }),
  };
});
vi.mock('../useSidebarKeyboardShortcuts', () => ({
  useSidebarKeyboardShortcuts: vi.fn(),
}));

const montar = ({
  jornadas = true,
  agendamento = true,
  relacionamentos = false,
  papel = 'administrator',
  funcao = null,
  chaves = [],
}) => {
  estado.relacionamentos = relacionamentos;
  window.globalConfig = {
    CRM_CALENDAR_MEETINGS_ENABLED: agendamento ? 'true' : 'false',
  };
  Object.assign(getters, {
    'globalConfig/get': ref({
      crmKanbanEnabled: true,
      crmAiEnabled: true,
      autonomiaAgentsEnabled: true,
      emailCampaignEnabled: true,
      whatsappApiCampaignsEnabled: true,
      campaignJourneyEnabled: jornadas,
      campaignImportEnabled: true,
      insuranceQuotingEnabled: true,
    }),
    getCurrentAccountId: ref(9),
    getCurrentRole: ref(papel),
    getCurrentCustomRoleId: ref(funcao),
    getCurrentUser: ref({ accounts: [{ id: 9, permissions: chaves }] }),
    'accounts/getAccount': ref(() => ({
      id: 9,
      autonomia_agents_enabled: true,
      autonomia_prospecting_enabled: true,
      autonomia_insurance_enabled: true,
      features: { crm_booking_v2: agendamento },
    })),
    // Todas as flags de conta ligadas, menos a jornada dos agentes quando a variante pede o menu antigo.
    'accounts/isFeatureEnabledonAccount': ref(
      (_id, flag) => jornadas || flag !== 'autonomia_agents_journey'
    ),
    'inboxes/getInboxes': ref([]),
    'labels/getLabelsOnSidebar': ref([]),
    'teams/getMyTeams': ref([]),
    'customViews/getContactCustomViews': ref([]),
    'customViews/getConversationCustomViews': ref([]),
  });
  const wrapper = shallowMount(Sidebar, {
    global: { stubs: { RouterLink: true } },
  });
  return wrapper.findComponent({ name: 'ForkSidebarNav' }).props('itens');
};

const VARIANTES = [
  {},
  { jornadas: false },
  { agendamento: false },
  { relacionamentos: true },
  {
    papel: 'agent',
    funcao: 7,
    chaves: ['crm_manage_ai', 'crm_view', 'agendamento_view'],
  },
];

describe('camada do fork contra o Sidebar.vue de verdade', () => {
  afterEach(() => {
    delete window.globalConfig;
  });

  const listas = () => VARIANTES.map(montar);

  it('com a flag ligada, o Sidebar entrega a lista ao menu novo', () => {
    const itens = montar({});
    expect(itens.length).toBeGreaterThan(10);
  });

  it('todo item do topo do upstream tem lugar no layout', () => {
    const conhecidos = nomesDoTopoConhecidos();
    const semLugar = listas()
      .flatMap(lista => nomes(lista))
      .filter(nome => !conhecidos.includes(nome));
    expect([...new Set(semLugar)]).toEqual([]);
  });

  it('todo filho dos itens que a camada desmonta tem lugar no layout', () => {
    const semLugar = listas().flatMap(lista =>
      lista.flatMap(item => {
        const filhosDoItem = (item.children || []).flatMap(filho => [
          { pai: item.name, nome: filho.name },
          ...(filho.children && FILHOS_CONHECIDOS[filho.name]
            ? filho.children.map(neto => ({ pai: filho.name, nome: neto.name }))
            : []),
        ]);
        return filhosDoItem
          .filter(({ pai }) => FILHOS_CONHECIDOS[pai])
          .filter(({ pai, nome }) => !FILHOS_CONHECIDOS[pai].includes(nome))
          .map(({ pai, nome }) => `${pai} › ${nome}`);
      })
    );
    expect([...new Set(semLugar)]).toEqual([]);
  });

  it('todo nome citado no layout ainda existe no upstream', () => {
    const existentes = new Set(
      listas().flatMap(lista =>
        lista.flatMap(item => [
          item.name,
          ...(item.children || []).flatMap(filho => [
            filho.name,
            ...(filho.children || []).map(neto => neto.name),
          ]),
        ])
      )
    );
    const sumiram = [
      ...nomesCitadosNoLayout(),
      ...Object.values(FILHOS_CONHECIDOS).flat(),
    ].filter(nome => !existentes.has(nome));
    expect([...new Set(sumiram)]).toEqual([]);
  });

  it('com a flag desligada, o menu de sempre continua', () => {
    montar({});
    getters['accounts/isFeatureEnabledonAccount'] = ref(
      (_id, flag) => flag !== 'menu_lateral_novo'
    );
    const wrapper = shallowMount(Sidebar, {
      global: {
        stubs: {
          RouterLink: true,
          SidebarGroup: {
            name: 'SidebarGroup',
            props: ['name', 'children'],
            template: '<li />',
          },
        },
      },
    });
    expect(wrapper.findComponent({ name: 'ForkSidebarNav' }).exists()).toBe(
      false
    );
    expect(
      wrapper.findAllComponents({ name: 'SidebarGroup' }).length
    ).toBeGreaterThan(10);
  });
});
