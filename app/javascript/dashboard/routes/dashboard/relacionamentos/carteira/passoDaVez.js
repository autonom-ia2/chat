// #2897 — o passo da vez na renovação: o que falta fazer agora e, por isso, o
// único botão azul da gaveta. Função pura (a renovação e o estado da cotação,
// de cotacaoDoCard.js): devolve o nome do passo, ou `null` quando não há o que
// apertar (a cotação está sendo feita, ou o agente espera a resposta da
// pessoa). "Renovou" só é o passo depois de as opções saírem; antes disso ele
// continua no rodapé, como botão secundário.
import { COTACAO, fimDaRenovacao, respostasEmGrupos } from './cotacaoDoCard';

export const PASSOS = {
  COTAR_AGORA: 'COTAR_AGORA',
  COTAR_DE_NOVO: 'COTAR_DE_NOVO',
  COTAR_COM_DADOS: 'COTAR_COM_DADOS',
  ENTRAR_NO_AGGER: 'ENTRAR_NO_AGGER',
  ANEXAR_PROPOSTA: 'ANEXAR_PROPOSTA',
  PEDIR_PROPOSTA: 'PEDIR_PROPOSTA',
  ENVIAR: 'ENVIAR',
  ENVIAR_RESUMO: 'ENVIAR_RESUMO',
  POR_TELEFONE: 'POR_TELEFONE',
  CONVERSAR: 'CONVERSAR',
  RENOVOU: 'RENOVOU',
};

const PELA_COTACAO = {
  [COTACAO.NAO_COMECOU]: PASSOS.COTAR_AGORA,
  [COTACAO.DEMOROU]: PASSOS.COTAR_DE_NOVO,
  [COTACAO.FALHOU]: PASSOS.COTAR_DE_NOVO,
  [COTACAO.AGGER_FORA]: PASSOS.ENTRAR_NO_AGGER,
  [COTACAO.FALTOU_SEM_AGENTE]: PASSOS.COTAR_COM_DADOS,
  [COTACAO.NAO_COTA]: PASSOS.ANEXAR_PROPOSTA,
  [COTACAO.PRONTA]: PASSOS.ENVIAR,
  [COTACAO.PRECO_SEM_PDF]: PASSOS.ENVIAR_RESUMO,
  [COTACAO.SEM_TELEFONE]: PASSOS.POR_TELEFONE,
  [COTACAO.NAO_QUER]: PASSOS.CONVERSAR,
  [COTACAO.BLOQUEADO]: PASSOS.CONVERSAR,
  [COTACAO.NAO_SAIU]: PASSOS.CONVERSAR,
  [COTACAO.ENVIADA_SOZINHA]: PASSOS.RENOVOU,
  [COTACAO.ENVIADA_POR_VOCE]: PASSOS.RENOVOU,
  [COTACAO.ENVIADA_POR]: PASSOS.RENOVOU,
};

// Entre as seguradoras que já deram preço e têm proposta a pedir, a de menor
// preço: é a dela que o botão azul pede.
const aMaisEmConta = respostas =>
  respostasEmGrupos(respostas)
    .deram.filter(resposta => !resposta.semPdf)
    .reduce(
      (melhor, resposta) =>
        !melhor || resposta.valor < melhor.valor ? resposta : melhor,
      null
    );

// `preenchendo`: a pessoa resolveu escrever os dados que faltam sem esperar a
// resposta que o agente pediu.
export const passoDaVez = (
  renovacao,
  cotacao,
  { preenchendo = false } = {}
) => {
  if (!renovacao || fimDaRenovacao(renovacao)) return null;
  if (cotacao === COTACAO.PARCIAL) {
    const escolhida = aMaisEmConta(renovacao.respostas);
    return escolhida
      ? { id: PASSOS.PEDIR_PROPOSTA, seguradora: escolhida.nome }
      : null;
  }
  if (cotacao === COTACAO.FALTOU_PERGUNTADO && preenchendo) {
    return { id: PASSOS.COTAR_COM_DADOS };
  }
  const id = PELA_COTACAO[cotacao];
  return id ? { id } : null;
};
