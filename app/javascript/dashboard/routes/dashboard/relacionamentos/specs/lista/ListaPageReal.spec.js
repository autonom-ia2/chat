import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import LabelsAPI from 'dashboard/api/labels';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ListaPage from '../../pages/ListaPage.vue';

// A lista de Relacionamentos fora da demonstração (#2894): lê do servidor pelo
// cliente de API, esconde Empresas de quem não tem a chave `companies` e mostra
// o erro com "Tentar de novo" quando o servidor recusa. As ações em grupo
// escrevem no servidor, somem para quem não tem a permissão e recarregam a
// lista depois.
const flagsLigadas = vi.hoisted(() => new Set());
const pode = vi.hoisted(() => ({
  criarCards: true,
  etiquetar: true,
  apagar: true,
  trazer: true,
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./teleportFalso')).TeleportFalso,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flagsLigadas.has(flag),
  }),
}));
vi.mock('../../lista/usePermissoesDaLista', () => ({
  usePermissoesDaLista: () => ({
    podeCriarCards: {
      get value() {
        return pode.criarCards;
      },
    },
    podeEtiquetar: {
      get value() {
        return pode.etiquetar;
      },
    },
    podeApagar: {
      get value() {
        return pode.apagar;
      },
    },
    podeTrazer: {
      get value() {
        return pode.trazer;
      },
    },
  }),
}));
vi.mock('dashboard/api/labels', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});
vi.mock('dashboard/api/relacionamentos', () => ({
  default: {
    pessoas: vi.fn(),
    contagensDePessoas: vi.fn(),
    todasAsPessoas: vi.fn(),
    empresas: vi.fn(),
    contagensDeEmpresas: vi.fn(),
    resumo: vi.fn(),
    opcoesDeFiltro: vi.fn(),
    funis: vi.fn(),
    criarCards: vi.fn(),
    aplicarEtiqueta: vi.fn(),
    apagar: vi.fn(),
  },
}));

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();
const marca = nome => `[data-relacionamentos="${nome}"]`;

const ANA = {
  id: 1,
  name: 'Ana Albuquerino',
  email: 'ana.albuquerino@exemplo.com.br',
  phone_number: '+5511910310001',
  thumbnail: '',
  blocked: false,
  contact_type: 'customer',
  customer_since: 1700000000,
  last_activity_at: 1700000000,
  created_at: 1690000000,
  additional_attributes: { city: 'Campinas', company_name: 'Padaria Bom Dia' },
  custom_attributes: {},
  labels: ['feira'],
  opted_out_at: null,
  opt_out_source: null,
};
const PADARIA = {
  id: 9,
  name: 'Padaria Bom Dia',
  domain: 'padaria-bom-dia.exemplo.com.br',
  cnpj: null,
  created_at: 1690000000,
  contacts_count: 3,
  customers_count: 1,
  last_activity_at: 1700000000,
};
const RESPOSTAS = {
  resumo: {
    total: 1,
    clientes: 1,
    sumiu_1_a_3_meses: 0,
    empresas: { total: 1, sem_conversa_3_meses: 0 },
  },
  contagensDePessoas: { todos: 1, clientes: 1 },
  pessoas: { itens: [ANA], total: 1, tem_mais: false },
  contagensDeEmpresas: { todas: 1, com_clientes: 1 },
  empresas: { itens: [PADARIA], total: 1, tem_mais: false },
};
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error: 'pedido recusado' } },
  });

const servidorResponde = () =>
  Object.entries(RESPOSTAS).forEach(([metodo, data]) =>
    RelacionamentosAPI[metodo].mockResolvedValue({ data })
  );

let aberta;
const abrir = async ({ query = {} } = {}) => {
  rota.name = 'relationships_home';
  rota.query = query;
  aberta = mount(ListaPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await flushPromises();
  return aberta;
};

const paramsDe = metodo =>
  RelacionamentosAPI[metodo].mock.calls.map(([params]) => params);
const comFiltros = params =>
  Object.keys(params).some(chave => chave.startsWith('filtros'));

beforeEach(() => {
  flagsLigadas.clear();
  pode.criarCards = true;
  pode.etiquetar = true;
  pode.apagar = true;
  pode.trazer = true;
  servidorResponde();
});

afterEach(() => {
  aberta?.unmount();
  aberta = null;
  vi.resetAllMocks();
});

describe('com os dados do servidor', () => {
  it('mostra as pessoas que o servidor devolveu', async () => {
    const w = await abrir();
    expect(w.find(marca('erro')).exists()).toBe(false);
    expect(w.findAll(marca('linha'))).toHaveLength(1);
    expect(w.get(marca('linha')).text()).toContain('Ana Albuquerino');
    expect(RelacionamentosAPI.resumo).toHaveBeenCalledTimes(1);
    expect(paramsDe('contagensDePessoas')).toEqual([{}]);
    expect(paramsDe('pessoas')).toEqual([
      { grupo: 'todos', ordem: 'ultima_conversa', pagina: 1 },
    ]);
  });
});

describe('aba Empresas e a chave `companies`', () => {
  it('sem a chave a aba some e a tela não pede empresas', async () => {
    const w = await abrir();
    expect(w.find(marca('aba-empresas')).exists()).toBe(false);
    expect(w.find('[role="tablist"]').exists()).toBe(false);
    expect(w.find('[role="tabpanel"]').exists()).toBe(false);
    expect(RelacionamentosAPI.empresas).not.toHaveBeenCalled();
    expect(RelacionamentosAPI.contagensDeEmpresas).not.toHaveBeenCalled();
  });

  it('sem a chave, `?aba=empresas` na URL abre Pessoas', async () => {
    const w = await abrir({ query: { aba: 'empresas' } });
    expect(w.get(marca('linha')).text()).toContain('Ana Albuquerino');
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledTimes(1);
    expect(RelacionamentosAPI.empresas).not.toHaveBeenCalled();
    expect(RelacionamentosAPI.contagensDeEmpresas).not.toHaveBeenCalled();
  });

  it('com a chave a aba aparece e pede empresas sem filtros', async () => {
    flagsLigadas.add(FEATURE_FLAGS.COMPANIES);
    const w = await abrir();
    expect(w.get('[role="tabpanel"]').attributes('aria-labelledby')).toBe(
      w.get(marca('aba-pessoas')).attributes('id')
    );
    await w.get(marca('aba-empresas')).trigger('click');
    await flushPromises();
    expect(roteador.push).toHaveBeenCalledWith({ query: { aba: 'empresas' } });
    expect(w.get(marca('linha')).text()).toContain('Padaria Bom Dia');
    expect(paramsDe('empresas')).toEqual([
      { grupo: 'todas', ordem: 'ultima_conversa', pagina: 1 },
    ]);
    expect(paramsDe('contagensDeEmpresas')).toEqual([{}]);
    expect(
      [...paramsDe('empresas'), ...paramsDe('contagensDeEmpresas')].some(
        comFiltros
      )
    ).toBe(false);
  });
});

describe('erro do servidor', () => {
  it('500 no resumo mostra o erro, e "Tentar de novo" pede outra vez', async () => {
    RelacionamentosAPI.resumo.mockRejectedValueOnce(erroHttp(500));
    const w = await abrir();
    expect(w.get(marca('erro')).attributes('role')).toBe('alert');
    expect(w.get(marca('erro')).text()).toContain(
      'Não consegui mostrar as pessoas.'
    );
    expect(w.find(marca('linha')).exists()).toBe(false);

    await w.get(`${marca('erro')} button`).trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.resumo).toHaveBeenCalledTimes(2);
    expect(w.find(marca('erro')).exists()).toBe(false);
    expect(w.get(marca('linha')).text()).toContain('Ana Albuquerino');
  });

  it('422 na lista de pessoas mostra o erro no lugar da lista', async () => {
    RelacionamentosAPI.pessoas.mockRejectedValue(erroHttp(422));
    const w = await abrir();
    expect(w.get(marca('erro')).text()).toContain(
      'Não consegui mostrar as pessoas.'
    );
    expect(w.find(marca('linha')).exists()).toBe(false);
  });

  it('403 em empresas mostra o erro no lugar da lista', async () => {
    flagsLigadas.add(FEATURE_FLAGS.COMPANIES);
    RelacionamentosAPI.empresas.mockRejectedValue(erroHttp(403));
    RelacionamentosAPI.contagensDeEmpresas.mockRejectedValue(erroHttp(403));
    const w = await abrir({ query: { aba: 'empresas' } });
    expect(w.get(marca('erro')).attributes('role')).toBe('alert');
    expect(w.find(marca('linha')).exists()).toBe(false);
  });
});

describe('ações em grupo: quem vê o quê', () => {
  const marcarAna = async w => {
    await w.get(`${marca('marcar')} input`).setValue(true);
  };

  it('com as permissões, a barra tem Criar cards e o menu tem Apagar', async () => {
    const w = await abrir();
    await marcarAna(w);
    expect(w.find(marca('criar-cards')).exists()).toBe(true);
    expect(w.find('[data-acao="apagar"]').exists()).toBe(true);
  });

  it('quem não pode ver o CRM não vê "Criar cards"', async () => {
    pode.criarCards = false;
    const w = await abrir();
    await marcarAna(w);
    expect(w.find(marca('criar-cards')).exists()).toBe(false);
    expect(w.find('[data-acao="criarCards"]').exists()).toBe(false);
    expect(w.find(marca('etiqueta')).exists()).toBe(true);
  });

  it('quem não pode editar contato não vê "Etiqueta"', async () => {
    pode.etiquetar = false;
    const w = await abrir();
    await marcarAna(w);
    expect(w.find(marca('etiqueta')).exists()).toBe(false);
    expect(w.find('[data-acao="etiqueta"]').exists()).toBe(false);
    expect(w.find(marca('criar-cards')).exists()).toBe(true);
  });

  it('sem nenhuma das três, a barra fica só com "Mandar mensagem"', async () => {
    pode.criarCards = false;
    pode.etiquetar = false;
    pode.apagar = false;
    const w = await abrir();
    await marcarAna(w);
    expect(w.find(marca('mandar-mensagem')).exists()).toBe(true);
    expect(w.find(marca('mais-acoes')).exists()).toBe(false);
  });

  it('quem não pode apagar contato não vê "Apagar"', async () => {
    pode.apagar = false;
    const w = await abrir();
    await marcarAna(w);
    expect(w.find('[data-acao="apagar"]').exists()).toBe(false);
    expect(w.find(marca('criar-cards')).exists()).toBe(true);
  });
});

describe('ações em grupo: escrevem no servidor e a lista recarrega', () => {
  const leituras = () =>
    ['resumo', 'contagensDePessoas', 'pessoas'].map(
      metodo => RelacionamentosAPI[metodo].mock.calls.length
    );
  const marcarAna = async w => {
    await w.get(`${marca('marcar')} input`).setValue(true);
  };
  const abrirApagar = async w => {
    await w.get(marca('mais-acoes')).trigger('click');
    await w.get('[data-acao="apagar"]').trigger('click');
  };

  it('apagar: manda os ids, avisa, recarrega lista, contagens e resumo e desmarca quem saiu', async () => {
    RelacionamentosAPI.apagar.mockResolvedValue({
      data: { apagadas: 1, de_fora: [] },
    });
    const w = await abrir();
    await marcarAna(w);
    await abrirApagar(w);
    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.apagar).toHaveBeenCalledWith({ pessoa_ids: [1] });
    expect(useAlert).toHaveBeenCalledWith('1 pessoa apagada.');
    expect(leituras()).toEqual([2, 2, 2]);
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('etiquetar: lê as etiquetas da conta, manda a escolhida e recarrega', async () => {
    LabelsAPI.get.mockResolvedValue({
      data: { payload: [{ title: 'feira' }] },
    });
    RelacionamentosAPI.aplicarEtiqueta.mockResolvedValue({
      data: { aplicadas: 1, de_fora: [] },
    });
    const w = await abrir();
    await marcarAna(w);
    await w.get(marca('etiqueta')).trigger('click');
    await flushPromises();
    w.getComponent({ name: 'DialogoEtiqueta' })
      .getComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'feira');
    await flushPromises();
    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.aplicarEtiqueta).toHaveBeenCalledWith({
      pessoa_ids: [1],
      etiqueta: 'feira',
    });
    expect(leituras()).toEqual([2, 2, 2]);
    expect(w.find(marca('barra')).exists()).toBe(false);
  });

  it('criar cards: lê os funis do servidor e manda funil e etapa escolhidos', async () => {
    RelacionamentosAPI.funis.mockResolvedValue({
      data: [{ id: 3, nome: 'Vendas', etapas: [{ id: 4, nome: 'Novo' }] }],
    });
    RelacionamentosAPI.criarCards.mockResolvedValue({
      data: {
        criados: 0,
        de_fora: [{ id: 1, nome: 'Ana Albuquerino', motivo: 'ja_tem_card' }],
      },
    });
    const w = await abrir();
    await marcarAna(w);
    await w.get(marca('criar-cards')).trigger('click');
    await flushPromises();
    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.criarCards).toHaveBeenCalledWith({
      pessoa_ids: [1],
      funil_id: 3,
      etapa_id: 4,
    });
    expect(w.get(marca('dialogo-cards')).text()).toContain(
      'Ana Albuquerino · Já tem card aberto neste funil'
    );
  });

  it('criar cards sem nenhum funil: diz que não há funil e "Abrir o CRM" leva ao CRM do menu', async () => {
    RelacionamentosAPI.funis.mockResolvedValue({ data: [] });
    const w = await abrir();
    await marcarAna(w);
    await w.get(marca('criar-cards')).trigger('click');
    await flushPromises();
    expect(w.get(marca('sem-funil')).text()).toBe(
      'Você ainda não tem um funil para receber os cards.'
    );
    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(roteador.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
    expect(RelacionamentosAPI.criarCards).not.toHaveBeenCalled();
    expect(w.find(marca('barra')).exists()).toBe(true);
  });

  it('apagar que para no meio: "Fechar" recarrega e deixa marcado só quem ainda falta', async () => {
    const muitas = Array.from({ length: 60 }, (_, i) => ({
      ...ANA,
      id: i + 1,
      name: `Pessoa ${i + 1}`,
    }));
    RelacionamentosAPI.pessoas.mockResolvedValue({
      data: { itens: muitas.slice(0, 25), total: 60, tem_mais: true },
    });
    RelacionamentosAPI.todasAsPessoas.mockResolvedValue({
      data: { itens: muitas, total: 60 },
    });
    RelacionamentosAPI.apagar
      .mockResolvedValueOnce({ data: { apagadas: 50, de_fora: [] } })
      .mockRejectedValueOnce(erroHttp(500));
    const w = await abrir();
    await marcarAna(w);
    await w
      .findAll('button')
      .find(b => b.text().startsWith('Marcar todas'))
      .trigger('click');
    await flushPromises();
    await abrirApagar(w);
    await w.get('[data-confirmar]').trigger('click');
    await flushPromises();
    expect(RelacionamentosAPI.apagar).toHaveBeenCalledTimes(2);
    expect(w.get(marca('dialogo-apagar')).text()).toContain(
      '50 pessoas apagadas.'
    );
    expect(w.get(marca('ainda-nao')).text()).toBe(
      '10 ainda não. Deu erro no meio do caminho.'
    );
    const antes = leituras();
    await w.get('[data-cancelar]').trigger('click');
    await flushPromises();
    expect(leituras()).toEqual(antes.map(vezes => vezes + 1));
    expect(w.get(`${marca('barra')} p`).text()).toBe('10 marcadas');
  });
});

// #2896 — "Trazer minha lista" é de quem pode importar contato.
describe('Trazer minha lista: quem vê', () => {
  it('quem pode vê o atalho no herói, e ele leva à tela de trazer', async () => {
    const w = await abrir();
    await w.get(marca('heroi-trazer')).trigger('click');
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_trazer',
    });
  });

  it('quem não pode não vê o atalho', async () => {
    pode.trazer = false;
    const w = await abrir();
    expect(w.find(marca('heroi-trazer')).exists()).toBe(false);
    expect(
      w.findAll('button').filter(b => b.text() === 'Trazer minha lista')
    ).toHaveLength(0);
    expect(w.get(marca('linha')).text()).toContain('Ana Albuquerino');
  });

  it('quem não pode, na conta vazia, não vê o botão principal de trazer', async () => {
    pode.trazer = false;
    RelacionamentosAPI.resumo.mockResolvedValue({
      data: { ...RESPOSTAS.resumo, total: 0, clientes: 0 },
    });
    const w = await abrir();
    expect(w.find(marca('heroi-acao')).exists()).toBe(false);
    expect(
      w.findAll('button').filter(b => b.text() === 'Trazer minha lista')
    ).toHaveLength(0);
  });
});
