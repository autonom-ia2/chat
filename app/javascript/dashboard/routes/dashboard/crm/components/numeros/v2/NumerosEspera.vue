<script setup>
import { useI18n } from 'vue-i18n';
import { P } from './numerosTextos';

// Carregando ou erro de CRM › Números (#1897), com "Tentar de novo".
defineProps({
  falhou: { type: Boolean, default: false },
});
const emit = defineEmits(['tentar']);
const { t } = useI18n();
</script>

<template>
  <div
    v-if="falhou"
    role="alert"
    data-numeros-erro
    class="flex flex-col items-start gap-4 rounded-2xl bg-n-ruby-2 p-6 ring-1 ring-inset ring-n-ruby-6"
  >
    <p class="m-0 text-base text-n-ruby-12">{{ t(`${P}.ERRO.TEXTO`) }}</p>
    <button
      type="button"
      data-numeros-tentar
      class="inline-flex min-h-11 items-center rounded-xl bg-n-ruby-9 px-5 text-base font-semibold text-white hover:bg-n-ruby-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('tentar')"
    >
      {{ t(`${P}.ERRO.ACAO`) }}
    </button>
  </div>
  <div
    v-else
    aria-busy="true"
    data-numeros-carregando
    class="flex flex-col gap-3"
  >
    <span class="sr-only">{{ t(`${P}.CARREGANDO`) }}</span>
    <div class="h-48 animate-pulse rounded-2xl bg-n-alpha-2" />
    <div class="h-24 animate-pulse rounded-2xl bg-n-alpha-2" />
  </div>
</template>
