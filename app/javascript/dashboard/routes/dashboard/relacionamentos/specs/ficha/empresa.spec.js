import { ref } from 'vue';
import CompanyAPI from 'dashboard/api/companies';
import { errosDaEmpresa } from '../../ficha/errosDoFormulario';
import {
  formularioDaEmpresa,
  linhasDaEmpresa,
  pedidoDaEmpresa,
  siteParaGravar,
} from '../../ficha/informacoesDaEmpresa';
import { useFichaDaEmpresa } from '../../ficha/useFichaDaEmpresa';
import { linhasDosCampos } from '../../ficha/atributos';
import { apagarEmpresas } from '../../fonte/apagarEmpresas';
import { criarEmpresa } from '../../fonte/gravarEmpresa';
import { GRAVOU_EM_PARTE } from '../../fonte/gravarPessoa';
import { empresaPassaNosFiltros } from '../../lista/filtros';
import {
  CAMPOS_DE_ORDEM_DAS_EMPRESAS,
  NA_PREFERENCIA_DAS_EMPRESAS,
  gruposDeOrdem,
  ordemNaTabela,
  preferenciaNaTabela,
} from '../../lista/ordens';

// #3078 — a lógica da Empresa com tudo o que a tela antiga de Empresas fazia:
// as informações e o pedido da gaveta, o apagar (na hora, ou na fila do
// servidor quando a empresa tem muitas pessoas, #3079), as
// ordens e os filtros da aba Empresas e as ações da ficha.
vi.mock('dashboard/api/companies', () => ({
  default: { create: vi.fn(), update: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/helper/sentryPrivacy', () => ({
  reportarSemDados: vi.fn(),
}));

const SEGUNDOS = Date.UTC(2026, 10, 1, 12) / 1000;
const AGORA = Date.UTC(2026, 10, 11, 12);
const erroHttp = status =>
  Object.assign(new Error(`status ${status}`), { response: { status } });

afterEach(() => {
  vi.resetAllMocks();
});

describe('linhasDaEmpresa', () => {
  const empresa = {
    city: ' Campinas ',
    description: 'Padaria do bairro.',
    contacts_count: 3,
    customers_count: 1,
    created_at: SEGUNDOS,
    last_activity_at: SEGUNDOS,
  };

  it('cidade, "Sobre", pessoas, clientes, desde quando e a última conversa', () => {
    const linhas = linhasDaEmpresa(empresa, { agora: AGORA });
    expect(linhas.map(l => l.chave)).toEqual([
      'cidade',
      'sobre',
      'pessoas',
      'clientes',
      'desde',
      'ultima_conversa',
    ]);
    expect(linhas[0].valor).toBe('Campinas');
    expect(linhas[1]).toMatchObject({
      valor: 'Padaria do bairro.',
      longo: true,
    });
    expect(linhas[2].valor).toBe('3');
    expect(linhas[4].valor).not.toBe('');
    expect(linhas[5].valor).toContain('10');
  });

  it('sem "Sobre" a linha não aparece; sem data, fica em branco', () => {
    const linhas = linhasDaEmpresa({ contacts_count: 0 });
    expect(linhas.map(l => l.chave)).not.toContain('sobre');
    const porChave = Object.fromEntries(linhas.map(l => [l.chave, l.valor]));
    expect(porChave).toMatchObject({
      cidade: '',
      desde: '',
      ultima_conversa: '',
      clientes: '0',
    });
  });

  it('os campos personalizados ficam fora de Informações (#3082)', () => {
    const linhas = linhasDaEmpresa(empresa, { agora: AGORA });
    expect(linhas.some(linha => linha.chave.startsWith('conta:'))).toBe(false);
  });

  it('"Seus campos" da empresa: os que aparecem na ficha, com nome e tipo', () => {
    const linhas = linhasDosCampos([
      {
        chave: 'porte',
        rotulo: 'Porte',
        tipo: 'text',
        valor: 'Pequeno',
        principal: true,
      },
      {
        chave: 'site2',
        rotulo: 'Outro',
        tipo: 'link',
        valor: 'x.com',
        principal: false,
      },
      {
        chave: 'ativo',
        rotulo: 'Ativo',
        tipo: 'checkbox',
        valor: null,
        principal: true,
      },
    ]);
    expect(linhas).toEqual([
      { chave: 'conta:porte', rotulo: 'Porte', tipo: 'text', valor: 'Pequeno' },
      { chave: 'conta:ativo', rotulo: 'Ativo', tipo: 'checkbox', valor: '' },
    ]);
  });
});

describe('formulário e pedido da gaveta da empresa', () => {
  it('a empresa nova abre vazia; a que existe, com o que tem', () => {
    expect(formularioDaEmpresa()).toEqual({
      nome: '',
      cnpj: '',
      site: '',
      cidade: '',
      sobre: '',
      foto: null,
      atributos: {},
    });
    expect(
      formularioDaEmpresa({
        name: 'Padaria',
        cnpj: '11222333000181',
        domain: 'padaria.com.br',
        city: 'Santos',
        description: 'Pães',
        custom_attributes: { porte: 'pequeno' },
      })
    ).toEqual({
      nome: 'Padaria',
      cnpj: '11.222.333/0001-81',
      site: 'padaria.com.br',
      cidade: 'Santos',
      sobre: 'Pães',
      foto: null,
      atributos: { porte: 'pequeno' },
    });
  });

  it('o site vai só com o nome, sem https nem barra', () => {
    expect(siteParaGravar('https://Padaria.com.br/')).toBe('padaria.com.br');
    expect(siteParaGravar('  padaria.com.br ')).toBe('padaria.com.br');
    expect(siteParaGravar('')).toBe('');
  });

  it('o que foi apagado vai como null; o campo esvaziado sai de verdade', () => {
    const inicial = formularioDaEmpresa({
      name: 'Padaria',
      custom_attributes: { porte: 'pequeno', ramo: 'pães' },
    });
    const pedido = pedidoDaEmpresa(
      { ...inicial, atributos: { porte: '', ramo: 'doces' } },
      inicial
    );
    expect(pedido).toEqual({
      empresa: {
        name: 'Padaria',
        domain: null,
        description: null,
        additional_attributes: { cnpj: null, city: null },
        custom_attributes: { ramo: 'doces' },
      },
      foto: null,
      apagar: ['porte'],
    });
  });

  it('nome, CNPJ, cidade, sobre e site entram limpos', () => {
    const formulario = {
      ...formularioDaEmpresa(),
      nome: ' Padaria ',
      cnpj: '11.222.333/0001-81',
      site: 'https://padaria.com.br',
      cidade: ' Santos ',
      sobre: ' Pães ',
    };
    expect(pedidoDaEmpresa(formulario).empresa).toMatchObject({
      name: 'Padaria',
      domain: 'padaria.com.br',
      description: 'Pães',
      additional_attributes: { cnpj: '11222333000181', city: 'Santos' },
    });
  });

  it('confere nome, CNPJ e site', () => {
    const inicial = formularioDaEmpresa();
    expect(
      errosDaEmpresa(inicial, {
        ...inicial,
        nome: ' ',
        cnpj: '123',
        site: 'não é site',
      })
    ).toEqual({ nome: 'NOME', cnpj: 'CNPJ', site: 'LINK' });
    expect(
      errosDaEmpresa(inicial, {
        ...inicial,
        nome: 'Padaria',
        cnpj: '11222333000181',
        site: 'padaria.com.br',
      })
    ).toEqual({});
  });
});

describe('apagarEmpresas (as marcadas na lista)', () => {
  const empresas = [
    { id: 1, name: 'A' },
    { id: 2, name: 'B' },
    { id: 3, name: 'C' },
  ];

  it('apaga uma a uma; a que não existe mais fica de fora com o motivo', async () => {
    CompanyAPI.delete.mockImplementation(async id => {
      if (id === 2) throw erroHttp(404);
      return { status: 200 };
    });
    const aoAndar = vi.fn();
    const feito = await apagarEmpresas({ pessoas: empresas, aoAndar });
    expect(CompanyAPI.delete.mock.calls.map(([id]) => id)).toEqual([1, 2, 3]);
    expect(feito).toEqual({
      apagadas: 2,
      deFora: [{ id: 2, nome: 'B', motivo: 'nao_existe_mais' }],
      faltam: [],
      erro: null,
      naFila: [],
    });
    expect(aoAndar).toHaveBeenCalledWith({ feitas: 3, total: 3 });
  });

  // #3079 — a empresa com muitas pessoas o servidor põe na fila (202): conta
  // como apagada e volta em `naFila`, para a tela avisar.
  it('a que o servidor põe na fila (202) conta como apagada e vem em naFila', async () => {
    CompanyAPI.delete.mockImplementation(async id => ({
      status: id === 3 ? 202 : 200,
    }));
    const feito = await apagarEmpresas({ pessoas: empresas });
    expect(feito).toMatchObject({
      apagadas: 3,
      faltam: [],
      erro: null,
      naFila: [{ id: 3, nome: 'C' }],
    });
  });

  // #3078 (revisão) — a falha no meio da fatia não apaga o que já foi feito:
  // a contagem diz quantas saíram, e só o resto continua marcado.
  it('outra falha para ali com o que já saiu contado; tentar de novo pede só o resto', async () => {
    CompanyAPI.delete
      .mockResolvedValueOnce({ status: 202 })
      .mockRejectedValueOnce(erroHttp(500));
    const feito = await apagarEmpresas({ pessoas: empresas });
    expect(feito.erro).toBeTruthy();
    expect(feito.apagadas).toBe(1);
    expect(feito.faltam).toEqual(empresas.slice(1));
    expect(feito.naFila).toEqual([{ id: 1, nome: 'A' }]);
    CompanyAPI.delete.mockResolvedValue({ status: 200 });
    const deNovo = await apagarEmpresas({ pessoas: feito.faltam });
    expect(CompanyAPI.delete.mock.calls.map(([id]) => id)).toEqual([
      1, 2, 2, 3,
    ]);
    expect(deNovo).toMatchObject({ apagadas: 2, faltam: [], erro: null });
  });
});

describe('criarEmpresa', () => {
  const pedido = {
    empresa: { name: 'Padaria' },
    foto: { arquivo: new File(['x'], 'logo.png', { type: 'image/png' }) },
    apagar: [],
  };

  it('se a foto falha, a falha traz a empresa criada; tentar de novo altera, não cria outra', async () => {
    CompanyAPI.create.mockResolvedValue({ data: { payload: { id: 5 } } });
    CompanyAPI.update.mockRejectedValueOnce(erroHttp(422));
    const falha = await criarEmpresa(pedido).catch(erro => erro);
    expect(falha).toMatchObject({
      name: GRAVOU_EM_PARTE,
      retomada: { empresa: { id: 5 } },
    });
    CompanyAPI.update.mockResolvedValue({ data: { payload: { id: 5 } } });
    expect(await criarEmpresa(pedido, falha.retomada)).toEqual({ id: 5 });
    expect(CompanyAPI.create).toHaveBeenCalledTimes(1);
    expect(CompanyAPI.update.mock.calls[1]).toEqual([
      5,
      { company: { name: 'Padaria' } },
    ]);
  });
});

describe('ordens e filtros da aba Empresas', () => {
  it('as cinco ordens da lista antiga, cada uma nos dois sentidos', () => {
    expect(CAMPOS_DE_ORDEM_DAS_EMPRESAS.map(({ chave }) => chave)).toEqual([
      'ULTIMA_CONVERSA',
      'CHEGADA',
      'NOME',
      'SITE',
      'PESSOAS',
    ]);
    const t = chave => chave;
    const grupos = gruposDeOrdem(t, CAMPOS_DE_ORDEM_DAS_EMPRESAS);
    expect(grupos[4]).toEqual({
      label: 'RELACIONAMENTOS.LISTA.ORDENAR.CAMPOS.PESSOAS',
      options: [
        expect.objectContaining({
          value: 'mais_pessoas',
          shortLabel: 'RELACIONAMENTOS.LISTA.ORDENAR.ESCOLHIDA.PESSOAS_MAIS',
        }),
        expect.objectContaining({ value: 'menos_pessoas' }),
      ],
    });
  });

  it('cada ordem vai e volta pela preferência `companies_sort_by`', () => {
    const valores = CAMPOS_DE_ORDEM_DAS_EMPRESAS.flatMap(({ ordens }) =>
      ordens.map(({ value }) => value)
    );
    const guardadas = valores.map(valor =>
      preferenciaNaTabela(NA_PREFERENCIA_DAS_EMPRESAS, valor)
    );
    expect(new Set(guardadas).size).toBe(10);
    expect(
      guardadas.map(guardada =>
        ordemNaTabela(NA_PREFERENCIA_DAS_EMPRESAS, guardada)
      )
    ).toEqual(valores);
    expect(ordemNaTabela(NA_PREFERENCIA_DAS_EMPRESAS, undefined)).toBe(
      'ultima_conversa'
    );
  });

  it('a empresa passa pela cidade e por quando chegou', () => {
    const agora = AGORA;
    const empresa = { city: 'Santos', created_at: agora / 1000 - 86_400 * 10 };
    expect(empresaPassaNosFiltros(empresa, {}, agora)).toBe(true);
    expect(empresaPassaNosFiltros(empresa, { cidade: 'Santos' }, agora)).toBe(
      true
    );
    expect(empresaPassaNosFiltros(empresa, { cidade: 'Rio' }, agora)).toBe(
      false
    );
    expect(
      empresaPassaNosFiltros(empresa, { chegouEm: 'ultimos_30' }, agora)
    ).toBe(true);
    expect(
      empresaPassaNosFiltros(empresa, { chegouEm: 'ultimos_7' }, agora)
    ).toBe(false);
  });
});

describe('useFichaDaEmpresa: as ações que vieram da ficha antiga', () => {
  const fonteDe = (extra = {}) => ({
    empresa: vi
      .fn()
      .mockResolvedValue({ id: 1, name: 'E1', contacts_count: 1 }),
    pessoasDaEmpresa: vi.fn().mockResolvedValue([]),
    conversasDaEmpresa: vi.fn().mockResolvedValue([]),
    cardsDaEmpresa: vi.fn().mockResolvedValue([]),
    notasDaEmpresa: vi.fn().mockResolvedValue([]),
    midiasDaEmpresa: vi.fn().mockResolvedValue({ itens: [], total: 4 }),
    porPessoaNaEmpresa: vi.fn().mockResolvedValue(),
    tirarPessoaDaEmpresa: vi.fn().mockResolvedValue(),
    salvarEmpresa: vi.fn(),
    apagarEmpresa: vi.fn().mockResolvedValue({ naFila: false }),
    ...extra,
  });

  it('só lê as mídias com a chave ligada', async () => {
    const fonte = fonteDe();
    const sem = useFichaDaEmpresa(fonte, ref(1));
    await sem.carregar();
    expect(fonte.midiasDaEmpresa).not.toHaveBeenCalled();
    expect(sem.midias.value).toEqual({ itens: [], total: 0 });
    const com = useFichaDaEmpresa(fonte, ref(1), { comMidias: () => true });
    await com.carregar();
    expect(com.midias.value.total).toBe(4);
  });

  it('pôr pessoa grava e relê a empresa e as partes das pessoas', async () => {
    const fonte = fonteDe();
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    fonte.empresa.mockResolvedValue({ id: 1, name: 'E1', contacts_count: 2 });
    fonte.pessoasDaEmpresa.mockResolvedValue([{ id: 7 }]);
    expect(await ficha.porPessoa(7)).toBe(true);
    expect(fonte.porPessoaNaEmpresa).toHaveBeenCalledWith(1, 7);
    expect(ficha.empresa.value.contacts_count).toBe(2);
    expect(ficha.pessoas.value).toEqual([{ id: 7 }]);
    expect(fonte.notasDaEmpresa).toHaveBeenCalledTimes(2);
  });

  // #3078 (revisão) — "Desfazer" de quem veio de outra empresa: volta para lá.
  it('devolver pessoa a põe de volta na empresa de antes e relê esta', async () => {
    const fonte = fonteDe();
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.devolverPessoa(7, 12)).toBe(true);
    expect(fonte.porPessoaNaEmpresa).toHaveBeenCalledWith(12, 7);
    expect(fonte.pessoasDaEmpresa).toHaveBeenCalledTimes(2);
  });

  // #3079 — apagar diz se a empresa saiu na hora ou ficou na fila do servidor.
  it('apagar devolve { naFila } e null quando falha', async () => {
    const fonte = fonteDe();
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.apagar()).toEqual({ naFila: false });
    fonte.apagarEmpresa.mockResolvedValue({ naFila: true });
    expect(await ficha.apagar()).toEqual({ naFila: true });
    fonte.apagarEmpresa.mockRejectedValue(erroHttp(500));
    expect(await ficha.apagar()).toBeNull();
  });

  // #3078 (revisão) — pôr e logo tirar: a resposta atrasada da primeira
  // releitura não troca a da segunda.
  it('releitura atrasada da mesma parte não troca a mais nova', async () => {
    const fonte = fonteDe();
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    let soltarAntiga;
    fonte.pessoasDaEmpresa
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            soltarAntiga = () => resolve([{ id: 'antiga' }]);
          })
      )
      .mockResolvedValueOnce([{ id: 'nova' }]);
    const antiga = ficha.relerParte('pessoas');
    await ficha.relerParte('pessoas');
    soltarAntiga();
    await antiga;
    expect(ficha.pessoas.value).toEqual([{ id: 'nova' }]);
  });

  it('tirar pessoa que já saiu continua certo mesmo se a releitura da empresa falhar', async () => {
    const fonte = fonteDe();
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    fonte.empresa.mockRejectedValue(erroHttp(500));
    expect(await ficha.tirarPessoa(7)).toBe(true);
    expect(ficha.empresa.value.name).toBe('E1');
  });

  it('o servidor recusou: devolve false e guarda a frase', async () => {
    const recusa = Object.assign(erroHttp(422), {
      response: { status: 422, data: { message: 'Site já usado.' } },
    });
    const fonte = fonteDe({ salvarEmpresa: vi.fn().mockRejectedValue(recusa) });
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.salvar({ empresa: { name: 'X' } })).toBe(false);
    expect(ficha.motivo.value).toBe('Site já usado.');
    expect(ficha.salvouEmParte.value).toBe(false);
  });

  it('gravou em parte: mostra a empresa como ficou e avisa', async () => {
    const parcial = Object.assign(new Error('foto'), {
      name: GRAVOU_EM_PARTE,
      response: { status: 422 },
      retomada: { empresaNaFicha: { id: 1, name: 'Nova' } },
    });
    const fonte = fonteDe({
      salvarEmpresa: vi.fn().mockRejectedValue(parcial),
    });
    const ficha = useFichaDaEmpresa(fonte, ref(1));
    await ficha.carregar();
    expect(await ficha.salvar({ empresa: { name: 'Nova' } })).toBe(false);
    expect(ficha.salvouEmParte.value).toBe(true);
    expect(ficha.empresa.value.name).toBe('Nova');
  });
});
