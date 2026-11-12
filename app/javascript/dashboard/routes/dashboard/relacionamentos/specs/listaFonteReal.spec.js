import axios from 'axios';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { listaFonte } from '../fonte/listaFonte';
import { FILTROS_VAZIOS } from '../lista/filtros';

// A fonte real da lista de Relacionamentos (#2894): fala com o servidor pelo
// cliente de API e devolve o mesmo formato da demonstração. O contrato do
// servidor está em spec/requests/api/v1/accounts/relacionamentos_spec.rb.
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

const real = () => listaFonte({ demo: null });
const responde = (metodo, data) =>
  RelacionamentosAPI[metodo].mockResolvedValue({ data });
const erroHttp = status =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error: 'pedido recusado' } },
  });

const ANA = { id: 1, name: 'Ana Albuquerino', phone_number: '+5511910310001' };
const PADARIA = { id: 9, name: 'Padaria Bom Dia', contacts_count: 3 };
const FILTROS_CHEIOS = {
  empresa: 7,
  etiqueta: 'feira',
  cidade: 'Campinas',
  chegouEm: 'ultimos_7',
};

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real', () => {
  it('não é a demonstração', () => {
    expect(real().usaDemo).toBe(false);
  });

  it('sem módulo de demonstração (produção) `?demo=` cai na fonte real', () => {
    expect(listaFonte({ demo: 'cheio', carregarDemo: null }).usaDemo).toBe(
      false
    );
  });
});

describe('resumo', () => {
  it('devolve os números do servidor como a tela lê', async () => {
    const resumo = {
      total: 4,
      clientes: 2,
      sumiu_1_a_3_meses: 1,
      empresas: { total: 3, sem_conversa_3_meses: 1 },
    };
    responde('resumo', resumo);
    expect(await real().resumo()).toEqual(resumo);
  });
});

describe('listar', () => {
  it('pede a página de pessoas e traduz `tem_mais` para `temMais`', async () => {
    responde('pessoas', { itens: [ANA], total: 26, tem_mais: true });
    expect(
      await real().listar({
        aba: 'pessoas',
        grupo: 'clientes',
        busca: 'ana',
        ordem: 'nome',
        filtros: { ...FILTROS_VAZIOS },
        pagina: 1,
      })
    ).toEqual({ itens: [ANA], total: 26, temMais: true });
  });

  it('manda grupo, busca, ordem, página e cada filtro como `filtros[…]`', async () => {
    responde('pessoas', { itens: [], total: 0, tem_mais: false });
    await real().listar({
      aba: 'pessoas',
      grupo: 'clientes',
      busca: 'ana',
      ordem: 'nome',
      filtros: FILTROS_CHEIOS,
      pagina: 2,
    });
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledWith({
      grupo: 'clientes',
      busca: 'ana',
      ordem: 'nome',
      pagina: 2,
      'filtros[empresa]': 7,
      'filtros[etiqueta]': 'feira',
      'filtros[cidade]': 'Campinas',
      'filtros[chegou_em]': 'ultimos_7',
    });
  });

  it('não manda busca vazia nem filtro vazio', async () => {
    responde('pessoas', { itens: [], total: 0, tem_mais: false });
    await real().listar({
      aba: 'pessoas',
      grupo: 'todos',
      busca: '',
      ordem: 'ultima_conversa',
      filtros: { ...FILTROS_VAZIOS, cidade: 'Santos' },
      pagina: 1,
    });
    expect(RelacionamentosAPI.pessoas).toHaveBeenCalledWith({
      grupo: 'todos',
      ordem: 'ultima_conversa',
      pagina: 1,
      'filtros[cidade]': 'Santos',
    });
  });

  it('os params chegam ao servidor como `filtros[chegou_em]=…`', async () => {
    responde('pessoas', { itens: [], total: 0, tem_mais: false });
    await real().listar({ aba: 'pessoas', filtros: FILTROS_CHEIOS });
    const [params] = RelacionamentosAPI.pessoas.mock.calls[0];
    const url = new URL(axios.getUri({ url: '/pessoas', params }), 'http://x');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      'filtros[empresa]': '7',
      'filtros[etiqueta]': 'feira',
      'filtros[cidade]': 'Campinas',
      'filtros[chegou_em]': 'ultimos_7',
    });
  });

  it('na aba Empresas pede empresas e nunca manda filtros', async () => {
    responde('empresas', { itens: [PADARIA], total: 1, tem_mais: false });
    expect(
      await real().listar({
        aba: 'empresas',
        grupo: 'com_clientes',
        busca: 'padaria',
        ordem: 'mais_novos',
        filtros: FILTROS_CHEIOS,
        pagina: 3,
      })
    ).toEqual({ itens: [PADARIA], total: 1, temMais: false });
    expect(RelacionamentosAPI.empresas).toHaveBeenCalledWith({
      grupo: 'com_clientes',
      busca: 'padaria',
      ordem: 'mais_novos',
      pagina: 3,
    });
    expect(RelacionamentosAPI.pessoas).not.toHaveBeenCalled();
  });
});

describe('contagens', () => {
  it('conta os grupos de pessoas com a busca e os filtros da lista', async () => {
    const contagens = { todos: 2, clientes: 1 };
    responde('contagensDePessoas', contagens);
    expect(
      await real().contagens('pessoas', {
        busca: 'ana',
        filtros: { ...FILTROS_VAZIOS, chegouEm: 'ultimos_30' },
      })
    ).toEqual(contagens);
    expect(RelacionamentosAPI.contagensDePessoas).toHaveBeenCalledWith({
      busca: 'ana',
      'filtros[chegou_em]': 'ultimos_30',
    });
  });

  it('conta os grupos de empresas sem mandar filtros', async () => {
    const contagens = { todas: 3, com_clientes: 1 };
    responde('contagensDeEmpresas', contagens);
    expect(
      await real().contagens('empresas', {
        busca: 'padaria',
        filtros: FILTROS_CHEIOS,
      })
    ).toEqual(contagens);
    expect(RelacionamentosAPI.contagensDeEmpresas).toHaveBeenCalledWith({
      busca: 'padaria',
    });
    expect(RelacionamentosAPI.contagensDePessoas).not.toHaveBeenCalled();
  });

  it('sem busca nem filtro não manda param nenhum', async () => {
    responde('contagensDeEmpresas', {});
    await real().contagens('empresas', {
      busca: '',
      filtros: { ...FILTROS_VAZIOS },
    });
    expect(RelacionamentosAPI.contagensDeEmpresas).toHaveBeenCalledWith({});
  });
});

describe('listarTodos', () => {
  it('pede a consulta inteira, sem página', async () => {
    responde('todasAsPessoas', { itens: [ANA], total: 1 });
    expect(
      await real().listarTodos({
        aba: 'pessoas',
        grupo: 'sumiu_1_a_3_meses',
        busca: 'ana',
        ordem: 'nome',
        filtros: { ...FILTROS_VAZIOS, etiqueta: 'feira' },
        pagina: 4,
      })
    ).toEqual({ itens: [ANA], total: 1 });
    expect(RelacionamentosAPI.todasAsPessoas).toHaveBeenCalledWith({
      grupo: 'sumiu_1_a_3_meses',
      busca: 'ana',
      ordem: 'nome',
      'filtros[etiqueta]': 'feira',
    });
  });
});

describe('opcoesDeFiltro', () => {
  it('devolve empresas, etiquetas e cidades como a gaveta lê', async () => {
    const opcoes = {
      empresas: [{ value: 9, label: 'Padaria Bom Dia' }],
      etiquetas: [{ value: 'feira', label: 'feira' }],
      cidades: [{ value: 'Campinas', label: 'Campinas' }],
    };
    responde('opcoesDeFiltro', opcoes);
    expect(await real().opcoesDeFiltro()).toEqual(opcoes);
  });
});

// Cada leitura da fonte: o método dela, o da API por baixo e os argumentos.
const LEITURAS = [
  ['resumo', 'resumo', []],
  ['contagens', 'contagensDePessoas', ['pessoas']],
  ['contagens', 'contagensDeEmpresas', ['empresas']],
  ['listar', 'pessoas', [{ aba: 'pessoas' }]],
  ['listar', 'empresas', [{ aba: 'empresas' }]],
  ['listarTodos', 'todasAsPessoas', [{ aba: 'pessoas' }]],
  ['opcoesDeFiltro', 'opcoesDeFiltro', []],
];

describe.each([422, 500])('erro do servidor (%i)', status => {
  it.each(LEITURAS)(
    '%s (%s) repassa o erro sem engolir',
    async (metodo, daApi, args) => {
      const recusado = erroHttp(status);
      RelacionamentosAPI[daApi].mockRejectedValue(recusado);
      await expect(real()[metodo](...args)).rejects.toBe(recusado);
    }
  );
});

// Quem não pode ver (401 ou 403) recebe uma falha com nome: a tela diz que a
// pessoa não tem acesso em vez de oferecer "Tentar de novo".
describe.each([401, 403])('sem acesso (%i)', status => {
  it.each(LEITURAS)(
    '%s (%s) vira a falha de nome SEM_ACESSO',
    async (metodo, daApi, args) => {
      RelacionamentosAPI[daApi].mockRejectedValue(erroHttp(status));
      const falha = await real()
        [metodo](...args)
        .catch(erro => erro);
      expect(falha).toBeInstanceOf(Error);
      expect(falha.name).toBe('SEM_ACESSO');
    }
  );
});
