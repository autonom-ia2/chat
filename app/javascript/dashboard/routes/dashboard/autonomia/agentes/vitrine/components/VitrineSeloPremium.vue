<script setup>
import { useI18n } from 'vue-i18n';

// #2858 F7 — o selo "Premium" dos cards pagos, no cartão e no detalhe. Cheio, em índigo: marca a categoria sem parecer
// aviso (nada de âmbar ou vermelho). Os cards grátis não têm selo.
const { t } = useI18n();
</script>

<template>
  <span
    data-vitrine-selo-premium
    class="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-semibold leading-none text-white rounded-full shadow-sm whitespace-nowrap shrink-0 bg-n-iris-9 ring-1 ring-inset ring-white/15"
  >
    <span class="i-lucide-gem size-3.5" aria-hidden="true" />
    {{ t('AGENTS.VITRINE.PREMIUM.SELO') }}
  </span>
</template>
