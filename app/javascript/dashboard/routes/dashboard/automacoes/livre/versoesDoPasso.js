// #3099 (F3 do épico #3095) — as duas versões do passo "mensagem" na receita
// (`passo.versoes`: { texto, modelo, criterio, divisao, espera }). A versão 1 é
// o próprio passo. O servidor confere de novo ao salvar
// (Autonomia::Automacao::DuasVersoes.problemas_ao_salvar). Sem importar
// receita.js: ela usa este arquivo para dizer o que falta no passo.

// O mesmo conteúdo, com as chaves em qualquer ordem (o banco devolve o modelo
// com as chaves reordenadas).
const ordenado = valor => {
  if (Array.isArray(valor)) return valor.map(ordenado);
  if (!valor || typeof valor !== 'object') return valor;
  return Object.keys(valor)
    .sort()
    .reduce(
      (novo, chave) => ({ ...novo, [chave]: ordenado(valor[chave]) }),
      {}
    );
};
const iguais = (a, b) =>
  JSON.stringify(ordenado(a)) === JSON.stringify(ordenado(b));

const temParte = partes =>
  (partes || []).some(parte => typeof parte !== 'string' || parte.trim());

export const temDuasVersoes = passo =>
  passo?.tipo === 'mensagem' && Boolean(passo.versoes);

// A versão 2 ficou igual à 1 (o mesmo texto e o mesmo modelo): não dá para
// comparar.
export const versoesIguais = passo =>
  temDuasVersoes(passo) &&
  iguais(passo.texto || [], passo.versoes.texto || []) &&
  iguais(passo.modelo || null, passo.versoes.modelo || null);

// Pronta: texto além de espaço; quando o passo usa modelo, o modelo dela com
// cada variável preenchida; e diferente da versão 1.
export const segundaVersaoPronta = passo => {
  if (!temDuasVersoes(passo)) return true;
  const { texto, modelo } = passo.versoes;
  if (!temParte(texto) || versoesIguais(passo)) return false;
  if (passo.modelo && !modelo) return false;
  return !modelo || (modelo.variaveis || []).every(temParte);
};

// O modelo da versão 2 só vale junto com o da versão 1: tirado o da 1, sai o
// da 2 também (o servidor recusaria a receita).
export const semModeloSobrando = passo =>
  temDuasVersoes(passo) && !passo.modelo && passo.versoes.modelo
    ? { ...passo, versoes: { ...passo.versoes, modelo: null } }
    : passo;
