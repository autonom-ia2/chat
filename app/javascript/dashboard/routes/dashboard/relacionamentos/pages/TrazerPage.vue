<script setup>
import { computed, ref, shallowRef } from 'vue';
import { useRoute } from 'vue-router';
import { usarDemo } from '../fonte/modoDemo';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import TrazerListaPage from './TrazerListaPage.vue';

// #2897 — a porta de "Trazer minha lista". Na conta sem a carteira de seguros
// ela é só a tela das listas (pages/TrazerListaPage.vue), na hora. Na conta que
// tem a carteira, baixa antes o que os seguros pedem
// (carteira/trazerComSeguros.js) e entrega à mesma tela: o código dos seguros
// não vai no pacote de quem não tem a carteira. Se não deu para baixar (a rede
// caiu, o painel foi atualizado), a pessoa vê o erro com "Tentar de novo" em
// vez de uma tela em branco.
//
// #2899 (E6.4) — na conta que lê PDF, a porta pergunta antes como trazer
// (`?como=planilha` ou `?como=pdfs`). Quem já está numa lista (`?leitura=`)
// segue nela. Sem a leitura, nada muda: só a tela das listas.
const props = defineProps({
  // De onde vem o que os seguros pedem. A rota não passa nada: vale o import.
  baixarSeguros: {
    type: Function,
    default: () => import('../carteira/trazerComSeguros.js'),
  },
});

const route = useRoute();
const demo = usarDemo(route.query);
const contaDeSeguros = useContaDeSeguros(demo).value;

const seguros = shallowRef(null);
const naoBaixou = ref(false);
const lePdf = ref(false);

const baixar = async () => {
  naoBaixou.value = false;
  try {
    const baixado = await props.baixarSeguros();
    lePdf.value = (await baixado.leituraDePdf?.({ demo })) === true;
    seguros.value = baixado;
  } catch {
    naoBaixou.value = true;
  }
};

const QUERY_DA_LISTA = ['leitura', 'planilha'];
const como = computed(() => {
  if (!lePdf.value) return 'planilha';
  if (route.query.como) return route.query.como;
  return QUERY_DA_LISTA.some(chave => route.query[chave]) ? 'planilha' : '';
});
const rotasDoComo = computed(() => ({
  planilha: { query: { ...route.query, como: 'planilha' } },
  pdfs: { query: { ...route.query, como: 'pdfs' } },
}));

if (contaDeSeguros) baixar();
</script>

<template>
  <TrazerListaPage v-if="!contaDeSeguros" />
  <template v-else-if="seguros">
    <component
      :is="seguros.ComoTrazer"
      v-if="como === ''"
      :rotas="rotasDoComo"
    />
    <component :is="seguros.TrazerPdfs" v-else-if="como === 'pdfs'" />
    <TrazerListaPage v-else :seguros="seguros" />
  </template>
  <section
    v-else
    data-relacionamentos="trazer"
    class="flex flex-col w-full h-full bg-n-surface-1"
    :aria-busy="!naoBaixou"
  >
    <div
      v-if="naoBaixou"
      data-carteira="nao-baixou"
      class="w-full max-w-3xl px-5 pt-8 mx-auto md:px-8 md:pt-10"
    >
      <ErroComTentarDeNovo @tentar="baixar" />
    </div>
  </section>
</template>
