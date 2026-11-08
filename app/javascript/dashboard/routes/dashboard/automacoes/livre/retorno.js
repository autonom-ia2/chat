// G3 (#2629) — o passo "criar retorno" na tela: a frase da linha, o pronto de
// cada peça do painel e quem recebe, em palavras.
const R = 'AUTOMACAO_LIVRE.RETORNO';

export const QUEM = ['responsavel', 'pessoas', 'time'];

const quemRecebe = (para, t) => {
  if (para?.quem === 'pessoas') {
    const n = para.pessoas?.length || 0;
    return t(`${R}.QUEM.PESSOAS`, { n }, n);
  }
  if (para?.quem === 'time') return t(`${R}.QUEM.TIME`);
  return t(`${R}.QUEM.RESPONSAVEL`);
};

// `quando`, `titulo` e `mensagem` já em palavras (as frases do editor).
export const fraseDoRetorno = (passo, t, { quando, titulo, mensagem }) =>
  t(`${R}.${passo.envio ? 'FRASE_COM_MENSAGEM' : 'FRASE'}`, {
    quem: quemRecebe(passo.para, t),
    quando,
    titulo,
    mensagem,
  });

// Sem `para`, vale o responsável; pessoas e time pedem a escolha.
export const paraPronto = para => {
  if (!para || para.quem === 'responsavel') return true;
  if (para.quem === 'pessoas') return Boolean(para.pessoas?.length);
  return para.quem === 'time' && Number.isInteger(para.time);
};

const textoPronto = partes =>
  (partes || []).some(parte => typeof parte !== 'string' || parte.trim());

// Sem envio, só o lembrete; com ele, a mensagem escrita.
export const envioPronto = envio => !envio || textoPronto(envio.mensagem);
