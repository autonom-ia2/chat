// Frente de local, país e endereço: o local digitado e confirmado, a área
// (raio, área visível do mapa ou área desenhada, #678), o erro do Google ao
// sugerir ou confirmar o local, o tipo de decisor e o pedaço do pedido que
// descreve onde buscar.
import { ref } from 'vue';
import { DEFAULT_DECISION_MAKER_TYPE } from '../../utils/decisionMakerTypes';
import { drawnAreaFromSaved, isDrawnAreaType } from '../../utils/drawnArea';

export const locationCenter = locationDetails => {
  if (!locationDetails?.latitude || !locationDetails?.longitude) return null;

  return {
    lat: Number(locationDetails.latitude),
    lng: Number(locationDetails.longitude),
  };
};

// Centro da busca por raio, o mesmo do círculo da prévia (LOCAL-42). É o do
// local escolhido; numa busca salva reaberta para repetir ou editar, é o
// centro que ela usou, como o setMapCenter(area_config.center) do Orth.
export const radiusCenter = ({ savedRadiusCenter, locationDetails }) =>
  savedRadiusCenter.value || locationCenter(locationDetails.value);

const radiusInMeters = form => Number(form.value.radius_km) * 1000;

// Desenho que vale para o tipo de área escolhido; o de outro tipo não conta.
export const currentDrawnArea = ({ form, drawnArea }) =>
  drawnArea.value?.type === form.value.area_type ? drawnArea.value : null;

// O círculo desenhado leva o próprio raio; o resto usa o raio do formulário.
const searchRadius = state => {
  const drawn = currentDrawnArea(state);
  return drawn?.type === 'circle'
    ? drawn.config.radius
    : radiusInMeters(state.form);
};

const areaConfig = state => {
  const { form, locationDetails, previewViewport, selectedLocationLabel } =
    state;
  const label = selectedLocationLabel.value || form.value.location.trim();
  const placeId = locationDetails.value?.place_id;

  if (isDrawnAreaType(form.value.area_type)) {
    return { ...currentDrawnArea(state)?.config, label, place_id: placeId };
  }

  const base = {
    center: radiusCenter(state),
    label,
    place_id: placeId,
    radius: radiusInMeters(form),
  };

  // Área visível: vale o que a prévia mostra, centro e limites. No raio o
  // centro é o do círculo da prévia; arrastar o mapa não muda a busca.
  if (form.value.area_type === 'viewport') {
    return {
      ...base,
      center: previewViewport.value?.center || base.center,
      bounds: previewViewport.value?.bounds,
    };
  }

  return base;
};

const isChecked = value => value === true || value === 'true';

// Repetir ou editar uma busca salva (#678): o local volta confirmado, sem
// consultar o Google, com o ponto e a área gravados. O raio é o que a pessoa
// pediu, não o que a expansão automática alcançou.
const restoreLocationForm = (
  {
    form,
    locationDetails,
    confirmedLocation,
    previewViewport,
    locationSuggestions,
    locationError,
    drawnArea,
    savedRadiusCenter,
  },
  search
) => {
  const area = search.area_config || {};
  const label = search.location_label || search.location || '';
  const radius = Number(search.requested_radius || search.radius);
  form.value = {
    ...form.value,
    location: search.location || '',
    area_type: search.area_type || 'radius',
    radius_km: radius > 0 ? radius / 1000 : form.value.radius_km,
    auto_expand_radius: isChecked(search.search_filters?.auto_expand_radius),
    decision_maker_type:
      search.decision_maker_type || DEFAULT_DECISION_MAKER_TYPE,
  };
  locationDetails.value = {
    label,
    place_id: search.location_place_id || area.place_id || '',
    latitude: search.location_latitude ?? area.center?.lat,
    longitude: search.location_longitude ?? area.center?.lng,
  };
  confirmedLocation.value = label;
  previewViewport.value = area.center
    ? { center: area.center, bounds: area.bounds }
    : null;
  savedRadiusCenter.value =
    form.value.area_type === 'radius' ? area.center || null : null;
  locationSuggestions.value = [];
  locationError.value = '';
  drawnArea.value = drawnAreaFromSaved(form.value.area_type, area, radius);
};

export const locationSlice = {
  formDefaults: () => ({
    location: '',
    area_type: 'radius',
    radius_km: 1,
    auto_expand_radius: false,
    decision_maker_type: DEFAULT_DECISION_MAKER_TYPE,
  }),
  createState: () => ({
    isSuggestingLocations: ref(false),
    locationSuggestions: ref([]),
    locationDetails: ref(null),
    confirmedLocation: ref(''),
    previewViewport: ref(null),
    locationError: ref(''),
    drawnArea: ref(null),
    savedRadiusCenter: ref(null),
  }),
  reset: ({
    locationSuggestions,
    locationDetails,
    confirmedLocation,
    previewViewport,
    locationError,
    drawnArea,
    savedRadiusCenter,
  }) => {
    locationSuggestions.value = [];
    locationDetails.value = null;
    confirmedLocation.value = '';
    previewViewport.value = null;
    locationError.value = '';
    drawnArea.value = null;
    savedRadiusCenter.value = null;
  },
  restoreForm: (state, search) => restoreLocationForm(state, search),
  toPayload: state => {
    const { form, locationDetails, selectedLocationLabel } = state;
    return {
      body: {
        location: form.value.location.trim(),
        radius: searchRadius(state),
        area_type: form.value.area_type,
        area_config: areaConfig(state),
      },
      metadata: {
        location_place_id: locationDetails.value?.place_id,
        location_latitude: locationDetails.value?.latitude,
        location_longitude: locationDetails.value?.longitude,
        location_label:
          selectedLocationLabel.value || form.value.location.trim(),
        filters: {
          auto_expand_radius: form.value.auto_expand_radius,
        },
        decision_maker_type: form.value.decision_maker_type,
      },
    };
  },
};
