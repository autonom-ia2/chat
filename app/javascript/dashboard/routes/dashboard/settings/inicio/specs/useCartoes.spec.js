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
    texto = formas[Math.min(quantidade ?? 0, formas.length - 1)];
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
  beforeEach(() => {
    estado.chaves = ['administrator'];
    estado.passos = [];
    publicar();
  });

  it('administrador vê os cartões do que o menu entrega, em grupos', () => {
    expect(idsPorGrupo(montar())).toEqual([
      ['SUA_EMPRESA', ['DADOS_EMPRESA', 'PLANO', 'HORARIOS']],
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
    expect(idsPorGrupo(cartoes)).toEqual([['CANAIS', ['CANAIS']]]);
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
