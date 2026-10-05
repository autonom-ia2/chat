<script setup>
import { useI18n } from 'vue-i18n';
import CrmPipelineDrawer from './CrmPipelineDrawer.vue';

// Review story (#1011): the funnel panel at "More settings", scrolled to the
// Meta block with the website Pixel field filled in.
useI18n().locale.value = 'pt_BR';

const pipeline = {
  id: 1,
  name: 'Funil Viagem',
  metadata: {
    meta_sync: {
      enabled: true,
      events: { won: true, lost: false, moved: true },
      pixel_id: '2164882667623689',
    },
  },
};
const stages = [
  { id: 10, name: 'Novo lead', position: 1, stage_type: 'open' },
  { id: 11, name: 'Cotação enviada', position: 2, stage_type: 'open' },
  { id: 12, name: 'Ganho', position: 3, stage_type: 'won' },
];
const shown = new WeakSet();
const showPixel = element => {
  if (!element || shown.has(element)) return;
  shown.add(element);
  setTimeout(() => {
    document.querySelector('.i-lucide-settings')?.closest('button')?.click();
    setTimeout(() => {
      document
        .getElementById('crm-pipeline-pixel-help')
        ?.closest('section')
        ?.scrollIntoView({ block: 'start' });
    }, 100);
  }, 100);
};
</script>

<!-- eslint-disable vue/no-undef-components -->
<template>
  <Story
    title="CRM/Pipeline/Drawer · website Pixel"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Meta block with Pixel">
      <div :ref="showPixel" class="h-screen bg-n-background">
        <CrmPipelineDrawer
          show
          mode="edit"
          :pipeline="pipeline"
          :stages="stages"
        />
      </div>
    </Variant>
  </Story>
</template>
