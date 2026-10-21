<script setup>
import { ref } from 'vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// "Como contamos" (#1871): as regras de crédito e de mês, na própria tela, com
// o exemplo do João.
const props = defineProps({
  fuso: { type: String, default: '' },
});

const { t } = useNumerosFormato();
const painel = ref(null);
defineExpose({ abrir: () => painel.value?.open() });

const REGRAS = [
  'REGRA_CREDITO',
  'REGRA_PARTICIPOU',
  'REGRA_FUNIL',
  'REGRA_SEM_RESPONSAVEL',
  'REGRA_ANTIGAS',
];
const PASSOS = ['EXEMPLO_1', 'EXEMPLO_2', 'EXEMPLO_3'];
</script>

<template>
  <SidePanel
    ref="painel"
    width="lg"
    :title="t(`${P}.COMO_CONTAMOS.TITULO`)"
    :description="t(`${P}.COMO_CONTAMOS.DESCRICAO`)"
  >
    <div data-como-contamos class="flex flex-col gap-5">
      <ul
        class="m-0 flex list-disc flex-col gap-2 ps-5 text-sm text-n-slate-12"
      >
        <li>{{ t(`${P}.COMO_CONTAMOS.REGRA_MES`, { fuso: props.fuso }) }}</li>
        <li v-for="regra in REGRAS" :key="regra">
          {{ t(`${P}.COMO_CONTAMOS.${regra}`) }}
        </li>
      </ul>
      <section
        class="flex flex-col gap-3 rounded-xl p-4 ring-1 ring-inset ring-n-weak"
      >
        <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${P}.COMO_CONTAMOS.EXEMPLO_TITULO`) }}
        </h4>
        <ol class="m-0 flex flex-col gap-2 ps-5 text-sm text-n-slate-11">
          <li v-for="passo in PASSOS" :key="passo">
            {{ t(`${P}.COMO_CONTAMOS.${passo}`) }}
          </li>
        </ol>
        <p class="mb-0 rounded-lg bg-n-teal-3 px-3 py-2 text-sm text-n-teal-11">
          {{ t(`${P}.COMO_CONTAMOS.EXEMPLO_RESULTADO`) }}
        </p>
      </section>
    </div>
  </SidePanel>
</template>
