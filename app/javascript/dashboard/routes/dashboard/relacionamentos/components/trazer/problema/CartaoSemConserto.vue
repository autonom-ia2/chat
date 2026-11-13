<script setup>
import { ref, useId } from 'vue';
import { useErroDoCartao } from '../../../trazer/useErroDoCartao';
import MolduraDoCartao from './MolduraDoCartao.vue';

// #2896, Fatia 2 — o cartão da linha que a tela não conserta: a fórmula numa
// célula que a pessoa não escreve aqui, a linha repetida sem a outra para
// comparar e toda linha quando a planilha já foi apagada do servidor. Diz o
// problema e só oferece "Deixar de fora": não há campo nem "Salvar".
const props = defineProps({
  problema: { type: Object, required: true },
  // O campo que a linha consertaria, para a frase da recusa que ela já tinha.
  campo: { type: String, default: '' },
  frases: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
});
const emit = defineEmits(['deixarDeFora']);

const moldura = ref(null);
const idDoErro = useId();
const { erro } = useErroDoCartao({
  recusa: () => props.recusa,
  campo: props.campo,
  raiz: moldura,
  ocupado: () => props.ocupado,
});
</script>

<template>
  <MolduraDoCartao
    ref="moldura"
    :linha="problema.linha"
    :frases="frases"
    :erro="erro"
    :id-do-erro="idDoErro"
    :ocupado="ocupado"
    @deixar-de-fora="linha => emit('deixarDeFora', linha)"
  />
</template>
