<script setup>
// One e-mail shown at its real width (600 px on a computer, 375 px on a phone) and scaled down to
// the width of its box. The HTML runs in an iframe with sandbox="": no script, no form, no way out.
// Exception to "Tailwind only": the scale and the height follow the measured width of the box, a
// value no utility class can hold, so they go in :style (the only inline style of this screen).
import { computed, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';

const props = defineProps({
  html: { type: String, default: '' },
  title: { type: String, required: true },
  device: { type: String, default: 'desktop' },
  height: { type: Number, default: 2400 },
});

const WIDTHS = { desktop: 600, mobile: 375 };
const box = useTemplateRef('box');
const { width } = useElementSize(box);

const frameWidth = computed(() => WIDTHS[props.device] || WIDTHS.desktop);
const scale = computed(() =>
  width.value ? Math.min(1, width.value / frameWidth.value) : 1
);
const outerStyle = computed(() => ({
  height: `${props.height * scale.value}px`,
}));
const frameStyle = computed(() => ({
  width: `${frameWidth.value}px`,
  height: `${props.height}px`,
  left: '50%',
  transform: `translateX(-50%) scale(${scale.value})`,
}));
</script>

<template>
  <div ref="box" class="relative w-full overflow-hidden" :style="outerStyle">
    <iframe
      :srcdoc="html"
      :title="title"
      sandbox=""
      referrerpolicy="no-referrer"
      tabindex="-1"
      class="absolute top-0 origin-top border-0 bg-white"
      :style="frameStyle"
    />
  </div>
</template>
