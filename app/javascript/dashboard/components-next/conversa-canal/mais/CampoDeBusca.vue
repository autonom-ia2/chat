<script setup>
// Campo com sugestões enquanto a pessoa digita (#1702): endereço do Google na
// Localização e contato da base na janela de Contato. Padrão WAI-ARIA "combobox com
// lista": setas andam pelas sugestões, Enter escolhe, Esc fecha. O texto digitado
// continua valendo mesmo sem escolher nada.
import { computed, ref, useId, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  label: { type: String, required: true },
  placeholder: { type: String, default: '' },
  ajuda: { type: String, default: '' },
  erro: { type: String, default: '' },
  // texto → Promise<[{ id, titulo, detalhe? }]>
  buscar: { type: Function, required: true },
  icone: { type: String, default: 'i-lucide-search' },
});

const emit = defineEmits(['escolher']);
const texto = defineModel({ type: String, default: '' });

const id = useId();
const sugestoes = ref([]);
const aberta = ref(false);
const ativa = ref(-1);
const carregando = ref(false);
const falha = ref('');
let ultimaBusca = 0;
// O texto escolhido na lista não dispara uma busca nova.
let escolhido = null;

const procurar = useDebounceFn(async valor => {
  // Pedido que ficou na espera e o texto já mudou (ou foi escolhido): não busca.
  if (valor !== texto.value || valor === escolhido) return;
  ultimaBusca += 1;
  const numero = ultimaBusca;
  carregando.value = true;
  falha.value = '';
  try {
    const lista = await props.buscar(valor);
    if (numero !== ultimaBusca) return;
    sugestoes.value = lista;
    aberta.value = lista.length > 0;
    ativa.value = -1;
  } catch (error) {
    if (numero !== ultimaBusca) return;
    sugestoes.value = [];
    aberta.value = false;
    falha.value = error?.response?.data?.error || error?.message || '';
  } finally {
    if (numero === ultimaBusca) carregando.value = false;
  }
}, 300);

// Qualquer busca em andamento deixa de valer (escolheu, apagou, fechou).
const esquecerBuscas = () => {
  ultimaBusca += 1;
  carregando.value = false;
  sugestoes.value = [];
  aberta.value = false;
};

watch(texto, valor => {
  if (valor === escolhido) return;
  escolhido = null;
  if (String(valor || '').trim().length < 2) {
    esquecerBuscas();
    return;
  }
  procurar(valor);
});

const escolher = item => {
  esquecerBuscas();
  escolhido = item.titulo;
  texto.value = item.titulo;
  emit('escolher', item);
};

const aoTeclar = evento => {
  if (!aberta.value) return;
  const total = sugestoes.value.length;
  if (evento.key === 'ArrowDown') {
    evento.preventDefault();
    ativa.value = (ativa.value + 1) % total;
  } else if (evento.key === 'ArrowUp') {
    evento.preventDefault();
    ativa.value = (ativa.value - 1 + total) % total;
  } else if (evento.key === 'Enter' && ativa.value >= 0) {
    evento.preventDefault();
    escolher(sugestoes.value[ativa.value]);
  } else if (evento.key === 'Escape') {
    // Fecha só a lista; a janela continua aberta.
    evento.preventDefault();
    evento.stopPropagation();
    aberta.value = false;
  }
};

const mensagem = computed(() => props.erro || falha.value || props.ajuda);
const ehErro = computed(() => Boolean(props.erro || falha.value));
</script>

<template>
  <div
    v-on-click-outside="() => (aberta = false)"
    class="relative flex flex-col gap-1 min-w-0"
  >
    <label :for="`${id}-campo`" class="text-sm font-medium text-n-slate-12">
      {{ label }}
    </label>
    <div class="relative">
      <Icon
        :icon="carregando ? 'i-lucide-loader-circle' : icone"
        class="absolute start-3 top-1/2 -translate-y-1/2 size-4 text-n-slate-11"
        :class="{ 'animate-spin': carregando }"
      />
      <input
        :id="`${id}-campo`"
        v-model="texto"
        type="text"
        role="combobox"
        autocomplete="off"
        :aria-expanded="aberta"
        :aria-controls="`${id}-lista`"
        :aria-activedescendant="ativa >= 0 ? `${id}-op-${ativa}` : undefined"
        :aria-invalid="ehErro"
        :placeholder="placeholder"
        class="reset-base w-full h-10 ps-9 pe-3 rounded-lg text-sm bg-n-alpha-black2 text-n-slate-12 outline outline-1 placeholder:text-n-slate-10 focus:outline-n-brand"
        :class="ehErro ? 'outline-n-ruby-8' : 'outline-n-weak'"
        @keydown="aoTeclar"
      />
    </div>
    <ul
      v-show="aberta"
      :id="`${id}-lista`"
      role="listbox"
      class="reset-base absolute top-full mt-1 z-50 w-full max-h-64 overflow-y-auto py-1 rounded-lg bg-n-alpha-3 backdrop-blur-[100px] shadow-lg border border-n-weak"
    >
      <li
        v-for="(item, indice) in sugestoes"
        :id="`${id}-op-${indice}`"
        :key="item.id"
        role="option"
        :aria-selected="indice === ativa"
        class="flex flex-col px-3 py-2 min-h-11 justify-center cursor-pointer text-sm"
        :class="indice === ativa ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
        @mousedown.prevent="escolher(item)"
      >
        <span class="text-n-slate-12 break-words">{{ item.titulo }}</span>
        <span v-if="item.detalhe" class="text-xs text-n-slate-11 break-words">
          {{ item.detalhe }}
        </span>
      </li>
    </ul>
    <p
      v-if="mensagem"
      class="text-xs break-words"
      :class="ehErro ? 'text-n-ruby-11' : 'text-n-slate-11'"
    >
      {{ mensagem }}
    </p>
  </div>
</template>
