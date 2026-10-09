<script setup>
import Banner from 'dashboard/components-next/banner/Banner.vue';

defineProps({
  tone: { type: String, default: 'slate' },
  role: { type: String, default: 'status' },
});
</script>

<template>
  <Banner :color="tone" :role="role" class="p-4">
    <div class="flex items-start gap-2">
      <span class="i-lucide-info size-5 shrink-0" aria-hidden="true" />
      <div><slot /></div>
    </div>
  </Banner>
</template>
