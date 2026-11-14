<script setup>
import { ref, shallowRef } from 'vue';
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
const props = defineProps({
  // De onde vem o que os seguros pedem. A rota não passa nada: vale o import.
  baixarSeguros: {
    type: Function,
    default: () => import('../carteira/trazerComSeguros.js'),
  },
});

const route = useRoute();
const contaDeSeguros = useContaDeSeguros(usarDemo(route.query)).value;

const seguros = shallowRef(null);
const naoBaixou = ref(false);

const baixar = async () => {
  naoBaixou.value = false;
  try {
    seguros.value = await props.baixarSeguros();
  } catch {
    naoBaixou.value = true;
  }
};

if (contaDeSeguros) baixar();
</script>

<template>
  <TrazerListaPage v-if="!contaDeSeguros" />
  <TrazerListaPage v-else-if="seguros" :seguros="seguros" />
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
