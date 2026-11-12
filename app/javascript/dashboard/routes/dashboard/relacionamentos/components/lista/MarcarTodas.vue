<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — "Marcar todas as 42 deste grupo", acima da lista, quando há marcadas
// e ainda faltam pessoas do grupo.
defineProps({
  total: { type: Number, required: true },
  carregando: { type: Boolean, default: false },
});
const emit = defineEmits(['marcarTodas']);

const { t } = useI18n();
</script>

<template>
  <div>
    <Button
      link
      :is-loading="carregando"
      :label="
        t('RELACIONAMENTOS.LISTA.MARCADAS.MARCAR_TODAS', { count: total })
      "
      @click="emit('marcarTodas')"
    />
  </div>
</template>
