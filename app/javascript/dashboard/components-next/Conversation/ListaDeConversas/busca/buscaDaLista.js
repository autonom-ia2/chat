// #2211 — as regras da busca da lista que não dependem da tela: quando buscar e como destacar o
// trecho achado. Sem regex: método de string e a decomposição Unicode (NFD) de cada letra.

import { nomeEhTelefone } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

export const MINIMO_DE_LETRAS = 2;
// Nas mensagens, o servidor só procura palavras de 3 letras ou mais (SearchService::BuscaDaLista):
// o destaque segue a mesma regra, para não marcar o que não foi buscado.
export const MINIMO_DE_LETRAS_NA_MENSAGEM = 3;
export const MINIMO_DE_DIGITOS = 4;
export const ESPERA_DA_DIGITACAO_MS = 300;
// A conversa vazia enviou (contato e conversa novos): a busca aberta na lista refaz o pedido.
export const BUSCA_DESATUALIZADA = 'lista:buscaDesatualizada';
const SINAIS_DE_TELEFONE = ' +()-.';
const TAMANHO_DO_TRECHO = 140;
const RETICENCIAS = '…';

const ehDigito = letra => letra >= '0' && letra <= '9';

// "11 97862-2068", "+55 (11) 9…": só dígitos e sinais de telefone.
export const pareceTelefone = texto => {
  const limpo = texto.trim();
  if (!limpo) return false;
  return [...limpo].every(
    letra => ehDigito(letra) || SINAIS_DE_TELEFONE.includes(letra)
  );
};

export const digitosDe = texto => [...texto].filter(ehDigito).join('');

// A partir de 2 letras; telefone a partir de 4 dígitos.
export const prontoParaBuscar = texto => {
  const limpo = (texto || '').trim();
  if (pareceTelefone(limpo))
    return digitosDe(limpo).length >= MINIMO_DE_DIGITOS;
  return limpo.length >= MINIMO_DE_LETRAS;
};

// Uma letra por letra: "Ã" → "a". Mantém o tamanho do texto, então a posição achada vale no original.
const letraSemAcento = letra => {
  const [base] = [...letra.normalize('NFD')];
  return (base || letra).toLowerCase();
};
const semAcento = texto => [...texto].map(letraSemAcento);

const acharPalavra = (letras, palavra, desde) => {
  const alvo = semAcento(palavra);
  for (let i = desde; i <= letras.length - alvo.length; i += 1) {
    let igual = true;
    for (let j = 0; j < alvo.length && igual; j += 1) {
      igual = letras[i + j] === alvo[j];
    }
    if (igual) return i;
  }
  return -1;
};

// Cada ocorrência de cada palavra vira um trecho destacado.
const marcas = (letras, palavras) => {
  const destacado = new Array(letras.length).fill(false);
  palavras.forEach(palavra => {
    const tamanho = [...palavra].length;
    let desde = 0;
    let achou = acharPalavra(letras, palavra, desde);
    while (achou >= 0) {
      for (let k = achou; k < achou + tamanho; k += 1) destacado[k] = true;
      desde = achou + tamanho;
      achou = acharPalavra(letras, palavra, desde);
    }
  });
  return destacado;
};

// Onde o trecho começa: no começo da palavra do primeiro achado (logo depois do espaço antes dele).
// Mensagem que cabe inteira no trecho aparece inteira.
const comecoDoTrecho = (original, primeiro) => {
  if (original.length <= TAMANHO_DO_TRECHO || primeiro < 0) return 0;
  let comeco = primeiro;
  while (comeco > 0 && original[comeco - 1] !== ' ') comeco -= 1;
  return comeco;
};

// O trecho da mensagem a partir do primeiro achado, em partes { texto, destaque }.
export const trechoComDestaque = (texto, busca) => {
  const original = [...(texto || '')];
  const palavras = (busca || '')
    .trim()
    .split(' ')
    .filter(palavra => [...palavra].length >= MINIMO_DE_LETRAS_NA_MENSAGEM);
  if (!original.length) return [];
  const letras = original.map(letraSemAcento);
  const destacado = marcas(letras, palavras);
  const primeiro = destacado.indexOf(true);
  const comeco = comecoDoTrecho(original, primeiro);
  const fim = Math.min(original.length, comeco + TAMANHO_DO_TRECHO);
  const partes = [];
  for (let i = comeco; i < fim; i += 1) {
    const ultima = partes[partes.length - 1];
    if (ultima && ultima.destaque === destacado[i]) {
      ultima.texto += original[i];
    } else {
      partes.push({ texto: original[i], destaque: destacado[i] });
    }
  }
  if (comeco > 0) partes.unshift({ texto: RETICENCIAS, destaque: false });
  if (fim < original.length)
    partes.push({ texto: RETICENCIAS, destaque: false });
  return partes;
};

// O nome que é só um telefone vai vazio ao avatar, que mostra o ícone de pessoa no lugar de "+5" (como o card da
// lista, #2202).
export const nomeNoAvatar = nome => (nomeEhTelefone(nome) ? '' : nome || '');
