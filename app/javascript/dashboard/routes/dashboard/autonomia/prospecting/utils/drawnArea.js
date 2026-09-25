// Área desenhada da busca (#678): círculo, retângulo e polígono. Converte as
// formas do Google Maps no formato que o servidor grava em area_config
// (SearchArea no backend) e diz quando a área já serve para buscar.
export const DRAWN_AREA_TYPES = ['circle', 'rectangle', 'polygon'];
export const MIN_POLYGON_POINTS = 3;

const COORDINATE_DIGITS = 6;
const METERS_PER_DEGREE = 111320;

export const isDrawnAreaType = areaType => DRAWN_AREA_TYPES.includes(areaType);

const round = value => Number(Number(value).toFixed(COORDINATE_DIGITS));

const pointOf = latLng => ({
  lat: round(latLng.lat()),
  lng: round(latLng.lng()),
});

export const circleArea = circle => ({
  type: 'circle',
  config: {
    center: pointOf(circle.getCenter()),
    radius: Math.round(circle.getRadius()),
  },
});

export const rectangleArea = rectangle => {
  const bounds = rectangle.getBounds();
  const northEast = bounds.getNorthEast();
  const southWest = bounds.getSouthWest();
  return {
    type: 'rectangle',
    config: {
      bounds: {
        north: round(northEast.lat()),
        south: round(southWest.lat()),
        east: round(northEast.lng()),
        west: round(southWest.lng()),
      },
    },
  };
};

export const polygonPoints = polygon => {
  const path = polygon.getPath();
  return Array.from({ length: path.getLength() }, (_, index) =>
    pointOf(path.getAt(index))
  );
};

export const polygonArea = polygon => {
  const path = polygonPoints(polygon);
  if (path.length < MIN_POLYGON_POINTS) return null;

  return { type: 'polygon', config: { path } };
};

// Quadrado em volta do clique, com meia largura igual ao raio padrão da busca.
export const rectangleAround = (latLng, halfSizeMeters) => {
  const lat = latLng.lat();
  const lng = latLng.lng();
  const latDelta = halfSizeMeters / METERS_PER_DEGREE;
  const lngDelta =
    halfSizeMeters / (METERS_PER_DEGREE * Math.cos((lat * Math.PI) / 180));
  return {
    north: round(lat + latDelta),
    south: round(lat - latDelta),
    east: round(lng + lngDelta),
    west: round(lng - lngDelta),
  };
};

export const isDrawnAreaReady = (areaType, drawnArea) =>
  !isDrawnAreaType(areaType) || drawnArea?.type === areaType;
