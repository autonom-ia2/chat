<script setup>
// Desenho da área da busca no mapa do formulário (#678, E2 frente B). Usa as
// formas editáveis do núcleo do Google Maps (Circle, Rectangle, Polygon); a
// biblioteca drawing (DrawingManager) foi retirada pelo Google em maio de 2026.
// Uma forma por vez: o círculo e o retângulo nascem no clique e se ajustam
// pelas alças; o polígono ganha um ponto a cada clique.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { loadGoogleMaps } from '../../utils/googleMapsLoader';
import {
  circleArea,
  polygonArea,
  polygonPoints,
  rectangleArea,
  rectangleAround,
} from '../../utils/drawnArea';

const props = defineProps({
  apiKey: { type: String, default: '' },
  center: { type: Object, required: true },
  shape: { type: String, required: true },
  defaultRadius: { type: Number, default: 1000 },
  modelValue: { type: Object, default: null },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const MAP_ZOOM = 13;
const SHAPE_STYLE = {
  fillColor: '#1f93ff',
  fillOpacity: 0.12,
  strokeColor: '#1f93ff',
  strokeOpacity: 0.8,
  strokeWeight: 2,
};

const mapElement = ref(null);
const loadError = ref('');
const pointsCount = ref(0);
let map = null;
let overlay = null;
let listeners = [];

const HINTS = {
  circle: () => t('PROSPECTING.SEARCH.AREA_DRAW.HINT_CIRCLE'),
  rectangle: () => t('PROSPECTING.SEARCH.AREA_DRAW.HINT_RECTANGLE'),
  polygon: () => t('PROSPECTING.SEARCH.AREA_DRAW.HINT_POLYGON'),
};

const hint = computed(() => HINTS[props.shape]?.() || '');
const isReady = computed(() => props.modelValue?.type === props.shape);
const hasOverlay = computed(() => pointsCount.value > 0 || isReady.value);

const removeListeners = () => {
  listeners.forEach(listener => listener.remove());
  listeners = [];
};

const clearOverlay = () => {
  removeListeners();
  if (overlay) overlay.setMap(null);
  overlay = null;
  pointsCount.value = 0;
};

const clearDrawing = () => {
  clearOverlay();
  emit('update:modelValue', null);
};

const emitPolygon = () => {
  pointsCount.value = polygonPoints(overlay).length;
  emit('update:modelValue', polygonArea(overlay));
};

const listen = (target, events, handler) => {
  events.forEach(event => listeners.push(target.addListener(event, handler)));
};

const createCircle = latLng => {
  overlay = new window.google.maps.Circle({
    ...SHAPE_STYLE,
    map,
    center: { lat: latLng.lat(), lng: latLng.lng() },
    radius: props.defaultRadius,
    editable: true,
    draggable: true,
  });
  const update = () => emit('update:modelValue', circleArea(overlay));
  listen(overlay, ['radius_changed', 'center_changed'], update);
  pointsCount.value = 1;
  update();
};

const createRectangle = latLng => {
  overlay = new window.google.maps.Rectangle({
    ...SHAPE_STYLE,
    map,
    bounds: rectangleAround(latLng, props.defaultRadius),
    editable: true,
    draggable: true,
  });
  const update = () => emit('update:modelValue', rectangleArea(overlay));
  listen(overlay, ['bounds_changed'], update);
  pointsCount.value = 1;
  update();
};

const createPolygon = latLng => {
  overlay = new window.google.maps.Polygon({
    ...SHAPE_STYLE,
    map,
    paths: [{ lat: latLng.lat(), lng: latLng.lng() }],
    editable: true,
  });
  listen(overlay.getPath(), ['insert_at', 'set_at', 'remove_at'], emitPolygon);
  emitPolygon();
};

const handleMapClick = event => {
  if (!event?.latLng) return;
  if (props.shape === 'polygon' && overlay) {
    overlay.getPath().push(event.latLng);
    return;
  }
  if (overlay) return;

  if (props.shape === 'circle') createCircle(event.latLng);
  if (props.shape === 'rectangle') createRectangle(event.latLng);
  if (props.shape === 'polygon') createPolygon(event.latLng);
};

const undoPolygonPoint = () => {
  if (props.shape !== 'polygon' || !overlay) return;
  overlay.getPath().pop();
};

const mapCenter = () => ({
  lat: Number(props.center.lat),
  lng: Number(props.center.lng),
});

let mapClickListener = null;

onMounted(async () => {
  if (!props.apiKey) return;

  try {
    await loadGoogleMaps(props.apiKey);
  } catch {
    loadError.value = t('PROSPECTING.SEARCH.MAP_LOAD_ERROR');
    return;
  }
  if (!mapElement.value) return;

  map = new window.google.maps.Map(mapElement.value, {
    center: mapCenter(),
    zoom: MAP_ZOOM,
    mapTypeControl: false,
    streetViewControl: false,
    fullscreenControl: true,
    zoomControl: true,
    clickableIcons: false,
  });
  mapClickListener = map.addListener('click', handleMapClick);
});

watch(
  () => props.shape,
  () => clearDrawing()
);

watch(
  () => [props.center?.lat, props.center?.lng],
  () => {
    if (map) map.panTo(mapCenter());
  }
);

onBeforeUnmount(() => {
  clearOverlay();
  if (mapClickListener) mapClickListener.remove();
  map = null;
});
</script>

<template>
  <div class="grid gap-2">
    <p class="text-xs text-n-slate-10">{{ hint }}</p>
    <div
      v-if="!apiKey"
      class="flex h-80 items-center justify-center rounded-md border border-n-weak bg-n-solid-2 px-4 text-center text-sm text-n-slate-10"
    >
      {{ t('PROSPECTING.SEARCH.MAP_API_KEY_MISSING') }}
    </div>
    <div
      v-else-if="loadError"
      class="flex h-80 items-center justify-center rounded-md border border-n-weak bg-n-solid-2 px-4 text-center text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </div>
    <div
      v-else
      ref="mapElement"
      role="application"
      :aria-label="t('PROSPECTING.SEARCH.AREA_DRAW.MAP_LABEL')"
      class="h-80 overflow-hidden rounded-md border border-n-weak bg-n-solid-2"
    />
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span
        role="status"
        class="text-xs"
        :class="isReady ? 'text-n-teal-11' : 'text-n-slate-10'"
      >
        <template v-if="isReady">
          {{ t('PROSPECTING.SEARCH.AREA_DRAW.READY') }}
        </template>
        <template v-else>
          {{ t('PROSPECTING.SEARCH.AREA_DRAW.PENDING') }}
        </template>
        <template v-if="shape === 'polygon' && pointsCount > 0">
          {{ t('PROSPECTING.SEARCH.AREA_DRAW.POINTS', { count: pointsCount }) }}
        </template>
      </span>
      <div class="flex gap-2">
        <button
          v-if="shape === 'polygon' && pointsCount > 0"
          type="button"
          class="inline-flex min-h-11 items-center rounded-md border border-n-weak px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
          @click="undoPolygonPoint"
        >
          {{ t('PROSPECTING.SEARCH.AREA_DRAW.UNDO_POINT') }}
        </button>
        <button
          v-if="hasOverlay"
          type="button"
          class="inline-flex min-h-11 items-center rounded-md border border-n-weak px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
          @click="clearDrawing"
        >
          {{ t('PROSPECTING.SEARCH.AREA_DRAW.CLEAR') }}
        </button>
      </div>
    </div>
  </div>
</template>
