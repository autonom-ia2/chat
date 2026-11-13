// #2896 — a planilha fictícia de "Trazer minha lista" (demo/trazer.js), como o
// servidor a teria lido. Tudo é inventado e sempre igual: nomes com sobrenome
// que não existe (como em demo/base.js), telefones no bloco fictício
// (11) 9XXXX-00NN e e-mails @exemplo.com.br.
//
// São 203 pessoas: 180 novas, 15 que já estavam na conta e 8 linhas que
// precisam da pessoa; mais 3 linhas que eram a mesma pessoa de outra e já
// foram juntadas (não entram nas 203).
//
// O formato é o que o servidor manda (app/services/relacionamentos/trazer/):
//   - cada coluna tem o índice dela na planilha; cada alvo (nome, telefone,
//     e-mail, empresa) é de uma coluna só e o resto é informação, com o campo;
//   - o telefone de um problema vem como está na planilha, sem o código do
//     país; o dos exemplos vem como a pessoa lê;
//   - cada linha aberta diz o motivo em código; a repetida não tem;
//   - (E3) o que cada coluna de informação tem escrito, com a conta de linhas
//     de cada valor: é disso que sai a pergunta "Quais destes querem dizer
//     cliente?" (demo/trazerValores.js). O código não lê esses textos: quem
//     diz o que quer dizer cliente é a pessoa.
import { DESTINOS } from '../trazer/destinos';

export const NOME_DO_ARQUIVO_DE_EXEMPLO = 'Clientes 2025.xlsx';

const SEM_PARA_QUE_SERVE = '';
const informacao = (indice, nome) => ({
  indice,
  nome,
  destino: DESTINOS.INFORMACAO,
  campo: { nome, para_que_serve: SEM_PARA_QUE_SERVE },
});

const CIDADE = 4;
const SITUACAO = 5;
const ANIVERSARIO = 6;
// A coluna feita para a pergunta dos valores: tem "Sim", "Não" e respostas que
// uma lista fechada de palavras não entenderia ("Sim, desde 2019").
export const COLUNA_JA_E_CLIENTE = 7;

// O leitor achou o telefone na coluna "Cel" sem certeza de quem ele é: é dela
// a pergunta "De quem é esse telefone?".
export const COLUNAS = [
  { indice: 0, nome: 'Nome', destino: DESTINOS.NOME },
  { indice: 1, nome: 'Cel', destino: DESTINOS.TELEFONE, duvidosa: true },
  { indice: 2, nome: 'E-mail', destino: DESTINOS.EMAIL },
  { indice: 3, nome: 'Empresa', destino: DESTINOS.EMPRESA },
  informacao(CIDADE, 'Cidade'),
  informacao(SITUACAO, 'Situação'),
  informacao(ANIVERSARIO, 'Aniversário'),
  informacao(COLUNA_JA_E_CLIENTE, 'Já é cliente?'),
];

// Os aniversários são muitos valores diferentes, cada um em poucas linhas: é a
// coluna que mostra a frase "E mais 7 valores diferentes…" (só os 20 primeiros
// entram na pergunta). São 27 datas, de "01/01" a "27/03", em 135 linhas.
const DATAS_DE_ANIVERSARIO = 27;
const MESES = 12;
const LINHAS_DA_PRIMEIRA_DATA = 9;
const DATAS_POR_DEGRAU = 3;
const doisDigitos = numero => String(numero).padStart(2, '0');
const ANIVERSARIOS = Array.from({ length: DATAS_DE_ANIVERSARIO }, (_, n) => [
  `${doisDigitos(n + 1)}/${doisDigitos((n % MESES) + 1)}`,
  LINHAS_DA_PRIMEIRA_DATA - Math.floor(n / DATAS_POR_DEGRAU),
]);

// O que cada coluna tem escrito, do valor que mais aparece ao que menos
// aparece: `[valor, em quantas linhas]`. Célula vazia não entra. A coluna que
// não está aqui (nome, telefone, e-mail) aparece na pergunta como coluna sem
// nada escrito: a demonstração não inventa 200 nomes para listar.
export const VALORES_DAS_COLUNAS = new Map([
  [
    3,
    [
      ['Casa Aurora', 14],
      ['Estúdio Vila Nova', 11],
      ['Oficina Trilho Azul', 8],
      ['Mercearia Flor do Campo', 6],
    ],
  ],
  [
    CIDADE,
    [
      ['São Paulo', 88],
      ['Campinas', 41],
      ['Santos', 27],
      ['Sorocaba', 19],
      ['Jundiaí', 12],
    ],
  ],
  [
    SITUACAO,
    [
      ['Cliente', 120],
      ['Interessado', 55],
      ['Ex-cliente', 18],
    ],
  ],
  [ANIVERSARIO, ANIVERSARIOS],
  [
    COLUNA_JA_E_CLIENTE,
    [
      ['Sim', 96],
      ['Não', 61],
      ['Sim, desde 2019', 14],
      ['Cliente antigo', 9],
      ['Ainda não', 7],
      ['Em negociação', 5],
    ],
  ],
]);

export const PERGUNTAS = [
  { id: 'clientes' },
  { id: 'telefone', coluna: 'Cel', indice: 1 },
];

export const RESUMO = {
  total: 203,
  novas: 180,
  completadas: 15,
  comProblema: 8,
  juntadas: 3,
};

// `celulas` é o que a planilha tem escrito, para cada pessoa de exemplo, nas
// colunas de informação (pelo índice da coluna): fica só aqui. A leitura leva
// `cliente`, que sai da resposta da pessoa (demo/trazerValores.js).
export const EXEMPLOS = [
  {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: 'Casa Aurora',
    celulas: {
      [CIDADE]: 'São Paulo',
      [SITUACAO]: 'Cliente',
      [ANIVERSARIO]: '01/01',
      [COLUNA_JA_E_CLIENTE]: 'Sim, desde 2019',
    },
  },
  {
    nome: 'Otávio Lourenzatto',
    telefone: '+55 11 96538-0007',
    email: 'otavio.lourenzatto@exemplo.com.br',
    empresa: '',
    celulas: {
      [CIDADE]: 'Campinas',
      [SITUACAO]: 'Interessado',
      [ANIVERSARIO]: '02/02',
      [COLUNA_JA_E_CLIENTE]: 'Não',
    },
  },
  {
    nome: 'Sofia Mendonzela',
    telefone: '+55 11 93816-0011',
    email: 'sofia.mendonzela@exemplo.com.br',
    empresa: 'Estúdio Vila Nova',
    celulas: {
      [CIDADE]: 'Santos',
      [SITUACAO]: 'Cliente',
      [COLUNA_JA_E_CLIENTE]: 'Sim',
    },
  },
];

// A linha 88 foi aprovada; a 143 e a 156 repetem o e-mail dela (a mesma
// pessoa, com outro telefone): de um grupo assim entra uma linha só.
const LINHA_APROVADA = {
  linha: 88,
  telefone: '(11) 94410-0088',
  email: 'paulo.hortencio@exemplo.com.br',
};
const repetida = (linha, nome, telefone) => ({
  linha,
  tipo: 'duplicada',
  nome,
  valor: LINHA_APROVADA.email,
  outraLinha: LINHA_APROVADA.linha,
  duplicadas: [
    LINHA_APROVADA,
    { linha, telefone, email: LINHA_APROVADA.email },
  ],
});

// As 8 linhas que precisam da pessoa, na ordem da planilha: telefone com dígito
// faltando, e-mail sem "@", linha sem nome, telefone errado numa linha que
// também não tem nome, fórmula na empresa (que a tela não conserta), a mesma
// pessoa em mais duas linhas e linha sem telefone nem e-mail.
export const PROBLEMAS = [
  {
    linha: 14,
    tipo: 'telefone',
    nome: 'Tadeu Imbirussu',
    valor: '(11) 9738-0014',
    motivo: 'invalid_brazilian_mobile_number',
  },
  {
    linha: 37,
    tipo: 'email',
    nome: 'Rita Carvalhedo',
    valor: 'rita.carvalhedo.exemplo.com.br',
    motivo: 'invalid_email',
  },
  {
    linha: 62,
    tipo: 'nome',
    nome: '',
    valor: '',
    contato: '(11) 95412-0062',
    motivo: 'blank_name',
  },
  {
    linha: 96,
    tipo: 'telefone',
    nome: '',
    valor: '(11) 9654-009',
    motivo: 'invalid_brazilian_mobile_number',
  },
  {
    linha: 118,
    tipo: 'formula',
    campo: 'empresa',
    nome: 'Lívia Quintanilho',
    motivo: 'formula_detected',
  },
  repetida(143, 'Paulo Hortêncio', '(11) 94410-0143'),
  repetida(156, 'Paulo H. Hortêncio', '(11) 94410-0156'),
  {
    linha: 171,
    tipo: 'sem_contato',
    nome: 'Helena Ourivesco',
    valor: '',
    motivo: 'missing_contact',
  },
];

// A linha 96 tem dois problemas: consertado o telefone, sobra o nome que falta
// (o servidor devolve a linha aberta com o problema que sobrou).
export const O_QUE_SOBRA = new Map([
  [96, { tipo: 'nome', nome: '', valor: '', motivo: 'blank_name' }],
]);
