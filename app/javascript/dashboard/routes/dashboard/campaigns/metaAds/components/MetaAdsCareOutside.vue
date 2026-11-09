<script setup>
// Anúncio criado fora do Chat2You (#2778, opção a): duplicar e trocar a foto ficam no Gerenciador de Anúncios da Meta.
// O link abre o próprio anúncio lá, em nova aba, como o "Ver no Facebook" do post.
defineProps({
  url: { type: String, default: '' },
});
</script>

<template>
  <div data-ad-care-outside class="flex flex-col items-start gap-1">
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t('CRM_KANBAN.META_ADS_HUB.GESTAO.CARE.OUTSIDE') }}
    </p>
    <a
      v-if="url"
      :href="url"
      target="_blank"
      rel="noopener noreferrer"
      data-ad-care-outside-link
      class="inline-flex min-h-11 items-center gap-1.5 rounded-xl text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.GESTAO.CARE.OPEN_MANAGER') }}
      <span class="i-lucide-external-link size-3.5" aria-hidden="true" />
    </a>
  </div>
</template>
