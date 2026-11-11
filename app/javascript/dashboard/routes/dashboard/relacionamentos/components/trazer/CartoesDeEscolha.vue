<script setup>
import { computed, ref } from 'vue';

// #2894 — escolha única por cartões grandes, no padrão WAI-ARIA de radiogroup:
// uma parada no Tab, setas movem e escolhem, Espaço/Enter escolhem. O texto de
// cada cartão vem de quem usa.
//   opcoes: [{ id, rotulo }]    v-model: o id escolhido ('' = nenhum)
// #2897 — a opção pode trazer uma linha de apoio (`descricao`) e atributos
// próprios do cartão (`atributos`, por exemplo a marca de quem usa).
const props = defineProps({
  opcoes: { type: Array, required: true },
  modelValue: { type: String, default: '' },
  rotuloId: { type: String, required: true },
  // Faltou escolher: o grupo fica marcado como inválido e aponta para o aviso.
  invalido: { type: Boolean, default: false },
  descritoPor: { type: String, default: undefined },
});
const emit = defineEmits(['update:modelValue']);

const botoes = ref([]);

// Sem escolha, o Tab cai no primeiro cartão; com escolha, no escolhido.
const comTab = computed(() => {
  const escolhido = props.opcoes.findIndex(o => o.id === props.modelValue);
  return escolhido === -1 ? 0 : escolhido;
});

const ir = indice => {
  const total = props.opcoes.length;
  const alvo = (indice + total) % total;
  emit('update:modelValue', props.opcoes[alvo].id);
  botoes.value[alvo]?.focus();
};

const SETAS = {
  ArrowRight: 1,
  ArrowDown: 1,
  ArrowLeft: -1,
  ArrowUp: -1,
};

const aoTecla = (evento, indice) => {
  if (evento.key === 'Home') ir(0);
  else if (evento.key === 'End') ir(props.opcoes.length - 1);
  else if (SETAS[evento.key]) ir(indice + SETAS[evento.key]);
  else return;
  evento.preventDefault();
};
</script>

<template>
  <div
    role="radiogroup"
    :aria-labelledby="rotuloId"
    :aria-invalid="invalido ? 'true' : undefined"
    :aria-describedby="descritoPor"
    class="grid gap-3 sm:grid-cols-3"
  >
    <button
      v-for="(opcao, indice) in opcoes"
      :key="opcao.id"
      :ref="el => (botoes[indice] = el)"
      type="button"
      role="radio"
      data-relacionamentos="resposta"
      :data-resposta="opcao.id"
      v-bind="opcao.atributos"
      :aria-checked="modelValue === opcao.id ? 'true' : 'false'"
      :tabindex="indice === comTab ? 0 : -1"
      class="flex items-center justify-between gap-3 px-5 py-4 text-lg font-semibold text-start transition-colors min-h-16 rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :class="
        modelValue === opcao.id
          ? 'bg-n-blue-3 text-n-slate-12 ring-2 ring-inset ring-n-blue-9'
          : 'bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1'
      "
      @click="emit('update:modelValue', opcao.id)"
      @keydown="aoTecla($event, indice)"
    >
      <span v-if="opcao.descricao" class="flex flex-col gap-1">
        {{ opcao.rotulo }}
        <span class="text-base font-normal text-n-slate-11">
          {{ opcao.descricao }}
        </span>
      </span>
      <template v-else>{{ opcao.rotulo }}</template>
      <span
        v-if="modelValue === opcao.id"
        class="i-lucide-check size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
    </button>
  </div>
</template>
