// #3099 — qual das duas versões da mensagem foi melhor, em palavras. Funções puras.
//
// A régua é a mesma da comparação com o grupo de controle (#3098, comparacaoComControle.js): a frase sai dos números
// redondos que a tela mostra ("De cada 100, 12 responderam"), e a diferença vira "o dobro", "o triplo" ou "N vezes".
// Até 15% de diferença é "quase igual" (empate). Com poucas respostas ou compras somadas nas duas versões, é cedo para
// dizer: uma ou duas a mais viram "o dobro" por sorte.
import { emGente, pelaDiferenca } from './comparacaoComControle';

export const MINIMO_DE_RESULTADOS = 10;

// Escolher "eu escolho" não muda a conta: a tela compara pelas respostas.
const CAMPO = { compras: 'compraram' };
export const campoDoCriterio = criterio => CAMPO[criterio] || 'responderam';
export const fraseDoCriterio = criterio =>
  criterio === 'compras' ? 'COMPRAS' : 'RESPOSTAS';

// "De cada 100 que receberam, N" para cada versão, com a mesma escala nas duas.
export const deCadaCem = (versao1, versao2, criterio) => {
  const campo = campoDoCriterio(criterio);
  const lado = versao => ({
    pessoas: versao?.receberam ?? 0,
    compraram: versao?.[campo] ?? 0,
  });
  const gente = emGente(lado(versao1), lado(versao2));
  return { escala: gente.escala, 1: gente.receberam, 2: gente.controle };
};

// Devolve { chave, melhor, vezes? }: `melhor` é 1, 2 ou null (empate ou cedo demais).
export const compararVersoes = (versao1, versao2, criterio) => {
  const campo = campoDoCriterio(criterio);
  const soma = (versao1?.[campo] ?? 0) + (versao2?.[campo] ?? 0);
  if (soma < MINIMO_DE_RESULTADOS) return { chave: 'POUCOS', melhor: null };

  const cem = deCadaCem(versao1, versao2, criterio);
  if (cem[1] === cem[2]) return { chave: 'EMPATE', melhor: null };
  const melhor = cem[2] > cem[1] ? 2 : 1;
  const pior = melhor === 1 ? 2 : 1;
  if (cem[pior] === 0) return { chave: 'SO_UMA', melhor };

  const { chave, vezes } = pelaDiferenca(cem[melhor] / cem[pior]);
  if (chave === 'IGUAL') return { chave: 'EMPATE', melhor: null };
  return vezes ? { chave, melhor, vezes } : { chave, melhor };
};
