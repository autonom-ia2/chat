// #2897 — o que a planilha de exemplo de "Trazer minha lista" ganha na
// demonstração da conta de seguros: a pergunta "Esta planilha tem seguros?",
// as colunas de seguro, os números da conferência, os seguros das fichas de
// exemplo e as linhas que precisam da pessoa. Só é carregado no ambiente de
// desenvolvimento (fonte/trazerSegurosFonte.js, `import.meta.env.DEV`).
//
// Tudo é inventado e sempre igual. A leitura das pessoas é a da demonstração
// das listas (demo/trazer.js); aqui os seguros entram por cima dela, no mesmo
// formato que o servidor manda (specs/carteira/paridadeDoTrazerSeguros.spec.js).
import { TIPOS_DE_SEGURO } from '../carteira/tiposDeSeguro';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';

const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const SIM = 'sim';
const INFORMACAO = 'informacao';

// ---- as colunas de seguro da planilha de exemplo -----------------------------

// Vêm depois das colunas das pessoas. Os nomes são os da planilha do corretor.
const COLUNAS_DE_SEGURO = [
  { nome: 'Apólice', destino: 'seguro_numero' },
  { nome: 'Ramo', destino: 'seguro_tipo' },
  { nome: 'Cia', destino: 'seguro_seguradora' },
  { nome: 'Início', destino: 'seguro_comeca' },
  { nome: 'Fim', destino: 'seguro_termina' },
  { nome: 'Prêmio', destino: 'seguro_valor' },
  { nome: 'Bem', destino: 'seguro_bem' },
];
// Na ordem do servidor: os quatro obrigatórios e depois os outros.
const OBRIGATORIOS = [
  'seguro_numero',
  'seguro_seguradora',
  'seguro_tipo',
  'seguro_termina',
];
export const DESTINOS_DE_SEGURO = [
  ...OBRIGATORIOS,
  'seguro_comeca',
  'seguro_valor',
  'seguro_bem',
];

export const ehDestinoDeSeguro = destino =>
  DESTINOS_DE_SEGURO.includes(destino);

// ---- o que a demonstração lembra de cada leitura -------------------------------

// `resposta`: o que a pessoa respondeu à pergunta dos seguros. `destinos`: o
// destino de cada coluna que a demonstração dos seguros decide (pelo índice).
// `linhas`: o estado de cada linha com problema de seguro.
export const estadoInicial = () => ({
  resposta: undefined,
  destinos: {},
  linhas: {},
});

const destinosDeFabrica = colunasDasPessoas =>
  Object.fromEntries(
    COLUNAS_DE_SEGURO.map(({ destino }, posicao) => [
      colunasDasPessoas + posicao,
      destino,
    ])
  );

// "Sim" põe cada coluna de seguro no destino dela; "Não" tira os destinos de
// seguro (as colunas voltam a ser informação). `colunasDasPessoas` é quantas
// colunas a leitura das pessoas tem: as de seguro vêm depois delas.
export const comAResposta = (estado, resposta, colunasDasPessoas) => ({
  ...estado,
  resposta,
  destinos: resposta === SIM ? destinosDeFabrica(colunasDasPessoas) : {},
});

// Só uma coluna por destino de seguro: a nova toma o destino e a antiga volta
// a ser informação.
export const comODestino = (estado, indice, destino) => {
  const outras = Object.entries(estado.destinos).map(([chave, atual]) => [
    chave,
    ehDestinoDeSeguro(destino) && atual === destino ? INFORMACAO : atual,
  ]);
  return {
    ...estado,
    destinos: { ...Object.fromEntries(outras), [indice]: destino },
  };
};

// A coluna deixou de ser decidida aqui (voltou para a demonstração das listas).
export const semODestino = (estado, indice) => ({
  ...estado,
  destinos: Object.fromEntries(
    Object.entries(estado.destinos).filter(
      ([chave]) => Number(chave) !== indice
    )
  ),
});

// ---- as linhas com problema de seguro -----------------------------------------

const LINHA_QUE_FICA = 300;
const LINHA_REPETIDA = 303;
const PROBLEMAS_DE_SEGURO = [
  {
    linha: 301,
    tipo: 'falta_termina',
    motivo: 'falta',
    nome: 'Paulo Exemplo',
  },
  {
    linha: 302,
    tipo: 'numero',
    motivo: 'notacao_cientifica',
    nome: 'Lia Exemplo',
  },
  {
    linha: LINHA_REPETIDA,
    tipo: 'duplicado',
    nome: 'Rui Exemplo',
    numero: 'EX-001288',
    outraLinha: LINHA_QUE_FICA,
    duplicadas: [
      {
        linha: LINHA_QUE_FICA,
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
        bem: 'Carro Exemplo 2022',
      },
    ],
  },
];

export const ehLinhaDeSeguro = linha =>
  PROBLEMAS_DE_SEGURO.some(problema => problema.linha === linha);

const problemaDaLinha = linha =>
  PROBLEMAS_DE_SEGURO.find(problema => problema.linha === linha);

export const aceitaConserto = linha =>
  problemaDaLinha(linha)?.tipo === 'duplicado';

// A escolha na apólice repetida: ficar com esta linha a guarda; ficar com a
// outra deixa esta de fora.
export const comAEscolha = (estado, linha, ficarCom) => ({
  ...estado,
  linhas: {
    ...estado.linhas,
    [linha]:
      ficarCom === linha
        ? { estado: GUARDADO, ficar_com: linha }
        : { estado: DEIXADO },
  },
});

export const comALinha = (estado, linha, situacao) => ({
  ...estado,
  linhas: { ...estado.linhas, [linha]: { estado: situacao } },
});

// Como no servidor, o motivo só vem na linha aberta.
const problemasDeSeguro = estado =>
  PROBLEMAS_DE_SEGURO.map(({ motivo, ...problema }) => {
    const daLinha = estado.linhas[problema.linha] ?? { estado: ABERTO };
    const comMotivo = motivo && daLinha.estado === ABERTO;
    return { ...problema, ...daLinha, ...(comMotivo ? { motivo } : {}) };
  });

// ---- os números da conferência -------------------------------------------------

// Na planilha de exemplo algumas pessoas têm mais de um seguro.
const SEGUROS_A_MAIS_DA_MESMA_PESSOA = 46;
const LINHAS_IDENTICAS = 2;
// De cada cem seguros, quantos são de cada tipo; o resto é "outro".
const PARTES_DE_CEM = { auto: 54, residencial: 18, vida: 12, empresarial: 8 };
const CEM = 100;

const porTipo = seguros => {
  const contados = Object.fromEntries(
    TIPOS_DE_SEGURO.map(tipo => [
      tipo,
      Math.floor((seguros * (PARTES_DE_CEM[tipo] ?? 0)) / CEM),
    ])
  );
  const somados = Object.values(contados).reduce((soma, n) => soma + n, 0);
  return { ...contados, outro: seguros - somados };
};

// Uma linha é um seguro: entram os que a demonstração das listas diz que
// entram. As linhas com problema de seguro ficam de fora (na repetida, entra
// uma das duas).
const resumoComSeguros = resumo => {
  const seguros = resumo.entram;
  const pessoas = Math.max(0, seguros - SEGUROS_A_MAIS_DA_MESMA_PESSOA);
  return {
    ...resumo,
    total: resumo.total + PROBLEMAS_DE_SEGURO.length,
    comProblema: resumo.comProblema + PROBLEMAS_DE_SEGURO.length,
    juntadas: 0,
    clientes: pessoas,
    seguros,
    pessoas,
    pessoasQueJaEstavam: Math.min(pessoas, resumo.completadas),
    porTipo: porTipo(seguros),
    repetidos: LINHAS_IDENTICAS,
  };
};

// ---- os seguros das fichas de exemplo ------------------------------------------

const seguro = (tipo, ramoOriginal, numero, termina, valor, bem) => ({
  tipo,
  ramoOriginal,
  seguradora: 'Seguradora Exemplo',
  numero,
  comeca: null,
  termina,
  valor,
  bem,
});

// Uma pessoa com dois seguros, uma com um e uma com um ramo que virou "outro".
const SEGUROS_DOS_EXEMPLOS = [
  [
    seguro(
      'auto',
      'Automóvel',
      'EX-001234',
      '2027-03-10',
      3410,
      'Carro Exemplo 2022'
    ),
    seguro('residencial', 'Residência', 'EX-004410', '2027-06-01', 890, null),
  ],
  [seguro('vida', 'Vida individual', 'EX-002207', '2027-01-15', 1260, null)],
  [seguro('outro', 'Fiança locatícia', 'EX-003981', '2026-12-20', null, null)],
];

// ---- a leitura com os seguros por cima -----------------------------------------

// A coluna que fica como informação da pessoa leva o campo dela, com o título
// da coluna, como o servidor manda.
const SEM_PARA_QUE_SERVE = '';
const colunaDeSeguro = (indice, nome, destino = INFORMACAO) =>
  destino === INFORMACAO
    ? {
        indice,
        nome,
        destino,
        campo: { nome, para_que_serve: SEM_PARA_QUE_SERVE },
      }
    : { indice, nome, destino };

const colunasDaPlanilha = (leitura, estado) => [
  ...leitura.colunas.map(coluna => {
    const destino = estado.destinos[coluna.indice];
    return destino ? { ...coluna, destino } : coluna;
  }),
  ...COLUNAS_DE_SEGURO.map(({ nome }, posicao) => {
    const indice = leitura.colunas.length + posicao;
    return colunaDeSeguro(indice, nome, estado.destinos[indice]);
  }),
];

// A pergunta dos seguros é a última, como no servidor.
const perguntasComSeguros = perguntas => [...perguntas, { id: 'seguros' }];

const faltamNas = colunas =>
  OBRIGATORIOS.filter(
    destino => !colunas.some(coluna => coluna.destino === destino)
  );

// Com "Sim" e as quatro colunas obrigatórias, as linhas são conferidas como
// seguro: aí entram os números, os seguros dos exemplos e as linhas com
// problema de seguro. Faltando coluna, só o bloco `seguros` diz o que falta.
const conferida = (leitura, estado) => ({
  ...leitura,
  resumo: resumoComSeguros(leitura.resumo),
  exemplos: leitura.exemplos.map((exemplo, posicao) => ({
    ...exemplo,
    cliente: true,
    seguros: SEGUROS_DOS_EXEMPLOS[posicao] ?? [],
  })),
  problemas: [...problemasDeSeguro(estado), ...leitura.problemas],
  problemasTotal: leitura.problemasTotal + PROBLEMAS_DE_SEGURO.length,
});

export const comSeguros = (leituraDasPessoas, estado) => {
  const colunas = colunasDaPlanilha(leituraDasPessoas, estado);
  const leitura = {
    ...leituraDasPessoas,
    colunas,
    perguntas: perguntasComSeguros(leituraDasPessoas.perguntas),
    respostas: {
      ...leituraDasPessoas.respostas,
      ...(estado.resposta ? { seguros: estado.resposta } : {}),
    },
  };
  if (estado.resposta !== SIM) return leitura;
  const faltam = faltamNas(colunas);
  const comOBloco = {
    ...leitura,
    seguros: { destinos: [...DESTINOS_DE_SEGURO], faltam },
  };
  return faltam.length ? comOBloco : conferida(comOBloco, estado);
};

// O que a lista trazida diz no andamento: os seguros e as pessoas que entraram.
export const contasDosSeguros = leitura => {
  const { seguros, pessoas, pessoasQueJaEstavam } = leitura.resumo;
  return {
    seguros,
    pessoas,
    pessoasNovas: Math.max(0, pessoas - pessoasQueJaEstavam),
    pessoasQueJaEstavam,
  };
};
