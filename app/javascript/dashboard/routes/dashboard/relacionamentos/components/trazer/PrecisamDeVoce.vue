<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { SITUACAO_DO_PROBLEMA } from '../../trazer/contagem';
import ProblemaDaLinha from './ProblemaDaLinha.vue';

// #2894 — "Precisam de você (5)": as linhas da planilha que o sistema não
// conseguiu organizar sozinho, cada uma com o conserto ali mesmo.
const props = defineProps({
  problemas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'deixarDeFora']);

const { t } = useI18n();
const abertas = computed(
  () =>
    props.problemas.filter(p => p.estado === SITUACAO_DO_PROBLEMA.ABERTO).length
);
</script>

<template>
  <section
    data-relacionamentos="precisam-de-voce"
    class="flex flex-col gap-4"
    aria-live="polite"
  >
    <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
      {{
        abertas
          ? t('RELACIONAMENTOS_TRAZER.PRECISAM.TITULO', { count: abertas })
          : t('RELACIONAMENTOS_TRAZER.PRECISAM.RESOLVIDO')
      }}
    </h2>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <ProblemaDaLinha
        v-for="problema in problemas"
        :key="problema.linha"
        :problema="problema"
        :ocupado="ocupado"
        @guardar="(linha, valor) => emit('guardar', linha, valor)"
        @deixar-de-fora="linha => emit('deixarDeFora', linha)"
      />
    </ul>
  </section>
</template>
