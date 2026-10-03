<script setup>
import { ref, onMounted } from 'vue';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideExecucao from './GuideExecucao.vue';

// "Feito pelo Guia" (#855): tudo o que o Guia mudou para esta pessoa nos
// últimos 5 dias, com o desfazer de cada turno. Mora na aba "Feito pelo Guia"
// do histórico (#861), ao lado das conversas anteriores.
const execucoes = ref([]);
const carregando = ref(true);
const falhou = ref(false);

onMounted(async () => {
  try {
    const { data } = await AutonomiaGuideAPI.execucoes();
    execucoes.value = data.execucoes || [];
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-3 w-full">
    <p v-if="carregando" class="flex items-center gap-2 mb-0 text-n-slate-11">
      <span class="i-svg-spinner size-4 shrink-0" />
      {{ $t('AUTONOMIA_GUIDE.DONE.LOADING') }}
    </p>
    <p v-else-if="falhou" class="mb-0 text-n-ruby-11">
      {{ $t('AUTONOMIA_GUIDE.DONE.LOAD_FAILED') }}
    </p>
    <p v-else-if="!execucoes.length" class="mb-0 text-n-slate-11">
      {{ $t('AUTONOMIA_GUIDE.DONE.EMPTY') }}
    </p>
    <template v-else>
      <GuideExecucao
        v-for="execucao in execucoes"
        :key="execucao.id"
        :execucao="execucao"
        mostrar-data
      />
    </template>
  </div>
</template>
