<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatarDinheiro, tomDoGrupo } from '../../ficha/compras';
import { useIdioma } from '../../ficha/idioma';
import { GRUPOS_DE_COMPRA_IDS } from '../../fonte/gruposDeCompra';

// #3097 — na visão por compra, os grupos viram cartões no lugar das pílulas:
// o nome, quantas pessoas em número grande e quanto elas já compraram (com uma
// moeda só; moedas diferentes não se somam). A faixa de cor do topo é a mesma
// do selo da ficha (verde, âmbar, vermelho). O escolhido fica invertido, como
// a pílula escolhida; tocar nele de novo volta para todos. Grupo com 0 pessoas não aparece, salvo o escolhido. No
// celular, 2 colunas (3 linhas, sem rolar de lado); no desktop, 6 numa linha.
// "Ver todos" e "Nunca compraram" ficam embaixo, como links: não são grupos
// de quem compra.
//   grupos: [{ id, nome, total }]   valores: { [id]: [{ moeda, total }] }
const props = defineProps({
  grupos: { type: Array, required: true },
  valores: { type: Object, default: () => ({}) },
  modelValue: { type: String, default: '' },
  todos: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idioma = useIdioma();
const L = 'RELACIONAMENTOS_COMPRAS.LISTA';

const FAIXAS = {
  verde: 'bg-n-teal-9',
  azul: 'bg-n-blue-9',
  ambar: 'bg-n-amber-9',
  vermelho: 'bg-n-ruby-9',
  neutro: 'bg-n-slate-7',
};
const NUNCA = GRUPOS_DE_COMPRA_IDS.NUNCA;

const escolhido = id => props.modelValue === id;
const cartoes = computed(() =>
  props.grupos.filter(
    grupo => grupo.id !== NUNCA && (grupo.total > 0 || escolhido(grupo.id))
  )
);
const nunca = computed(() => props.grupos.find(grupo => grupo.id === NUNCA));
const valorDe = id => {
  const moedas = props.valores?.[id] || [];
  if (moedas.length !== 1 || !(moedas[0].total > 0)) return '';
  return t(`${L}.EM_COMPRAS`, {
    valor: formatarDinheiro(moedas[0].total, moedas[0].moeda, idioma.value),
  });
};
// Tocar de novo no cartão escolhido volta para todos.
const escolher = id => {
  emit('update:modelValue', escolhido(id) ? props.todos.id : id);
};
const escolherLink = id => {
  if (!escolhido(id)) emit('update:modelValue', id);
};
const links = computed(() =>
  [
    {
      id: props.todos.id,
      rotulo: t(`${L}.VER_TODOS`, { count: props.todos.total ?? 0 }),
    },
    nunca.value?.total && {
      id: NUNCA,
      rotulo: t(`${L}.NUNCA_COMPRARAM`, { count: nunca.value.total }),
    },
  ].filter(Boolean)
);
</script>

<template>
  <div class="flex flex-col gap-3" data-relacionamentos="cartoes-de-compra">
    <ul
      class="grid grid-cols-2 gap-2 p-0 m-0 list-none sm:grid-cols-3 lg:grid-cols-6 md:gap-3"
    >
      <li v-for="grupo in cartoes" :key="grupo.id">
        <button
          type="button"
          :data-grupo="grupo.id"
          :aria-pressed="escolhido(grupo.id)"
          class="group relative flex flex-col items-start w-full h-full gap-1 p-3 md:p-4 overflow-hidden text-start rounded-2xl ring-1 ring-inset transition-shadow hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="
            escolhido(grupo.id)
              ? 'bg-n-slate-12 ring-n-slate-12'
              : 'bg-n-solid-1 ring-n-weak hover:ring-n-slate-6'
          "
          @click="escolher(grupo.id)"
        >
          <span
            aria-hidden="true"
            class="absolute inset-x-0 top-0 h-1"
            :class="FAIXAS[tomDoGrupo(grupo.id)]"
          />
          <span
            class="text-sm font-medium leading-snug line-clamp-2 min-h-10"
            :class="escolhido(grupo.id) ? 'text-n-slate-1' : 'text-n-slate-12'"
          >
            {{ grupo.nome }}
          </span>
          <span
            class="mt-1 text-2xl font-bold leading-none md:text-3xl tabular-nums"
            :class="escolhido(grupo.id) ? 'text-n-slate-1' : 'text-n-slate-12'"
          >
            {{ grupo.total ?? 0 }}
            <span class="sr-only">{{ t(`${L}.PESSOAS`) }}</span>
          </span>
          <span
            v-if="valorDe(grupo.id)"
            class="text-xs tabular-nums"
            :class="
              escolhido(grupo.id)
                ? 'text-n-slate-1 opacity-80'
                : 'text-n-slate-11'
            "
          >
            {{ valorDe(grupo.id) }}
          </span>
        </button>
      </li>
    </ul>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="link in links"
        :key="link.id"
        type="button"
        :aria-pressed="escolhido(link.id)"
        class="px-4 text-sm font-medium rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :class="
          escolhido(link.id)
            ? 'bg-n-slate-12 text-n-slate-1'
            : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3'
        "
        @click="escolherLink(link.id)"
      >
        {{ link.rotulo }}
      </button>
    </div>
  </div>
</template>
