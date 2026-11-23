<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #3168 — acima da lista, em "Meus grupos", quando o que está na tela já não é
// o grupo escolhido (a pessoa mexeu na busca ou nos filtros): "Guardar no
// grupo" (principal) grava a tela no grupo; "Voltar ao que era" reaplica o
// grupo como estava guardado.
defineProps({
  guardando: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'voltar']);

const { t } = useI18n();
const MG = 'RELACIONAMENTOS.LISTA.MEUS_GRUPOS';
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 rounded-xl bg-n-amber-3 ring-1 ring-inset ring-n-amber-4"
    data-relacionamentos="faixa-grupo-mudou"
  >
    <p class="m-0 text-sm font-medium text-n-amber-12">
      {{ t(`${MG}.MUDOU`) }}
    </p>
    <div class="flex flex-wrap items-center gap-2">
      <Button
        slate
        ghost
        class="min-h-11"
        data-relacionamentos="voltar-ao-grupo"
        :label="t(`${MG}.VOLTAR`)"
        @click="emit('voltar')"
      />
      <Button
        class="min-h-11"
        data-relacionamentos="guardar-da-faixa"
        :is-loading="guardando"
        :label="t(`${MG}.GUARDAR_NO_GRUPO`)"
        @click="emit('guardar')"
      />
    </div>
  </div>
</template>
