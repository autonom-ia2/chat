<script setup>
import { I18nT } from 'vue-i18n';
import FunilResumoCartao from './FunilResumoCartao.vue';

// #1384 — "Vendas e meta" em uma frase, no resumo e no Confira.
defineProps({
  venda: { type: Boolean, default: true },
  meta: { type: [String, Number], default: '' },
  dinheiro: { type: Function, required: true },
});

defineEmits(['alterar']);
</script>

<template>
  <FunilResumoCartao
    parte="sales"
    icone="i-lucide-target"
    tom="bg-n-teal-3 text-n-teal-11"
    :titulo="$t('CRM_FUNIL.VENDAS.ROTULO')"
    @alterar="$emit('alterar')"
  >
    <template v-if="venda">
      {{ $t('CRM_FUNIL.RESUMO.VENDA') }}
      <I18nT
        v-if="Number(meta) > 0"
        keypath="CRM_FUNIL.RESUMO.META"
        tag="span"
        scope="global"
      >
        <template #valor>
          <strong class="font-semibold">{{ dinheiro(meta) }}</strong>
        </template>
      </I18nT>
      <template v-else>{{ $t('CRM_FUNIL.RESUMO.SEM_META') }}</template>
    </template>
    <template v-else>{{ $t('CRM_FUNIL.RESUMO.NAO_VENDA') }}</template>
  </FunilResumoCartao>
</template>
