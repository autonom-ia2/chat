<script setup>
import { nextTick, ref, useTemplateRef } from 'vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

// #2283 — menu de botão ("Alterar" da linha, "Mais" da barra): role="menu",
// setas entre os itens, Home/End, Esc fecha e devolve o foco ao botão.
// itens: [{ chave, rotulo, icone?, perigo?, separar?, classe? }]
defineProps({
  rotuloDoBotao: { type: String, required: true },
  ariaLabel: { type: String, required: true },
  titulo: { type: String, default: '' },
  itens: { type: Array, required: true },
  alinhar: { type: String, default: 'end' },
  iconeDoBotao: { type: String, default: '' },
  classeDoBotao: { type: String, default: 'w-full px-3' },
});
const emit = defineEmits(['escolher']);

const aberto = ref(false);
const lista = useTemplateRef('lista');
const botao = useTemplateRef('botao');

const itensDoMenu = () => [
  ...(lista.value?.querySelectorAll('[role="menuitem"]') || []),
];
const focar = indice => {
  const todos = itensDoMenu();
  if (!todos.length) return;
  todos[(indice + todos.length) % todos.length].focus();
};
const aoAbrir = async () => {
  aberto.value = true;
  await nextTick();
  focar(0);
};
const aoFechar = () => {
  aberto.value = false;
  botao.value?.focus();
};
const teclas = event => {
  const todos = itensDoMenu();
  const atual = todos.indexOf(document.activeElement);
  const passo = { ArrowDown: 1, ArrowUp: -1 }[event.key];
  if (passo) {
    event.preventDefault();
    focar(atual + passo);
  } else if (event.key === 'Home') {
    event.preventDefault();
    focar(0);
  } else if (event.key === 'End') {
    event.preventDefault();
    focar(todos.length - 1);
  }
};
const escolher = (item, esconder) => {
  esconder();
  emit('escolher', item.chave);
};
</script>

<template>
  <Popover :align="alinhar" @show="aoAbrir" @hide="aoFechar">
    <template #default>
      <button
        ref="botao"
        type="button"
        aria-haspopup="menu"
        :aria-expanded="aberto"
        :aria-label="ariaLabel"
        :class="classeDoBotao"
        class="inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap rounded-xl border border-solid border-n-weak bg-n-solid-1 text-base font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      >
        <span
          v-if="iconeDoBotao"
          :class="iconeDoBotao"
          class="size-5 shrink-0"
          aria-hidden="true"
        />
        {{ rotuloDoBotao }}
      </button>
    </template>
    <template #content="{ hide }">
      <div
        ref="lista"
        role="menu"
        :aria-label="ariaLabel"
        class="flex min-w-60 flex-col p-2"
        @keydown="teclas"
      >
        <p v-if="titulo" class="mb-0 px-3 pb-1 pt-2 text-sm text-n-slate-11">
          {{ titulo }}
        </p>
        <template v-for="item in itens" :key="item.chave">
          <div
            v-if="item.separar"
            role="separator"
            class="my-1 border-t border-n-weak"
          />
          <button
            type="button"
            role="menuitem"
            class="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-start text-base hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 focus-visible:outline-none"
            :class="[
              item.perigo ? 'text-n-ruby-11' : 'text-n-slate-12',
              item.classe,
            ]"
            @click="escolher(item, hide)"
          >
            <span
              v-if="item.icone"
              :class="item.icone"
              class="size-5 shrink-0 text-n-slate-11"
              aria-hidden="true"
            />
            {{ item.rotulo }}
          </button>
        </template>
      </div>
    </template>
  </Popover>
</template>
