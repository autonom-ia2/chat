<script setup>
import { nextTick, ref, useId } from 'vue';
import { onClickOutside } from '@vueuse/core';

// #1181 — o "⋯" do cartão (Mais opções): botão de menu com o padrão WAI-ARIA menu button.
// Abre e leva o foco ao primeiro item; setas andam entre os itens; Esc e Tab fecham, e o Esc
// devolve o foco ao botão. Clique fora fecha.
defineProps({
  rotulo: { type: String, required: true },
  itens: { type: Array, required: true },
});

const emit = defineEmits(['escolher']);

const menuId = `menu-${useId()}`;
const aberto = ref(false);
const raiz = ref(null);
const botao = ref(null);
const itensRefs = ref([]);

const focarItem = indice => {
  const lista = itensRefs.value;
  if (!lista.length) return;
  const alvo = (indice + lista.length) % lista.length;
  lista[alvo]?.focus();
};

const abrir = async () => {
  aberto.value = true;
  await nextTick();
  focarItem(0);
};

const fechar = ({ devolverFoco = false } = {}) => {
  aberto.value = false;
  if (devolverFoco) botao.value?.focus();
};

const alternar = () => (aberto.value ? fechar() : abrir());

const escolher = item => {
  fechar({ devolverFoco: true });
  emit('escolher', item.chave);
};

const aoTeclar = evento => {
  const atual = itensRefs.value.indexOf(document.activeElement);
  if (evento.key === 'Escape') {
    evento.preventDefault();
    fechar({ devolverFoco: true });
  } else if (evento.key === 'ArrowDown') {
    evento.preventDefault();
    focarItem(atual + 1);
  } else if (evento.key === 'ArrowUp') {
    evento.preventDefault();
    focarItem(atual - 1);
  } else if (evento.key === 'Tab') {
    fechar();
  }
};

onClickOutside(raiz, () => {
  if (aberto.value) fechar();
});
</script>

<template>
  <div ref="raiz" class="relative">
    <button
      ref="botao"
      type="button"
      aria-haspopup="menu"
      :aria-expanded="aberto ? 'true' : 'false'"
      :aria-controls="aberto ? menuId : undefined"
      :aria-label="rotulo"
      class="grid rounded-xl place-items-center size-11 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      @click.stop="alternar"
    >
      <span class="i-lucide-ellipsis size-5" aria-hidden="true" />
    </button>
    <ul
      v-if="aberto"
      :id="menuId"
      role="menu"
      class="absolute z-30 flex flex-col p-1 m-0 list-none shadow-lg end-0 top-12 min-w-52 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
      @keydown="aoTeclar"
    >
      <li v-for="item in itens" :key="item.chave" role="none">
        <button
          ref="itensRefs"
          type="button"
          role="menuitem"
          class="flex items-center w-full gap-2 px-3 text-sm text-start rounded-lg min-h-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :class="item.perigo ? 'text-n-ruby-11' : 'text-n-slate-12'"
          @click.stop="escolher(item)"
        >
          <span
            v-if="item.perigo"
            class="i-lucide-trash-2 size-4"
            aria-hidden="true"
          />
          {{ item.texto }}
        </button>
      </li>
    </ul>
  </div>
</template>
