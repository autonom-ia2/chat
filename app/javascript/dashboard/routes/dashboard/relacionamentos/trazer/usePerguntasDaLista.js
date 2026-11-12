import { ESCRITA } from './estadoDoTrazer';
import { EVENTOS, proximo } from './etapas';
import { FRASE_FALTA_VALORES, fraseDaEscrita } from './falhasDaTela';
import {
  PERGUNTA_CLIENTES,
  PERGUNTA_VALORES,
  mudouQuemDizQuemEhCliente,
  posicaoDaPergunta,
  responderPergunta,
  trocarColunaDeCliente,
} from './respostas';

// #2896, Fatia 2 — as perguntas da tela "Trazer minha lista" (a parte de
// trazer/useTrazerLista.js que cuida delas): a resposta de cada uma fica na
// tela e só vai ao servidor na última, de uma vez.
// E3 — menos em dois casos, em que a tela grava na hora:
//   - a resposta de "São clientes?" muda a coluna que diz quem é cliente: a
//     pergunta "Quais destes querem dizer cliente?" só existe depois que o
//     servidor conta os valores da coluna;
//   - a pessoa foi trazida de volta a uma pergunta (`perguntaDeNovo`): ela
//     responde só essa e volta para onde estava.
// Depois de gravar, as perguntas são as da leitura que voltou: a tela vai para
// a primeira sem resposta ou, com todas respondidas, para o conferir.
const SEM_PERGUNTA = -1;

// A resposta da pergunta da vez tem de ir ao servidor antes de a tela seguir?
const gravaAgora = ({ estado, leitura, respostas, perguntaDeNovo }) => {
  const { pergunta, totalDePerguntas } = estado.value;
  if (pergunta >= totalDePerguntas - 1 || perguntaDeNovo.value) return true;
  return (
    leitura.value.perguntas?.[pergunta]?.id === PERGUNTA_CLIENTES &&
    mudouQuemDizQuemEhCliente(leitura.value.perguntas, respostas.value)
  );
};

export const usePerguntasDaLista = tela => {
  const { fonte, leitura, respostas, ocupado, memoria } = tela;
  const { recusaDaPergunta, perguntaDeNovo } = tela;

  // Mexeu na resposta: a recusa que a pergunta tinha deixa de valer.
  const responder = (pergunta, valor) => {
    recusaDaPergunta.value = null;
    respostas.value = responderPergunta(respostas.value, pergunta, valor);
  };
  const escolherColunaDeCliente = coluna => {
    recusaDaPergunta.value = null;
    respostas.value = trocarColunaDeCliente(respostas.value, coluna);
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
    if (!gravaAgora(tela)) {
      tela.ir(EVENTOS.CONTINUAR);
      return;
    }
    // Quem leu de novo já foi para onde a leitura pede.
    if ((await gravarAsRespostas()) !== ESCRITA.GRAVOU) return;
    perguntaDeNovo.value = false;
    tela.posicionar();
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

// E3 — o servidor não trouxe porque falta dizer quais valores da coluna querem
// dizer cliente (ele não traz adivinhando): a tela lê a leitura de novo (a
// pergunta e as contagens são as de agora) e leva a pessoa à pergunta, que diz
// por quê.
export const usePedidoDosValores = tela => {
  const { estado, leitura, recusaDaPergunta } = tela;

  // Devolve false quando a leitura de agora não tem a pergunta: quem chamou
  // diz que não trouxe. A leitura de novo que falha já disse o que houve.
  const pedirOsValoresDeCliente = async () => {
    if ((await tela.reler()) !== ESCRITA.RELEU) return true;
    const { perguntas } = leitura.value;
    const pergunta = posicaoDaPergunta(perguntas, PERGUNTA_VALORES);
    if (pergunta === SEM_PERGUNTA) return false;
    estado.value = proximo(estado.value, {
      tipo: EVENTOS.RETOMOU,
      perguntas: perguntas.length,
      pergunta,
    });
    recusaDaPergunta.value = { chave: FRASE_FALTA_VALORES };
    return true;
  };

  return { pedirOsValoresDeCliente };
};
