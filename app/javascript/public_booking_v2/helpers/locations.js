// Tipo de local da API → chave de tradução. Tipo desconhecido vira "Reunião" genérica.
const KNOWN_TYPES = [
  'whatsapp_video',
  'whatsapp_voice',
  'custom_link',
  'in_person',
  'google_meet',
  'teams',
];

export const locationKey = type =>
  KNOWN_TYPES.includes(type) ? type.toUpperCase() : 'OTHER';
