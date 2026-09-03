<script setup>
import { computed } from 'vue';
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
      pointBorderColor: 'rgb(var(--card-color))',
      valueColor: dataset.borderColor || dataset.backgroundColor,
      data: [...(dataset.data || [])],
    })),
  };
});

const formatValue = value => Number(value).toLocaleString();
</script>

<template>
  <VizLineChart
    v-bind="$attrs"
    :data="chartData"
    :format-value="formatValue"
    :height="props.height"
    :point-radius="3"
    :aria-label="props.ariaLabel"
    class="[--cw-viz-line-label-color:rgb(var(--slate-11))] [--cw-viz-line-axis-color:rgb(var(--slate-4))] [--cw-viz-line-axis-font-size:0.75rem] [--cw-viz-line-value-font-size:0.75rem] [--cw-viz-line-width:0.0625rem] [--cw-viz-line-point-border-width:0.25rem] [--cw-viz-line-tooltip-background:rgb(var(--solid-2))] [--cw-viz-line-tooltip-color:rgb(var(--slate-12))] [--cw-viz-line-tooltip-border-color:rgb(var(--border-strong))]"
  />
</template>
