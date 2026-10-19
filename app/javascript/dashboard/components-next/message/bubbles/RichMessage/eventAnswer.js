// As respostas a um convite de evento (chat#1709, rodada 2), agregadas na própria mensagem do evento em
// `content_attributes.event_responses` (aqui `eventResponses`): [{ senderType, senderId, response, extraGuests, at }],
// uma por pessoa. response: going | not_going | maybe.
const RESPONSES = ['going', 'not_going', 'maybe'];

// { going, not_going, maybe }: quantas pessoas responderam cada uma.
export const eventResponseCounts = eventResponses =>
  (Array.isArray(eventResponses) ? eventResponses : []).reduce(
    (counts, entry) =>
      RESPONSES.includes(entry?.response)
        ? { ...counts, [entry.response]: counts[entry.response] + 1 }
        : counts,
    { going: 0, not_going: 0, maybe: 0 }
  );

// A data e a hora no fuso da conta, sem nome de fuso (regra do Rodrigo: nunca "Horário de Brasília").
export const eventDateLabel = (isoText, timeZone, locale) => {
  const date = new Date(isoText);
  if (!isoText || Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat(locale || undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
    ...(timeZone ? { timeZone } : {}),
  }).format(date);
};
