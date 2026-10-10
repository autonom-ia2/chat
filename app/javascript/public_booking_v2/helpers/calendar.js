// "Adicionar ao Google Agenda" (RA-15): no navegador de dentro do WhatsApp/Instagram o download do .ics pode não
// abrir, então oferecemos também o modelo de evento do Google, montado aqui. Só título, horário e local: nenhum dado
// da pessoa.
const GOOGLE_TEMPLATE = 'https://calendar.google.com/calendar/render';

// 2026-10-13T18:00:00.000Z -> 20261013T180000Z (formato que o Google pede), sem regex.
const compactUtc = date =>
  `${date.toISOString().split('.')[0].split('-').join('').split(':').join('')}Z`;

export const googleCalendarUrl = ({ title, startsAt, endsAt, location }) => {
  const start = new Date(startsAt || '');
  const end = new Date(endsAt || '');
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return null;

  const params = new URLSearchParams({
    action: 'TEMPLATE',
    text: title,
    dates: `${compactUtc(start)}/${compactUtc(end)}`,
  });
  if (location) params.set('location', location);
  return `${GOOGLE_TEMPLATE}?${params.toString()}`;
};
