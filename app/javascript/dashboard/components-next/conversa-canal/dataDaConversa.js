// Hora e dia das mensagens no fuso da conta (#1702), nunca no do computador de quem
// vê. `quando` é o created_at da mensagem em segundos.

// O painel guarda o idioma como "pt_BR"; o Intl quer "pt-BR".
export const idiomaDoPainel = locale =>
  String(locale || 'en').replace('_', '-');

// Criar um Intl.DateTimeFormat custa caro: um por combinação, reaproveitado.
const formatadores = new Map();
const formatador = (idioma, opcoes) => {
  const chave = JSON.stringify([idioma, opcoes]);
  if (!formatadores.has(chave)) {
    formatadores.set(chave, new Intl.DateTimeFormat(idioma, opcoes));
  }
  return formatadores.get(chave);
};
export const horaDaMensagem = (quando, fuso, idioma = 'pt-BR') =>
  formatador(idioma, {
    timeZone: fuso,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(quando * 1000));

// Chave do dia (aaaa-mm-dd) no fuso da conta, para saber quando o dia muda.
export const diaDaMensagem = (quando, fuso) =>
  formatador('en-CA', {
    timeZone: fuso,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(quando * 1000));

const diasEntre = (diaA, diaB) =>
  Math.round((Date.parse(diaA) - Date.parse(diaB)) / 86400000);

// "Hoje", "Ontem", o dia da semana nos últimos 7 dias ("sábado", em minúsculas, como
// o app escreve) ou a data curta ("07/10/2026").
export const rotuloDoDia = ({ quando, agora, fuso, t, idioma = 'pt-BR' }) => {
  const dia = diaDaMensagem(quando, fuso);
  const diferenca = diasEntre(diaDaMensagem(agora, fuso), dia);
  if (diferenca === 0) return t('CONVERSA_CANAL.DIA.HOJE');
  if (diferenca === 1) return t('CONVERSA_CANAL.DIA.ONTEM');
  const opcoes =
    diferenca > 1 && diferenca < 7
      ? { weekday: 'long' }
      : { day: '2-digit', month: '2-digit', year: 'numeric' };
  return formatador(idioma, { timeZone: fuso, ...opcoes }).format(
    new Date(quando * 1000)
  );
};

// Data e hora completas da dica (ao parar o mouse na hora do balão), no fuso da conta
// e no idioma do painel: "17 de out. de 2026, 14:32". Sem o nome do fuso (regra #1456).
export const dataEHoraDaMensagem = (quando, fuso, idioma = 'pt-BR') =>
  formatador(idioma, {
    timeZone: fuso,
    dateStyle: 'medium',
    timeStyle: 'short',
    calendar: 'gregory',
  }).format(new Date(quando * 1000));
