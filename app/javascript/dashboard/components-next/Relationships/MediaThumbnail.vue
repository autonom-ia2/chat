<script setup>
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { useIntersectionObserver } from '@vueuse/core';
import axios from 'dashboard/api/relationships';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  url: { type: String, required: true },
  name: { type: String, required: true },
  type: { type: String, default: 'file' },
});
const POLL_INTERVAL = 5000;
const MAX_POLLS = 132; // Eleven minutes: demand TTL plus one bounded conversion.
const target = ref(null);
const visible = ref(false);
const image = ref('');
const retryable = ref(false);
const icon = computed(
  () =>
    ({
      image: 'i-lucide-image',
      video: 'i-lucide-video',
      audio: 'i-lucide-music',
    })[props.type] || 'i-lucide-file'
);
let generation = 0;
let timer;
const release = () => {
  clearTimeout(timer);
  if (image.value) URL.revokeObjectURL(image.value);
  image.value = '';
};
const load = async () => {
  generation += 1;
  const current = generation;
  const url = props.url;
  clearTimeout(timer);
  retryable.value = false;
  const request = async attempt => {
    try {
      const response = await axios.get(url, { responseType: 'blob' });
      if (current !== generation || url !== props.url) return;
      if (response.status === 202 && attempt < MAX_POLLS) {
        timer = setTimeout(() => request(attempt + 1), POLL_INTERVAL);
        return;
      }
      if (response.data.type === 'image/jpeg')
        image.value = URL.createObjectURL(response.data);
      else retryable.value = true;
    } catch {
      if (current === generation) retryable.value = true;
    }
  };
  await request(0);
};
useIntersectionObserver(target, ([entry]) => {
  visible.value = entry.isIntersecting;
});
watch([() => props.url, visible], ([url, isVisible], previous) => {
  generation += 1;
  clearTimeout(timer);
  if (previous?.[0] !== url) release();
  if (isVisible && !image.value) load();
});
onBeforeUnmount(() => {
  generation += 1;
  release();
});
</script>

<template>
  <div
    ref="target"
    class="size-12 shrink-0 relative flex items-center justify-center"
  >
    <img
      v-if="image"
      :src="image"
      :alt="name"
      class="size-12 rounded object-cover"
    />
    <span
      v-else
      :class="icon"
      class="size-8 text-n-slate-10"
      role="img"
      :aria-label="name"
    />
    <Button
      v-if="retryable"
      xs
      ghost
      icon="i-lucide-refresh-cw"
      class="absolute end-0 bottom-0"
      :aria-label="$t('RELATIONSHIPS.RETRY')"
      @click="load"
    />
  </div>
</template>
