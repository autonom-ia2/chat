<script setup>
// #2138 — o que uma parte do painel mostra enquanto carrega (1 ou 2 linhas de
// esqueleto) e quando o pedido falha (uma frase e "Tentar de novo").
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { ESTADO } from './useParteDoPainel';

defineProps({
  estado: { type: String, required: true },
  linhas: { type: Number, default: 2 },
});
defineEmits(['tentar']);

const { t } = useI18n();
const LARGURAS = ['w-4/5', 'w-3/5'];
</script>

<template>
  <div
    v-if="estado === ESTADO.CARREGANDO"
    class="flex flex-col gap-2 py-1"
    role="status"
    :aria-label="t('PAINEL_DO_CONTATO.CARREGANDO')"
    data-test-id="esqueleto"
  >
    <span
      v-for="indice in linhas"
      :key="indice"
      class="h-4 rounded bg-n-alpha-2 animate-pulse"
      :class="LARGURAS[(indice - 1) % LARGURAS.length]"
    />
  </div>
  <div
    v-else-if="estado === ESTADO.ERRO"
    class="flex flex-col items-start"
    data-test-id="erro-da-parte"
  >
    <p class="m-0 text-sm text-n-slate-12">
      {{ t('PAINEL_DO_CONTATO.ERRO') }}
    </p>
    <Button
      :label="t('PAINEL_DO_CONTATO.TENTAR_DE_NOVO')"
      variant="link"
      color="blue"
      size="sm"
      class="min-h-11"
      @click="$emit('tentar')"
    />
  </div>
</template>
