<script setup>
// Anúncios da Meta: as abas da página (Resultado, Seus posts #2199, Conexão…), a mesma linha para quem gerencia e
// para quem só vê (#2199: quem tem meta_ads_view vê Resultado e Seus posts, sem Conexão). A lista e os rótulos, já
// traduzidos, vêm da página.
defineProps({
  views: { type: Array, required: true },
  active: { type: String, required: true },
  labels: { type: Object, required: true },
});

const emit = defineEmits(['choose']);
</script>

<template>
  <div
    role="group"
    :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.LABEL')"
    class="flex gap-1 p-1 rounded-lg bg-n-alpha-1 w-fit"
  >
    <button
      v-for="name in views"
      :key="name"
      type="button"
      :data-view-tab="name"
      :aria-pressed="active === name"
      class="px-4 text-[13px] font-520 border-0 rounded-md min-h-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :class="
        active === name
          ? 'bg-n-solid-1 text-n-slate-12 shadow-[0_1px_2px_rgba(0,0,0,0.06)]'
          : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
      "
      @click="emit('choose', name)"
    >
      {{ labels[name] }}
    </button>
  </div>
</template>
