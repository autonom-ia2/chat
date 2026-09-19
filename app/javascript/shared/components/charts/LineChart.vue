<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { LineChart as VizLineChart } from '@chatwoot/viz';

// Fork-only line chart. Upstream (4.16+) dropped chart.js/vue-chartjs in favour
// of @chatwoot/viz, so this component keeps its chart.js-style `collection`
// contract ({ labels, datasets[] }) and adapts it to the viz data shape
// ({ categories, series[] }), mirroring shared/charts/BarChart.vue. The old
// `chartOptions` prop (chart.js option bag) was dropped: viz renders its own
// legend/tooltips and no consumer passed it.
const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  ariaLabel: {
    type: String,
    default: '',
  },
  height: {
    type: Number,
    default: 256,
  },
  showValues: {
    type: Boolean,
    default: true,
  },
  showTooltip: {
    type: Boolean,
    default: true,
  },
  pointRadius: {
    type: Number,
    default: 3,
  },
  yTickCount: {
    type: Number,
    default: 5,
  },
  xInset: {
    type: Number,
    default: undefined,
  },
  xLabelStride: {
    type: Number,
    default: 1,
  },
  xTickLabels: {
    type: Array,
    default: () => [],
  },
  pointBorderColor: {
    type: String,
    default: 'rgb(var(--card-color))',
  },
});

defineOptions({ inheritAttrs: false });

const toSeriesId = (dataset, index) =>
  dataset.id || `${(dataset.label || 'series').toString()}-${index}`;

const chartData = computed(() => {
  const { labels = [], datasets = [] } = props.collection || {};
  return {
    categories: [...labels],
    series: datasets.map((dataset, index) => ({
      id: toSeriesId(dataset, index),
      label: dataset.label,
      color: dataset.borderColor || dataset.backgroundColor,
      pointBorderColor: props.pointBorderColor,
      valueColor: dataset.borderColor || dataset.backgroundColor,
      data: [...(dataset.data || [])],
    })),
  };
});

const formatValue = value => Number(value).toLocaleString();

const chart = ref(null);

const applyXLabelStride = async () => {
  await nextTick();
  const root = chart.value?.$el || chart.value;
  const ticks = root?.querySelectorAll?.('.cw-viz-line__x-tick') || [];
  const stride = Math.max(Math.floor(props.xLabelStride || 1), 1);

  ticks.forEach((tick, index) => {
    const isEdge = index === 0 || index === ticks.length - 1;
    tick.classList.toggle('hidden', !isEdge && index % stride !== 0);

    const label = props.xTickLabels[index];
    const text = tick.querySelector('text');
    if (label !== undefined && text) text.textContent = String(label);
  });
};

onMounted(applyXLabelStride);
watch(
  () => [props.collection, props.xLabelStride, props.xTickLabels],
  applyXLabelStride,
  { deep: true }
);
</script>

<template>
  <VizLineChart
    ref="chart"
    v-bind="$attrs"
    :data="chartData"
    :format-value="formatValue"
    :height="props.height"
    :point-radius="props.pointRadius"
    :show-values="props.showValues"
    :show-tooltip="props.showTooltip"
    :y-tick-count="props.yTickCount"
    :x-inset="props.xInset"
    :aria-label="props.ariaLabel"
    class="[--cw-viz-line-label-color:rgb(var(--slate-11))] [--cw-viz-line-axis-color:rgb(var(--slate-4))] [--cw-viz-line-axis-font-size:0.75rem] [--cw-viz-line-value-font-size:0.75rem] [--cw-viz-line-width:0.0625rem] [--cw-viz-line-point-border-width:0.25rem] [--cw-viz-line-tooltip-background:rgb(var(--solid-2))] [--cw-viz-line-tooltip-color:rgb(var(--slate-12))] [--cw-viz-line-tooltip-border-color:rgb(var(--border-strong))]"
  />
</template>
