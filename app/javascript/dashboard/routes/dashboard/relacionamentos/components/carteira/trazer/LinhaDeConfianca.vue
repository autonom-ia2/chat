<script setup>
// #3057 — a linha de confiança das telas de trazer: um escudo e uma frase
// curta (por padrão, "Nada entra antes de você conferir"). Quem usa pode
// trocar a frase pelo slot.
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <p
    data-carteira="confianca"
    class="flex items-start gap-2 m-0 text-sm font-medium text-n-teal-11"
  >
    <span
      class="i-lucide-shield-check size-5 shrink-0 mt-px"
      aria-hidden="true"
    />
    <span>
      <slot>{{ t('RELACIONAMENTOS_CARTEIRA.CONFIANCA') }}</slot>
    </span>
  </p>
</template>
