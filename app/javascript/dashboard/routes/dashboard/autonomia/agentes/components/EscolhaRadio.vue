<script setup>
import { nextTick, ref } from 'vue';

// #1181 — cartões-rádio do módulo (padrão WAI-ARIA radio group): role=radio, alvo de 44 px, um só
// item no Tab (o marcado, ou o primeiro disponível) e setas que andam e marcam, pulando opção
// desabilitada. Opção desabilitada fica visível e anunciada (aria-disabled), com o motivo no texto.
// opcoes: [{ valor, titulo, texto?, desabilitada?, ambar? }]
const props = defineProps({
  rotulo: { type: String, required: true },
  opcoes: { type: Array, required: true },
  modelValue: { type: [String, Number], default: null },
});

const emit = defineEmits(['update:modelValue']);

const botoes = ref([]);

const disponiveis = () => props.opcoes.filter(opcao => !opcao.desabilitada);

const comFoco = opcao => {
  const marcada = props.opcoes.find(
    item => item.valor === props.modelValue && !item.desabilitada
  );
  return (marcada || disponiveis()[0])?.valor === opcao.valor;
};

const escolher = opcao => {
  if (opcao.desabilitada || opcao.valor === props.modelValue) return;
  emit('update:modelValue', opcao.valor);
};

const mover = async (evento, opcao, passo) => {
  evento.preventDefault();
  const lista = disponiveis();
  if (!lista.length) return;
  const atual = lista.findIndex(item => item.valor === opcao.valor);
  const proxima = lista[(atual + passo + lista.length) % lista.length];
  escolher(proxima);
  await nextTick();
  const indice = props.opcoes.indexOf(proxima);
  botoes.value[indice]?.focus();
};

const aoTeclar = (evento, opcao) => {
  if (evento.key === 'ArrowDown' || evento.key === 'ArrowRight') {
    mover(evento, opcao, 1);
  } else if (evento.key === 'ArrowUp' || evento.key === 'ArrowLeft') {
    mover(evento, opcao, -1);
  } else if (evento.key === ' ') {
    evento.preventDefault();
    escolher(opcao);
  }
};
</script>

<template>
  <div role="radiogroup" :aria-label="rotulo" class="flex flex-col gap-2">
    <button
      v-for="opcao in opcoes"
      :key="opcao.valor"
      ref="botoes"
      type="button"
      role="radio"
      :aria-checked="opcao.valor === modelValue ? 'true' : 'false'"
      :aria-disabled="opcao.desabilitada ? 'true' : undefined"
      :tabindex="comFoco(opcao) ? '0' : '-1'"
      class="flex items-start w-full gap-3 px-4 py-3 text-start transition rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
      :class="[
        opcao.valor === modelValue
          ? 'ring-2 ring-n-blue-11 bg-n-blue-2'
          : 'ring-n-slate-7 bg-n-solid-1 hover:bg-n-slate-2',
        opcao.ambar && opcao.valor !== modelValue ? 'bg-n-amber-2' : '',
        opcao.desabilitada ? 'cursor-not-allowed opacity-70' : '',
      ]"
      @click="escolher(opcao)"
      @keydown="aoTeclar($event, opcao)"
    >
      <span
        aria-hidden="true"
        class="grid mt-0.5 rounded-full place-items-center size-5 shrink-0 ring-2 ring-inset"
        :class="
          opcao.valor === modelValue ? 'ring-n-blue-11' : 'ring-n-slate-8'
        "
      >
        <span
          v-if="opcao.valor === modelValue"
          class="rounded-full size-2.5 bg-n-blue-11"
        />
      </span>
      <span class="flex flex-col gap-0.5 grow">
        <span class="text-sm font-medium text-n-slate-12">{{
          opcao.titulo
        }}</span>
        <span v-if="opcao.texto" class="text-sm text-n-slate-11">{{
          opcao.texto
        }}</span>
      </span>
    </button>
  </div>
</template>
