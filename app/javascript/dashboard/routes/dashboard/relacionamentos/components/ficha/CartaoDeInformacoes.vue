<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaSecao from './CartaoDaSecao.vue';
import ListaDeInformacoes from './ListaDeInformacoes.vue';

// #3075 — o cartão Informações da ficha. Quem pode mudar (`podeEditar`) tem
// "Alterar" no topo; quem só pode ver lê que não pode mudar nada (a ficha
// antiga dizia o mesmo, RecordReadOnly). Quem pode mudar os campos da ficha
// (`podeEscolherCampos`) tem "Escolher campos" embaixo das informações.
// #3078 — o mesmo cartão na ficha da pessoa e na da empresa (`raiz`: de onde
// vêm os nomes das linhas).
defineProps({
  linhas: { type: Array, required: true },
  redes: { type: Array, default: () => [] },
  raiz: { type: String, default: 'RELACIONAMENTOS_FICHA.INFORMACOES' },
  podeEditar: { type: Boolean, default: true },
  podeEscolherCampos: { type: Boolean, default: false },
});
const emit = defineEmits(['alterar', 'escolherCampos']);

const { t } = useI18n();
</script>

<template>
  <CartaoDaSecao
    :titulo="t('RELACIONAMENTOS_FICHA.INFORMACOES.TITULO')"
    data-relacionamentos="informacoes"
  >
    <template v-if="podeEditar" #acao>
      <Button
        data-relacionamentos="alterar"
        slate
        faded
        :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ALTERAR')"
        @click="emit('alterar')"
      />
    </template>
    <p
      v-if="!podeEditar"
      data-relacionamentos="so-leitura"
      class="flex items-start gap-2 p-3 m-0 mb-4 text-sm rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      <span
        class="mt-0.5 i-lucide-eye size-4 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t('RELACIONAMENTOS_FICHA.INFORMACOES.SO_LEITURA') }}
    </p>
    <ListaDeInformacoes :raiz="raiz" :linhas="linhas" :redes="redes" />
    <Button
      v-if="podeEditar && podeEscolherCampos"
      data-relacionamentos="escolher-campos"
      slate
      ghost
      icon="i-lucide-settings-2"
      class="!h-11 mt-4 -ms-3"
      :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ESCOLHER_CAMPOS')"
      @click="emit('escolherCampos')"
    />
  </CartaoDaSecao>
</template>
