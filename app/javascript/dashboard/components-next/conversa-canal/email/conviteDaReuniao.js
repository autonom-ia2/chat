// Convite de reunião dentro do e-mail (#1984): o arquivo de calendário (.ics) que vem junto
// do convite do Teams, Meet ou Outlook, lido no recebimento e guardado em `email.convite`.
// Aqui só a apresentação: dia e horário no fuso da conta, quem convidou, quem vai e a
// resposta da própria caixa.

export const RESPOSTAS = ['aceito', 'talvez', 'recusado'];

const formatar = (idioma, fuso, opcoes, segundos) =>
  new Intl.DateTimeFormat(idioma, { timeZone: fuso, ...opcoes }).format(
    new Date(segundos * 1000)
  );

const diaNoFuso = (segundos, fuso) =>
  formatar(
    'en-CA',
    fuso,
    { year: 'numeric', month: '2-digit', day: '2-digit' },
    segundos
  );

const diasEntre = (diaA, diaB) =>
  Math.round((Date.parse(diaA) - Date.parse(diaB)) / 86400000);

// "Hoje", "Amanhã" ou "qua., 22 de out." — sempre no fuso da conta.
export const diaDoConvite = ({ inicio, agora, fuso, t, idioma = 'pt-BR' }) => {
  const diferenca = diasEntre(diaNoFuso(inicio, fuso), diaNoFuso(agora, fuso));
  if (diferenca === 0) return t('CONVERSA_CANAL.EMAIL.CONVITE.HOJE');
  if (diferenca === 1) return t('CONVERSA_CANAL.EMAIL.CONVITE.AMANHA');
  return formatar(
    idioma,
    fuso,
    { weekday: 'short', day: 'numeric', month: 'short' },
    inicio
  );
};

// "16:00 – 16:30"
export const horarioDoConvite = ({ inicio, fim, fuso, idioma = 'pt-BR' }) => {
  const hora = segundos =>
    formatar(
      idioma,
      fuso,
      { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' },
      segundos
    );
  return fim ? `${hora(inicio)} – ${hora(fim)}` : hora(inicio);
};

export const nomeDaPessoa = pessoa => pessoa?.nome || pessoa?.email || '';

// Bloco de data, como na folhinha: mês curto, dia e dia da semana.
export const blocoDaData = ({ inicio, fuso, idioma = 'pt-BR' }) => ({
  mes: formatar(idioma, fuso, { month: 'short' }, inicio).replace('.', ''),
  dia: formatar(idioma, fuso, { day: 'numeric' }, inicio),
  semana: formatar(idioma, fuso, { weekday: 'short' }, inicio).replace('.', ''),
});

// Duração em minutos (null sem fim).
export const minutosDoConvite = ({ inicio, fim }) =>
  fim ? Math.round((fim - inicio) / 60) : null;

// O aplicativo da chamada pelo endereço do link: o botão diz "Entrar no Teams".
const APLICATIVOS = [
  ['teams.microsoft.com', 'Teams'],
  ['teams.live.com', 'Teams'],
  ['meet.google.com', 'Meet'],
  ['zoom.us', 'Zoom'],
];
export const aplicativoDaChamada = link => {
  try {
    const { hostname } = new URL(link);
    const achado = APLICATIVOS.find(
      ([dominio]) => hostname === dominio || hostname.endsWith(`.${dominio}`)
    );
    return achado ? achado[1] : null;
  } catch {
    return null;
  }
};
