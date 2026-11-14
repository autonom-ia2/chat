import { ehPlanilha } from './arquivo';
import { ESCRITA } from './estadoDoTrazer';
import { EVENTOS, ETAPAS, proximo } from './etapas';
import { ERROS, NOMES, erroDaLeitura, erroDaRetomada } from './falhasDaTela';
import { primeiraSemResposta } from './respostas';

// #2896, Fatia 2 — a leitura da planilha na tela "Trazer minha lista" (as
// partes de trazer/useTrazerLista.js que cuidam dela): o que a tela faz com a
// leitura que chega, o envio e a retomada, e a leitura de novo depois de uma
// mudança.

// As perguntas e as respostas são as da leitura que acabou de voltar. A fonte
// que não as devolve não apaga o que a tela tem.
const acertarPerguntas = ({ estado, leitura, respostas }) => {
  const { perguntas, respostas: guardadas } = leitura.value;
  if (guardadas) respostas.value = { ...guardadas };
  if (!Array.isArray(perguntas)) return;
  estado.value = proximo(estado.value, {
    tipo: EVENTOS.PERGUNTAS_MUDARAM,
    perguntas: perguntas.length,
  });
};

// A troca de coluna devolveu a pessoa a uma pergunta: a pergunta diz por quê.
const marcarPerguntaDeNovo = ({ estado, perguntaDeNovo, memoria }) => {
  if (!memoria.veioDeUmaTroca) return;
  memoria.veioDeUmaTroca = false;
  perguntaDeNovo.value = estado.value.etapa === ETAPAS.PERGUNTAS;
};

export const useChegadaDaLeitura = tela => {
  const { estado, leitura, respostas, erro } = tela;

  const usarLeitura = lida => {
    leitura.value = lida;
    acertarPerguntas(tela);
    // A leitura mudou: a recusa do trazer falava da leitura de antes.
    if (erro.value === ERROS.NADA_PARA_TRAZER) erro.value = ERROS.NENHUM;
  };

  // A leitura voltou do servidor fora da ordem das telas: a tela vai para a
  // primeira pergunta sem resposta ou, com todas respondidas, para o conferir.
  const posicionar = () => {
    const perguntas = leitura.value.perguntas ?? [];
    estado.value = proximo(estado.value, {
      tipo: EVENTOS.RETOMOU,
      perguntas: perguntas.length,
      pergunta: primeiraSemResposta(perguntas, respostas.value),
    });
    marcarPerguntaDeNovo(tela);
  };

  // A pergunta que ficou sem resposta depois da troca de uma coluna é feita de
  // novo: a tela volta a ela (a primeira, se for mais de uma).
  const perguntarOQueFicouSemResposta = () => {
    estado.value = proximo(estado.value, {
      tipo: EVENTOS.PERGUNTAR,
      pergunta: primeiraSemResposta(leitura.value.perguntas, respostas.value),
    });
    marcarPerguntaDeNovo(tela);
  };

  return { usarLeitura, posicionar, perguntarOQueFicouSemResposta };
};

// ---- ler a planilha e retomar a leitura ------------------------------------

// O que a fonte devolve entra na tela e a tela vai para a etapa dela
// (`seguir`), de uma vez só; a falha vira o erro do Enviar. A leitura que o
// servidor ainda não terminou fica guardada pelo id.
const receber = async (tela, pedir, erroDa, seguir) => {
  const { lendo, erro, leitura, respostas, memoria } = tela;
  lendo.value = true;
  erro.value = ERROS.NENHUM;
  memoria.leituraPendente.value = null;
  try {
    const lida = await pedir();
    leitura.value = lida;
    // O servidor pode já trazer respostas guardadas; a tela parte delas.
    respostas.value = { ...(lida.respostas ?? {}) };
    seguir();
    return true;
  } catch (falha) {
    if (tela.recusado(falha)) return false;
    erro.value = erroDa(falha);
    if (falha?.leituraId !== undefined) {
      memoria.leituraPendente.value = falha.leituraId;
    }
    return false;
  } finally {
    lendo.value = false;
  }
};

export const useEnvioDaPlanilha = tela => {
  const { fonte, estado, leitura, erro, memoria } = tela;

  const aoLer = () => {
    estado.value = proximo(estado.value, {
      tipo: EVENTOS.LEU,
      perguntas: leitura.value.perguntas.length,
    });
  };
  const ler = async arquivo => {
    memoria.ultimaEntrada = { arquivo };
    await receber(tela, () => fonte.ler(arquivo), erroDaLeitura, aoLer);
  };

  // A leitura que o servidor já tem (a página foi recarregada, ou a espera do
  // envio falhou): só pergunta por ela, sem enviar arquivo.
  const retomar = async id => {
    const retomou = await receber(
      tela,
      () => fonte.retomar(id),
      erroDaRetomada,
      tela.posicionar
    );
    // A leitura que falhou continua no servidor: "tentar de novo" pergunta por ela.
    if (!retomou && erro.value === ERROS.LEITURA) {
      memoria.leituraPendente.value = id;
    }
  };

  const escolherArquivo = async arquivo => {
    if (!ehPlanilha(arquivo?.name)) {
      erro.value = ERROS.TIPO;
      return;
    }
    await ler(arquivo);
  };

  // Em demonstração a fonte pode oferecer um arquivo de mentira (para mostrar
  // os erros do arquivo sem precisar de um arquivo de verdade).
  const usarExemplo = () => {
    const exemplo = fonte.arquivoDeExemplo?.() ?? null;
    return exemplo ? escolherArquivo(exemplo) : ler(null);
  };

  return { ler, retomar, escolherArquivo, usarExemplo };
};

// ---- ler de novo depois de uma mudança ---------------------------------------

const aoFalharAReleitura = (tela, falha) => {
  if (tela.recusado(falha) || falha?.name === NOMES.LEITURA_INTERROMPIDA) {
    return;
  }
  if (tela.venceu(falha)) return;
  if (falha?.name === NOMES.LEITURA_PENDENTE) {
    tela.releituraParada.value = true;
    return;
  }
  tela.voltarAoEnvio(
    falha?.name === NOMES.LEITURA_NAO_ENCONTRADA
      ? ERROS.JA_TRAZIDA
      : ERROS.SEM_NINGUEM
  );
};

export const useReleitura = tela => {
  const { fonte, leitura, relendo, releituraParada, mudou } = tela;

  // Espera a leitura que o servidor está fazendo de novo (ou busca a leitura
  // como está agora, `porqueMudou`) e leva a pessoa para onde ela pede.
  const reler = async ({ porqueMudou = false } = {}) => {
    relendo.value = true;
    releituraParada.value = false;
    try {
      tela.usarLeitura(await fonte.retomar(leitura.value.id));
      tela.posicionar();
      mudou.value = porqueMudou;
      return ESCRITA.RELEU;
    } catch (falha) {
      aoFalharAReleitura(tela, falha);
      return ESCRITA.NAO_GRAVOU;
    } finally {
      relendo.value = false;
    }
  };

  return { reler };
};
