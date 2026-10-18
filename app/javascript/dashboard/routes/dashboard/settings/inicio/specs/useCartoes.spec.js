import { mount } from '@vue/test-utils';
import { computed, defineComponent, ref } from 'vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/sidebarFork.json';
import { hasPermissions } from 'dashboard/helper/permissionsHelper';
import { publicarMenu } from 'dashboard/components-next/sidebar/fork/menuPublicado';
import { routes } from '../inicio.routes';
import { useCartoes, normalizar } from '../useCartoes';

// Página inicial de Configurações (#1617): quem vê qual cartão, a busca e o "Comece por aqui".

// Os textos de verdade do catálogo pt_BR, para a busca procurar no que a pessoa lê.
const traduzir = (chave, valores, quantidade) => {
  let texto = chave.split('.').reduce((no, parte) => no?.[parte], ptBR);
  if (typeof texto !== 'string') return chave;
  if (texto.includes(' | ')) {
    const formas = texto.split(' | ');
    // Como o vue-i18n: com duas formas, 1 usa a primeira; com três, 0, 1 e o resto.
    const indice =
      formas.length === 2
        ? Number(quantidade !== 1)
        : Math.min(quantidade ?? 0, formas.length - 1);
    texto = formas[indice];
  }
  return Object.entries(valores || {}).reduce(
    (resultado, [nome, valor]) => resultado.split(`{${nome}}`).join(valor),
    texto
  );
};

const estado = { chaves: ['administrator'], passos: [] };
const listas = {
  'inboxes/getInboxes': [{ id: 1 }, { id: 2 }],
  'agents/getAgents': [{ id: 1 }],
  'teams/getTeams': [],
  'labels/getLabels': [{ id: 1 }],
};

// Permissão de cada tela, como nas rotas reais.
const ADMIN = ['administrator'];
const META = {
  general_settings_index: ADMIN,
  autonomia_financial_subscription: ADMIN,
  settings_inbox_list: [...ADMIN, 'inbox_view', 'inbox_manage'],
  agent_list: ADMIN,
  crm_handoff_settings_index: [...ADMIN, 'crm_manage_ai', 'crm_admin'],
  labels_list: [...ADMIN, 'label_manage'],
  settings_applications: ADMIN,
  coisa_nova: ADMIN,
};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: traduzir }) }));
vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: to => ({ meta: { permissions: META[to.name] || ADMIN } }),
  }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: listas, dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    shouldShow: (_flag, permissoes) =>
      hasPermissions(permissoes, estado.chaves),
  }),
}));
vi.mock('dashboard/composables/useOnboardingTrail', () => ({
  useOnboardingTrail: () => {
    const passos = ref(estado.passos);
    return {
      passos,
      total: computed(() => passos.value.length),
      carregar: vi.fn(),
    };
  },
}));

const folha = (name, rota) => ({ name, label: name, to: { name: rota } });
const CONFIGURACOES = [
  folha('Settings Account Settings', 'general_settings_index'),
  folha('Settings Agents', 'agent_list'),
  folha('Settings Inboxes', 'settings_inbox_list'),
  folha('Settings Labels', 'labels_list'),
  folha('Settings Integrations', 'settings_applications'),
];
const publicar = (filhos = CONFIGURACOES, extras = []) =>
  publicarMenu([
    {
      name: 'Financial',
      label: 'Financeiro',
      children: [folha('Subscription', 'autonomia_financial_subscription')],
    },
    ...extras,
    { name: 'Settings', label: 'Configurações', children: filhos },
  ]);

const montar = () =>
  mount(
    defineComponent({
      setup: () => ({ cartoes: useCartoes() }),
      template: '<div />',
    })
  ).vm.cartoes;

const idsPorGrupo = cartoes =>
  cartoes.grupos.value.map(grupo => [
    grupo.id,
    grupo.cartoes.map(cartao => cartao.id),
  ]);

describe('useCartoes', () => {
  const configOriginal = window.globalConfig;
  afterEach(() => {
    window.globalConfig = configOriginal;
  });

  beforeEach(() => {
    estado.chaves = ['administrator'];
    estado.passos = [];
    publicar();
  });

  it('administrador vê os cartões do que o menu entrega, em grupos', () => {
    expect(idsPorGrupo(montar())).toEqual([
      [
        'SUA_EMPRESA',
        ['DADOS_EMPRESA', 'PLANO', 'CUSTOS_WHATSAPP', 'HORARIOS'],
      ],
      ['CANAIS', ['CANAIS']],
      ['PESSOAS', ['USUARIOS']],
      ['ATENDIMENTO', ['ETIQUETAS']],
      ['CONEXOES', ['INTEGRACOES']],
    ]);
  });

  it('cartão cuja tela a pessoa não abre não aparece', () => {
    estado.chaves = ['inbox_view'];
    expect(idsPorGrupo(montar())).toEqual([
      ['SUA_EMPRESA', ['HORARIOS']],
      ['CANAIS', ['CANAIS']],
    ]);
  });

  it('função só com crm_manage_ai vê o cartão da passagem, e a rota settings_inicio a deixa entrar', () => {
    estado.chaves = ['crm_manage_ai'];
    publicar([folha('Settings CRM Handoff', 'crm_handoff_settings_index')]);
    expect(idsPorGrupo(montar())).toEqual([['PESSOAS', ['PASSAGEM']]]);
    expect(hasPermissions(routes[0].meta.permissions, ['crm_manage_ai'])).toBe(
      true
    );
    expect(hasPermissions(routes[0].meta.permissions, ['crm_admin'])).toBe(
      true
    );
  });

  it('busca por pedaço do texto, sem acento e sem maiúscula', () => {
    const cartoes = montar();
    cartoes.termo.value = 'HORARIO';
    expect(idsPorGrupo(cartoes)).toEqual([['SUA_EMPRESA', ['HORARIOS']]]);
    cartoes.termo.value = 'whats';
    expect(idsPorGrupo(cartoes)).toEqual([
      ['SUA_EMPRESA', ['CUSTOS_WHATSAPP']],
      ['CANAIS', ['CANAIS']],
    ]);
    cartoes.termo.value = 'xyz';
    expect(cartoes.grupos.value).toEqual([]);
    expect(cartoes.encontrados.value).toBe(0);
    expect(normalizar('  Ações ')).toBe('acoes');
  });

  it('"Comece por aqui" é a primeira pendência da trilha, e o passo feito mostra o número', () => {
    estado.passos = [
      { id: 'canal', status: 'feito', titulo: 'Conectar um canal' },
      {
        id: 'chave_ia',
        status: 'pendente',
        titulo: 'Conectar a chave da OpenAI',
      },
      { id: 'configuracoes', status: 'pendente', titulo: 'Criar etiquetas' },
    ];
    const cartoes = montar();
    expect(cartoes.primeiraPendencia.value.id).toBe('ETIQUETAS');
    expect(cartoes.primeiraPendencia.value.estado).toEqual({
      tipo: 'falta',
      texto: 'Falta: criar etiquetas',
    });
    const canais = cartoes.grupos.value.find(g => g.id === 'CANAIS').cartoes[0];
    expect(canais.estado).toEqual({
      tipo: 'pronto',
      texto: '2 canais ligados',
    });
  });

  it('cartões de telas fora de Configurações: só com o recurso da instalação e a permissão da rota', () => {
    window.globalConfig = {
      CRM_KANBAN_ENABLED: 'true',
      EMAIL_CAMPAIGN_ENABLED: 'true',
    };
    const ids = idsPorGrupo(montar());
    expect(ids.find(([grupo]) => grupo === 'CANAIS')[1]).toEqual([
      'CANAIS',
      'EMAIL_ENVIO',
    ]);
    expect(ids.find(([grupo]) => grupo === 'PESSOAS')[1]).toEqual([
      'USUARIOS',
      'QUEM_CUIDA',
    ]);
    estado.chaves = ['inbox_view'];
    expect(
      idsPorGrupo(montar()).flatMap(([, cartoes]) => cartoes)
    ).not.toContain('QUEM_CUIDA');
  });

  it('recurso da instalação desligado: o cartão não aparece, mesmo com permissão', () => {
    window.globalConfig = {
      CRM_KANBAN_ENABLED: 'false',
      EMAIL_CAMPAIGN_ENABLED: 'true',
    };
    const ids = idsPorGrupo(montar()).flatMap(([, cartoes]) => cartoes);
    expect(ids).not.toContain('QUEM_CUIDA');
    expect(ids).not.toContain('EMAIL_ENVIO');
    window.globalConfig = {
      CRM_KANBAN_ENABLED: 'true',
      EMAIL_CAMPAIGN_ENABLED: 'false',
    };
    const semEmail = idsPorGrupo(montar()).flatMap(([, cartoes]) => cartoes);
    expect(semEmail).toContain('QUEM_CUIDA');
    expect(semEmail).not.toContain('EMAIL_ENVIO');
  });

  it('caixa que pede reconexão deixa o cartão de canais vermelho e vira o "Comece por aqui"', () => {
    listas['inboxes/getInboxes'] = [
      { id: 1 },
      { id: 2, reauthorization_required: true },
    ];
    const cartoes = montar();
    const canais = cartoes.grupos.value.find(g => g.id === 'CANAIS').cartoes[0];
    expect(canais.estado).toEqual({
      tipo: 'erro',
      texto: 'Precisa reconectar: 1 canal',
    });
    expect(cartoes.primeiraPendencia.value.id).toBe('CANAIS');
    listas['inboxes/getInboxes'] = [{ id: 1 }, { id: 2 }];
  });

  it('"Agentes externos" some só onde a aba Agente de IA por caixa está ligada (#1660), sem cair em "Outros"', () => {
    const comRobos = [
      ...CONFIGURACOES,
      folha('Settings Agent Bots', 'agent_bots'),
    ];
    const temRobos = () =>
      montar()
        .grupos.value.flatMap(grupo => grupo.cartoes.map(c => c.id))
        .includes('ROBOS');
    const conta = ligado => {
      listas.getCurrentAccountId = 7;
      listas['accounts/getAccount'] = () => ({
        autonomia_agente_ia_por_caixa: ligado,
      });
    };
    conta(false);
    publicar(comRobos);
    expect(temRobos()).toBe(true);
    conta(true);
    publicar(comRobos);
    expect(temRobos()).toBe(false);
    expect(montar().grupos.value.at(-1).id).not.toBe('OUTROS');
    delete listas['accounts/getAccount'];
    delete listas.getCurrentAccountId;
  });

  it('Primeiros passos vira cartão só quando o básico da trilha está feito, com o que falta', () => {
    publicar([...CONFIGURACOES]);
    const ids = () =>
      montar().grupos.value.flatMap(grupo => grupo.cartoes.map(c => c.id));
    const basico = ['perfil', 'chave_ia', 'canal', 'primeira_resposta'].map(
      id => ({ id, etapa: 'ligar', status: 'feito', pulavel: false })
    );
    estado.passos = [
      ...basico,
      { id: 'funil', etapa: 'organizar', status: 'pendente', pulavel: false },
    ];
    expect(ids()).not.toContain('PRIMEIROS_PASSOS');
    estado.passos = [
      ...basico,
      { id: 'funil', etapa: 'organizar', status: 'feito', pulavel: false },
      {
        id: 'agente_ia',
        etapa: 'organizar',
        status: 'pendente',
        pulavel: true,
      },
    ];
    const cartao = montar()
      .grupos.value.flatMap(grupo => grupo.cartoes)
      .find(c => c.id === 'PRIMEIROS_PASSOS');
    expect(cartao).toMatchObject({
      grupo: 'SUA_EMPRESA',
      estado: { tipo: 'falta' },
    });
  });

  it('configuração nova sem cartão aparece em "Outros"', () => {
    publicar([...CONFIGURACOES, folha('Settings Coisa Nova', 'coisa_nova')]);
    const grupos = montar().grupos.value;
    expect(grupos.at(-1)).toMatchObject({
      id: 'OUTROS',
      cartoes: [{ id: 'Settings Coisa Nova', titulo: 'Settings Coisa Nova' }],
    });
  });

  it('sem o menu publicado, a página espera (carregado falso)', () => {
    publicarMenu(null);
    expect(montar().carregado.value).toBe(false);
  });
});
