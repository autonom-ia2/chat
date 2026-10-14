<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CampoQuando from '../CampoQuando.vue';

// #1423 — "Deve fechar até": calendário da casa (sem o campo nativo), com os
// atalhos fim do mês, em 15 e em 30 dias. Na criação e no Negócio.
defineProps({
  somenteLeitura: { type: Boolean, default: false },
  // #1498 — "Vencimento" e "Prometeu pagar em" na Cobrança.
  rotulo: { type: String, default: '' },
});
const fecharAte = defineModel({ type: String, default: '' });
const { t } = useI18n();
const N = 'CRM_CARD.NEGOCIO';

const dois = numero => String(numero).padStart(2, '0');
const texto = data =>
  `${data.getFullYear()}-${dois(data.getMonth() + 1)}-${dois(data.getDate())}`;
const diaDaqui = dias => {
  const data = new Date();
  data.setDate(data.getDate() + dias);
  return texto(data);
};
const fimDoMes = () => {
  const data = new Date();
  return texto(new Date(data.getFullYear(), data.getMonth() + 1, 0));
};
const atalhos = computed(() => [
  { rotulo: t(`${N}.ATALHO_MES`), valor: fimDoMes() },
  { rotulo: t(`${N}.ATALHO_15`), valor: diaDaqui(15) },
  { rotulo: t(`${N}.ATALHO_30`), valor: diaDaqui(30) },
]);
</script>

<template>
  <CampoQuando
    v-model="fecharAte"
    :com-hora="false"
    :rotulo="rotulo || t(`${N}.FECHAR_ATE`)"
    :atalhos="atalhos"
    :desligado="somenteLeitura"
    limpar
  />
</template>
