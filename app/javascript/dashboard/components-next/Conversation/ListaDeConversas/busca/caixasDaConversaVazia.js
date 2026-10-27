// #2211 — as regras da conversa vazia ("Escrever" na busca da lista) que não dependem da tela.
// O resto (tipo de mensagem, modelo, e-mail, continuar a conversa) é o da Nova conversa
// (NovaConversa/novaConversa.js e os composables dela).
import camelcaseKeys from 'camelcase-keys';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { ordenarCanais } from 'dashboard/components-next/NovaConversa/novaConversa';
import { telefoneLegivel } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

// Instagram nunca: lá só a pessoa manda a primeira mensagem.
export const semInstagram = (caixas = []) =>
  caixas.filter(caixa => caixa.channelType !== INBOX_TYPES.INSTAGRAM);

// Telefone que ainda não é contato: o contato só nasce ao enviar, então as caixas não vêm
// do servidor (contactable_inboxes pede um contato). Valem as que mandam para um número:
// WhatsApp oficial, SMS, Twilio e a caixa API (o WhatsApp do celular). Ao enviar, o
// servidor confirma a caixa escolhida para o contato criado.
const MANDAM_PARA_TELEFONE = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.SMS,
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.API,
];

export const caixasParaTelefone = (caixasDaConta = []) =>
  ordenarCanais(
    caixasDaConta
      .filter(caixa => MANDAM_PARA_TELEFONE.includes(caixa.channel_type))
      .map(caixa => camelcaseKeys(caixa, { deep: true }))
  );

// Uma caixa só: a tela já vem pronta para escrever. Mais de uma: a pessoa escolhe.
export const caixaJaEscolhida = (caixas = []) =>
  caixas.length === 1 ? caixas[0].id : null;

// A conta tem caixa de Instagram: a tela explica por que ela não está na lista.
export const temInstagram = (caixasDaConta = []) =>
  caixasDaConta.some(caixa => caixa.channel_type === INBOX_TYPES.INSTAGRAM);

// A rota pede a conversa vazia: "Escrever" (?comecar=<id do contato>) ou o telefone novo
// (?telefone=<número>). Quem mostra a tela (ConversationView) e quem some com ela (o botão do
// menu no celular) leem daqui.
export const pedidoDeConversaVazia = (query = {}) => {
  const { comecar = '', telefone = '' } = query;
  return comecar || telefone ? { contatoId: comecar, telefone } : null;
};

// A linha de baixo da caixa, no topo da conversa vazia e na gaveta "Por onde mandar?": o número (como a
// lista escreve, "+55 11 4000-0001") ou o e-mail por onde a mensagem sai. O WhatsApp pelo celular (caixa
// API do WAHA) mostra o número da sessão. A gaveta "Nova conversa" segue com o linhaDoCanal dela.
const PREFIXO_TWILIO = 'whatsapp:';
export const linhaDaCaixa = caixa => {
  if (!caixa) return '';
  if (caixa.channelType === INBOX_TYPES.EMAIL) return caixa.email || '';
  const numero = caixa.phoneNumber || caixa.wahaPhoneNumber || '';
  return telefoneLegivel(
    numero.startsWith(PREFIXO_TWILIO)
      ? numero.slice(PREFIXO_TWILIO.length)
      : numero
  );
};
