// Calendário Ouro — o dia e a hora sempre no fuso da conta (Configurações),
// nunca no do navegador. O dia vira uma chave "AAAA-MM-DD" e as contas de dia
// são feitas sobre a chave, ao meio-dia UTC, para não pular dia no horário de verão.
import { scheduleToUtc } from 'dashboard/components-next/CampaignJourney/scheduleTime';

const partes = (data, fuso) =>
  Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: fuso,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(data)
      .map(parte => [parte.type, parte.value])
  );

export const chaveDoDia = (data, fuso) => {
  const p = partes(data, fuso);
  return `${p.year}-${p.month}-${p.day}`;
};

// Minutos desde a meia-noite, no fuso da conta.
export const minutosDoDia = (data, fuso) => {
  const p = partes(data, fuso);
  return Number(p.hour) * 60 + Number(p.minute);
};

export const dataDaChave = chave => new Date(`${chave}T12:00:00Z`);

export const somarDias = (chave, dias) => {
  const data = dataDaChave(chave);
  data.setUTCDate(data.getUTCDate() + dias);
  return data.toISOString().slice(0, 10);
};

export const diasEntre = (de, ate) =>
  Math.round((dataDaChave(ate) - dataDaChave(de)) / 86400000);

// Semana de domingo a sábado, como no calendário do Brasil.
export const inicioDaSemana = chave =>
  somarDias(chave, -dataDaChave(chave).getUTCDay());

export const diasDaSemana = chave => {
  const inicio = inicioDaSemana(chave);
  return Array.from({ length: 7 }, (_, i) => somarDias(inicio, i));
};

export const inicioDoMes = chave => `${chave.slice(0, 8)}01`;

export const somarMeses = (chave, meses) => {
  const data = dataDaChave(inicioDoMes(chave));
  data.setUTCMonth(data.getUTCMonth() + meses);
  return data.toISOString().slice(0, 10);
};

// As semanas inteiras que o mês toca (5 ou 6 linhas de 7 dias).
export const semanasDoMes = chave => {
  const primeiro = inicioDoMes(chave);
  const ultimo = somarDias(somarMeses(primeiro, 1), -1);
  const semanas = [];
  let dia = inicioDaSemana(primeiro);
  while (dia <= ultimo) {
    semanas.push(diasDaSemana(dia));
    dia = somarDias(dia, 7);
  }
  return semanas;
};

export const formatarDia = (chave, idioma, opcoes) =>
  new Intl.DateTimeFormat(idioma, { timeZone: 'UTC', ...opcoes }).format(
    dataDaChave(chave)
  );

export const formatarHora = (data, fuso, idioma) =>
  new Intl.DateTimeFormat(idioma, {
    timeZone: fuso,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(data);

// "AAAA-MM-DD" + "HH:MM" no fuso da conta → instante em ISO (UTC).
export const instanteNaConta = (chave, hora, fuso) =>
  scheduleToUtc(`${chave}T${hora}`, fuso);
