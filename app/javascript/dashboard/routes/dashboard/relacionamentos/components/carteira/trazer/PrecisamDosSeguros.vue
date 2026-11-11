<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { SITUACAO_DO_PROBLEMA } from '../../../trazer/contagem';
import ProblemaDoSeguro from './ProblemaDoSeguro.vue';

// #2897 — "Precisam de você (4)": os seguros que não deu para organizar
// sozinho, cada um com o conserto ali mesmo. Ao resolver (ou voltar atrás), o
// foco vai para o próximo em aberto (ou para o título) e a mudança é dita numa
// região viva que fica sempre na tela, fora dos formulários.
const props = defineProps({
  problemas: { type: Array, required: true },
  seguradoras: { type: Array, default: () => [] },
  ocupado: { type: Boolean, default: false },
  // A marca de quem usa (os PDFs têm a sua).
  marca: { type: String, default: undefined },
});
const emit = defineEmits(['guardar', 'deixarDeFora', 'reabrir']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.TRAZER.PRECISAM.${chave}`, valores);
const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const ANUNCIOS = {
  [GUARDADO]: 'ANUNCIO.PRONTO',
  [DEIXADO]: 'ANUNCIO.DEIXADO',
  [ABERTO]: 'ANUNCIO.REABERTO',
};

const raiz = ref(null);
const titulo = ref(null);
const anuncio = ref('');

const abertos = computed(
  () => props.problemas.filter(p => p.estado === ABERTO).length
);

const queMudou = (antes, depois) => {
  const anterior = new Map(antes.map(p => [p.linha, p.estado]));
  return depois.find(p => anterior.get(p.linha) !== p.estado);
};

const primeiroCampoDe = linha => {
  const item = raiz.value?.querySelector(`[data-linha="${linha}"]`);
  return item?.querySelector('input, form button:not([disabled])');
};

// Reabriu: o foco vai para o próprio. Resolveu: para o próximo em aberto
// depois dele (ou o primeiro em aberto); sem nenhum, para o título.
const levarOFoco = (lista, mudado) => {
  const posicao = lista.indexOf(mudado);
  const emAberto = lista.filter(p => p.estado === ABERTO);
  const proximo =
    lista.slice(posicao + 1).find(p => p.estado === ABERTO) ?? emAberto[0];
  const alvo = mudado.estado === ABERTO ? mudado : proximo;
  (alvo ? primeiroCampoDe(alvo.linha) : titulo.value)?.focus();
};

watch(
  () => props.problemas,
  async (depois, antes) => {
    const mudado = queMudou(antes, depois);
    if (!mudado) return;
    anuncio.value = tp(ANUNCIOS[mudado.estado], {
      quem: mudado.nome || mudado.arquivo,
    });
    await nextTick();
    levarOFoco(depois, mudado);
  }
);
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="precisam-de-voce"
    :data-carteira="marca"
    class="flex flex-col gap-4"
  >
    <h2
      ref="titulo"
      data-relacionamentos="precisam-titulo"
      tabindex="-1"
      class="m-0 text-2xl font-semibold tracking-tight outline-none text-n-slate-12"
    >
      {{ abertos ? tp('TITULO', { count: abertos }) : tp('RESOLVIDO') }}
    </h2>
    <p class="m-0 -mt-2 text-base text-n-slate-11">{{ tp('APOIO') }}</p>
    <p data-carteira="anuncio-precisam" role="status" class="sr-only">
      {{ anuncio }}
    </p>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <ProblemaDoSeguro
        v-for="problema in problemas"
        :key="problema.linha"
        :problema="problema"
        :seguradoras="seguradoras"
        :ocupado="ocupado"
        @guardar="(linha, valor) => emit('guardar', linha, valor)"
        @deixar-de-fora="linha => emit('deixarDeFora', linha)"
        @reabrir="linha => emit('reabrir', linha)"
      />
    </ul>
  </section>
</template>
