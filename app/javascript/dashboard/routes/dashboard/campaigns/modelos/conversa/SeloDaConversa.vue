<script setup>
// O selo do modelo de produto ou de carrossel na escolha de modelo da conversa
// (#1716): diz que o próximo passo é escolher produtos ou montar cartões.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { tipoNaConversa } from './modeloNaConversa';

const props = defineProps({
  template: { type: Object, required: true },
});

const { t } = useI18n();
const ICONES = {
  um: 'i-lucide-shopping-bag',
  varios: 'i-lucide-list',
  carrossel: 'i-lucide-gallery-horizontal',
  cartoes: 'i-lucide-gallery-horizontal',
};
const tipo = computed(() => tipoNaConversa(props.template));
</script>

<template>
  <span class="contents">
    <span
      v-if="tipo"
      class="inline-flex items-center gap-1 px-2 py-1 text-xs leading-none rounded-lg bg-n-teal-3 text-n-teal-11"
      :data-selo-do-modelo="tipo"
    >
      <span :class="ICONES[tipo]" class="size-3.5" aria-hidden="true" />
      {{ t(`MODELOS_WHATSAPP.CONVERSA.SELO.${tipo}`) }}
    </span>
  </span>
</template>
