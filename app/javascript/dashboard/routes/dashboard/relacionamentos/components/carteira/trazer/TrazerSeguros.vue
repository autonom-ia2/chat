<script setup>
import { computed, onMounted, ref } from 'vue';
import { PERGUNTA_SEGUROS } from '../../../carteira/segurosDaPlanilha';
import { PASSOS } from '../../../carteira/useTrazerSeguros';
import { ERROS } from '../../../trazer/falhasDaTela';
import ComoTrazer from './ComoTrazer.vue';
import ConferirSeguros from './ConferirSeguros.vue';
import PerguntaDeSeguros from './PerguntaDeSeguros.vue';
import ProntoDeSeguros from './ProntoDeSeguros.vue';

// #2897 — as telas que "Trazer minha lista" ganha na conta que tem a carteira
// de seguros. A página (pages/TrazerListaPage.vue) só baixa esta peça nessa
// conta, e só a mostra nos momentos em que a tela é a da carteira
// (carteira/useTrazerSeguros.js, `passo`): escolher como trazer, a pergunta
// "Esta planilha tem seguros?", o Conferir com seguros e o fim.
// `tela` é o estado de "Trazer minha lista" (trazer/useTrazerLista.js) e
// `carteira`, o que a carteira pede a mais: os dois chegam inteiros, como a
// página os tem.
const props = defineProps({
  tela: { type: Object, required: true },
  carteira: { type: Object, required: true },
});
const emit = defineEmits(['ver', 'outra']);

const raiz = ref(null);
const passo = computed(() => props.carteira.passo.value);

// A página leva o foco ao título de cada tela nova, mas esta peça chega depois
// (ela é baixada à parte): na primeira vez o foco é por conta dela. A escolha
// de como trazer é a tela em que a pessoa entra: ali o foco fica onde está.
onMounted(() => {
  if (passo.value === PASSOS.COMO) return;
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
});
</script>

<template>
  <div ref="raiz" data-carteira="trazer-seguros-tela" :data-passo="passo">
    <ComoTrazer
      v-if="passo === PASSOS.COMO"
      @planilha="carteira.escolherPlanilha"
    />
    <PerguntaDeSeguros
      v-else-if="passo === PASSOS.PERGUNTA"
      :resposta="tela.respostas.value[PERGUNTA_SEGUROS] ?? ''"
      :ocupado="tela.ocupado.value"
      :relendo="tela.relendo.value"
      :recusa="tela.recusaDaPergunta.value"
      @responder="carteira.responder"
      @voltar="tela.voltar"
    />
    <ConferirSeguros
      v-else-if="passo === PASSOS.CONFERIR"
      :leitura="tela.leitura.value"
      :ocupado="tela.ocupado.value"
      :relendo="tela.relendo.value"
      :com-erro="tela.erro.value === ERROS.TRAZER"
      :recusa-do-conserto="tela.recusaDoConserto.value"
      :recusa-da-coluna="tela.recusaDaColuna.value"
      :recusa-do-trazer="tela.erro.value"
      :faltam-carregar="tela.faltamCarregar.value"
      :carregando-mais="tela.carregandoMais.value"
      :erro-do-mais="tela.erroDoMais.value"
      :faltam="carteira.faltam.value"
      :pedidos="carteira.pedidosComFalta.value"
      @guardar="tela.guardar"
      @deixar-de-fora="tela.deixarDeFora"
      @reabrir="tela.reabrir"
      @trocar="tela.trocarDestino"
      @mostrar-mais="tela.mostrarMais"
      @trazer="carteira.trazer"
      @escolher-outra="emit('outra')"
      @voltar="tela.voltar"
      @tentar="tela.tentarDeNovo"
    />
    <ProntoDeSeguros
      v-else-if="passo === PASSOS.PRONTO"
      :chegaram="carteira.chegaram.value"
      @ver="emit('ver')"
      @outra="emit('outra')"
    />
  </div>
</template>
