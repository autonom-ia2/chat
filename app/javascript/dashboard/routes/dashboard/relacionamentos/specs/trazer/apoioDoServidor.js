import { trazerFonte } from '../../fonte/trazerFonte';

// Apoio dos specs de "Trazer minha lista" que falam com o servidor de mentira
// (#2896): as respostas no formato do contrato e a fonte real com a espera de
// mentira. Quem simula o cliente de API (`vi.mock`) é cada spec.
export const INTERVALO = 1000;
export const TETO = 5000;
export const PLANILHA = { name: 'Clientes 2025.xlsx' };
export const LENDO = { id: 812, situacao: 'lendo' };

export const COLUNAS = [
  { indice: 0, nome: 'Nome', destino: 'nome' },
  { indice: 1, nome: 'Cel', destino: 'telefone' },
  { indice: 6, nome: 'Situação', destino: 'informacao' },
];

export const problema = (linha, extra = {}) => ({
  linha,
  tipo: 'telefone',
  nome: `Pessoa ${linha}`,
  valor: '(11) 9738-0014',
  estado: 'aberto',
  ...extra,
});

export const REPETIDA = {
  linha: 143,
  tipo: 'duplicada',
  nome: 'Paulo Hortêncio',
  valor: 'Paulo Hortêncio',
  outraLinha: 88,
  duplicadas: [
    { linha: 88, telefone: '(11) 94410-0088', email: '' },
    { linha: 143, telefone: '(11) 94410-0143', email: '' },
  ],
  estado: 'aberto',
};

export const RESUMO = {
  total: 200,
  novas: 180,
  completadas: 15,
  comProblema: 1,
  juntadas: 0,
  entram: 195,
};

// A leitura pronta, como o GET a devolve (e como responder e trocar a coluna a
// devolvem quando a planilha não precisa ser lida de novo).
export const pronta = (extra = {}) => ({
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.xlsx',
  valores: 'inteiros',
  colunas: COLUNAS,
  tem_empresa: true,
  perguntas: [],
  respostas: {},
  resumo: RESUMO,
  exemplos: [],
  problemas: [problema(14)],
  problemas_total: 1,
  pagina: 1,
  por_pagina: 200,
  ...extra,
});

// Uma página de problemas de uma leitura com mais linhas do que cabem numa só.
export const pagina = (numero, linhas, total, extra = {}) =>
  pronta({
    problemas: linhas.map(linha => problema(linha)),
    problemas_total: total,
    pagina: numero,
    por_pagina: 2,
    ...extra,
  });

export const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });

export const semRede = () => new Error('Network Error');

export const erroDeNome = (nome, extra = {}) =>
  Object.assign(new Error(nome), { name: nome, ...extra });

// `api` é o cliente simulado: cada resposta vale para uma chamada, na ordem.
export const responder =
  api =>
  (metodo, ...respostas) =>
    respostas.reduce(
      (mock, data) => mock.mockResolvedValueOnce({ data }),
      api[metodo]
    );

// A fonte real com a espera de mentira: em vez de dormir, só anda o relógio.
export const montarFonteReal = () => {
  const relogio = { agora: 0 };
  const espera = vi.fn(async ms => {
    relogio.agora += ms;
  });
  const fonte = trazerFonte({
    demo: null,
    espera,
    intervaloDaConsulta: INTERVALO,
    tetoDaConsulta: TETO,
    agora: () => relogio.agora,
  });
  return { fonte, espera, relogio };
};

// Uma fonte real que já leu a planilha (a leitura 812 está guardada nela).
export const fonteComLeitura = async (api, resposta = pronta()) => {
  const montada = montarFonteReal();
  responder(api)('enviar', LENDO);
  responder(api)('leitura', resposta);
  const leitura = await montada.fonte.ler(PLANILHA);
  Object.values(api).forEach(pedido => pedido.mockClear());
  return { ...montada, leitura };
};
