// #2693 — o pedido de busca que vai ao servidor (searches#create), montado na
// porta ou a partir de uma busca salva ("Buscar de novo", "Procurar mais
// longe"). As chaves são as que o motor entende:
// - advanced_filters: SearchRunner#advanced_filter_matches? (as mesmas da tela
//   antiga, utils/advancedLeadFilters.js);
// - score_mode: 'general' (as melhores para você) ou 'gbp' (as que aparecem
//   pouco no Google), SearchRunner#search_score_mode;
// - raio: até 50 km, o teto do Google (SearchArea::MAX_CIRCLE_RADIUS).
const KM = 1000;
export const RAIO_MAXIMO = 50 * KM;
const SIM = 'yes';
const NAO = 'no';

// "Mais ajustes" (AcharMaisAjustesPainel) vira advanced_filters.
const NOTA = {
  n3: { rating_min: '3' },
  n4: { rating_min: '4' },
  n45: { rating_min: '4.5' },
  abaixo_4: { rating_max: '3.9' },
};
const AVALIACOES = {
  n10: { reviews_min: '10' },
  n20: { reviews_min: '20' },
  n50: { reviews_min: '50' },
};
const TEM_OU_NAO = { tem: SIM, nao: NAO };

export const filtrosDosAjustes = (ajustes = {}) => ({
  ...(NOTA[ajustes.nota] || {}),
  ...(AVALIACOES[ajustes.avaliacoes] || {}),
  ...(TEM_OU_NAO[ajustes.site]
    ? { has_website: TEM_OU_NAO[ajustes.site] }
    : {}),
  ...(TEM_OU_NAO[ajustes.fotos]
    ? { has_photos: TEM_OU_NAO[ajustes.fotos] }
    : {}),
  ...(ajustes.aberta ? { open_now: SIM } : {}),
  ...(ajustes.mostraHorario ? { has_opening_hours: SIM } : {}),
});

// A presença fraca é o modo gbp; o padrão continua o modo geral.
export const modoDaOrdem = primeiro =>
  primeiro === 'pouco' ? 'gbp' : 'general';

export const montarPedido = ({ oQue, lugar, como }) => {
  const centro =
    lugar.latitude && lugar.longitude
      ? { lat: Number(lugar.latitude), lng: Number(lugar.longitude) }
      : null;
  const raio = como.km * KM;
  return {
    query: oQue.trim(),
    requested_limit: como.n,
    location: lugar.rotulo,
    radius: raio,
    area_type: 'radius',
    area_config: {
      center: centro,
      label: lugar.rotulo,
      place_id: lugar.placeId,
      radius: raio,
    },
    metadata: {
      location_place_id: lugar.placeId,
      location_latitude: lugar.latitude,
      location_longitude: lugar.longitude,
      location_label: lugar.rotulo,
      filters: { auto_expand_radius: true },
      score_mode: modoDaOrdem(como.primeiro),
      advanced_filters: filtrosDosAjustes(como.ajustes),
    },
  };
};

// O que a busca salva precisa guardar para ser refeita (search_payload).
export const pedidoSalvoDe = search => ({
  query: search.query || '',
  location: search.location || '',
  radius: search.radius ?? null,
  requestedRadius: search.requested_radius ?? search.radius ?? null,
  areaType: search.area_type || 'radius',
  areaConfig: search.area_config || {},
  requestedLimit: search.requested_limit ?? null,
  metadata: {
    location_place_id: search.location_place_id,
    location_latitude: search.location_latitude,
    location_longitude: search.location_longitude,
    location_label: search.location_label,
    score_mode: search.score_mode,
    advanced_filters: search.advanced_filters || {},
    filters: search.search_filters || {},
    ...(search.preset_id ? { preset_id: search.preset_id } : {}),
    ...(search.decision_maker_type
      ? { decision_maker_type: search.decision_maker_type }
      : {}),
  },
});

const porRaio = salvo => salvo.areaType === 'radius';

// "Procurar mais longe" só vale para a busca por raio que ainda não chegou ao
// teto: o raio que a busca alcançou dobra, até 50 km.
export const podeIrMaisLonge = salvo =>
  Boolean(salvo) && porRaio(salvo) && Number(salvo.radius) < RAIO_MAXIMO;

// A mesma busca de novo, sem o cache (fresh), como o "Repetir" da tela antiga.
// "Buscar de novo" pede o raio que a pessoa escolheu (a expansão automática
// roda de novo); "Procurar mais longe" dobra o raio alcançado.
export const pedidoDeNovo = (salvo, { maisLonge = false } = {}) => {
  const raio = maisLonge
    ? Math.min(Number(salvo.radius) * 2, RAIO_MAXIMO)
    : salvo.requestedRadius;
  return {
    query: salvo.query,
    location: salvo.location,
    radius: raio,
    area_type: salvo.areaType,
    area_config: porRaio(salvo)
      ? { ...salvo.areaConfig, radius: raio }
      : salvo.areaConfig,
    requested_limit: salvo.requestedLimit,
    fresh: true,
    metadata: salvo.metadata,
  };
};
