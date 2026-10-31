// #2414 F0 — operações sobre a receita (a árvore de passos). Tudo devolve uma
// cópia nova: a versão salva é imutável, e o editor só troca a referência.
import { TIPOS_DE_PASSO, ACOES_DA_PLATAFORMA } from './catalogo';

export const copiar = valor => JSON.parse(JSON.stringify(valor));

// Lista raiz: 'raiz'. Lista de um caminho: '<id do passo>:<chave do caminho>'.
export const RAIZ = 'raiz';
export const idDaLista = (passoId, caminhoChave) =>
  `${passoId}:${caminhoChave}`;

// Aplica `fn` só na lista `listaId`, onde quer que ela esteja na árvore.
const mapearListas = (passos, listaId, fn, aqui = RAIZ) => {
  const lista = aqui === listaId ? fn(passos) : passos;
  return lista.map(passo => {
    if (!passo.caminhos) return passo;
    return {
      ...passo,
      caminhos: passo.caminhos.map(caminho => ({
        ...caminho,
        passos: mapearListas(
          caminho.passos,
          listaId,
          fn,
          idDaLista(passo.id, caminho.chave)
        ),
      })),
    };
  });
};

export const inserirPasso = (passos, listaId, indice, novo) =>
  mapearListas(passos, listaId, lista => [
    ...lista.slice(0, indice),
    novo,
    ...lista.slice(indice),
  ]);

export const trocarPasso = (passos, id, novo) =>
  passos.map(passo => {
    if (passo.id === id) return novo;
    if (!passo.caminhos) return passo;
    return {
      ...passo,
      caminhos: passo.caminhos.map(caminho => ({
        ...caminho,
        passos: trocarPasso(caminho.passos, id, novo),
      })),
    };
  });

export const tirarPasso = (passos, id) =>
  passos
    .filter(passo => passo.id !== id)
    .map(passo =>
      passo.caminhos
        ? {
            ...passo,
            caminhos: passo.caminhos.map(caminho => ({
              ...caminho,
              passos: tirarPasso(caminho.passos, id),
            })),
          }
        : passo
    );

export const todosOsPassos = passos =>
  passos.flatMap(passo => [
    passo,
    ...(passo.caminhos || []).flatMap(caminho => todosOsPassos(caminho.passos)),
  ]);

export const acharPasso = (passos, id) =>
  todosOsPassos(passos).find(passo => passo.id === id) || null;

const acaoDaPlataforma = passo =>
  ACOES_DA_PLATAFORMA.find(acao => acao.chave === passo.acao) || {};

export const passoSemVolta = passo =>
  passo.tipo === 'acao_plataforma'
    ? Boolean(acaoDaPlataforma(passo).semVolta)
    : Boolean(TIPOS_DE_PASSO[passo.tipo]?.semVolta);

export const custoDoPasso = passo => TIPOS_DE_PASSO[passo.tipo]?.custo || 0;

export const temSemVolta = receita =>
  todosOsPassos(receita?.passos || []).some(passoSemVolta);

export const usaIA = receita =>
  todosOsPassos(receita?.passos || []).some(passo => custoDoPasso(passo) > 0);

export const custoPorVez = receita =>
  todosOsPassos(receita?.passos || []).reduce(
    (soma, passo) => soma + custoDoPasso(passo),
    0
  );

// Receita vazia de "Montar do zero" (com gatilho já escolhido, se veio da etapa).
export const receitaVazia = (gatilho = null, freio = {}) => ({
  gatilho,
  condicoes: [],
  passos: [],
  meta: null,
  freio,
});
