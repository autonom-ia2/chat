import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ListaPage from '../../pages/ListaPage.vue';

// A lista de Relacionamentos fora da demonstração (#2894): lê do servidor pelo
// cliente de API, esconde Empresas de quem não tem a chave `companies` e mostra
// o erro com "Tentar de novo" quando o servidor recusa.
const flagsLigadas = vi.hoisted(() => new Set());

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./dialogoFalso')).TeleportFalso,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flagsLigadas.has(flag),
  }),
}));
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
