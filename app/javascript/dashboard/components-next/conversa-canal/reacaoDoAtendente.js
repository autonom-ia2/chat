// Reação do ATENDENTE a uma mensagem do WhatsApp (#1702), como no WhatsApp Web:
// 6 emojis rápidos + "+" para o seletor completo; o mesmo emoji de novo tira a
// reação. O número da empresa tem UMA reação por mensagem (qualquer atendente
// troca a da empresa). O servidor manda ao WhatsApp e grava em `reactions`.
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../message/constants';
import { canReact } from '../message/actions/messageActions';

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

// Instagram (#2113): a caixa do login do Instagram. A ligada por página do Facebook
// não reage pelo painel.
const ehInstagram = caixa => caixa?.channel_type === INBOX_TYPES.INSTAGRAM;

// A reação do Instagram vai sem a tag HUMAN_AGENT: fica na janela padrão de 24 h desde
// a última mensagem do cliente, mesmo quando o texto tem 7 dias (can_reply), como o
// servidor (ConversaCanal::ReacaoNoInstagram). Sem mensagem do cliente carregada, vale
// o can_reply.
const JANELA_PADRAO = 24 * 60 * 60;
const ultimaDoCliente = conversa =>
  (conversa?.messages || []).reduce(
    (ultima, mensagem) =>
      mensagem.message_type === MESSAGE_TYPES.INCOMING
        ? Math.max(ultima, mensagem.created_at || 0)
        : ultima,
    0
  );
const janelaPadraoAberta = (conversa, agora) => {
  const ultima = ultimaDoCliente(conversa);
  return !ultima || agora < ultima + JANELA_PADRAO;
};

const NAO_REAGE = { visivel: false, bloqueado: false };
const PENDENTES = [MESSAGE_STATUS.FAILED, MESSAGE_STATUS.PROGRESS];

// Com 'react' nas ações do motor da caixa WAHA comum (#1709), a reação vai pelo
// conector (wahaMessageActions.react), que acha a mensagem pelo próprio registro: não
// precisa do sourceId. A regra é a do #1709 (canReact, igual ao servidor), mais a
// mensagem ainda saindo, que não tem o que reagir.
const reagePelaCaixa = conversa =>
  Array.isArray(conversa?.whatsapp_api_message_actions) &&
  conversa.whatsapp_api_message_actions.includes('react');

const estadoPelasAcoes = (conversa, mensagem) => {
  const cabe =
    canReact(conversa, { ...mensagem, private: mensagem.isPrivate }) &&
    mensagem.status !== MESSAGE_STATUS.PROGRESS;
  return cabe
    ? { visivel: true, bloqueado: false, pelaCaixa: true }
    : NAO_REAGE;
};

// Na caixa híbrida, a mensagem cujo id provisório do WAHA não virou o id do WhatsApp
// (`waha-native-pending-…`) não reage por nenhum caminho: o WhatsApp não a acharia.
const ID_PROVISORIO_DO_WAHA = 'waha-native-pending-';
const comIdProvisorio = mensagem =>
  String(mensagem.sourceId ?? '').startsWith(ID_PROVISORIO_DO_WAHA);

// WhatsApp oficial e híbrido: só mensagem do cliente (doc da Meta) e com a janela
// de 24 h aberta; o híbrido fora da janela (whatsapp_api_reply) também não reage.
// WAHA: recebida ou enviada, sem janela. Com 'react' nas ações da conversa, vale a
// regra do conector (estadoPelasAcoes).
// Instagram (#2113): como o oficial, só mensagem do cliente e com a janela padrão aberta.
// A linha que o agente da Autonomia cria para a reação do cliente não é mensagem do
// canal: não reage.
export const estadoDaReacao = ({
  caixa,
  conversa,
  mensagem,
  agora = Date.now() / 1000,
}) => {
  if (comIdProvisorio(mensagem)) return NAO_REAGE;
  if (reagePelaCaixa(conversa)) return estadoPelasAcoes(conversa, mensagem);
  const soDoCliente = ehCloud(caixa) || ehInstagram(caixa);
  if (!soDoCliente && !ehWaha(caixa)) return NAO_REAGE;
  if (mensagem.isPrivate || !mensagem.sourceId) return NAO_REAGE;
  if (mensagem.deleted || PENDENTES.includes(mensagem.status)) return NAO_REAGE;
  // Apagada pelo cliente: o servidor recusa (ConversaCanal::ReacaoDoAtendente).
  if (mensagem.contentAttributes?.deletedByContactAt) return NAO_REAGE;
  if (mensagem.contentAttributes?.autonomiaReaction) return NAO_REAGE;

  const recebida = mensagem.messageType === MESSAGE_TYPES.INCOMING;
  const enviada = mensagem.messageType === MESSAGE_TYPES.OUTGOING;
  if (soDoCliente ? !recebida : !(recebida || enviada)) return NAO_REAGE;

  const bloqueado =
    soDoCliente &&
    (!conversa?.can_reply ||
      Boolean(conversa?.whatsapp_api_reply) ||
      (ehInstagram(caixa) && !janelaPadraoAberta(conversa, agora)));
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
