<script setup>
// Frente de telefone: bloco de contato do painel do lead (telefone e site).
import { useI18n } from 'vue-i18n';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div class="rounded-md border border-n-weak bg-n-solid-2 p-3">
    <div class="text-xs font-medium text-n-slate-10">
      {{ t('PROSPECTING.SEARCH.CONTACT_DATA') }}
    </div>
    <div class="mt-2 text-sm text-n-slate-12">
      {{ lead.phone || '-' }}
    </div>
    <a
      v-if="lead.website"
      :href="lead.website"
      target="_blank"
      rel="noopener noreferrer"
      class="mt-1 block truncate text-sm text-n-brand underline"
    >
      {{ lead.website }}
    </a>
  </div>
</template>
