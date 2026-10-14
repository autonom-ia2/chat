// Link de mapa de uma localização (chat#1473, P5): a enviada (types/Location.vue) e a recebida
// (ReceivedLocation.vue). O mesmo endereço e o mesmo formato estão na versão em texto do envio
// (app/services/rich_messages/types/location.rb, MAP_LINK e `decimal`): mudou um, mude o outro.
const MAP_LINK = 'https://maps.google.com/?q=';
const LATITUDE_MAX = 90;
const LONGITUDE_MAX = 180;

// Só número finito na faixa vira coordenada: texto, ausente ou fora da faixa não cria link.
const coordinateOf = (value, limit) =>
  Number.isFinite(value) && Math.abs(value) <= limit ? value : null;

// Notação decimal comum, sempre com ao menos uma casa e sem notação científica (90 → "90.0",
// 1e-7 → "0.0000001"), igual ao `decimal` do location.rb, para o link sair o mesmo nos dois lados.
const decimalOf = value => {
  if (Number.isInteger(value)) return value.toFixed(1);

  const [mantissa, exponent] = String(value).split('e');
  if (!exponent) return mantissa;

  const mantissaDecimals = (mantissa.split('.')[1] ?? '').length;
  return value.toFixed(mantissaDecimals - Number(exponent));
};

// O link do ponto, ou '' quando alguma coordenada não é válida.
export const mapHrefOf = (latitude, longitude) => {
  const lat = coordinateOf(latitude, LATITUDE_MAX);
  const long = coordinateOf(longitude, LONGITUDE_MAX);
  if (lat === null || long === null) return '';

  return `${MAP_LINK}${decimalOf(lat)},${decimalOf(long)}`;
};
