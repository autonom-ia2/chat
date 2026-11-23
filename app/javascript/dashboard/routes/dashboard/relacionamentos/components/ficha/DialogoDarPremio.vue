<script setup>
import { computed, ref } from 'vue';
import DialogoDaFicha from './DialogoDaFicha.vue';
import {
  F,
  useTextosDaFidelidade,
} from 'dashboard/routes/dashboard/fidelidade/useTextosDaFidelidade';
import { progresso } from 'dashboard/routes/dashboard/fidelidade/regras';

// #3100 — confirmar o prêmio antes de tirar os carimbos: "Dar o prêmio para
// Maria?". Diz qual é o prêmio, quantos saem e, se ela tinha mais que a meta,
// quantos ficam para o próximo cartão. Fica anotado quem deu (o servidor grava
// o atendente). `confirmar` vai para quem usa, que chama o servidor.
const props = defineProps({
  programa: { type: Object, required: true },
  tem: { type: Number, required: true },
  nome: { type: String, required: true },
  carregando: { type: Boolean, default: false },
});
const emit = defineEmits(['confirmar']);

const { t, unidade } = useTextosDaFidelidade();
const D = `${F}.DAR_PREMIO`;

const conta = computed(() => progresso(props.tem, props.programa.meta));
const texto = computed(() => {
  const saem = t(`${D}.TEXTO`, {
    premio: props.programa.premio,
    quantos: unidade(props.programa.meta, props.programa.tipo),
  });
  if (!conta.value.sobra) return saem;
  return `${saem} ${t(`${D}.SOBRA`, {
    quantos: unidade(conta.value.sobra, props.programa.tipo),
  })}`;
});

const dialogo = ref(null);
defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <DialogoDaFicha
    ref="dialogo"
    :titulo="t(`${D}.TITULO`, { nome })"
    :texto="texto"
    :confirmar="t(`${D}.CONFIRMAR`)"
    :cancelar="t(`${D}.CANCELAR`)"
    marca-confirmar="confirmar-premio"
    :carregando="carregando"
    @confirm="emit('confirmar')"
  />
</template>
