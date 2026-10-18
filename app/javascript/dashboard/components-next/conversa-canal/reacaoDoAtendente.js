// Reação do ATENDENTE a uma mensagem do WhatsApp (#1702), como no WhatsApp Web:
// 6 emojis rápidos + "+" para o seletor completo; o mesmo emoji de novo tira a
// reação. O número da empresa tem UMA reação por mensagem (qualquer atendente
// troca a da empresa). O servidor manda ao WhatsApp e grava em `reactions`.
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../message/constants';

export const REACOES_RAPIDAS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

// O menu do balão pede para abrir a barra daquela mensagem.
export const ABRIR_REACOES = 'conversaCanal:abrirReacoes';

const tipoDoAutor = reacao => reacao.senderType ?? reacao.sender_type;

// O emoji com que a empresa (qualquer atendente) reagiu, ou ''.
export const reacaoDaEquipe = reacoes =>
  reacoes.find(reacao => tipoDoAutor(reacao) === 'User')?.emoji || '';

// Clicar no emoji que já está lá tira a reação (manda vazio).
export const emojiParaEnviar = (atual, escolhido) =>
  atual === escolhido ? '' : escolhido;

const ehCloud = caixa =>
  caixa?.channel_type === INBOX_TYPES.WHATSAPP &&
  caixa?.provider === 'whatsapp_cloud';

const ehWaha = caixa =>
  caixa?.channel_type === INBOX_TYPES.API && Boolean(caixa?.waha_provider);

const NAO_REAGE = { visivel: false, bloqueado: false };
const PENDENTES = [MESSAGE_STATUS.FAILED, MESSAGE_STATUS.PROGRESS];

// As ações que o motor da caixa WAHA comum declara (#1709): `whatsapp_api_message_actions`
// da conversa, do store (snake_case) ou já convertida (camelCase).
export const acoesDaConversa = conversa => {
  const acoes =
    conversa?.whatsapp_api_message_actions ??
    conversa?.whatsappApiMessageActions;
  return Array.isArray(acoes) ? acoes : [];
};

// Com 'react' nas ações, a reação vai pelo conector da caixa (POST .../reaction), que
// acha a mensagem pelo próprio registro: não precisa do sourceId. Mesmas regras do
// servidor (Waha::RichNative::MessageActions.reactable?).
const estadoPelasAcoes = mensagem => {
  const atributos = mensagem.contentAttributes || {};
  const lado = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(
    mensagem.messageType
  );
  const fora =
    !lado ||
    mensagem.isPrivate ||
    mensagem.deleted ||
    PENDENTES.includes(mensagem.status) ||
    atributos.externalError ||
    atributos.deletedByContactAt ||
    atributos.viewOnceUnavailable;
  return fora
    ? NAO_REAGE
    : { visivel: true, bloqueado: false, pelaCaixa: true };
};

// WhatsApp oficial e híbrido: só mensagem do cliente (doc da Meta) e com a janela
// de 24 h aberta; o híbrido fora da janela (whatsapp_api_reply) também não reage.
// WAHA: recebida ou enviada, sem janela. Com 'react' nas ações da conversa, vale a
// regra do conector (estadoPelasAcoes).
export const estadoDaReacao = ({ caixa, conversa, mensagem }) => {
  if (acoesDaConversa(conversa).includes('react')) {
    return estadoPelasAcoes(mensagem);
  }
  const cloud = ehCloud(caixa);
  if (!cloud && !ehWaha(caixa)) return NAO_REAGE;
  if (mensagem.isPrivate || !mensagem.sourceId) return NAO_REAGE;
  if (mensagem.deleted || PENDENTES.includes(mensagem.status)) return NAO_REAGE;
  // Apagada pelo cliente: o servidor recusa (ConversaCanal::ReacaoDoAtendente).
  if (mensagem.contentAttributes?.deletedByContactAt) return NAO_REAGE;

  const recebida = mensagem.messageType === MESSAGE_TYPES.INCOMING;
  const enviada = mensagem.messageType === MESSAGE_TYPES.OUTGOING;
  if (cloud ? !recebida : !(recebida || enviada)) return NAO_REAGE;

  const bloqueado =
    cloud && (!conversa?.can_reply || Boolean(conversa?.whatsapp_api_reply));
  return { visivel: true, bloqueado };
};

// Próximo botão da barra pelo teclado (setas, Home, End), dando a volta.
export const proximoIndice = (tecla, atual, total) => {
  if (tecla === 'ArrowRight') return (atual + 1) % total;
  if (tecla === 'ArrowLeft') return (atual - 1 + total) % total;
  if (tecla === 'Home') return 0;
  if (tecla === 'End') return total - 1;
  return null;
};
