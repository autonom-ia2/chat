// Encaminhar mensagens como no WhatsApp Web (#1702). Estado da conversa aberta:
// - modo seleção (menu "Encaminhar"): checkbox em cada mensagem e a barra de baixo;
// - janela "Encaminhar mensagem para" (botão ao lado da mídia ou a seta da barra).
// Uma conversa aberta por vez no painel, então o estado é um só, do módulo; quem
// troca de conversa chama `sairDaSelecao` (EncaminharDaConversa.vue).
import { reactive, readonly } from 'vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';

// 5 conversas por vez é o limite do WhatsApp (Central de Ajuda, "Sobre os limites
// de encaminhamento"); 30 mensagens é o nosso teto. O servidor confere os dois.
export const LIMITE_DE_DESTINOS = 5;
export const LIMITE_DE_MENSAGENS = 30;

// Mídias que ganham o botão redondo de encaminhar ao lado do balão.
const MIDIAS_COM_BOTAO = ['image', 'video', 'file', 'location', 'contact'];
const TIPOS_DE_CONTEUDO = ['text', 'sticker'];

const estado = reactive({
  ativa: false,
  conversaId: null,
  ids: [],
  janelaAberta: false,
});

export const selecao = readonly(estado);

// Saiu de modelo ou de campanha (ConversaCanal::Pele::MARCAS_DE_MODELO). Encaminha como
// texto, como qualquer outra (Rodrigo, 17/10); o álbum o deixa solto, com o desenho dele.
const MARCAS_DE_MODELO = [
  'templateParams',
  'campaignId',
  'whatsappApiCampaignId',
  'campaignTemplateName',
];
export const deModeloOuCampanha = mensagem =>
  MARCAS_DE_MODELO.some(marca =>
    Boolean(mensagem?.additionalAttributes?.[marca])
  );

// A mesma regra do servidor (ConversaCanal::Encaminhamento): do cliente ou da
// empresa, nunca nota, apagada (pela equipe ou pelo cliente), não suportada, com falha
// ou de visualização única. Modelo e campanha vão como texto.
export const encaminhavel = mensagem => {
  if (!mensagem || mensagem.private) return false;
  const tipos = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
  if (!tipos.includes(mensagem.messageType)) return false;
  if (!TIPOS_DE_CONTEUDO.includes(mensagem.contentType || 'text')) return false;
  const falhou = [MESSAGE_STATUS.FAILED, MESSAGE_STATUS.PROGRESS];
  if (falhou.includes(mensagem.status)) return false;
  const atributos = mensagem.contentAttributes || {};
  if (atributos.deleted || atributos.deletedByContactAt) return false;
  if (atributos.isUnsupported) return false;
  const anexos = Array.isArray(mensagem.attachments)
    ? mensagem.attachments
    : [];
  if (anexos.some(anexo => anexo?.isViewOnce === true)) return false;
  return (
    Boolean(mensagem.content) || anexos.length > 0 || !!atributos.richMessage
  );
};

export const temBotaoAoLado = mensagem => {
  if (!encaminhavel(mensagem)) return false;
  const anexos = Array.isArray(mensagem.attachments)
    ? mensagem.attachments
    : [];
  if (anexos.some(anexo => MIDIAS_COM_BOTAO.includes(anexo?.fileType))) {
    return true;
  }
  const rico = mensagem.contentAttributes?.richMessage?.type;
  return ['location', 'contact'].includes(rico);
};

// Marcada quando todos os ids dela (um álbum tem vários) estão na seleção.
export const estaMarcada = ids =>
  ids.length > 0 && ids.every(id => estado.ids.includes(id));

export const comecarSelecao = (conversaId, ids) => {
  estado.conversaId = conversaId;
  estado.ids = [...ids];
  estado.janelaAberta = false;
  estado.ativa = true;
};

// -> false quando passaria do teto (a tela avisa).
export const alternarMensagem = ids => {
  if (estaMarcada(ids)) {
    estado.ids = estado.ids.filter(id => !ids.includes(id));
    return true;
  }
  const juntos = [...new Set([...estado.ids, ...ids])];
  if (juntos.length > LIMITE_DE_MENSAGENS) return false;
  estado.ids = juntos;
  return true;
};

// Botão ao lado da mídia: vai direto à janela, só com aquela mensagem.
export const encaminhamentoDireto = (conversaId, ids) => {
  estado.conversaId = conversaId;
  estado.ids = [...ids];
  estado.ativa = false;
  estado.janelaAberta = true;
};

export const abrirJanela = () => {
  if (estado.ids.length) estado.janelaAberta = true;
};

// Fechar a janela volta para a seleção (se veio dela) ou limpa (se veio do botão).
export const fecharJanela = () => {
  estado.janelaAberta = false;
  if (!estado.ativa) estado.ids = [];
};

export const sairDaSelecao = () => {
  estado.ativa = false;
  estado.janelaAberta = false;
  estado.ids = [];
  estado.conversaId = null;
};
