import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import { RECUSADO } from '../../carteira/recusas';
import { NAO_ACHEI, SEM_ACESSO } from '../../ficha/falhas';
import { aoMeioDia, erroHttp } from './apoio';

// A fonte real da carteira (#2897): fala com o servidor pelo cliente de API e
// devolve o formato das peças. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos/seguros_spec.rb.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    lista: vi.fn(),
    contagens: vi.fn(),
    resumo: vi.fn(),
    opcoesDeFiltro: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
    daPessoa: vi.fn(),
    daEmpresa: vi.fn(),
    corrigir: vi.fn(),
    cancelar: vi.fn(),
    voltarAAtivo: vi.fn(),
    linkDoPdf: vi.fn(),
    guardarPdf: vi.fn(),
    tirarPdf: vi.fn(),
  },
}));

const real = () => carteiraFonte({ demo: null });
const responde = (metodo, data) =>
  SegurosAPI[metodo].mockResolvedValue({ data });

// Um seguro como o servidor manda: datas sem hora, selo e dias prontos.
const DO_SERVIDOR = {
  id: 7,
  pessoaId: 23,
  tipo: 'auto',
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'ativo',
  dias: 17,
  canceladoEm: null,
  origem: { tipo: 'planilha', arquivo: null, em: 1700000000 },
};
const NA_TELA = {
  ...DO_SERVIDOR,
  comeca: aoMeioDia(2025, 11, 29),
  termina: aoMeioDia(2026, 11, 29),
};

describe('escolha da fonte', () => {
  it('fora da demonstração é a real', () => {
    expect(real().usaDemo).toBe(false);
  });

  it('sem módulo de demonstração (produção) `?demo=` cai na fonte real', () => {
    expect(carteiraFonte({ demo: 'cheio', carregarDemo: null }).usaDemo).toBe(
      false
    );
  });
});

describe('leituras de um seguro', () => {
  it('traduz as datas do servidor para segundos, ao meio-dia de quem lê', async () => {
    responde('seguro', DO_SERVIDOR);

    expect(await real().seguro(7)).toEqual(NA_TELA);
    expect(SegurosAPI.seguro).toHaveBeenCalledWith(7);
  });

  it('seguro sem data de início fica sem data', async () => {
    responde('seguro', { ...DO_SERVIDOR, comeca: null });

    expect((await real().seguro(7)).comeca).toBeNull();
  });

  it('selo, dias e instantes seguem como vieram', async () => {
    responde('seguro', { ...DO_SERVIDOR, canceladoEm: 1700000500 });

    const seguro = await real().seguro(7);

    expect(seguro.selo).toBe('ativo');
    expect(seguro.dias).toBe(17);
    expect(seguro.canceladoEm).toBe(1700000500);
    expect(seguro.origem.em).toBe(1700000000);
  });

  it.each([
    ['daPessoa', 23],
    ['daEmpresa', 9],
  ])('%s devolve os seguros com as datas traduzidas', async (metodo, id) => {
    responde(metodo, [DO_SERVIDOR]);

    expect(await real()[metodo](id)).toEqual([NA_TELA]);
    expect(SegurosAPI[metodo]).toHaveBeenCalledWith(id);
  });
});

describe('a lista', () => {
  it('pede só o que está preenchido e devolve itens, total e se tem mais', async () => {
    responde('lista', { itens: [DO_SERVIDOR], total: 31, temMais: true });

    const resposta = await real().listar({
      grupo: 'vence_7_dias',
      busca: '',
      ordem: 'vence_primeiro',
      pagina: 2,
      filtros: { tipo: 'auto', seguradora: '' },
    });

    expect(SegurosAPI.lista).toHaveBeenCalledWith({
      grupo: 'vence_7_dias',
      ordem: 'vence_primeiro',
      pagina: 2,
      'filtros[tipo]': 'auto',
    });
    expect(resposta).toEqual({ itens: [NA_TELA], total: 31, temMais: true });
  });

  it('leva a busca e a seguradora quando há', async () => {
    responde('lista', { itens: [], total: 0, temMais: false });

    await real().listar({
      busca: 'AT-0004',
      filtros: { tipo: '', seguradora: 'Horizonte Seguros' },
    });

    expect(SegurosAPI.lista).toHaveBeenCalledWith({
      busca: 'AT-0004',
      'filtros[seguradora]': 'Horizonte Seguros',
    });
  });

  it('as contagens levam a busca e os filtros, nunca o grupo', async () => {
    const contagens = { todos: 4, vence_7_dias: 1 };
    responde('contagens', contagens);

    const resposta = await real().contagens('seguros', {
      busca: 'ana',
      filtros: { tipo: 'auto' },
    });

    expect(SegurosAPI.contagens).toHaveBeenCalledWith({
      busca: 'ana',
      'filtros[tipo]': 'auto',
    });
    expect(resposta).toEqual(contagens);
  });

  it('as contagens sem consulta não mandam nada', async () => {
    responde('contagens', {});

    await real().contagens('seguros');

    expect(SegurosAPI.contagens).toHaveBeenCalledWith({});
  });

  it.each([
    ['resumo', 'resumo', { total: 4, vence7: 1 }],
    ['opcoesDeFiltro', 'opcoesDeFiltro', { tipos: ['auto'], seguradoras: [] }],
  ])('%s devolve o que o servidor mandou', async (metodo, daApi, data) => {
    responde(daApi, data);

    expect(await real()[metodo]()).toEqual(data);
  });
});

describe('a história', () => {
  it('traduz as datas das mudanças e deixa o resto como veio', async () => {
    responde('historia', [
      {
        tipo: 'corrigido',
        quando: 1700000900,
        quem: { id: 1, nome: 'Bia' },
        mudancas: [
          { campo: 'termina', antes: '2026-11-29', depois: '2026-12-05' },
          { campo: 'valor', antes: 610, depois: 640 },
          { campo: 'comeca', antes: null, depois: '2025-12-05' },
        ],
      },
      { tipo: 'cancelado', quando: 1700000800, quem: null, mudancas: null },
    ]);

    const [corrigido, cancelado] = await real().historia(7);

    expect(SegurosAPI.historia).toHaveBeenCalledWith(7);
    expect(corrigido.quando).toBe(1700000900);
    expect(corrigido.mudancas).toEqual([
      {
        campo: 'termina',
        antes: aoMeioDia(2026, 11, 29),
        depois: aoMeioDia(2026, 12, 5),
      },
      { campo: 'valor', antes: 610, depois: 640 },
      { campo: 'comeca', antes: null, depois: aoMeioDia(2025, 12, 5) },
    ]);
    expect(cancelado.mudancas).toBeNull();
  });
});

describe('escritas', () => {
  it('corrigir manda a data como "AAAA-MM-DD" e devolve o seguro da tela', async () => {
    responde('corrigir', DO_SERVIDOR);

    const seguro = await real().corrigir(7, {
      termina: aoMeioDia(2026, 12, 5),
      valor: 640,
    });

    expect(SegurosAPI.corrigir).toHaveBeenCalledWith(7, {
      termina: '2026-12-05',
      valor: 640,
    });
    expect(seguro).toEqual(NA_TELA);
  });

  it('corrigir manda `null` para apagar a data de início e o valor', async () => {
    responde('corrigir', DO_SERVIDOR);

    await real().corrigir(7, { comeca: null, valor: null });

    expect(SegurosAPI.corrigir).toHaveBeenCalledWith(7, {
      comeca: null,
      valor: null,
    });
  });

  it.each(['cancelar', 'voltarAAtivo', 'tirarPdf'])(
    '%s devolve o seguro da tela',
    async metodo => {
      responde(metodo, DO_SERVIDOR);

      expect(await real()[metodo](7)).toEqual(NA_TELA);
      expect(SegurosAPI[metodo]).toHaveBeenCalledWith(7);
    }
  );

  it('guardarPdf leva o arquivo e devolve o seguro da tela', async () => {
    const arquivo = new File(['%PDF-1.4'], 'apolice.pdf', {
      type: 'application/pdf',
    });
    responde('guardarPdf', { ...DO_SERVIDOR, temPdf: true });

    const seguro = await real().guardarPdf(7, arquivo);

    expect(SegurosAPI.guardarPdf).toHaveBeenCalledWith(7, arquivo);
    expect(seguro).toEqual({ ...NA_TELA, temPdf: true });
  });

  it('pdf devolve só o link, pedido de novo a cada chamada', async () => {
    responde('linkDoPdf', { url: 'https://arquivos.example/apolice' });
    const fonte = real();

    expect(await fonte.pdf(7)).toBe('https://arquivos.example/apolice');
    await fonte.pdf(7);

    expect(SegurosAPI.linkDoPdf).toHaveBeenCalledTimes(2);
  });
});

describe('recusas', () => {
  it.each([
    [404, NAO_ACHEI],
    [401, SEM_ACESSO],
    [403, SEM_ACESSO],
  ])('%i vira a falha %s', async (status, nome) => {
    SegurosAPI.seguro.mockRejectedValue(erroHttp(status));

    await expect(real().seguro(7)).rejects.toMatchObject({
      name: nome,
      codigo: '',
    });
  });

  it('422 vira RECUSADO com o código que o servidor mandou', async () => {
    SegurosAPI.corrigir.mockRejectedValue(
      erroHttp(422, { error: 'termina_antes' })
    );

    await expect(real().corrigir(7, { valor: 1 })).rejects.toMatchObject({
      name: RECUSADO,
      codigo: 'termina_antes',
    });
  });

  it('422 sem código fica RECUSADO com código vazio', async () => {
    SegurosAPI.cancelar.mockRejectedValue(erroHttp(422, {}));

    await expect(real().cancelar(7)).rejects.toMatchObject({
      name: RECUSADO,
      codigo: '',
    });
  });

  it('413 (PDF maior que o servidor aceita) vira RECUSADO com `arquivo_grande`', async () => {
    const arquivo = new File(['%PDF-1.4'], 'a.pdf', {
      type: 'application/pdf',
    });
    SegurosAPI.guardarPdf.mockRejectedValue(erroHttp(413, '<html></html>'));

    await expect(real().guardarPdf(7, arquivo)).rejects.toMatchObject({
      name: RECUSADO,
      codigo: 'arquivo_grande',
    });
  });

  it('guarda a falha original como causa', async () => {
    const falha = erroHttp(404);
    SegurosAPI.historia.mockRejectedValue(falha);

    await expect(real().historia(7)).rejects.toMatchObject({ cause: falha });
  });

  it.each([
    ['listar', 'lista'],
    ['contagens', 'contagens'],
    ['resumo', 'resumo'],
    ['opcoesDeFiltro', 'opcoesDeFiltro'],
    ['daPessoa', 'daPessoa'],
    ['daEmpresa', 'daEmpresa'],
    ['pdf', 'linkDoPdf'],
    ['guardarPdf', 'guardarPdf'],
    ['tirarPdf', 'tirarPdf'],
    ['voltarAAtivo', 'voltarAAtivo'],
  ])('%s também dá nome ao 401', async (metodo, daApi) => {
    SegurosAPI[daApi].mockRejectedValue(erroHttp(401));

    await expect(real()[metodo](7)).rejects.toMatchObject({
      name: SEM_ACESSO,
    });
  });

  it('outra falha (rede, 500) sobe como veio', async () => {
    const falha = erroHttp(500);
    SegurosAPI.resumo.mockRejectedValue(falha);

    await expect(real().resumo()).rejects.toBe(falha);
  });
});
