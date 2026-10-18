// Dados do cartão de e-mail (#1786): quem escreveu de verdade, para quem, a data como
// o leitor de e-mail mostra e o bloqueio do rastreio das nossas campanhas.
// Funções puras, testáveis sem tela.
import { MESSAGE_TYPES } from '../../message/constants';

const minusculo = texto =>
  String(texto || '')
    .trim()
    .toLowerCase();

// "Fulano <fulano@x.com>" ou "fulano@x.com" → { nome, endereco }. Sem regex: o
// endereço fica entre o último "<" e o ">" seguinte.
export const lerEndereco = texto => {
  const bruto = String(texto || '').trim();
  const abre = bruto.lastIndexOf('<');
  const fecha = bruto.indexOf('>', abre);
  if (abre >= 0 && fecha > abre) {
    const nome = bruto.slice(0, abre).trim().split('"').join('');
    return { nome, endereco: bruto.slice(abre + 1, fecha).trim() };
  }
  return { nome: '', endereco: bruto };
};

const lista = valor => {
  if (Array.isArray(valor)) return valor.filter(Boolean);
  if (!valor) return [];
  return String(valor)
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);
};

// Quem escreveu este e-mail. O Chatwoot grava todo e-mail de entrada com o contato
// da conversa como remetente (mailbox_sanitizer.rb), mesmo quando quem escreveu foi
// outra pessoa (alguém em cópia). O endereço real fica em `email.from`.
export const remetenteDoEmail = ({ contentAttributes, sender, recebido }) => {
  const doCabecalho = lerEndereco(lista(contentAttributes?.email?.from)[0]);
  const endereco = doCabecalho.endereco || sender?.email || '';
  const doContato =
    !doCabecalho.endereco || minusculo(endereco) === minusculo(sender?.email);
  return {
    nome: doContato
      ? sender?.name || doCabecalho.nome || endereco
      : doCabecalho.nome || endereco,
    endereco,
    foto: doContato ? sender?.thumbnail || '' : '',
    // Selo "em cópia": entrada escrita por alguém que não é o contato da conversa.
    emCopia: Boolean(recebido && !doContato),
  };
};

export const destinatariosDoEmail = contentAttributes => ({
  para: lista(contentAttributes?.email?.to ?? contentAttributes?.toEmails),
  cc: lista(contentAttributes?.ccEmails ?? contentAttributes?.email?.cc),
  cco: lista(contentAttributes?.bccEmails ?? contentAttributes?.email?.bcc),
});

// Nome curto para "para mim, Paulo": o nome antes do @ quando não há outro.
export const nomeCurto = texto => {
  const { nome, endereco } = lerEndereco(texto);
  return (nome || endereco.split('@')[0] || '').split(' ')[0];
};

const formatadores = new Map();
const formatador = (idioma, opcoes) => {
  const chave = JSON.stringify([idioma, opcoes]);
  if (!formatadores.has(chave)) {
    formatadores.set(chave, new Intl.DateTimeFormat(idioma, opcoes));
  }
  return formatadores.get(chave);
};

const UM_DIA = 86400;

// Como o leitor de e-mail: hoje só a hora; este ano "16 de out."; antes, com o ano.
// Sempre no fuso da conta, nunca no do computador de quem vê.
export const dataCurtaDoEmail = ({ quando, agora, fuso, idioma = 'pt-BR' }) => {
  const dia = formatador('en-CA', {
    timeZone: fuso,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const data = new Date(quando * 1000);
  const hoje = new Date(agora * 1000);
  if (dia.format(data) === dia.format(hoje)) {
    return formatador(idioma, {
      timeZone: fuso,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).format(data);
  }
  const mesmoAno =
    formatador('en-CA', { timeZone: fuso, year: 'numeric' }).format(data) ===
    formatador('en-CA', { timeZone: fuso, year: 'numeric' }).format(hoje);
  return formatador(idioma, {
    timeZone: fuso,
    day: 'numeric',
    month: 'short',
    ...(mesmoAno ? {} : { year: 'numeric' }),
  }).format(data);
};

// "sex., 16 de out. de 2026, 12:20 (há 1 dia)": a data inteira do detalhe.
export const dataCompletaDoEmail = ({
  quando,
  agora,
  fuso,
  idioma = 'pt-BR',
}) => {
  const texto = formatador(idioma, {
    timeZone: fuso,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(quando * 1000));
  const dias = Math.round((quando - agora) / UM_DIA);
  if (!dias) return texto;
  const relativo = new Intl.RelativeTimeFormat(idioma, {
    numeric: 'auto',
  }).format(dias, 'day');
  return `${texto} (${relativo})`;
};

// Pixel de abertura e links de clique das nossas campanhas
// (email_campaigns/tracking/injector.rb): carregar na tela do atendente contaria uma
// abertura ou um clique falso. Comparação de texto, sem regex.
const RASTREIO_DE_CAMPANHA = '/email_campaigns/t/';
export const ehRastreioDeCampanha = url =>
  String(url || '').includes(RASTREIO_DE_CAMPANHA);
export const semRastreio = url => (ehRastreioDeCampanha(url) ? '' : url);

// E-mail de verdade da conversa (entrada ou saída, não nota privada nem aviso).
export const ehEmail = mensagem =>
  !mensagem.private &&
  [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(
    mensagem.message_type
  );

// O assunto da conversa: o gravado na conversa (o mesmo que o servidor usa no envio,
// ConversationReplyMailer#mail_subject) ou, na falta, o do primeiro e-mail que tiver.
export const assuntoDaConversa = ({ conversa, emails = [] }) =>
  conversa?.additional_attributes?.mail_subject ||
  emails.find(m => m.content_attributes?.email?.subject)?.content_attributes
    .email.subject ||
  '';

// A resposta numa conversa que já existe sai com "Re: <assunto>" (#1786, #1809).
export const assuntoDaResposta = assunto => (assunto ? `Re: ${assunto}` : '');
