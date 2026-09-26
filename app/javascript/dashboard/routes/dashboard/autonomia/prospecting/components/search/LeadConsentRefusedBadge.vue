<script setup>
// Selo "Não quer ser contatado" (chat#713), no card e no painel. Vale com
// qualquer status, inclusive no lead descartado: a recusa é da pessoa.
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <span
    data-test="lead-consent-refused"
    class="inline-flex items-center gap-1 rounded-full bg-n-amber-3 px-2 py-0.5 text-[11px] font-semibold text-n-amber-11 ring-1 ring-n-amber-5"
  >
    <span class="i-lucide-bell-off size-3" aria-hidden="true" />
    {{ t('PROSPECTING.CONSENT_REFUSAL.BADGE') }}
  </span>
</template>
