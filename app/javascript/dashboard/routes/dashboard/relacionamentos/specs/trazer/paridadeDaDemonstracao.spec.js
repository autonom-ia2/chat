import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import { LENDO, PLANILHA, montarFonteReal, responder } from './apoioDoServidor';

// #2896, Fatia 2 (item 18 da revisão do dono) — a demonstração é o que o dono
// abre para aprovar a tela: ela tem de entregar o MESMO formato da fonte real.
// Aqui as duas fontes são comparadas de verdade: a real lê corpos como o
// servidor os manda (os de spec/requests/api/v1/accounts/
// relacionamentos_trazer_spec.rb, relacionamentos_trazer_linhas_spec.rb e
// relacionamentos_trazer_respostas_spec.rb) e a demonstração lê a planilha de
// exemplo. O que se compara é a forma: as chaves de cada parte e o tipo de cada
// valor (E3: também a pergunta "Quais destes querem dizer cliente?", a resposta
// dela, `resumo.clientes` e as recusas novas). O que cada uma faz está em demonstracaoLinhas.spec.js e
// demonstracaoColunas.spec.js.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);

beforeEach(() => esquecerMemoriaDaDemo());
afterEach(() => vi.resetAllMocks());

// ---- a forma de um valor: as chaves e o tipo de cada coisa -----------------

// De uma lista fica a forma de cada item diferente (a ordem e a quantidade não
// contam): duas listas têm a mesma forma quando têm os mesmos tipos de item.
const forma = valor => {
  if (Array.isArray(valor)) {
    return [...new Set(valor.map(item => JSON.stringify(forma(item))))].sort();
  }
  if (valor === null) return 'null';
  if (typeof valor !== 'object') return typeof valor;
  return Object.fromEntries(
    Object.keys(valor)
      .sort()
      .map(chave => [chave, forma(valor[chave])])
  );
};

// ---- os corpos do servidor --------------------------------------------------

const DUPLICADAS = [
  {
    linha: 2,
    telefone: '11987650001',
    email: 'ana.albuquerino@exemplo.com.br',
  },
  { linha: 7, telefone: '11987650001', email: '' },
];

// Cada tipo de linha como o servidor a manda aberta (com o `motivo`; a repetida
// não tem).
const ABERTAS = {
  telefone: {
    linha: 4,
    tipo: 'telefone',
    nome: 'Carla Carvalhedo',
    valor: '(11) 2345-678',
    estado: 'aberto',
    motivo: 'invalid_brazilian_mobile_number',
  },
  email: {
    linha: 5,
    tipo: 'email',
    nome: 'Davi Dornelino',
    valor: 'davi.dornelino.exemplo.com.br',
    estado: 'aberto',
    motivo: 'invalid_email',
  },
  nome: {
    linha: 3,
    tipo: 'nome',
    nome: '',
    valor: '',
    contato: '11987650003',
    estado: 'aberto',
    motivo: 'blank_name',
  },
  sem_contato: {
    linha: 6,
    tipo: 'sem_contato',
    nome: 'Elisa Esteveira',
    valor: '',
    estado: 'aberto',
    motivo: 'missing_contact',
  },
  duplicada: {
    linha: 7,
    tipo: 'duplicada',
    nome: 'Ana Repetida',
    valor: '11987650001',
    estado: 'aberto',
    outraLinha: 2,
    duplicadas: DUPLICADAS,
  },
  formula: {
    linha: 8,
    tipo: 'formula',
    campo: 'empresa',
    nome: 'Elisa Esteveira',
    estado: 'aberto',
    motivo: 'formula_detected',
  },
};

// O que a linha guardada traz a mais: o valor como vai ser gravado ou, na
// repetida, a linha com que a pessoa ficou. A linha `formula` nunca é guardada.
const GUARDADO = {
  telefone: { corrigido: '+5511987650004' },
  email: { corrigido: 'davi.dornelino@exemplo.com.br' },
  nome: { corrigido: 'Fabio Ferreirinho' },
  sem_contato: { corrigido: '+5511987650007' },
  duplicada: { ficar_com: 7 },
};

const semMotivo = ({ motivo, ...linha }) => linha;
const doServidor = (tipo, estado) => {
  if (estado === 'aberto') return ABERTAS[tipo];
  const base = { ...semMotivo(ABERTAS[tipo]), estado };
  return estado === 'guardado' ? { ...base, ...GUARDADO[tipo] } : base;
};

const TIPOS = Object.keys(ABERTAS);
const ESTADOS = ['aberto', 'guardado', 'deixado'];
const EXISTE = (tipo, estado) => !(tipo === 'formula' && estado === 'guardado');
const CASOS = TIPOS.flatMap(tipo =>
  ESTADOS.filter(estado => EXISTE(tipo, estado)).map(estado => [tipo, estado])
);

// O GET da leitura pronta, como o servidor responde depois que a pessoa
// respondeu às duas perguntas.
const corpo = (extra = {}) => ({
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    { indice: 2, nome: 'E-mail', destino: 'email' },
    { indice: 3, nome: 'Empresa', destino: 'empresa' },
    {
      indice: 4,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    },
    {
      indice: 5,
      nome: 'Aniversário',
      destino: 'informacao',
      campo: { nome: 'Aniversário', para_que_serve: '' },
    },
  ],
  tem_empresa: true,
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {},
  resumo: {
    total: 8,
    novas: 1,
    completadas: 1,
    comProblema: 6,
    juntadas: 0,
    entram: 2,
    clientes: 0,
  },
  exemplos: [
    {
      nome: 'Ana Albuquerino',
      telefone: '+5511987650001',
      email: 'ana.albuquerino@exemplo.com.br',
      empresa: 'Padaria Bom Dia',
      cliente: false,
    },
    {
      nome: 'Bruno Brandolim',
      telefone: '+5511987650002',
      email: '',
      empresa: '',
      cliente: false,
    },
  ],
  problemas: TIPOS.map(tipo => ABERTAS[tipo]),
  problemas_total: 6,
  pagina: 1,
  por_pagina: 200,
  ...extra,
});

// E3 — a pergunta "Quais destes querem dizer cliente?", como o servidor a
// manda quando há coluna de cliente (o contrato está no brief do E3).
const DOS_VALORES = {
  id: 'valores_cliente',
  coluna: 'Situação',
  indice: 4,
  preenchidas: 5,
  valores: [
    { chave: '9f2c1d', valor: 'Cliente', linhas: 3 },
    { chave: 'a01b77', valor: 'Interessado', linhas: 2 },
  ],
  outros: null,
};
const MAIS_DE_VINTE = { ...DOS_VALORES, outros: { valores: 7, linhas: 9 } };
const COM_COLUNA_DE_CLIENTE = {
  perguntas: [
    { id: 'clientes' },
    DOS_VALORES,
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: { clientes: 'algumas', coluna_cliente: 4 },
};

const RESPONDIDA = {
  perguntas: COM_COLUNA_DE_CLIENTE.perguntas,
  respostas: {
    clientes: 'algumas',
    coluna_cliente: 4,
    valores_cliente: { modo: 'valores', chaves: ['9f2c1d'] },
    telefone: 'da_pessoa',
  },
  resumo: { ...corpo().resumo, clientes: 1 },
  colunas: corpo().colunas.map(coluna => {
    if (coluna.indice === 1) {
      return { indice: 1, nome: 'Celular', destino: 'telefone' };
    }
    return coluna.indice === 4
      ? { indice: 4, nome: 'Situação', destino: 'cliente' }
      : coluna;
  }),
};

// ---- as duas fontes ---------------------------------------------------------

const realComLeitura = async resposta => {
  const { fonte } = montarFonteReal();
  responde('enviar', LENDO);
  responde('leitura', resposta);
  return { fonte, leitura: await fonte.ler(PLANILHA) };
};

const demoComLeitura = async (planilha = null) => {
  const fonte = trazerFonte({
    demo: 'cheio',
    planilha,
    carregarDemo: () => import('../../demo/trazer.js'),
    atraso: 0,
    atrasoDaLeitura: 0,
  });
  return { fonte, leitura: await fonte.ler(null) };
};

const daLinha = (leitura, linha) =>
  leitura.problemas.find(problema => problema.linha === linha);
const doTipo = (leitura, tipo) =>
  leitura.problemas.find(problema => problema.tipo === tipo);

// A linha de exemplo de cada tipo e o valor que a conserta.
const NA_DEMO = {
  telefone: { linha: 14, valor: '(11) 97380-0014' },
  email: { linha: 37, valor: 'rita.carvalhedo@exemplo.com.br' },
  nome: { linha: 62, valor: 'Ana Imbirussu' },
  sem_contato: { linha: 171, valor: '(11) 98123-0171' },
  duplicada: { linha: 143, valor: 143 },
  formula: { linha: 118 },
};

const linhaDaDemo = async (tipo, estado) => {
  const { fonte, leitura } = await demoComLeitura();
  const { linha, valor } = NA_DEMO[tipo];
  if (estado === 'aberto') return daLinha(leitura, linha);
  const depois =
    estado === 'guardado'
      ? await fonte.consertar(leitura.id, linha, valor)
      : await fonte.deixarDeFora(leitura.id, linha);
  return daLinha(depois, linha);
};

const linhaDaReal = async (tipo, estado) => {
  const { leitura } = await realComLeitura(
    corpo({ problemas: [doServidor(tipo, estado)], problemas_total: 1 })
  );
  return leitura.problemas[0];
};

// ---- a leitura inteira ------------------------------------------------------

describe('a leitura inteira tem a mesma forma nas duas fontes', () => {
  it('as mesmas partes, com os mesmos tipos de valor', async () => {
    const real = await realComLeitura(corpo());
    const demo = await demoComLeitura();
    expect(forma(demo.leitura)).toEqual(forma(real.leitura));
  });

  it('a planilha de exemplo tem todos os tipos de linha que o servidor manda', async () => {
    const { leitura } = await demoComLeitura();
    expect([...new Set(leitura.problemas.map(p => p.tipo))].sort()).toEqual(
      [...TIPOS].sort()
    );
    expect(leitura.problemas.every(p => p.estado === 'aberto')).toBe(true);
    expect(leitura.problemasTotal).toBe(leitura.problemas.length);
    expect(leitura.resumo.comProblema).toBe(leitura.problemas.length);
  });

  it('depois de respondidas as perguntas, as respostas e as colunas também', async () => {
    const real = await realComLeitura(corpo(RESPONDIDA));
    const { fonte, leitura } = await demoComLeitura();
    const situacao = leitura.colunas.find(coluna => coluna.nome === 'Situação');
    const respostas = {
      clientes: 'algumas',
      colunaCliente: situacao.indice,
      telefone: 'da_pessoa',
    };
    // Marcar a coluna já devolve a leitura pronta, com a pergunta dos valores.
    const { chave } = (await fonte.responder(leitura.id, respostas)).perguntas
      .find(pergunta => pergunta.id === 'valores_cliente')
      .valores.find(valor => valor.valor === 'Cliente');
    const demo = await fonte.responder(leitura.id, {
      ...respostas,
      valores_cliente: { modo: 'valores', chaves: [chave] },
    });
    expect(forma(demo)).toEqual(forma(real.leitura));
    expect(forma(demo.respostas)).toEqual({
      clientes: 'string',
      colunaCliente: 'number',
      telefone: 'string',
      valores_cliente: { chaves: ['"string"'], modo: 'string' },
    });
  });

  it('"toda linha com algo escrito" volta só com o modo, nas duas', async () => {
    const preenchidas = { modo: 'preenchidas' };
    const real = await realComLeitura(
      corpo({
        ...RESPONDIDA,
        respostas: { ...RESPONDIDA.respostas, valores_cliente: preenchidas },
      })
    );
    const { fonte, leitura } = await demoComLeitura();
    const situacao = leitura.colunas.find(coluna => coluna.nome === 'Situação');
    const respostas = { clientes: 'algumas', colunaCliente: situacao.indice };
    await fonte.responder(leitura.id, respostas);
    const demo = await fonte.responder(leitura.id, {
      ...respostas,
      valores_cliente: preenchidas,
    });
    expect(demo.respostas.valores_cliente).toEqual(preenchidas);
    expect(real.leitura.respostas.valores_cliente).toEqual(preenchidas);
  });

  it('o aviso de mudança desfeita vem na mesma chave', async () => {
    const real = await realComLeitura(corpo({ aviso: 'mudanca_desfeita' }));
    const { fonte, leitura } = await demoComLeitura('mudanca_desfeita');
    const email = leitura.colunas.find(coluna => coluna.destino === 'email');
    await fonte.trocarDestino(leitura.id, email.indice, 'nao_guardar');
    const demo = await fonte.retomar(leitura.id);
    expect(demo.aviso).toBe(real.leitura.aviso);
    expect(forma(demo)).toEqual(forma(real.leitura));
  });
});

// ---- as colunas, as perguntas e os exemplos ----------------------------------

describe('as colunas, as perguntas e os exemplos têm a mesma forma', () => {
  const partes = async () => ({
    real: (await realComLeitura(corpo())).leitura,
    demo: (await demoComLeitura()).leitura,
  });

  it.each([
    ['a coluna comum', coluna => !coluna.duvidosa && !coluna.campo],
    ['a coluna duvidosa', coluna => coluna.duvidosa === true],
    ['a informação, com o campo', coluna => Boolean(coluna.campo)],
  ])('%s', async (_nome, qual) => {
    const { real, demo } = await partes();
    expect(demo.colunas.filter(qual).length).toBeGreaterThan(0);
    expect(forma(demo.colunas.filter(qual))).toEqual(
      forma(real.colunas.filter(qual))
    );
  });

  it('o índice de cada coluna é a posição dela na planilha, sem repetir', async () => {
    const { demo } = await partes();
    const indices = demo.colunas.map(coluna => coluna.indice);
    expect(new Set(indices).size).toBe(indices.length);
    expect(indices).toEqual([...indices].sort((a, b) => a - b));
  });

  it.each(['clientes', 'telefone'])('a pergunta "%s"', async id => {
    const { real, demo } = await partes();
    const pergunta = leitura => leitura.perguntas.find(item => item.id === id);
    expect(forma(pergunta(demo))).toEqual(forma(pergunta(real)));
  });

  // E3 — a pergunta dos valores só existe com coluna de cliente: nas duas
  // fontes ela tem as mesmas partes, com `outros` nulo ou com os dois números.
  it.each([
    ['com todos os valores na lista', DOS_VALORES, 'Situação'],
    ['com mais de 20 valores', MAIS_DE_VINTE, 'Aniversário'],
  ])('a pergunta "valores_cliente", %s', async (_nome, enviada, coluna) => {
    const real = await realComLeitura(
      corpo({
        ...COM_COLUNA_DE_CLIENTE,
        perguntas: [{ id: 'clientes' }, enviada],
      })
    );
    const { fonte, leitura } = await demoComLeitura();
    const { indice } = leitura.colunas.find(item => item.nome === coluna);
    await fonte.responder(leitura.id, {
      clientes: 'algumas',
      colunaCliente: indice,
    });
    const demo = await fonte.retomar(leitura.id);
    const pergunta = lida =>
      lida.perguntas.find(item => item.id === 'valores_cliente');
    expect(pergunta(demo)).toMatchObject({ coluna, indice });
    expect(forma(pergunta(demo))).toEqual(forma(pergunta(real.leitura)));
  });

  it('a pergunta do telefone aponta a coluna duvidosa pelo índice', async () => {
    const { demo } = await partes();
    const pergunta = demo.perguntas.find(item => item.id === 'telefone');
    const duvidosa = demo.colunas.find(coluna => coluna.duvidosa);
    expect(pergunta).toEqual({
      id: 'telefone',
      coluna: duvidosa.nome,
      indice: duvidosa.indice,
    });
  });

  it('os exemplos (o telefone já como a pessoa lê)', async () => {
    const { real, demo } = await partes();
    expect(forma(demo.exemplos)).toEqual(forma(real.exemplos));
    expect(real.exemplos[0].telefone).toBe('+55 11 98765-0001');
    demo.exemplos.forEach(exemplo => {
      expect(exemplo.telefone.startsWith('+55 11 9')).toBe(true);
    });
  });
});

// ---- cada tipo de linha, em cada estado --------------------------------------

describe('cada tipo de linha tem a mesma forma, em cada estado', () => {
  it.each(CASOS)('%s, %s', async (tipo, estado) => {
    const real = await linhaDaReal(tipo, estado);
    const demo = await linhaDaDemo(tipo, estado);
    expect(demo).toMatchObject({ tipo, estado });
    expect(forma(demo)).toEqual(forma(real));
  });

  it('a linha com fórmula num campo que a tela não conserta nunca é guardada', async () => {
    const { fonte, leitura } = await demoComLeitura();
    await expect(
      fonte.consertar(leitura.id, NA_DEMO.formula.linha, 'Casa Aurora')
    ).rejects.toMatchObject({
      name: 'VALOR_INVALIDO',
      motivo: 'formula_detected',
    });
  });

  it('o telefone de cada problema vem como na planilha, sem o código do país', async () => {
    const { leitura } = await demoComLeitura();
    const repetida = doTipo(leitura, 'duplicada');
    [
      doTipo(leitura, 'telefone').valor,
      doTipo(leitura, 'nome').contato,
      ...repetida.duplicadas.map(linha => linha.telefone),
    ].forEach(telefone => {
      expect(telefone.startsWith('(11) ')).toBe(true);
      expect(telefone.includes('+55')).toBe(false);
    });
  });
});

// ---- o que cada escrita devolve ------------------------------------------------

describe('cada escrita devolve a mesma forma nas duas fontes', () => {
  it('consertar, deixar de fora e voltar atrás devolvem a leitura inteira', async () => {
    const real = await realComLeitura(corpo());
    const demo = await demoComLeitura();
    const guardada = doServidor('telefone', 'guardado');
    responde('consertar', { problema: guardada, entram: 3 });
    responde('deixarDeFora', {
      problema: doServidor('telefone', 'deixado'),
      entram: 2,
    });
    responde('reabrir', { problema: ABERTAS.telefone, entram: 2 });
    const { linha, valor } = NA_DEMO.telefone;

    expect(
      forma(await demo.fonte.consertar(demo.leitura.id, linha, valor))
    ).toEqual(forma(await real.fonte.consertar(812, 4, '(11) 98765-0004')));
    expect(
      forma(await demo.fonte.deixarDeFora(demo.leitura.id, linha))
    ).toEqual(forma(await real.fonte.deixarDeFora(812, 4)));
    expect(forma(await demo.fonte.reabrir(demo.leitura.id, linha))).toEqual(
      forma(await real.fonte.reabrir(812, 4))
    );
  });

  it('a troca que vale na hora devolve a leitura inteira', async () => {
    const real = await realComLeitura(corpo());
    const demo = await demoComLeitura();
    responde('trocarColuna', corpo());
    const situacao = demo.leitura.colunas.find(c => c.nome === 'Situação');
    expect(
      forma(
        await demo.fonte.trocarDestino(
          demo.leitura.id,
          situacao.indice,
          'informacao'
        )
      )
    ).toEqual(forma(await real.fonte.trocarDestino(812, 4, 'informacao')));
  });

  it('a troca que faz ler a planilha de novo devolve só o marcador', async () => {
    const real = await realComLeitura(corpo());
    const demo = await demoComLeitura();
    responde('trocarColuna', LENDO);
    const email = demo.leitura.colunas.find(c => c.destino === 'email');
    const daReal = await real.fonte.trocarDestino(812, 2, 'nao_guardar');
    const daDemo = await demo.fonte.trocarDestino(
      demo.leitura.id,
      email.indice,
      'nao_guardar'
    );
    expect(daReal).toEqual({ situacao: 'lendo', id: 812 });
    expect(daDemo).toEqual({ situacao: 'lendo', id: demo.leitura.id });
  });

  it('retomar e "mostrar mais" devolvem a leitura inteira', async () => {
    const real = await realComLeitura(corpo({ problemas_total: 7 }));
    const demo = await demoComLeitura();
    responde('leitura', corpo({ problemas_total: 7 }));
    expect(forma(await demo.fonte.retomar(demo.leitura.id))).toEqual(
      forma(await real.fonte.retomar(812))
    );
    responde('leitura', corpo({ problemas_total: 7, pagina: 2 }));
    expect(forma(await demo.fonte.maisProblemas(demo.leitura.id))).toEqual(
      forma(await real.fonte.maisProblemas(812))
    );
  });

  it('a recusa de um valor tem o mesmo nome e leva o motivo', async () => {
    const real = await realComLeitura(corpo());
    const demo = await demoComLeitura();
    TrazerAPI.consertar.mockRejectedValueOnce(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: { error: 'valor_invalido', motivo: 'blank_phone_number' },
        },
      })
    );
    const daReal = await real.fonte.consertar(812, 4, '').catch(falha => falha);
    const daDemo = await demo.fonte
      .consertar(demo.leitura.id, NA_DEMO.telefone.linha, '')
      .catch(falha => falha);
    expect(daDemo).toBeInstanceOf(Error);
    expect({ name: daDemo.name, motivo: daDemo.motivo }).toEqual({
      name: daReal.name,
      motivo: daReal.motivo,
    });
  });
});

// ---- as recusas da pergunta dos valores (E3) ------------------------------------

describe('as recusas da pergunta dos valores têm o mesmo nome nas duas fontes', () => {
  const recusa422 = error =>
    Object.assign(new Error('422'), {
      response: { status: 422, data: { error } },
    });
  const comAColuna = async () => {
    const real = await realComLeitura(corpo(COM_COLUNA_DE_CLIENTE));
    const demo = await demoComLeitura();
    const situacao = demo.leitura.colunas.find(c => c.nome === 'Situação');
    const algumas = { clientes: 'algumas', colunaCliente: situacao.indice };
    await demo.fonte.responder(demo.leitura.id, algumas);
    return { real, demo, algumas };
  };

  it('o valor marcado que não é da coluna: tela desatualizada', async () => {
    const { real, demo, algumas } = await comAColuna();
    const deOutraColuna = { modo: 'valores', chaves: ['nao-existe'] };
    TrazerAPI.responder.mockRejectedValueOnce(
      recusa422('resposta_desconhecida')
    );
    const daReal = await real.fonte
      .responder(812, { valores_cliente: deOutraColuna })
      .catch(falha => falha);
    const daDemo = await demo.fonte
      .responder(demo.leitura.id, {
        ...algumas,
        valores_cliente: deOutraColuna,
      })
      .catch(falha => falha);
    expect(daDemo).toBeInstanceOf(Error);
    expect(daDemo.name).toBe(daReal.name);
    expect(daDemo.name).toBe('TELA_DESATUALIZADA');
  });

  it('trazer sem ter dito quem é cliente: FALTA_VALORES_CLIENTE', async () => {
    const { real, demo } = await comAColuna();
    TrazerAPI.trazer.mockRejectedValueOnce(recusa422('falta_valores_cliente'));
    const daReal = await real.fonte.trazer(812).catch(falha => falha);
    const daDemo = await demo.fonte
      .trazer(demo.leitura.id)
      .catch(falha => falha);
    expect(daDemo).toBeInstanceOf(Error);
    expect(daDemo.name).toBe(daReal.name);
    expect(daDemo.name).toBe('FALTA_VALORES_CLIENTE');
  });
});

// ---- o desfazer (Fatia 3) -------------------------------------------------------

describe('o desfazer tem a mesma forma e as mesmas recusas nas duas fontes', () => {
  const PRONTA_NA_DEMO = 'trazida-antiga-1';
  const recusa422 = () =>
    Object.assign(new Error('422'), {
      response: { status: 422, data: { error: 'nao_pode_desfazer' } },
    });
  const fontes = () => ({
    real: montarFonteReal().fonte,
    demo: trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
    }),
  });
  // A lista da demonstração que ainda está sendo trazida.
  const trazendoNaDemo = async demo => {
    const { id } = await demo.ler(null);
    return (await demo.trazer(id)).trazidaId;
  };

  it('a prévia: os mesmos três números', async () => {
    const { real, demo } = fontes();
    responde('previaDoDesfazer', { tira: 162, ficam: 18, devolve: 15 });
    const daReal = await real.previaDoDesfazer(812);
    const daDemo = await demo.previaDoDesfazer(PRONTA_NA_DEMO);
    expect(forma(daDemo)).toEqual(forma(daReal));
  });

  it('o pedido: a lista e a situação de agora, que é `desfazendo`', async () => {
    const { real, demo } = fontes();
    responde('desfazer', { id: 812, situacao: 'desfazendo' });
    const daReal = await real.desfazer(812);
    const daDemo = await demo.desfazer(PRONTA_NA_DEMO);
    expect(Object.keys(daDemo).sort()).toEqual(Object.keys(daReal).sort());
    expect(daDemo.situacao).toBe(daReal.situacao);
  });

  it('a lista sendo desfeita aparece no histórico e no andamento com a mesma situação', async () => {
    const { real, demo } = fontes();
    responde('listas', [
      {
        id: 812,
        arquivo: 'Clientes 2025.xlsx',
        quando: '2026-11-08T14:03:00Z',
        quem: 'Marina Pavanelli',
        total: 195,
        situacao: 'desfazendo',
        porcentagem: 100,
        pode_tentar: false,
        pode_desfazer: false,
      },
    ]);
    responde('andamento', {
      porcentagem: 100,
      situacao: 'desfazendo',
      total: 195,
      novas: 180,
      completadas: 15,
    });
    await demo.desfazer(PRONTA_NA_DEMO);
    const [daReal] = await real.historico();
    const daDemo = (await demo.historico()).find(l => l.id === PRONTA_NA_DEMO);
    // O id da demonstração é um texto; o do servidor, um número.
    expect(Object.keys(daDemo).sort()).toEqual(Object.keys(daReal).sort());
    expect([
      daDemo.situacao,
      daDemo.porcentagem,
      daDemo.podeTentar,
      daDemo.podeDesfazer,
    ]).toEqual([
      daReal.situacao,
      daReal.porcentagem,
      daReal.podeTentar,
      daReal.podeDesfazer,
    ]);
    expect((await demo.andamento(PRONTA_NA_DEMO)).situacao).toBe(
      (await real.andamento(812)).situacao
    );
  });

  it('a lista pronta e a que parou no meio dizem, do mesmo jeito, que dá para desfazer', async () => {
    const { real, demo } = fontes();
    const listaDoServidor = (id, situacao, podeTentar) => ({
      id,
      arquivo: `${id}.xlsx`,
      quando: '2026-11-08T14:03:00Z',
      quem: 'Marina Pavanelli',
      total: 195,
      situacao,
      porcentagem: 100,
      pode_tentar: podeTentar,
      pode_desfazer: true,
    });
    responde('listas', [
      listaDoServidor(1, 'pronto', false),
      listaDoServidor(2, 'falhou', true),
    ]);
    const resumo = listas =>
      ['pronto', 'falhou'].map(situacao => {
        const lista = listas.find(l => l.situacao === situacao);
        return [lista.situacao, lista.podeTentar, lista.podeDesfazer];
      });
    const daReal = resumo(await real.historico());
    expect(daReal).toEqual([
      ['pronto', false, true],
      ['falhou', true, true],
    ]);
    expect(resumo(await demo.historico())).toEqual(daReal);
  });

  it.each(['previaDoDesfazer', 'desfazer'])(
    '%s da lista que ainda está entrando: NAO_PODE_DESFAZER',
    async metodo => {
      const { real, demo } = fontes();
      TrazerAPI[metodo].mockRejectedValueOnce(recusa422());
      const daReal = await real[metodo](812).catch(falha => falha);
      const daDemo = await demo[metodo](await trazendoNaDemo(demo)).catch(
        falha => falha
      );
      expect(daDemo).toBeInstanceOf(Error);
      expect(daDemo.name).toBe(daReal.name);
      expect(daDemo.name).toBe('NAO_PODE_DESFAZER');
    }
  );
});

// ---- os métodos ---------------------------------------------------------------

describe('as duas fontes têm os mesmos métodos', () => {
  const metodos = fonte =>
    Object.keys(fonte)
      .filter(chave => typeof fonte[chave] === 'function')
      .sort();
  // Só a demonstração oferece um arquivo de mentira (`?planilha=`).
  const SO_NA_DEMO = ['arquivoDeExemplo'];

  it('com os mesmos nomes', () => {
    const real = trazerFonte({ demo: null });
    const demo = trazerFonte({
      demo: 'cheio',
      carregarDemo: () => import('../../demo/trazer.js'),
    });
    expect(real.usaDemo).toBe(false);
    expect(demo.usaDemo).toBe(true);
    // As duas têm o desfazer (Fatia 3): a tela não sabe qual está usando.
    expect(real.temDesfazer).toBe(true);
    expect(demo.temDesfazer).toBe(true);
    expect(metodos(demo)).toEqual([...metodos(real), ...SO_NA_DEMO].sort());
  });
});
