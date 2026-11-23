<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { VISOES } from '../../fonte/gruposDeCompra';
import ChaveDeOpcoes from '../comum/ChaveDeOpcoes.vue';

// #3097 — "Ver os grupos por: Conversa | Compra", acima das pílulas da aba
// Pessoas. Duas opções num grupo de rádio (setas trocam, como o padrão do
// WAI-ARIA), cada uma com 44 px de alvo. A escolhida fica branca, na cor da
// marca: é a porta de entrada dos grupos por compra e precisa ser vista.
// #3168 — com `comMeusGrupos`, uma terceira opção: "Meus grupos" (os grupos
// que a pessoa guardou). O desenho do rádio foi para ChaveDeOpcoes.
const props = defineProps({
  modelValue: { type: String, required: true },
  comMeusGrupos: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const opcoes = computed(() => [
  {
    value: VISOES.CONVERSA,
    label: t('RELACIONAMENTOS_COMPRAS.LISTA.CONVERSA'),
  },
  { value: VISOES.COMPRA, label: t('RELACIONAMENTOS_COMPRAS.LISTA.COMPRA') },
  ...(props.comMeusGrupos
    ? [
        {
          value: VISOES.MEUS,
          label: t('RELACIONAMENTOS.LISTA.MEUS_GRUPOS.CHAVE'),
        },
      ]
    : []),
]);
</script>

<template>
  <ChaveDeOpcoes
    :model-value="modelValue"
    :opcoes="opcoes"
    :rotulo="t('RELACIONAMENTOS_COMPRAS.LISTA.VISAO')"
    marca="chave-dos-grupos"
    @update:model-value="emit('update:modelValue', $event)"
  />
</template>
