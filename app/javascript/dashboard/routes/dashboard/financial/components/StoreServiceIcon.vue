<script setup>
import { computed, ref, watch } from 'vue';

const props = defineProps({
  item: { type: Object, required: true },
});
const failed = ref(false);
const logoUrl = computed(() => props.item.service.logoUrl);
watch(logoUrl, () => {
  failed.value = false;
});
</script>

<template>
  <div
    class="flex items-center justify-center flex-shrink-0 w-12 h-12 rounded-md bg-n-alpha-2 text-n-slate-11"
  >
    <img
      v-if="logoUrl && !failed"
      :src="logoUrl"
      alt=""
      referrerpolicy="no-referrer"
      class="object-contain w-10 h-10"
      loading="lazy"
      @error="failed = true"
    />
    <span
      v-else
      :class="item.group === 'agent' ? 'i-lucide-bot' : 'i-lucide-blocks'"
      class="w-6 h-6"
      aria-hidden="true"
    />
  </div>
</template>
