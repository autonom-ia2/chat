<script setup>
import { nextTick, ref, useId } from 'vue';
import { onClickOutside } from '@vueuse/core';

// #1181 PR3 — "Mais opções" do herói do agente (protótipo T07): botão com texto sobre o navy e menu
// no padrão WAI-ARIA menu button. Abre e leva o foco ao primeiro item; setas, Home e End andam entre
// os itens; Esc devolve o foco ao botão; Tab e clique fora fecham. Escolher um item devolve o foco ao
// botão antes de avisar, para a gaveta que abrir depois saber a quem devolver o foco.
// itens: [{ chave, texto, icone, perigo?, separar? }] — `separar` põe uma linha antes do item.
defineProps({
  rotulo: { type: String, required: true },
  itens: { type: Array, required: true },
});

const emit = defineEmits(['escolher']);

const menuId = `mais-${useId()}`;
const aberto = ref(false);
const raiz = ref(null);
const botao = ref(null);
const itensRefs = ref([]);

const focarItem = indice => {
  const lista = itensRefs.value;
  if (!lista.length) return;
  lista[(indice + lista.length) % lista.length]?.focus();
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

const escolher = item => {
  fechar({ devolverFoco: true });
  emit('escolher', item.chave);
};

const TECLAS = {
  ArrowDown: atual => focarItem(atual + 1),
  ArrowUp: atual => focarItem(atual - 1),
  Home: () => focarItem(0),
  End: () => focarItem(-1),
};

const aoTeclar = evento => {
  const atual = itensRefs.value.indexOf(document.activeElement);
  if (evento.key === 'Escape') {
    evento.preventDefault();
    fechar({ devolverFoco: true });
    return;
  }
  if (evento.key === 'Tab') {
    fechar();
    return;
  }
  const mover = TECLAS[evento.key];
  if (!mover) return;
  evento.preventDefault();
  mover(atual);
};

onClickOutside(raiz, () => {
  if (aberto.value) fechar();
});
</script>

<template>
  <div ref="raiz" class="relative">
    <button
      ref="botao"
      data-mais
      type="button"
      aria-haspopup="menu"
      :aria-expanded="aberto ? 'true' : 'false'"
      :aria-controls="aberto ? menuId : undefined"
      class="inline-flex items-center gap-2 px-4 text-sm font-semibold text-white rounded-xl min-h-11 ring-1 ring-inset ring-white/40 hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      @click.stop="aberto ? fechar() : abrir()"
    >
      <span class="i-lucide-ellipsis size-5" aria-hidden="true" />
      <span>{{ rotulo }}</span>
    </button>
    <ul
      v-if="aberto"
      :id="menuId"
      role="menu"
      :aria-label="rotulo"
      class="absolute z-30 flex flex-col p-1 m-0 list-none shadow-lg end-0 top-12 min-w-64 rounded-xl bg-n-solid-1 ring-1 ring-n-weak"
      @keydown="aoTeclar"
    >
      <template v-for="item in itens" :key="item.chave">
        <li
          v-if="item.separar"
          role="separator"
          class="my-1 border-t border-n-weak"
        />
        <li role="none">
          <button
            ref="itensRefs"
            type="button"
            role="menuitem"
            :data-item="item.chave"
            class="flex items-center w-full gap-2 px-3 text-sm text-start rounded-lg min-h-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            :class="item.perigo ? 'text-n-ruby-11' : 'text-n-slate-12'"
            @click.stop="escolher(item)"
          >
            <span
              v-if="item.icone"
              :class="item.icone"
              class="size-4 shrink-0"
              aria-hidden="true"
            />
            {{ item.texto }}
          </button>
        </li>
      </template>
    </ul>
  </div>
</template>
