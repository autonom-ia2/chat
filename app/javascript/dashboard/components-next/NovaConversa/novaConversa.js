import { INBOX_TYPES, ehWhatsappDoCelular } from 'dashboard/helper/inbox';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import { canStartWithWhatsappApi } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import {
  nomeEhTelefone,
  telefoneLegivel,
} from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

// #1459 — as regras da tela "Nova conversa", em funções puras: que tipo de
// mensagem o canal pede, como ele se chama para a pessoa e o que ainda falta
// para enviar.

export const TIPOS = {
  WHATSAPP_LIVRE: 'whatsapp_livre',
  WHATSAPP_PRONTA: 'whatsapp_pronta',
  WHATSAPP_TWILIO: 'whatsapp_twilio',
  EMAIL: 'email',
  TEXTO: 'texto',
};

export const MODOS = { ESCREVER: 'escrever', PRONTA: 'pronta' };

const PREFIXO_TWILIO = 'whatsapp:';

const ehWhatsappTwilio = canal =>
  canal?.channelType === INBOX_TYPES.TWILIO && canal?.medium === 'whatsapp';

// Que tipo de mensagem este canal pede. Vazio enquanto não há canal.
export const tipoDeMensagem = canal => {
  if (!canal) return '';
  if (canal.channelType === INBOX_TYPES.WHATSAPP) {
    return canStartWithWhatsappApi(canal)
      ? TIPOS.WHATSAPP_LIVRE
      : TIPOS.WHATSAPP_PRONTA;
  }
  if (ehWhatsappTwilio(canal)) return TIPOS.WHATSAPP_TWILIO;
  if (canal.channelType === INBOX_TYPES.EMAIL) return TIPOS.EMAIL;
  return TIPOS.TEXTO;
};

// O nome do tipo de canal para a pessoa: a chave do catálogo, nunca o nome
// técnico da caixa.
export const chaveDoCanal = canal => {
  const tipo = canal?.channelType;
  if (tipo === INBOX_TYPES.WHATSAPP || ehWhatsappTwilio(canal)) {
    return 'WHATSAPP';
  }
  // #2255: a caixa API ligada ao WAHA é o WhatsApp do celular, não "Outro canal".
  if (ehWhatsappDoCelular(canal)) return 'WHATSAPP_CELULAR';
  if (tipo === INBOX_TYPES.EMAIL) return 'EMAIL';
  if (tipo === INBOX_TYPES.SMS || tipo === INBOX_TYPES.TWILIO) return 'SMS';
  if (tipo === INBOX_TYPES.WEB) return 'SITE';
  return 'OUTRO';
};

// "+551140000001" → "+55 11 4000-0001". Um jeito só de mostrar telefone no painel
// (#2255): a regra mora em telefoneDoPais.
export { telefoneLegivel };

// O telefone ou o e-mail de uma pessoa, para a linha de baixo do nome.
export const contatoLegivel = pessoa =>
  pessoa?.phoneNumber
    ? telefoneLegivel(pessoa.phoneNumber)
    : pessoa?.email || '';

// A ordem dos canais na gaveta: WhatsApp primeiro (o que aceita texto livre
// antes do que só aceita mensagem pronta), depois e-mail, SMS, site e o
// resto; no mesmo tipo, por nome. O primeiro da lista é o que já vem marcado.
const ORDEM_DOS_CANAIS = [
  'WHATSAPP',
  'WHATSAPP_CELULAR',
  'EMAIL',
  'SMS',
  'SITE',
  'OUTRO',
];

const pesoDoCanal = canal => {
  const chave = chaveDoCanal(canal);
  const semTextoLivre =
    chave === 'WHATSAPP' && !canStartWithWhatsappApi(canal) ? 1 : 0;
  return ORDEM_DOS_CANAIS.indexOf(chave) * 2 + semTextoLivre;
};

export const ordenarCanais = (canais = []) =>
  [...canais].sort(
    (a, b) =>
      pesoDoCanal(a) - pesoDoCanal(b) ||
      (a.name || '').localeCompare(b.name || '')
  );

// A linha de baixo do canal: o número ou o e-mail por onde a mensagem sai.
export const linhaDoCanal = canal => {
  if (!canal) return '';
  if (canal.channelType === INBOX_TYPES.EMAIL) return canal.email || '';
  // WhatsApp pelo celular (caixa API do WAHA): o número da sessão (#2255).
  const numero = canal.phoneNumber || canal.wahaPhoneNumber || '';
  return telefoneLegivel(
    numero.startsWith(PREFIXO_TWILIO)
      ? numero.slice(PREFIXO_TWILIO.length)
      : numero
  );
};

export const aceitaAnexo = canal =>
  canal?.channelType === INBOX_TYPES.EMAIL ||
  canal?.channelType === INBOX_TYPES.WEB;

// #1988 — WhatsApp oficial (Cloud API) e WhatsApp comum (caixa API ligada ao WAHA),
// os mesmos que ganham a pele do WhatsApp na conversa (pele.js). O Twilio fica de fora.
export const ehCanalWhatsapp = canal =>
  canal?.channelType === INBOX_TYPES.WHATSAPP || ehWhatsappDoCelular(canal);

// #1988 — a caixa de escrever do WhatsApp (texto, "+", emoji, microfone e assinatura)
// vale onde o texto é livre: o WhatsApp oficial que pode responder e o WhatsApp comum.
export const usaCaixaDoWhatsapp = ({ canal, tipo }) =>
  ehCanalWhatsapp(canal) &&
  (tipo === TIPOS.WHATSAPP_LIVRE || tipo === TIPOS.TEXTO);

// O formato da gravação, o mesmo da caixa de resposta (ReplyBox.audioRecordFormat):
// a Cloud API só toca como voz o OGG; o 360dialog e o WAHA recebem MP3.
export const formatoDoAudio = canal =>
  canal?.channelType === INBOX_TYPES.WHATSAPP &&
  canal?.provider === 'whatsapp_cloud'
    ? AUDIO_FORMATS.OGG
    : AUDIO_FORMATS.MP3;

// A Cloud API manda um anexo por mensagem (o texto vai como legenda do primeiro),
// como a caixa de resposta faz (ReplyBox.sendMessageAsMultipleMessages). O WAHA
// recebe tudo numa mensagem só.
export const umAnexoPorMensagem = canal =>
  canal?.channelType === INBOX_TYPES.WHATSAPP;

// A mensagem sai como modelo aprovado (e não como texto escrito na hora)?
export const usaModelo = ({ tipo, modo }) =>
  tipo === TIPOS.WHATSAPP_PRONTA ||
  (tipo === TIPOS.WHATSAPP_LIVRE && modo === MODOS.PRONTA);

// O que falta para enviar, uma coisa por vez e na ordem da tela. Devolve a
// chave do catálogo (NOVA_CONVERSA.RODAPE.FALTA.*) ou '' quando está pronto.
// Continuando uma conversa (#1505), `tipo` vem do que a conversa permite e o
// e-mail segue o assunto dela (`comAssunto` falso).
export const oQueFalta = ({
  contato,
  canal,
  tipo: tipoDado = '',
  comAssunto = true,
  modo = MODOS.ESCREVER,
  mensagem = '',
  assunto = '',
  modelo = null,
  camposProntos = false,
  modeloDoEmail = null,
  anexos = [],
}) => {
  if (!contato?.id) return 'CONTATO';
  if (!canal) return 'CANAL';
  const tipo = tipoDado || tipoDeMensagem(canal);
  // No WhatsApp via Twilio a mensagem pronta é escolhida e enviada no
  // próprio seletor: o botão do rodapé nunca fica pronto.
  if (tipo === TIPOS.WHATSAPP_TWILIO) return 'MODELO';
  if (usaModelo({ tipo, modo })) {
    if (!modelo) return 'MODELO';
    return camposProntos ? '' : 'CAMPOS';
  }
  if (tipo === TIPOS.EMAIL && comAssunto && !assunto.trim()) return 'ASSUNTO';
  // #1809: com modelo de e-mail, dá para enviar só o modelo (como na resposta).
  if (tipo === TIPOS.EMAIL && modeloDoEmail) return '';
  // #1988: só o anexo (a gravação, a foto) já é mensagem, como na caixa de resposta.
  return mensagem.trim() || anexos.length ? '' : 'MENSAGEM';
};

// "boas_vindas_cliente" → "Boas vindas cliente": o nome do modelo como a
// pessoa leria.
export const nomeLegivel = (nome = '') => {
  const limpo = nome.split('_').join(' ').split('-').join(' ').trim();
  return limpo.charAt(0).toUpperCase() + limpo.slice(1);
};

// O que a pessoa digitou pode virar um contato novo? Só telefone com DDI
// (+55…) ou e-mail, que é o que a criação rápida aceita.
export const podeCriarContato = (valor = '') => {
  const texto = valor.trim();
  if (texto.startsWith('+')) {
    const numeros = texto.slice(1);
    return (
      numeros.length >= 8 &&
      [...numeros].every(letra => letra >= '0' && letra <= '9')
    );
  }
  const [antes, depois, ...resto] = texto.split('@');
  return Boolean(antes && depois?.includes('.') && !resto.length);
};

// Onde a pessoa estava quando abriu a gaveta, para a migalha do cabeçalho.
export const lugarDeOrigem = ({ rota = '', comContato = false }) => {
  if (rota.startsWith('contacts')) return 'CONTATOS';
  if (comContato && !rota.includes('conversation')) return 'CONTATOS';
  return 'CONVERSAS';
};

// O primeiro nome de uma pessoa, para as frases que falam dela.
// Nome que é só telefone ("+55 11 95555-4444") vai inteiro: o "primeiro nome" seria "+55" (#2255).
export const primeiroNome = (nome = '') => {
  if (nomeEhTelefone(nome)) return nome.trim();
  return nome.trim().split(' ')[0] || '';
};

// Em que momento a gaveta está, para o cabeçalho, a prévia e o rodapé
// mudarem juntos.
export const TELAS = {
  ENVIADA: 'enviada',
  SEM_CONTATO: 'sem_contato',
  SEM_CANAL: 'sem_canal',
  ESCREVENDO: 'escrevendo',
};

export const telaDaGaveta = ({
  enviada = false,
  contato = null,
  carregandoCanais = false,
  erroNosCanais = false,
  canais = [],
}) => {
  if (enviada) return TELAS.ENVIADA;
  if (!contato) return TELAS.SEM_CONTATO;
  const semCanal = !carregandoCanais && !erroNosCanais && !canais.length;
  return semCanal ? TELAS.SEM_CANAL : TELAS.ESCREVENDO;
};
