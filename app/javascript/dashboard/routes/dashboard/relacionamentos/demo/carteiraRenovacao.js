// #2897 — o que se faz no card da renovação, na demonstração: enviar a
// proposta, marcar "Renovou" ou "Não renovou" (com desfazer), cotar com os
// dados que faltavam, pedir a proposta de uma seguradora e o texto em palavras
// simples. Só é carregado no ambiente de desenvolvimento. Como as outras
// escritas da carteira (demo/carteira.js), tudo fica na memória e cada ação
// devolve o seguro novo. Os estados que o exemplo de sempre não mostra (`?caso=`)
// ficam em demo/carteiraCasos.js.
import {
  emSegundos,
  escrever,
  escritaDe,
  feito,
  reporEscrita,
  seguroPorId,
} from './carteira';
import { comOCaso, propostaDeExemplo, respostasPara } from './carteiraCasos';
import { historiaDaDemo, naoSaiuNaDemo } from './carteiraHistoria';
import { DESFECHOS } from '../carteira/situacaoDaRenovacao';

const VOCE = { papel: 'voce' };
const MOTIVO_ESCRITO = 'outro';

// A história do seguro como o `?caso=` o mostra (o envio que não saiu entra
// como mais uma linha).
export const historiaComOCaso = (id, caso, agora = Date.now()) => {
  const seguro = comOCaso(seguroPorId(id, agora), caso, agora);
  return seguro
    ? historiaDaDemo(seguro, escritaDe(id).feitos, agora, caso)
    : [];
};

// O seguro como o `?caso=` o mostra, já com o que ia sair sozinho e não saiu
// (o mesmo que a história conta).
const seguroComOCaso = (seguro, caso, agora = Date.now()) => {
  const visto = comOCaso(seguro, caso, agora);
  return visto
    ? { ...visto, naoSaiu: naoSaiuNaDemo(visto, agora, caso) }
    : visto;
};

// ---- escritas ---------------------------------------------------------------

// Muda a renovação do seguro e registra o que foi feito na história.
const naRenovacao = (id, agora, tipo, mudar, valores = {}, outros = {}) => {
  const seguro = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: {
      ...atual.campos,
      ...outros,
      renovacao: { ...seguro.renovacao, ...mudar(seguro) },
    },
    feitos: feito(atual, tipo, agora, valores),
  }));
  return seguroPorId(id, agora);
};

export const enviarProposta = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'proposta_enviada', seguro => ({
    etapa: 'Opções enviadas',
    proposta: {
      // A proposta que só existe pelo `?caso=` não está guardada: vai a de exemplo.
      ...(seguro.renovacao.proposta ?? propostaDeExemplo(seguro)),
      enviadaPor: VOCE,
      enviadaEm: emSegundos(agora),
    },
  }));

// "Renovou" e "Não renovou" guardam como estava antes, para o Desfazer.
const comDesfecho = (id, agora, fechar) => {
  const antes = escritaDe(id);
  const seguro = fechar();
  escrever(id, atual => ({ ...atual, antesDoDesfecho: antes }));
  return seguro;
};

export const renovou = (id, _dados, agora = Date.now()) =>
  comDesfecho(id, agora, () =>
    naRenovacao(
      id,
      agora,
      'renovou',
      () => ({ etapa: 'Renovado', cotando: false }),
      {},
      { renovadoEm: emSegundos(agora) }
    )
  );

// O seguro continua com o selo de agora e vira Vencido quando terminar.
// O motivo escrito à mão vai à história com as palavras de quem escreveu.
export const naoRenovou = (id, { motivo, texto = '' }, agora = Date.now()) => {
  const escrito = motivo === MOTIVO_ESCRITO;
  return comDesfecho(id, agora, () =>
    naRenovacao(
      id,
      agora,
      escrito ? 'nao_renovou_outro' : 'nao_renovou',
      () => ({ desfecho: DESFECHOS.NAO_RENOVOU, cotando: false }),
      escrito ? { texto } : { motivo },
      { motivo, motivoEscrito: texto }
    )
  );
};

export const desfazerDesfecho = (id, _dados, agora = Date.now()) => {
  const { antesDoDesfecho } = escritaDe(id);
  if (antesDoDesfecho) reporEscrita(id, antesDoDesfecho);
  return seguroPorId(id, agora);
};

// Quem preencheu os dados que faltavam: não falta mais nada, e a cotação anda.
export const cotarComDados = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'cotacao_pedida', () => ({
    faltou: [],
    cotando: true,
  }));

// A proposta oficial da seguradora escolhida entre as que já deram preço.
export const pedirProposta = (id, { seguradora }, agora = Date.now()) =>
  naRenovacao(
    id,
    agora,
    'proposta_pedida',
    seguro => {
      const { valor, variacao, periodo } = respostasPara(seguro).find(
        resposta => resposta.nome === seguradora
      );
      return {
        respostas: null,
        proposta: {
          seguradora,
          valor,
          variacao,
          periodo,
          mesmaCobertura: true,
          oficial: true,
        },
      };
    },
    { seguradora }
  );

// Conta que não cota sozinha: a equipe cota por fora e põe a proposta no card.
export const anexarProposta = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'proposta_anexada', seguro => ({
    proposta: { ...propostaDeExemplo(seguro), oficial: true },
  }));

// ---- seu seguro em palavras simples (Tela 19) --------------------------------

const nasPalavras = (id, agora, mudanca, tipo) => {
  const { palavras } = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: { ...atual.campos, palavras: { ...palavras, ...mudanca } },
    feitos: tipo ? feito(atual, tipo, agora) : atual.feitos,
  }));
  return seguroPorId(id, agora);
};

export const salvarPalavras = (id, { texto }, agora = Date.now()) =>
  nasPalavras(id, agora, { texto });

export const enviarPalavras = (id, _dados, agora = Date.now()) =>
  nasPalavras(id, agora, { enviadoEm: emSegundos(agora) }, 'palavras_enviadas');

export const demoDaRenovacao = {
  comOCaso: seguroComOCaso,
  historiaComOCaso,
  enviarProposta,
  renovou,
  naoRenovou,
  desfazerDesfecho,
  cotarComDados,
  pedirProposta,
  anexarProposta,
  salvarPalavras,
  enviarPalavras,
};
