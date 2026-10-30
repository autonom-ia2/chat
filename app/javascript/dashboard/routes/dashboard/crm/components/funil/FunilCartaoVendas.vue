<script setup>
import { I18nT } from 'vue-i18n';
import FunilResumoCartao from './FunilResumoCartao.vue';
import { useCrmPermissions } from '../../composables/useCrmPermissions';

// #1384 — "Vendas e meta" em uma frase, no resumo e no Confira.
// #1498 — virou "Para que serve", sempre no topo: Vender ou Atender, para a
// pessoa achar onde troca o tipo. Vender fala da meta; Atender, de como cada
// pedido termina. "Alterar" abre a mesma pergunta da criação.
defineProps({
  venda: { type: Boolean, default: true },
  meta: { type: [String, Number], default: '' },
  dinheiro: { type: Function, required: true },
  sucesso: { type: String, default: '' },
  fracasso: { type: String, default: '' },
});

defineEmits(['alterar']);
// #2075 — sem a chave de valores a meta não vem do servidor: o cartão não fala dela (nem "sem meta").
const { canSeeSalesValues } = useCrmPermissions();
</script>

<template>
  <FunilResumoCartao
    parte="sales"
    :icone="venda ? 'i-lucide-badge-dollar-sign' : 'i-lucide-life-buoy'"
    :tom="venda ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-blue-3 text-n-blue-11'"
    :titulo="$t('CRM_FUNIL.TIPO.ROTULO')"
    @alterar="$emit('alterar')"
  >
    <template v-if="venda">
      <I18nT keypath="CRM_FUNIL.RESUMO.TIPO_VENDER" tag="span" scope="global">
        <template #tipo>
          <strong class="font-semibold">
            {{ $t('CRM_FUNIL.TIPO.VENDER.NOME') }}
          </strong>
        </template>
      </I18nT>
      <template v-if="canSeeSalesValues">
        {{ ' ' }}
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
    </template>
    <I18nT
      v-else
      keypath="CRM_FUNIL.RESUMO.TIPO_ATENDER"
      tag="span"
      scope="global"
    >
      <template #tipo>
        <strong class="font-semibold">
          {{ $t('CRM_FUNIL.TIPO.ATENDER.NOME') }}
        </strong>
      </template>
      <template #sucesso>
        <strong class="font-semibold">{{ sucesso }}</strong>
      </template>
      <template #fracasso>
        <strong class="font-semibold">{{ fracasso }}</strong>
      </template>
    </I18nT>
  </FunilResumoCartao>
</template>
