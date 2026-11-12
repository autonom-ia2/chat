import { ESCRITA } from './estadoDoTrazer';
import { EVENTOS } from './etapas';
import { fraseDaEscrita } from './falhasDaTela';
import { responderPergunta } from './respostas';

// #2896, Fatia 2 — as perguntas da tela "Trazer minha lista" (a parte de
// trazer/useTrazerLista.js que cuida delas): a resposta de cada uma fica na
// tela e só vai ao servidor na última, de uma vez.
export const usePerguntasDaLista = tela => {
  const { fonte, estado, leitura, respostas, ocupado, memoria } = tela;
  const { recusaDaPergunta, perguntaDeNovo } = tela;

  // Mexeu na resposta: a recusa que a pergunta tinha deixa de valer.
  const responder = (pergunta, valor) => {
    recusaDaPergunta.value = null;
    respostas.value = responderPergunta(respostas.value, pergunta, valor);
  };
  const escolherColunaDeCliente = coluna => {
    recusaDaPergunta.value = null;
    respostas.value = { ...respostas.value, colunaCliente: coluna };
  };

  const gravarAsRespostas = () =>
    tela.escrever(
      () => fonte.responder(leitura.value.id, respostas.value),
      falha => {
        recusaDaPergunta.value = { chave: fraseDaEscrita(falha) };
        return false;
      }
    );

  const continuar = async () => {
    if (ocupado.value) return;
    memoria.veioDeUmaTroca = false;
    const ultima = estado.value.pergunta >= estado.value.totalDePerguntas - 1;
    // Quem leu de novo já foi para onde a leitura pede.
    if (ultima && (await gravarAsRespostas()) !== ESCRITA.GRAVOU) return;
    perguntaDeNovo.value = false;
    tela.ir(EVENTOS.CONTINUAR);
  };

  // Com uma escrita em voo a tela não sai do lugar.
  const voltar = () => {
    if (ocupado.value) return;
    perguntaDeNovo.value = false;
    recusaDaPergunta.value = null;
    tela.ir(EVENTOS.VOLTAR);
  };

  return { responder, escolherColunaDeCliente, continuar, voltar };
};
