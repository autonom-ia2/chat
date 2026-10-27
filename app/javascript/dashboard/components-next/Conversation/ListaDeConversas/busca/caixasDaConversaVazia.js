// #2211 — as regras da conversa vazia ("Escrever" na busca da lista) que não dependem da tela.
// O resto (tipo de mensagem, modelo, e-mail, continuar a conversa) é o da Nova conversa
// (NovaConversa/novaConversa.js e os composables dela).
import camelcaseKeys from 'camelcase-keys';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { ordenarCanais } from 'dashboard/components-next/NovaConversa/novaConversa';
import { telefoneLegivel } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

// Instagram nunca: lá só a pessoa manda a primeira mensagem.
export const semInstagram = (caixas = []) =>
  caixas.filter(caixa => caixa.channelType !== INBOX_TYPES.INSTAGRAM);

// Telefone que ainda não é contato: o contato só nasce ao enviar, então as caixas não vêm
// do servidor (contactable_inboxes pede um contato). Valem as que mandam para um número:
// WhatsApp oficial, SMS, Twilio e o WhatsApp do celular (caixa API ligada ao WAHA, a mesma
// regra do ehCanalWhatsapp). Integração e webhook comuns (caixa API sem WAHA) ficam de fora.
// Ao enviar, o servidor confirma a caixa escolhida para o contato criado.
const MANDAM_PARA_TELEFONE = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.SMS,
  INBOX_TYPES.TWILIO,
];

const mandaParaTelefone = caixa =>
  MANDAM_PARA_TELEFONE.includes(caixa.channel_type) ||
  (caixa.channel_type === INBOX_TYPES.API && Boolean(caixa.waha_provider));

const paraATela = caixas =>
  ordenarCanais(caixas.map(caixa => camelcaseKeys(caixa, { deep: true })));

export const caixasParaTelefone = (caixasDaConta = []) =>
  paraATela(caixasDaConta.filter(mandaParaTelefone));

// E-mail que ainda não é de ninguém (o servidor diz que é e-mail): só as caixas de e-mail.
export const caixasParaEmail = (caixasDaConta = []) =>
  paraATela(
    caixasDaConta.filter(caixa => caixa.channel_type === INBOX_TYPES.EMAIL)
  );

// O número que veio no link vale como telefone (país e tamanho possíveis)? Sem isso, a tela avisa
// já na abertura, em vez de deixar escrever e falhar no envio.
export const telefonePossivel = telefone =>
  Boolean(parsePhoneNumberFromString(String(telefone || ''))?.isPossible());

// Uma caixa só: a tela já vem pronta para escrever. Mais de uma: a pessoa escolhe.
export const caixaJaEscolhida = (caixas = []) =>
  caixas.length === 1 ? caixas[0].id : null;

// A conta tem caixa de Instagram: a tela explica por que ela não está na lista.
export const temInstagram = (caixasDaConta = []) =>
  caixasDaConta.some(caixa => caixa.channel_type === INBOX_TYPES.INSTAGRAM);

// A rota pede a conversa vazia: "Escrever" (?comecar=<id do contato>), o telefone novo
// (?telefone=<número>) ou o e-mail novo (?email=<endereço>). Quem mostra a tela (ConversationView) e
// quem some com ela (o botão do menu no celular) leem daqui. Parâmetro repetido no link
// (?comecar=1&comecar=2) vem como lista: vale o primeiro.
const primeiro = valor => (Array.isArray(valor) ? valor[0] : valor) || '';

export const pedidoDeConversaVazia = (query = {}) => {
  const contatoId = primeiro(query.comecar);
  const telefone = primeiro(query.telefone);
  const email = primeiro(query.email);
  return contatoId || telefone || email ? { contatoId, telefone, email } : null;
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
