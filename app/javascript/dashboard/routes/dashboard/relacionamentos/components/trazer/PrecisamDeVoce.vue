<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { SITUACAO_DO_PROBLEMA } from '../../trazer/contagem';
import ProblemaDaLinha from './ProblemaDaLinha.vue';

// #2894 — "Precisam de você (5)": as linhas da planilha que o sistema não
// conseguiu organizar sozinho, cada uma com o conserto ali mesmo.
// Ao resolver (ou reabrir) uma linha, o formulário some ou volta: o foco vai
// para o próximo problema aberto (ou para o título) e a mudança é anunciada
// numa região viva que fica sempre no DOM, fora dos formulários.
const props = defineProps({
  problemas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();
const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const ANUNCIOS = {
  [GUARDADO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.PRONTO',
  [DEIXADO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.DEIXADA',
  [ABERTO]: 'RELACIONAMENTOS_TRAZER.PRECISAM.ANUNCIO.REABERTA',
};

const raiz = ref(null);
const titulo = ref(null);
const anuncio = ref('');

const abertas = computed(
  () => props.problemas.filter(p => p.estado === ABERTO).length
);

const linhaMudada = (antes, depois) => {
  const anterior = new Map(antes.map(p => [p.linha, p.estado]));
  return depois
    .filter(p => anterior.has(p.linha) && anterior.get(p.linha) !== p.estado)
    .at(-1);
};

const primeiroCampo = linha => {
  const item = raiz.value?.querySelector(`[data-linha="${linha}"]`);
  return (
    item?.querySelector('input') ??
    item?.querySelector('form button:not([disabled])')
  );
};

// O próximo problema aberto depois da linha mudada; se não há, o primeiro.
const proximoAberto = (lista, mudada) => {
  const posicao = lista.findIndex(p => p.linha === mudada.linha);
  const todos = lista.filter(p => p.estado === ABERTO);
  return (
    lista.slice(posicao + 1).find(p => p.estado === ABERTO) ?? todos[0] ?? null
  );
};

const levarOFoco = (lista, mudada) => {
  const alvo =
    mudada.estado === ABERTO ? mudada : (proximoAberto(lista, mudada) ?? null);
  const campo = alvo ? primeiroCampo(alvo.linha) : titulo.value;
  campo?.focus();
};

watch(
  () => props.problemas,
  async (depois, antes) => {
    const mudada = linhaMudada(antes, depois);
    if (!mudada) return;
    anuncio.value = t(ANUNCIOS[mudada.estado], { linha: mudada.linha });
    await nextTick();
    levarOFoco(depois, mudada);
  }
);
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="precisam-de-voce"
    class="flex flex-col gap-4"
  >
    <h2
      ref="titulo"
      data-relacionamentos="precisam-titulo"
      tabindex="-1"
      class="m-0 text-2xl font-semibold tracking-tight outline-none text-n-slate-12"
    >
      {{
        abertas
          ? t('RELACIONAMENTOS_TRAZER.PRECISAM.TITULO', { count: abertas })
          : t('RELACIONAMENTOS_TRAZER.PRECISAM.RESOLVIDO')
      }}
    </h2>
    <p class="m-0 -mt-2 text-base text-n-slate-11">
      {{ t('RELACIONAMENTOS_TRAZER.PRECISAM.APOIO') }}
    </p>
    <p data-relacionamentos="anuncio-precisam" role="status" class="sr-only">
      {{ anuncio }}
    </p>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <ProblemaDaLinha
        v-for="problema in problemas"
        :key="problema.linha"
        :problema="problema"
        :ocupado="ocupado"
        @guardar="(linha, valor) => emit('guardar', linha, valor)"
        @deixar-de-fora="linha => emit('deixarDeFora', linha)"
        @reabrir="linha => emit('reabrir', linha)"
      />
    </ul>
  </section>
</template>
