import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import {
  esquecerOsSegurosDaDemo,
  trazerSegurosFonte,
} from '../../fonte/trazerSegurosFonte';
import {
  LENDO,
  PLANILHA,
  erroHttp,
  montarFonteReal,
  pronta,
  responder,
} from '../trazer/apoioDoServidor';

// #2897 — a fonte de "Trazer minha lista" na conta de seguros
// (fonte/trazerSegurosFonte.js). A demonstração é o que o dono abre para
// aprovar a tela: ela tem de entregar as MESMAS chaves que a fonte real, que
// aqui lê corpos como o servidor os manda (tudo fictício). O que se compara é
// a forma do que os seguros acrescentam à leitura; o resto da leitura já é
// comparado em specs/trazer/paridadeDaDemonstracao.spec.js.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('../trazer/apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);

beforeEach(() => {
  esquecerMemoriaDaDemo();
  esquecerOsSegurosDaDemo();
});
afterEach(() => vi.resetAllMocks());

// ---- os corpos do servidor --------------------------------------------------

const DESTINOS = [
  'seguro_numero',
  'seguro_seguradora',
  'seguro_tipo',
  'seguro_termina',
  'seguro_comeca',
  'seguro_valor',
  'seguro_bem',
];
const ID = 812;
const LINHA_REPETIDA = 131;
const OUTRA_LINHA = 88;

const RESUMO = {
  total: 16,
  novas: 0,
  completadas: 0,
  comProblema: 3,
  juntadas: 0,
  entram: 12,
  clientes: 9,
  seguros: 12,
  pessoas: 9,
  pessoasQueJaEstavam: 2,
  porTipo: { auto: 7, residencial: 1, vida: 2, empresarial: 0, outro: 2 },
  repetidos: 1,
};

const REPETIDA = {
  linha: LINHA_REPETIDA,
  tipo: 'duplicado',
  nome: 'Rui Exemplo',
  estado: 'aberto',
  numero: 'EX-000131',
  outraLinha: OUTRA_LINHA,
  duplicadas: [
    {
      linha: OUTRA_LINHA,
      seguradora: 'Seguradora Exemplo',
      termina: '2027-03-10',
      valor: 3410,
      bem: 'Carro Exemplo 2022',
    },
    {
      linha: LINHA_REPETIDA,
      seguradora: 'Seguradora Exemplo',
      termina: '2027-03-10',
      valor: 3140,
      bem: null,
    },
  ],
};
const SEM_TERMINA = {
  linha: 40,
  tipo: 'falta_termina',
  motivo: 'falta',
  nome: 'Paulo Exemplo',
  estado: 'aberto',
};
// O servidor só manda o motivo na linha aberta.
const SEM_TERMINA_DEIXADA = {
  linha: SEM_TERMINA.linha,
  tipo: SEM_TERMINA.tipo,
  nome: SEM_TERMINA.nome,
  estado: 'deixado',
};
const NUMERO_ESTRAGADO = {
  linha: 41,
  tipo: 'numero',
  motivo: 'notacao_cientifica',
  nome: 'Lia Exemplo',
  estado: 'aberto',
};

const seguro = (extra = {}) => ({
  tipo: 'auto',
  ramoOriginal: 'Automóvel',
  seguradora: 'Seguradora Exemplo',
  numero: 'EX-000001',
  comeca: null,
  termina: '2027-03-10',
  valor: 3410,
  bem: 'Carro Exemplo 2022',
  ...extra,
});

// A leitura da planilha com seguros, com as linhas já conferidas.
const conferida = (extra = {}) =>
  pronta({
    id: ID,
    perguntas: [{ id: 'clientes' }, { id: 'seguros' }],
    respostas: { clientes: 'sim_todas', seguros: 'sim' },
    seguros: { destinos: DESTINOS, faltam: [] },
    resumo: RESUMO,
    exemplos: [
      {
        nome: 'Marina Exemplo',
        telefone: '+5511987650001',
        email: 'marina@exemplo.com.br',
        empresa: '',
        cliente: true,
        seguros: [seguro(), seguro({ tipo: 'outro', valor: null, bem: null })],
      },
    ],
    problemas: [SEM_TERMINA, NUMERO_ESTRAGADO, REPETIDA],
    problemas_total: 3,
    ...extra,
  });

// Antes da resposta: só a pergunta existe.
const semResposta = () =>
  pronta({
    id: ID,
    perguntas: [{ id: 'clientes' }, { id: 'seguros' }],
    problemas: [],
    problemas_total: 0,
  });

// ---- as duas fontes ---------------------------------------------------------

const fonteReal = () => trazerSegurosFonte({ listas: montarFonteReal().fonte });

// A fonte real que já leu a planilha: a primeira leitura é `resposta`.
const realComLeitura = async (resposta = conferida()) => {
  const fonte = fonteReal();
  responde('enviar', LENDO);
  responde('leitura', resposta);
  const leitura = await fonte.ler(PLANILHA);
  Object.values(TrazerAPI).forEach(pedido => pedido.mockClear());
  return { fonte, leitura };
};

const fonteDemo = () =>
  trazerSegurosFonte({
    demo: 'cheio',
    listas: trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
    }),
    carregarDemo: () => import('../../demo/trazerSeguros.js'),
  });

const SIM = { clientes: 'sim_todas', telefone: 'da_pessoa', seguros: 'sim' };

// A demonstração com a planilha de exemplo lida e o "sim" respondido.
const demoComSeguros = async () => {
  const fonte = fonteDemo();
  const { id } = await fonte.ler(PLANILHA);
  const marcador = await fonte.responder(id, SIM);
  return { fonte, id, marcador, leitura: await fonte.retomar(id) };
};

// ---- a forma ----------------------------------------------------------------

const chaves = objeto => Object.keys(objeto).sort();
// As formas diferentes que os itens de uma lista têm (só as chaves).
const formasDe = lista => [
  ...new Set(lista.map(item => chaves(item).join(','))),
];
const doTipo = (leitura, tipo) =>
  leitura.problemas.find(problema => problema.tipo === tipo);

describe('a pergunta e a resposta dos seguros', () => {
  it('as duas fontes trazem a pergunta, por último, antes de qualquer resposta', async () => {
    const real = await realComLeitura(semResposta());
    const demo = await fonteDemo().ler(PLANILHA);
    [real.leitura, demo].forEach(leitura => {
      expect(leitura.perguntas.at(-1)).toEqual({ id: 'seguros' });
      expect(leitura.respostas.seguros).toBeUndefined();
      expect(leitura.seguros).toBeUndefined();
    });
  });

  it('a resposta que muda devolve só o marcador, e a leitura volta com ela', async () => {
    const real = await realComLeitura(semResposta());
    responde('responder', LENDO);
    const doServidor = await real.fonte.responder(ID, SIM);
    const demo = await demoComSeguros();

    expect(doServidor).toEqual({ situacao: 'lendo', id: ID });
    expect(demo.marcador).toEqual({ situacao: 'lendo', id: demo.id });
    expect(demo.leitura.respostas.seguros).toBe('sim');
  });

  it('a fonte real manda a resposta dos seguros junto das outras', async () => {
    const real = await realComLeitura(semResposta());
    responde('responder', LENDO);
    await real.fonte.responder(ID, SIM);
    expect(TrazerAPI.responder).toHaveBeenCalledWith(ID, {
      clientes: 'sim_todas',
      telefone: 'da_pessoa',
      seguros: 'sim',
    });
  });

  it('a mesma resposta de novo devolve a leitura inteira', async () => {
    const demo = await demoComSeguros();
    const deNovo = await demo.fonte.responder(demo.id, SIM);
    expect(deNovo.situacao).toBeUndefined();
    expect(deNovo.respostas.seguros).toBe('sim');
  });

  it('com "não" a leitura não tem nada de seguro', async () => {
    const fonte = fonteDemo();
    const { id } = await fonte.ler(PLANILHA);
    await fonte.responder(id, { ...SIM, seguros: 'nao' });
    const leitura = await fonte.retomar(id);
    expect(leitura.respostas.seguros).toBe('nao');
    expect(leitura.seguros).toBeUndefined();
    expect(leitura.resumo.seguros).toBeUndefined();
  });
});

describe('a leitura conferida tem as mesmas chaves nas duas fontes', () => {
  it('o bloco dos seguros, o resumo e os seguros dos exemplos', async () => {
    const real = await realComLeitura();
    const demo = await demoComSeguros();

    expect(chaves(demo.leitura.seguros)).toEqual(chaves(real.leitura.seguros));
    expect(demo.leitura.seguros.destinos).toEqual(DESTINOS);
    expect(demo.leitura.seguros.faltam).toEqual([]);
    expect(chaves(demo.leitura.resumo)).toEqual(chaves(real.leitura.resumo));
    expect(chaves(demo.leitura.resumo.porTipo)).toEqual(
      chaves(real.leitura.resumo.porTipo)
    );
    const segurosDe = leitura =>
      leitura.exemplos.flatMap(exemplo => exemplo.seguros);
    expect(formasDe(segurosDe(demo.leitura))).toEqual(
      formasDe(segurosDe(real.leitura))
    );
    expect(segurosDe(demo.leitura).length).toBeGreaterThan(0);
  });

  it('cada linha com problema de seguro, pelo tipo', async () => {
    const real = await realComLeitura();
    const demo = await demoComSeguros();
    ['falta_termina', 'numero', 'duplicado'].forEach(tipo => {
      expect(chaves(doTipo(demo.leitura, tipo))).toEqual(
        chaves(doTipo(real.leitura, tipo))
      );
    });
    expect(formasDe(doTipo(demo.leitura, 'duplicado').duplicadas)).toEqual(
      formasDe(doTipo(real.leitura, 'duplicado').duplicadas)
    );
  });

  it('os números da demonstração fecham entre si', async () => {
    const { resumo } = (await demoComSeguros()).leitura;
    const somaDosTipos = Object.values(resumo.porTipo).reduce(
      (soma, quantos) => soma + quantos,
      0
    );
    expect(resumo.seguros).toBe(resumo.entram);
    expect(somaDosTipos).toBe(resumo.seguros);
    expect(resumo.pessoas).toBeLessThanOrEqual(resumo.seguros);
    expect(resumo.pessoasQueJaEstavam).toBeLessThanOrEqual(resumo.pessoas);
  });

  it('faltando coluna obrigatória, as linhas não são conferidas como seguro', async () => {
    const demo = await demoComSeguros();
    const fim = demo.leitura.colunas.find(
      coluna => coluna.destino === 'seguro_termina'
    );
    const leitura = await demo.fonte.trocarDestino(
      demo.id,
      fim.indice,
      'informacao'
    );
    expect(leitura.seguros.faltam).toEqual(['seguro_termina']);
    expect(leitura.resumo.seguros).toBeUndefined();
    expect(doTipo(leitura, 'duplicado')).toBeUndefined();
    leitura.exemplos.forEach(exemplo => {
      expect(exemplo.seguros).toBeUndefined();
    });

    // Apontar a coluna de novo completa as obrigatórias: a planilha é relida.
    const marcador = await demo.fonte.trocarDestino(
      demo.id,
      fim.indice,
      'seguro_termina'
    );
    expect(marcador).toEqual({ situacao: 'lendo', id: demo.id });
    expect((await demo.fonte.retomar(demo.id)).seguros.faltam).toEqual([]);
  });

  it('cada destino de seguro é de uma coluna só', async () => {
    const demo = await demoComSeguros();
    const doDestino = (leitura, destino) =>
      leitura.colunas.filter(coluna => coluna.destino === destino);
    const [bem] = doDestino(demo.leitura, 'seguro_bem');
    const leitura = await demo.fonte.trocarDestino(
      demo.id,
      bem.indice,
      'seguro_valor'
    );
    expect(doDestino(leitura, 'seguro_valor').map(c => c.indice)).toEqual([
      bem.indice,
    ]);
    expect(doDestino(leitura, 'seguro_bem')).toEqual([]);
  });
});

describe('as linhas com problema de seguro', () => {
  it('a apólice repetida é escolhida com `ficar_com` e a leitura é pedida de novo', async () => {
    const real = await realComLeitura();
    const guardada = { ...REPETIDA, estado: 'guardado', ficar_com: 131 };
    responde('consertar', { problema: guardada, entram: 13, clientes: 9 });
    responde(
      'leitura',
      conferida({
        problemas: [SEM_TERMINA, NUMERO_ESTRAGADO, guardada],
        resumo: { ...RESUMO, entram: 13, seguros: 13, pessoas: 10 },
      })
    );

    const leitura = await real.fonte.consertar(ID, LINHA_REPETIDA, 131);

    expect(TrazerAPI.consertar).toHaveBeenCalledWith(ID, LINHA_REPETIDA, {
      ficar_com: 131,
    });
    expect(doTipo(leitura, 'duplicado')).toMatchObject({
      estado: 'guardado',
      ficar_com: 131,
    });
    expect(leitura.resumo).toMatchObject({ seguros: 13, pessoas: 10 });
  });

  it('na demonstração a escolha guarda a linha, com as mesmas chaves', async () => {
    const demo = await demoComSeguros();
    const { linha } = doTipo(demo.leitura, 'duplicado');
    const leitura = await demo.fonte.consertar(demo.id, linha, linha);
    const escolhida = doTipo(leitura, 'duplicado');
    expect(escolhida).toMatchObject({ estado: 'guardado', ficar_com: linha });
    expect(chaves(escolhida)).toEqual(
      chaves({ ...REPETIDA, ficar_com: LINHA_REPETIDA })
    );
  });

  it('a linha de seguro sem conserto recusa o valor, nas duas fontes', async () => {
    const real = await realComLeitura();
    TrazerAPI.consertar.mockRejectedValueOnce(
      erroHttp(422, 'valor_invalido', { motivo: 'conserto_na_planilha' })
    );
    const demo = await demoComSeguros();
    const { linha } = doTipo(demo.leitura, 'numero');

    const recusas = await Promise.all([
      real.fonte.consertar(ID, NUMERO_ESTRAGADO.linha, 'EX-1').catch(e => e),
      demo.fonte.consertar(demo.id, linha, 'EX-1').catch(e => e),
    ]);
    recusas.forEach(recusa => {
      expect(recusa.name).toBe('VALOR_INVALIDO');
      expect(recusa.motivo).toBe('conserto_na_planilha');
    });
  });

  it('deixar de fora pede os números de novo, sem trocar as linhas da tela', async () => {
    const real = await realComLeitura();
    const deixada = SEM_TERMINA_DEIXADA;
    responde('deixarDeFora', { problema: deixada, entram: 12, clientes: 9 });
    // O servidor manda a primeira página; a tela fica com as linhas que tinha.
    responde(
      'leitura',
      conferida({
        problemas: [deixada],
        resumo: { ...RESUMO, pessoas: 8, pessoasQueJaEstavam: 1 },
      })
    );

    const leitura = await real.fonte.deixarDeFora(ID, SEM_TERMINA.linha);

    expect(TrazerAPI.leitura).toHaveBeenCalledWith(ID, 1);
    expect(leitura.problemas).toHaveLength(3);
    expect(doTipo(leitura, 'falta_termina').estado).toBe('deixado');
    expect(leitura.resumo).toMatchObject({
      pessoas: 8,
      pessoasQueJaEstavam: 1,
    });
  });

  it('se o pedido dos números falha, a linha fica como a escrita devolveu', async () => {
    const real = await realComLeitura();
    const deixada = SEM_TERMINA_DEIXADA;
    responde('deixarDeFora', { problema: deixada, entram: 11, clientes: 9 });
    TrazerAPI.leitura.mockRejectedValueOnce(new Error('Network Error'));

    const leitura = await real.fonte.deixarDeFora(ID, SEM_TERMINA.linha);

    expect(doTipo(leitura, 'falta_termina').estado).toBe('deixado');
    expect(leitura.resumo).toMatchObject({ entram: 11, seguros: 11 });
  });

  it('na planilha só de pessoas a fonte não pede os números de novo', async () => {
    const real = await realComLeitura(pronta({ id: ID }));
    const [linha] = real.leitura.problemas;
    responde('deixarDeFora', {
      problema: { ...linha, estado: 'deixado' },
      entram: 194,
    });
    const leitura = await real.fonte.deixarDeFora(ID, linha.linha);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(leitura.resumo.entram).toBe(194);
  });

  it('na demonstração deixar de fora e voltar atrás mudam só a linha', async () => {
    const demo = await demoComSeguros();
    const { linha } = doTipo(demo.leitura, 'falta_termina');
    const deixada = await demo.fonte.deixarDeFora(demo.id, linha);
    expect(doTipo(deixada, 'falta_termina').estado).toBe('deixado');
    // Como no servidor, o motivo só vem na linha aberta.
    expect(Object.keys(doTipo(deixada, 'falta_termina')).sort()).toEqual(
      Object.keys(SEM_TERMINA_DEIXADA).sort()
    );
    const aberta = await demo.fonte.reabrir(demo.id, linha);
    expect(doTipo(aberta, 'falta_termina').estado).toBe('aberto');
    expect(doTipo(aberta, 'falta_termina').motivo).toBe('falta');
    expect(aberta.resumo).toEqual(demo.leitura.resumo);
  });
});

describe('trazer e o andamento', () => {
  it('o trazer recusado por faltar coluna do seguro é tela desatualizada', async () => {
    const real = await realComLeitura();
    TrazerAPI.trazer.mockRejectedValueOnce(
      erroHttp(422, 'falta_coluna_do_seguro', { faltam: ['seguro_termina'] })
    );
    const demo = await demoComSeguros();
    const fim = demo.leitura.colunas.find(
      coluna => coluna.destino === 'seguro_termina'
    );
    await demo.fonte.trocarDestino(demo.id, fim.indice, 'informacao');

    const recusas = await Promise.all([
      real.fonte.trazer(ID).catch(e => e),
      demo.fonte.trazer(demo.id).catch(e => e),
    ]);
    recusas.forEach(recusa => {
      expect(recusa.name).toBe('TELA_DESATUALIZADA');
    });
  });

  it('a recusa que não é dos seguros sobe com o nome que a fonte das listas dá', async () => {
    const real = await realComLeitura();
    TrazerAPI.trazer.mockRejectedValueOnce(erroHttp(422, 'nada_para_trazer'));
    await expect(real.fonte.trazer(ID)).rejects.toMatchObject({
      name: 'NADA_PARA_TRAZER',
    });
  });

  it('o andamento da lista com seguros diz os seguros e as pessoas, nas duas fontes', async () => {
    const real = await realComLeitura();
    responde('trazer', { trazidaId: ID });
    responde('andamento', {
      porcentagem: 100,
      situacao: 'pronto',
      total: 12,
      novas: 0,
      completadas: 0,
      seguros: 12,
      pessoas: 9,
      pessoasNovas: 7,
      pessoasQueJaEstavam: 2,
    });
    expect(real.fonte.chegaram()).toBeNull();
    const { trazidaId } = await real.fonte.trazer(ID);
    const doServidor = await real.fonte.andamento(trazidaId);

    const demo = await demoComSeguros();
    const trazida = await demo.fonte.trazer(demo.id);
    const daDemo = await demo.fonte.andamento(trazida.trazidaId);

    expect(chaves(daDemo)).toEqual(chaves(doServidor));
    expect(real.fonte.chegaram()).toEqual({
      seguros: 12,
      pessoas: 9,
      pessoasNovas: 7,
      pessoasQueJaEstavam: 2,
    });
    expect(chaves(demo.fonte.chegaram())).toEqual(
      chaves(real.fonte.chegaram())
    );
    expect(demo.fonte.chegaram().seguros).toBe(demo.leitura.resumo.seguros);
  });

  it('a lista que não trouxe seguros não tem essas contas', async () => {
    const real = await realComLeitura(pronta({ id: ID }));
    responde('andamento', {
      porcentagem: 40,
      situacao: 'trazendo',
      total: 195,
      novas: 0,
      completadas: 0,
    });
    const andamento = await real.fonte.andamento(ID);
    expect(chaves(andamento)).toEqual(
      ['completadas', 'novas', 'porcentagem', 'situacao', 'total'].sort()
    );
    expect(real.fonte.chegaram()).toBeNull();
  });
});
