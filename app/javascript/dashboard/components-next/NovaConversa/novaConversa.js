import parsePhoneNumber from 'libphonenumber-js';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { canStartWithWhatsappApi } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

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
  if (tipo === INBOX_TYPES.EMAIL) return 'EMAIL';
  if (tipo === INBOX_TYPES.SMS || tipo === INBOX_TYPES.TWILIO) return 'SMS';
  if (tipo === INBOX_TYPES.WEB) return 'SITE';
  return 'OUTRO';
};

// "+551140000001" → "+55 (11) 4000-0001": o código do país e o número como
// se escreve naquele país. O que a biblioteca não reconhece como telefone
// completo (com DDI) volta como veio.
export const telefoneLegivel = (numero = '') => {
  const telefone = parsePhoneNumber(numero);
  if (!telefone?.isPossible()) return numero;
  return `+${telefone.countryCallingCode} ${telefone.formatNational()}`;
};

// O telefone ou o e-mail de uma pessoa, para a linha de baixo do nome.
export const contatoLegivel = pessoa =>
  pessoa?.phoneNumber
    ? telefoneLegivel(pessoa.phoneNumber)
    : pessoa?.email || '';

// A ordem dos canais na gaveta: WhatsApp primeiro (o que aceita texto livre
// antes do que só aceita mensagem pronta), depois e-mail, SMS, site e o
// resto; no mesmo tipo, por nome. O primeiro da lista é o que já vem marcado.
const ORDEM_DOS_CANAIS = ['WHATSAPP', 'EMAIL', 'SMS', 'SITE', 'OUTRO'];

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
  const numero = canal.phoneNumber || '';
  return telefoneLegivel(
    numero.startsWith(PREFIXO_TWILIO)
      ? numero.slice(PREFIXO_TWILIO.length)
      : numero
  );
};

export const aceitaAnexo = canal =>
  canal?.channelType === INBOX_TYPES.EMAIL ||
  canal?.channelType === INBOX_TYPES.WEB;

// A mensagem sai como modelo aprovado (e não como texto escrito na hora)?
export const usaModelo = ({ tipo, modo }) =>
  tipo === TIPOS.WHATSAPP_PRONTA ||
  (tipo === TIPOS.WHATSAPP_LIVRE && modo === MODOS.PRONTA);

// O que falta para enviar, uma coisa por vez e na ordem da tela. Devolve a
// chave do catálogo (NOVA_CONVERSA.RODAPE.FALTA.*) ou '' quando está pronto.
export const oQueFalta = ({
  contato,
  canal,
  modo = MODOS.ESCREVER,
  mensagem = '',
  assunto = '',
  modelo = null,
  camposProntos = false,
}) => {
  if (!contato?.id) return 'CONTATO';
  if (!canal) return 'CANAL';
  const tipo = tipoDeMensagem(canal);
  // No WhatsApp via Twilio a mensagem pronta é escolhida e enviada no
  // próprio seletor: o botão do rodapé nunca fica pronto.
  if (tipo === TIPOS.WHATSAPP_TWILIO) return 'MODELO';
  if (usaModelo({ tipo, modo })) {
    if (!modelo) return 'MODELO';
    return camposProntos ? '' : 'CAMPOS';
  }
  if (tipo === TIPOS.EMAIL && !assunto.trim()) return 'ASSUNTO';
  return mensagem.trim() ? '' : 'MENSAGEM';
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
