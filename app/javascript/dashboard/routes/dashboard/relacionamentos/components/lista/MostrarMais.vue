<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — rodapé da lista: "Mostrando 25 de 120" e, enquanto houver mais, o
// botão "Mostrar mais" (mais 25).
defineProps({
  mostradas: { type: Number, required: true },
  total: { type: Number, required: true },
  temMais: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
});
const emit = defineEmits(['mais']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col items-center gap-3">
    <p aria-live="polite" class="m-0 text-sm tabular-nums text-n-slate-11">
      {{
        t('RELACIONAMENTOS.LISTA.MOSTRAR_MAIS.CONTAGEM', { mostradas, total })
      }}
    </p>
    <Button
      v-if="temMais"
      slate
      faded
      size="lg"
      data-relacionamentos="mostrar-mais"
      :is-loading="carregando"
      :label="t('RELACIONAMENTOS.LISTA.MOSTRAR_MAIS.BOTAO')"
      @click="emit('mais')"
    />
  </div>
</template>
