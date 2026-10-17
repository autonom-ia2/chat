// Balões que só existem com a pele do WhatsApp (#1702). Message.vue pergunta aqui antes
// de escolher o balão de sempre; null = segue o caminho do Chatwoot. Sem pele, Message.vue
// nem pergunta.
import { MESSAGE_TYPES } from '../message/constants';
import EnqueteDoWhatsapp from './enquete/EnqueteDoWhatsapp.vue';
import PedidoDoWhatsapp from './pedido/PedidoDoWhatsapp.vue';
import ContatosDoWhatsapp from './midia/ContatosDoWhatsapp.vue';
import EmojiGrandeDoWhatsapp from './midia/EmojiGrandeDoWhatsapp.vue';
import NaoSuportadaDoWhatsapp from './NaoSuportadaDoWhatsapp.vue';
import MidiaIndisponivelDoWhatsapp from './MidiaIndisponivelDoWhatsapp.vue';
import ReceivedLocation from '../message/bubbles/RichMessage/ReceivedLocation.vue';
import ContactBubble from '../message/bubbles/Contact.vue';
import { ehEnquete } from './enquete/enquete';
import { ehPedido } from './pedido/pedido';
import { umContatoComVariosTelefones, variosContatos } from './midia/contatos';
import { ehSoEmoji } from './soEmoji';
import { midiaIndisponivel, tipoNaoSuportado } from './marcasDaMensagem';

// Localização só na chave (sem o anexo `location`): o cartão sai da própria chave.
const localizacaoSemAnexo = mensagem =>
  Boolean(mensagem.contentAttributes?.sharedLocation) &&
  !mensagem.attachments?.length;

// Só emoji vale para texto simples: sem anexo, sem citação e sem marca no topo.
const soEmoji = mensagem => {
  const atributos = mensagem.contentAttributes || {};
  return (
    !mensagem.private &&
    mensagem.messageType !== MESSAGE_TYPES.ACTIVITY &&
    !mensagem.attachments?.length &&
    !atributos.inReplyTo &&
    !atributos.quotedMessage &&
    !atributos.forwarded &&
    !atributos.frequentlyForwarded &&
    !atributos.deletedByContactAt &&
    !atributos.deleted &&
    !atributos.isUnsupported &&
    ehSoEmoji(mensagem.content)
  );
};

export const balaoDaPele = mensagem => {
  const atributos = mensagem.contentAttributes || {};
  if (atributos.isUnsupported || atributos.viewOnceUnavailable === true) {
    return tipoNaoSuportado(atributos) ? NaoSuportadaDoWhatsapp : null;
  }
  if (mensagem.private) return null;
  if (midiaIndisponivel(atributos)) return MidiaIndisponivelDoWhatsapp;
  if (ehEnquete(atributos)) return EnqueteDoWhatsapp;
  if (ehPedido(atributos)) return PedidoDoWhatsapp;
  if (variosContatos(mensagem.attachments, atributos)) {
    return ContatosDoWhatsapp;
  }
  if (umContatoComVariosTelefones(mensagem.attachments, atributos)) {
    return ContactBubble;
  }
  if (localizacaoSemAnexo(mensagem)) return ReceivedLocation;
  if (soEmoji(mensagem)) return EmojiGrandeDoWhatsapp;
  return null;
};
