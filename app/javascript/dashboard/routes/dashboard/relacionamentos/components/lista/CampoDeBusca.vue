<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

// #2894 — a busca da lista. Ao digitar espera 300 ms antes de avisar quem usa
// (a lista não pisca a cada letra); Enter avisa na hora; o X (e Esc) limpa e
// avisa na hora. Se quem usa limpar a busca por fora, o campo esvazia junto.
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const ESPERA_AO_DIGITAR_MS = 300;

const { t } = useI18n();

const texto = ref(props.modelValue);
let relogio = null;

const parar = () => {
  clearTimeout(relogio);
  relogio = null;
};

const avisar = () => {
  parar();
  emit('update:modelValue', texto.value);
};

const aoDigitar = () => {
  parar();
  relogio = setTimeout(avisar, ESPERA_AO_DIGITAR_MS);
};

const limpar = () => {
  texto.value = '';
  avisar();
};

watch(
  () => props.modelValue,
  novo => {
    if (novo === '') {
      parar();
      texto.value = '';
    }
  }
);

onBeforeUnmount(parar);
</script>

<template>
  <div class="relative">
    <span
      class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-5 text-n-slate-10 top-1/2 ltr:left-4 rtl:right-4"
      aria-hidden="true"
    />
    <input
      v-model="texto"
      type="search"
      data-relacionamentos="busca"
      autocomplete="off"
      :placeholder="placeholder"
      :aria-label="t('RELACIONAMENTOS.LISTA.BUSCA.ROTULO')"
      class="w-full min-h-11 rounded-xl border-0 bg-n-alpha-black2 text-base text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak placeholder:text-n-slate-10 focus:outline-2 focus:outline-n-brand ltr:pl-12 ltr:pr-12 rtl:pl-12 rtl:pr-12 [&::-webkit-search-cancel-button]:hidden"
      @input="aoDigitar"
      @keydown.enter.prevent="avisar"
      @keydown.esc="limpar"
    />
    <button
      v-if="texto"
      type="button"
      :aria-label="t('RELACIONAMENTOS.LISTA.BUSCA.LIMPAR')"
      class="absolute inset-y-0 flex items-center justify-center rounded-xl text-n-slate-11 hover:text-n-slate-12 size-11 ltr:right-0 rtl:left-0 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="limpar"
    >
      <span class="i-lucide-x size-5" aria-hidden="true" />
    </button>
  </div>
</template>
