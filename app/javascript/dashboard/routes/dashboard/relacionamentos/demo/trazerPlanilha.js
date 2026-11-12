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
//   - cada linha aberta diz o motivo em código; a repetida não tem.
import { DESTINOS } from '../trazer/destinos';

export const NOME_DO_ARQUIVO_DE_EXEMPLO = 'Clientes 2025.xlsx';

const SEM_PARA_QUE_SERVE = '';
const informacao = (indice, nome) => ({
  indice,
  nome,
  destino: DESTINOS.INFORMACAO,
  campo: { nome, para_que_serve: SEM_PARA_QUE_SERVE },
});

// A coluna "Situação" é a que diz quem já é cliente (quando a pessoa a marca).
export const COLUNA_QUE_DIZ_QUEM_E_CLIENTE = 5;

// O leitor achou o telefone na coluna "Cel" sem certeza de quem ele é: é dela
// a pergunta "De quem é esse telefone?".
export const COLUNAS = [
  { indice: 0, nome: 'Nome', destino: DESTINOS.NOME },
  { indice: 1, nome: 'Cel', destino: DESTINOS.TELEFONE, duvidosa: true },
  { indice: 2, nome: 'E-mail', destino: DESTINOS.EMAIL },
  { indice: 3, nome: 'Empresa', destino: DESTINOS.EMPRESA },
  informacao(4, 'Cidade'),
  informacao(COLUNA_QUE_DIZ_QUEM_E_CLIENTE, 'Situação'),
  informacao(6, 'Aniversário'),
];

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

// `clienteNaPlanilha` é o que a coluna "Situação" diz de cada pessoa: fica só
// aqui, a leitura leva `cliente` (demo/trazerColunas.js).
export const EXEMPLOS = [
  {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: 'Casa Aurora',
    clienteNaPlanilha: true,
  },
  {
    nome: 'Otávio Lourenzatto',
    telefone: '+55 11 96538-0007',
    email: 'otavio.lourenzatto@exemplo.com.br',
    empresa: '',
    clienteNaPlanilha: false,
  },
  {
    nome: 'Sofia Mendonzela',
    telefone: '+55 11 93816-0011',
    email: 'sofia.mendonzela@exemplo.com.br',
    empresa: 'Estúdio Vila Nova',
    clienteNaPlanilha: true,
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
