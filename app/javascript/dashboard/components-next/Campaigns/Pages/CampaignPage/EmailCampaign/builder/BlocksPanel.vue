<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEmailEditor } from './composables/useEmailEditor';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Ícone i-lucide ESTÁTICO por bloco (decisão E12: cards Vue, não o media cru do
// GrapesJS). Chave = block.getId(); fallback genérico se um id novo aparecer.
// Os nomes i-lucide-* abaixo são LITERAIS estáticos para o extractor de ícones
// (@egoist/tailwindcss-icons) gerá-los — não montar nomes dinamicamente.
const BLOCK_ICONS = {
  'autonomia-text': 'i-lucide-align-left',
  'autonomia-heading': 'i-lucide-heading',
  'autonomia-image': 'i-lucide-image',
  'autonomia-button': 'i-lucide-mouse-pointer-click',
  'autonomia-hero': 'i-lucide-layout-template',
  'autonomia-offer': 'i-lucide-badge-percent',
  'autonomia-benefits': 'i-lucide-layout-grid',
  'autonomia-testimonial': 'i-lucide-quote',
  'autonomia-products': 'i-lucide-shopping-bag',
  'autonomia-image-text': 'i-lucide-image',
  'autonomia-video': 'i-lucide-play-circle',
  'autonomia-cta': 'i-lucide-mouse-pointer-click',
  'autonomia-faq': 'i-lucide-circle-help',
  'autonomia-divider': 'i-lucide-minus',
  'autonomia-footer': 'i-lucide-panel-bottom',
};
const DEFAULT_ICON = 'i-lucide-square';

const { t } = useI18n();
const { blocks, dragStart, dragStop } = useEmailEditor();

const iconFor = block => BLOCK_ICONS[block.getId()] || DEFAULT_ICON;

// Agrupa os blocos por categoria (block.getCategoryLabel()), preservando a
// ordem de registro dentro de cada grupo e a ordem de aparição dos grupos.
const groups = computed(() => {
  const byCategory = new Map();
  blocks.value.forEach(block => {
    const label = block.getCategoryLabel?.() || '';
    if (!byCategory.has(label)) byCategory.set(label, []);
    byCategory.get(label).push(block);
  });
  return Array.from(byCategory, ([label, items]) => ({ label, items }));
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0 overflow-y-auto">
    <div v-if="blocks.length === 0" class="px-4 py-6 text-sm text-n-slate-11">
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.BLOCKS.EMPTY') }}
    </div>

    <div
      v-for="group in groups"
      :key="group.label"
      class="flex flex-col gap-2 px-3 py-3"
    >
      <p
        class="px-1 mb-0 text-xs font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ group.label }}
      </p>
      <div class="grid grid-cols-2 gap-2">
        <div
          v-for="block in group.items"
          :key="block.getId()"
          draggable="true"
          class="flex flex-col items-center justify-center gap-2 min-h-20 px-2 py-3 text-center transition-colors border rounded-lg cursor-grab select-none border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-brand hover:text-n-slate-12 hover:bg-n-alpha-1 active:cursor-grabbing"
          @dragstart="dragStart(block, $event)"
          @dragend="dragStop()"
        >
          <Icon :icon="iconFor(block)" class="text-xl text-n-slate-11" />
          <span class="text-xs leading-4 text-n-slate-12">
            {{ block.getLabel() }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
