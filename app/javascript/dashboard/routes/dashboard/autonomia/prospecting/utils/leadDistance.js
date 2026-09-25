// Distância do lead ao centro da busca aberta (#678), para ordenar "mais perto
// primeiro" como no Orth. É calculada na tela, a partir da área gravada na
// busca: vale para busca antiga e para o lead atualizado ao vivo.
const EARTH_RADIUS_KM = 6371;

const toNumber = value => {
  if (value === null || value === undefined || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const point = (lat, lng) => {
  const latitude = toNumber(lat);
  const longitude = toNumber(lng);
  if (latitude === null || longitude === null) return null;
  return { lat: latitude, lng: longitude };
};

const boundsCenter = bounds => {
  if (!bounds) return null;
  const north = toNumber(bounds.north);
  const south = toNumber(bounds.south);
  const east = toNumber(bounds.east);
  const west = toNumber(bounds.west);
  if ([north, south, east, west].includes(null)) return null;
  return { lat: (north + south) / 2, lng: (east + west) / 2 };
};

const pathCenter = path => {
  const points = (path || []).map(item => point(item?.lat, item?.lng));
  if (!points.length || points.includes(null)) return null;
  const sum = points.reduce(
    (total, item) => ({ lat: total.lat + item.lat, lng: total.lng + item.lng }),
    { lat: 0, lng: 0 }
  );
  return { lat: sum.lat / points.length, lng: sum.lng / points.length };
};

// Centro da área da busca: círculo, retângulo, polígono ou, em busca sem área
// gravada, o ponto do local confirmado.
export const searchCenter = search => {
  if (!search) return null;
  const areaConfig = search.area_config || {};
  return (
    point(areaConfig.center?.lat, areaConfig.center?.lng) ||
    boundsCenter(areaConfig.bounds) ||
    pathCenter(areaConfig.path) ||
    point(search.location_latitude, search.location_longitude)
  );
};

const radians = degrees => (degrees * Math.PI) / 180;

// Haversine, em km.
export const distanceKm = (center, lead) => {
  const target = point(lead?.latitude, lead?.longitude);
  if (!center || !target) return null;

  const deltaLat = radians(target.lat - center.lat);
  const deltaLng = radians(target.lng - center.lng);
  const a =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(radians(center.lat)) *
      Math.cos(radians(target.lat)) *
      Math.sin(deltaLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
};
