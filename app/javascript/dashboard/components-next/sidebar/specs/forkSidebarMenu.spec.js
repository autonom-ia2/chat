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
      children: [
        folha('Reports Agent', 'agent_reports_index'),
        folha('Reports Inbox', 'inbox_reports_index'),
        folha('Reports Team', 'team_reports_index'),
        folha('Reports SLA', 'sla_reports'),
      ],
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

    // CRM primeiro, só com o Kanban e marcado na página Números; a Agenda junta o agendamento.
    expect(nomes(acompanhar.itens)).toEqual(['CRM', 'Relationships', 'Agenda']);
    expect(acompanhar.itens[0]).toMatchObject({
      to: { name: 'crm_kanban_index' },
    });
    expect(acompanhar.itens[0].children).toBeUndefined();
    expect(acompanhar.itens[0].activeOn).toEqual(
      expect.arrayContaining(['crm_kanban_index', 'crm_dashboard_index'])
    );
    expect(nomes(acompanhar.itens[2].children)).toEqual([
      'CRM Booking',
      'CRM Calendar',
    ]);

    // Cotação sem as abas; Capitão e Financeiro fora do menu.
    expect(nomes(crescer.itens)).toEqual(['Insurance']);
    expect(crescer.itens[0]).toMatchObject({ to: { name: 'ins_a' } });
    expect(crescer.itens[0].children).toBeUndefined();
    expect(nomes(automatico.itens)).toEqual(['Agents', 'Automacoes']);
    expect(automatico.itens[0].label).toBe('FORK_SIDEBAR.ITENS.AGENTES');

    // Relatórios sem Funis (virou a aba Números do CRM); nomes do dia a dia.
    expect(
      resultados.itens[0].children.map(filho => [filho.name, filho.label])
    ).toEqual([
      ['Reports Agent', 'FORK_SIDEBAR.ITENS.RELATORIO_USUARIOS'],
      ['Reports Inbox', 'FORK_SIDEBAR.ITENS.RELATORIO_CANAIS'],
      ['Reports Team', 'FORK_SIDEBAR.ITENS.RELATORIO_TIMES'],
      ['Reports SLA', 'FORK_SIDEBAR.ITENS.RELATORIO_PRAZOS'],
    ]);

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
    const menu = organizeForkMenu(upstream, { ...ctx, basicoConcluido: true });
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
      'CRM',
      'Contacts',
      'Companies',
      'Agenda',
    ]);
    expect(acompanhar.itens[3]).toMatchObject({
      label: 'FORK_SIDEBAR.ITENS.AGENDA',
      to: { name: 'crm_calendar_index' },
    });
  });

  it('item marcado nas telas filhas sem item próprio (S9)', () => {
    const comCampanhas = [
      ...upstream.filter(item => item.name !== 'Settings'),
      {
        name: 'Campaigns',
        label: 'Campanhas',
        children: [folha('Campaign Journey', 'campaigns_journey_index')],
      },
      {
        name: 'Settings',
        label: 'Configurações',
        children: [
          {
            ...folha('Settings Inboxes', 'settings_inbox_list'),
            activeOn: [
              'settings_inbox_list',
              'settings_inbox_show',
              'settings_inbox_new',
              'settings_inboxes_page_channel',
            ],
          },
        ],
      },
    ];
    const menu = organizeForkMenu(comCampanhas, ctx);
    const itens = [
      ...menu.topo,
      ...menu.grupos.flatMap(g => g.itens),
      ...menu.rodape,
    ];
    const caminho = to => `/${to.name}`;
    const dono = (name, path = '/outra') =>
      acharAtivo(itens, { name, path, params: {} }, caminho)?.item.name;

    expect(dono('campaigns_email_builder')).toBe('Campaigns');
    expect(dono('campaigns_journey_new')).toBe('Campaigns');
    expect(dono('relationships_company_media')).toBe('Relationships');
    expect(dono('relationships_qualquer_tela_nova')).toBe('Relationships');
    expect(dono('contacts_import_journey')).toBe('Relationships');
    expect(dono('contacts_campaign_imports')).toBe('Relationships');
    expect(dono('crm_dashboard_index')).toBe('CRM');
    [
      'settings_inbox_new',
      'settings_inboxes_page_channel',
      'settings_inbox_show',
    ].forEach(rota =>
      expect(dono(rota, '/app/settings/inboxes/1/whatsapp-api')).toBe(
        'Settings'
      )
    );

    // Sem a navegação de Relacionamentos, a importação marca Contatos.
    const semNavegacao = organizeForkMenu(
      [
        ...comCampanhas.filter(item => item.name !== 'Relationships'),
        {
          name: 'Contacts',
          label: 'Contatos',
          children: [folha('All Contacts')],
        },
      ],
      ctx
    );
    const itensSem = semNavegacao.grupos.flatMap(g => g.itens);
    expect(
      acharAtivo(
        itensSem,
        { name: 'contacts_import_journey', path: '/x' },
        caminho
      ).item.name
    ).toBe('Contacts');
  });

  it('Prospecção fica em Acompanhar, depois do CRM, e acende nas telas dela', () => {
    const configuracoes = [
      'settings_prospecting_index',
      'autonomia_prospecting_settings',
    ];
    const menu = organizeForkMenu(
      [
        ...upstream,
        {
          name: 'Prospecting',
          label: 'Prospecção',
          activeOn: ['autonomia_prospecting_search', ...configuracoes],
          children: [
            folha('Prospecting Search', 'autonomia_prospecting_search'),
            folha('Prospecting Lists', 'autonomia_prospecting_lists'),
            {
              ...folha('Prospecting Settings', 'settings_prospecting_index'),
              activeOn: configuracoes,
            },
          ],
        },
      ],
      ctx
    );
    const acompanhar = menu.grupos.find(grupo => grupo.id === 'ACOMPANHAR');
    expect(nomes(acompanhar.itens).slice(0, 2)).toEqual(['CRM', 'Prospecting']);
    expect(
      nomes(menu.grupos.find(grupo => grupo.id === 'CRESCER').itens)
    ).not.toContain('Prospecting');
    const itens = menu.grupos.flatMap(grupo => grupo.itens);
    const caminho = to => `/${to.name}`;
    ['settings_prospecting_index', 'autonomia_prospecting_search'].forEach(
      rota => {
        const ativa = acharAtivo(itens, { name: rota, path: '/x' }, caminho);
        expect(ativa.item.name).toBe('Prospecting');
        expect(acompanhar.itens).toContain(ativa.item);
      }
    );
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
  // #2211: o Sidebar instala o ⌘K da busca da lista (useAtalhoDaBusca).
  useRouter: () => ({ push: vi.fn() }),
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

// O menu de sempre (flag do menu novo desligada), lido dos SidebarGroup que o Sidebar.vue renderiza.
const menuDeSempre = opcoes => {
  montar(opcoes);
  const todas = getters['accounts/isFeatureEnabledonAccount'].value;
  getters['accounts/isFeatureEnabledonAccount'] = ref(
    (id, flag) => flag !== 'menu_lateral_novo' && todas(id, flag)
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
  return {
    novo: wrapper.findComponent({ name: 'ForkSidebarNav' }).exists(),
    grupos: wrapper.findAllComponents({ name: 'SidebarGroup' }).map(grupo => ({
      name: grupo.props('name'),
      children: (grupo.props('children') || []).map(filho => filho.name),
    })),
  };
};

// O menu de hoje no main (8ba5b440), com todas as flags, como o Sidebar.vue monta para o administrador.
const MENU_DE_SEMPRE = [
  { name: 'FirstSteps', children: [] },
  { name: 'Inbox', children: [] },
  {
    name: 'Conversation',
    children: [
      'All',
      'Mentions',
      'Participating',
      'Unattended',
      'Folders',
      'Teams',
      'Channels',
      'Labels',
    ],
  },
  {
    name: 'Captain',
    children: [
      'Overview',
      'FAQs',
      'Documents',
      'Scenarios',
      'Playground',
      'Inboxes',
      'Tools',
      'Settings',
    ],
  },
  { name: 'Calls', children: [] },
  { name: 'Automacoes', children: [] },
  { name: 'Agents', children: [] },
  {
    name: 'Prospecting',
    children: [
      'Prospecting Search',
      'Prospecting Lists',
      'Prospecting Settings',
    ],
  },
  { name: 'Insurance', children: ['Insurance Connections', 'Insurance Agent'] },
  {
    name: 'Contacts',
    children: ['All Contacts', 'Active', 'Segments', 'Tagged With'],
  },
  {
    name: 'CRM',
    children: [
      'CRM Kanban',
      'CRM Scheduling',
      'CRM Dashboard',
      'CRM AI Usage',
      'CRM SLA',
    ],
  },
  { name: 'Financial', children: ['Subscription', 'Invoices'] },
  { name: 'Companies', children: ['All Companies'] },
  {
    name: 'Reports',
    children: [
      'Report Overview',
      'Report Conversation',
      'Reports Agent',
      'Reports Label',
      'Reports Inbox',
      'Reports Team',
      'Reports CSAT',
      'Reports SLA',
      'Reports Bot',
    ],
  },
  { name: 'SeusPosts', children: [] },
  {
    name: 'Campaigns',
    children: [
      'Campaign Audiences',
      'Campaign Journey',
      'Campaign WhatsApp Templates',
      'Campaign Links and QR codes',
      'Campaign Meta Ads',
      'Campaign Management',
    ],
  },
  { name: 'CentralDeAjuda', children: [] },
  {
    name: 'Settings',
    children: [
      'Settings Account Settings',
      'Settings Prospecting',
      'Settings Agents',
      'Settings Teams',
      'Settings Agent Assignment',
      'Settings Inboxes',
      'Settings Templates',
      'Settings Labels',
      'Settings Custom Attributes',
      'Settings Agent Bots',
      'Settings Macros',
      'Settings Canned Responses',
      'Settings Integrations',
      'Settings Data',
      'Settings Audit Logs',
      'Settings Custom Roles',
      'Conversation Workflow',
      'Settings Security',
      'Settings Billing',
    ],
  },
];

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

  it('com a flag ligada, o menu novo recebe a mesma lista do menu de sempre e a organiza', () => {
    const itens = montar({});
    expect(
      itens.map(item => ({
        name: item.name,
        children: (item.children || []).map(filho => filho.name),
      }))
    ).toEqual(MENU_DE_SEMPRE);

    const menu = organizeForkMenu(itens, ctx);
    expect(nomes(menu.topo)).toEqual(['FirstSteps']);
    expect(menu.grupos.map(grupo => [grupo.id, nomes(grupo.itens)])).toEqual([
      ['ATENDER', ['Conversation', 'Inbox', 'Calls', 'Prazos']],
      ['ACOMPANHAR', ['CRM', 'Prospecting', 'Contacts', 'Companies', 'Agenda']],
      ['CRESCER', ['SeusPosts', 'Campaigns', 'Insurance']],
      ['AUTOMATICO', ['Agents', 'Automacoes']],
      ['RESULTADOS', ['Reports']],
    ]);
    expect(nomes(menu.rodape)).toEqual(['CentralDeAjuda', 'Settings']);
    expect(menu.configuracoesExtras).toEqual([]);
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

  it('com a flag desligada, o menu de sempre continua igual ao do main (nomes e filhos)', () => {
    const { novo, grupos } = menuDeSempre({});
    expect(novo).toBe(false);
    expect(grupos).toEqual(MENU_DE_SEMPRE);
  });
});
