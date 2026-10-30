<script setup>
import { computed, ref } from 'vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import { useNumerosFormato } from '../useNumerosFormato';

// Números › Origens (#2001, F6) — "Como contamos" de Números › Origens: as regras desta tela. A do gasto só aparece quando a
// tela mostra gasto.
const props = defineProps({
  fuso: { type: String, default: '' },
  comGasto: { type: Boolean, default: false },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t } = useNumerosFormato();
const painel = ref(null);
defineExpose({ abrir: () => painel.value?.open() });

const regras = computed(() =>
  [
    t(`${O}.COMO_CONTAMOS.REGRA_QUEM`, { fuso: props.fuso }),
    t(`${O}.COMO_CONTAMOS.REGRA_ORIGEM`),
    t(`${O}.COMO_CONTAMOS.REGRA_VENDA`),
    t(`${O}.COMO_CONTAMOS.REGRA_DIRETO`),
    props.comGasto && t(`${O}.COMO_CONTAMOS.REGRA_GASTO`),
    props.comGasto && t(`${O}.COMO_CONTAMOS.REGRA_GASTO_TOTAL`),
  ].filter(Boolean)
);
</script>

<template>
  <SidePanel
    ref="painel"
    width="lg"
    :title="t(`${O}.COMO_CONTAMOS.TITULO`)"
    :description="t(`${O}.COMO_CONTAMOS.DESCRICAO`)"
  >
    <ul
      data-origens-como-contamos
      class="m-0 flex list-disc flex-col gap-2 ps-5 text-sm text-n-slate-12"
    >
      <li v-for="regra in regras" :key="regra">{{ regra }}</li>
    </ul>
  </SidePanel>
</template>
