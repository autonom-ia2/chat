// #2897 — o passo da vez na gaveta do seguro: o único botão azul do rodapé e,
// quando ele toma o lugar do passo de sempre, o que fica ao lado como botão
// secundário (molde: passoDaVez.js, da gaveta da renovação). Função pura:
// devolve os nomes; quem desenha traduz. Sem pendência vale o passo da
// situação (situacaoDoSeguro.js: "Ver PDF", "Abrir a renovação"…). Algo que
// não saiu vem antes de tudo: o caminho é conversar. Depois, o texto em
// palavras simples pronto e ainda não enviado.
import { oQueNaoSaiu } from './oQueNaoSaiu';
import { ACOES_DO_SEGURO, situacaoDoSeguro } from './situacaoDoSeguro';

export const PASSOS_DO_SEGURO = {
  ...ACOES_DO_SEGURO,
  CONVERSAR: 'CONVERSAR',
  ENVIAR_PALAVRAS: 'ENVIAR_PALAVRAS',
};

// Enquanto a apólice é lida, quando a leitura falha ou quando o envio sozinho
// não saiu, não há texto esperando alguém apertar Enviar.
const SEM_TEXTO_A_ENVIAR = ['lendo', 'erro', 'nao_saiu'];

export const palavrasEsperamEnvio = seguro => {
  const { palavras } = seguro ?? {};
  return (
    Boolean(palavras) &&
    !palavras.enviadoEm &&
    !SEM_TEXTO_A_ENVIAR.includes(palavras.estado)
  );
};

// `alterandoPalavras`: a pessoa está mudando o texto; enviar agora mandaria o
// texto antigo.
export const passoDoSeguro = (
  seguro,
  agora = Date.now(),
  { alterandoPalavras = false } = {}
) => {
  const { acao } = situacaoDoSeguro(seguro, agora);
  const deSempre = { azul: acao, depois: null };
  if (oQueNaoSaiu(seguro)) {
    // No seguro vencido o passo já é conversar: não se repete.
    return acao === ACOES_DO_SEGURO.CONVERSAR_COM
      ? deSempre
      : { azul: PASSOS_DO_SEGURO.CONVERSAR, depois: acao };
  }
  return palavrasEsperamEnvio(seguro) && !alterandoPalavras
    ? { azul: PASSOS_DO_SEGURO.ENVIAR_PALAVRAS, depois: acao }
    : deSempre;
};
