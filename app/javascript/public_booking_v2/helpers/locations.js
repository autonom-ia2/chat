// Locais da página. O nome é o que o servidor manda (rótulo do dono ou nome leigo do catálogo); sem ele, a tradução
// do tipo. Tipo desconhecido vira "Atendimento" genérico. O local presencial mostra o endereço que o dono publicou.
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

export const locationName = (location, t) =>
  location?.label || t(`BOOKING_V2.LOCATION.${locationKey(location?.type)}`);

export const locationAddress = location =>
  location?.type === 'in_person' ? location.address || '' : '';

export const locationHint = (location, t) => {
  const address = locationAddress(location);
  if (address) return t('BOOKING_V2.ADDRESS', { address });
  return t(`BOOKING_V2.LOCATION_HINT.${locationKey(location?.type)}`);
};

export const locationOptions = (locations, t) =>
  locations.map(item => ({
    value: item.type,
    label: locationName(item, t),
    hint: locationHint(item, t),
  }));
