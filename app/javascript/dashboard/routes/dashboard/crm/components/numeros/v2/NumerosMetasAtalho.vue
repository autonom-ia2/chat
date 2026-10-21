<script setup>
import { computed, nextTick, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import NumerosMetasGaveta from './NumerosMetasGaveta.vue';
import { P, nomeDoMes } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';
import { usePodeDefinirMetas } from './usePodeDefinirMetas';

// "Metas de outubro" na visão Equipe (#1991): o caminho para a gaveta de quem
// define as metas, enquanto a Equipe ainda é o painel de hoje (F5 do #1871).
// A gaveta só monta no primeiro clique: nada é pedido antes.
const { t, locale } = useNumerosFormato();
const { currentAccount } = useAccount();
const podeDefinirMetas = usePodeDefinirMetas();
const gaveta = ref(null);
const montada = ref(false);
const abrir = async () => {
  montada.value = true;
  await nextTick();
  gaveta.value?.abrir();
};

const mesNome = computed(() => {
  const fuso = fusoDaConta(currentAccount.value);
  const partes = new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    ...(fuso ? { timeZone: fuso } : {}),
  }).formatToParts(new Date());
  const valor = tipo => partes.find(parte => parte.type === tipo)?.value;
  return nomeDoMes(`${valor('year')}-${valor('month')}`, {
    locale: locale(),
    fuso,
  });
});
</script>

<template>
  <template v-if="podeDefinirMetas">
    <button
      type="button"
      data-numeros-metas-atalho
      class="inline-flex min-h-11 w-fit items-center gap-1.5 rounded-xl px-3 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="abrir"
    >
      <span class="i-lucide-target size-4" aria-hidden="true" />
      {{ t(`${P}.TOPO.METAS_LINK`, { mes: mesNome }) }}
    </button>
    <NumerosMetasGaveta v-if="montada" ref="gaveta" />
  </template>
</template>
