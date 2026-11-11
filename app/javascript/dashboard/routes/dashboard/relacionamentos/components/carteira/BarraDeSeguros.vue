<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2897 — a barra que aparece embaixo ao marcar seguros: "3 marcados", a ação
// principal (Mandar mensagem) e o X que desmarca. A mensagem vai por pessoa:
// quem tem dois seguros marcados recebe uma só.
defineProps({
  quantos: { type: Number, required: true },
});
const emit = defineEmits(['mandarMensagem', 'fechar']);

const { t } = useI18n();
const tc = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores, plural);
</script>

<template>
  <div
    data-carteira="barra"
    role="region"
    :aria-label="tc('BARRA')"
    class="flex flex-wrap items-center gap-2 p-3 shadow-xl rounded-2xl bg-n-solid-1 ring-1 ring-n-weak sm:gap-3 sm:px-4"
  >
    <p
      aria-live="polite"
      class="flex-1 m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:flex-none sm:me-1"
    >
      {{ tc('MARCADOS', { count: quantos }, quantos) }}
    </p>
    <Button
      ghost
      slate
      size="lg"
      class="sm:order-3 sm:ms-auto"
      icon="i-lucide-x"
      :aria-label="tc('DESMARCAR')"
      @click="emit('fechar')"
    />
    <Button
      size="lg"
      class="w-full whitespace-nowrap sm:order-2 sm:w-auto"
      icon="i-lucide-send"
      data-carteira="mandar-mensagem"
      :label="tc('MANDAR_MENSAGEM')"
      @click="emit('mandarMensagem')"
    />
  </div>
</template>
