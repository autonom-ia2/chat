// #2896 — a tradução entre o servidor e a tela de "Trazer minha lista", em
// funções puras (quem fala com o servidor é fonte/trazerFonte.js). O servidor já
// responde quase no formato da tela; aqui fica só o que muda de nome ou de forma:
//   - a leitura perde a paginação e ganha os problemas de todas as páginas;
//   - a recusa do envio e a leitura que falhou ganham nome, para a tela escolher
//     a frase sem olhar código de HTTP;
//   - o telefone dos exemplos vem sem formato (+5511987650001) e sai como a
//     pessoa lê; o valor de cada problema fica como está na planilha;
//   - quem identifica a coluna é o índice dela na planilha: o nome pode repetir
//     ou vir vazio;
//   - a lista do histórico troca a data por milissegundos e `pode_tentar` por
//     `podeTentar`; `desfazendo` chega como `desfeito` (a tela ainda não tem esse
//     selo).
import { formatarTelefone } from '../lista/telefone';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

export const SITUACAO_DA_LEITURA = {
  LENDO: 'lendo',
  PRONTA: 'pronta',
  FALHOU: 'falhou',
};

const PRIMEIRA_PAGINA = 1;
const DESFAZENDO = 'desfazendo';

export const erroNomeado = (nome, mensagem, causa) =>
  Object.assign(new Error(mensagem, causa ? { cause: causa } : undefined), {
    name: nome,
  });

// ---- a leitura da planilha -------------------------------------------------

const copia = valor => JSON.parse(JSON.stringify(valor ?? null));

const exemploDaTela = exemplo => ({
  ...exemplo,
  telefone: formatarTelefone(exemplo.telefone),
});

// `problemas` são os de todas as páginas (a fonte junta); sem eles, os da
// própria resposta. As respostas das perguntas ficam para a Fatia 2.
export const leituraDaTela = (resposta, problemas = resposta.problemas) => ({
  id: resposta.id,
  arquivo: resposta.arquivo,
  valores: resposta.valores,
  colunas: copia(resposta.colunas) ?? [],
  perguntas: copia(resposta.perguntas) ?? [],
  resumo: copia(resposta.resumo) ?? {},
  exemplos: (copia(resposta.exemplos) ?? []).map(exemploDaTela),
  problemas: copia(problemas) ?? [],
});

export const paginasDeProblemas = ({
  problemas_total: total = 0,
  por_pagina: porPagina = 0,
}) =>
  porPagina > 0
    ? Math.max(PRIMEIRA_PAGINA, Math.ceil(total / porPagina))
    : PRIMEIRA_PAGINA;

// O envio que o servidor recusa (422 com `error`).
const NOME_DA_RECUSA_DO_ENVIO = new Map([
  ['tipo', 'PLANILHA_TIPO'],
  ['arquivo_grande', 'PLANILHA_GRANDE'],
]);

export const erroDoEnvio = falha => {
  const nome = NOME_DA_RECUSA_DO_ENVIO.get(falha?.response?.data?.error);
  return nome
    ? erroNomeado(nome, 'O servidor recusou a planilha.', falha)
    : falha;
};

// A leitura que terminou em `falhou`, com o porquê em `erro`.
const NOME_DA_LEITURA_QUE_FALHOU = new Map([
  ['vazia', 'PLANILHA_VAZIA'],
  ['sem_contato', 'PLANILHA_SEM_CONTATO'],
]);

export const erroDaLeitura = resposta =>
  erroNomeado(
    NOME_DA_LEITURA_QUE_FALHOU.get(resposta?.erro) ?? 'LEITURA_FALHOU',
    'O servidor não conseguiu ler a planilha.'
  );

// ---- as colunas ------------------------------------------------------------

export const colunaPeloIndice = (leitura, indice) => {
  const coluna = leitura.colunas.find(item => item.indice === indice);
  if (!coluna) {
    throw erroNomeado('COLUNA_NAO_ENCONTRADA', 'Essa coluna não existe.');
  }
  return coluna;
};

// O nome da informação e o "para que serve" entram na Fatia 2.
export const corpoDoDestino = destino => ({ destino });

export const leituraComColunas = (leitura, colunas) => ({
  ...leitura,
  colunas: copia(colunas) ?? [],
});

// ---- as listas que a conta já trouxe ---------------------------------------

const situacaoDaTela = situacao =>
  situacao === DESFAZENDO ? SITUACOES_DA_LISTA.DESFEITO : situacao;

export const listaDaTela = lista => ({
  id: lista.id,
  arquivo: lista.arquivo,
  quando: Date.parse(lista.quando),
  // Quem trouxe pode já ter saído da conta.
  quem: lista.quem ?? '',
  total: lista.total,
  situacao: situacaoDaTela(lista.situacao),
  porcentagem: lista.porcentagem,
  podeTentar: lista.pode_tentar === true,
});

export const andamentoDaTela = andamento => ({
  porcentagem: andamento.porcentagem,
  situacao: situacaoDaTela(andamento.situacao),
  total: andamento.total,
  novas: andamento.novas,
  completadas: andamento.completadas,
});
