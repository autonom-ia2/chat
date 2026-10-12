<script setup>
import { computed } from 'vue';

const props = defineProps({
  numeros: { type: Array, required: true },
});

// Em quais números usar. Um modelo vale para todos os números da mesma conta do
// WhatsApp, então a escolha é por conta e mostra os números que vêm junto. Só
// aparecem números do WhatsApp oficial (o adaptador já filtra).
const rascunho = defineModel('rascunho', { type: Object, required: true });

const contas = computed(() => {
  const porConta = props.numeros.reduce((mapa, numero) => {
    const atual = mapa[numero.conta.id] || { ...numero.conta, numeros: [] };
    return {
      ...mapa,
      [numero.conta.id]: { ...atual, numeros: [...atual.numeros, numero] },
    };
  }, {});
  return Object.values(porConta);
});

const marcada = conta =>
  conta.numeros.every(numero => rascunho.value.numeros.includes(numero.id));

const alternar = conta => {
  const ids = conta.numeros.map(numero => numero.id);
  const numeros = marcada(conta)
    ? rascunho.value.numeros.filter(id => !ids.includes(id))
    : [...new Set([...rascunho.value.numeros, ...ids])];
  rascunho.value = { ...rascunho.value, numeros };
};
</script>

<template>
  <div data-etapa-numeros class="flex flex-col gap-5">
    <p class="mb-0 text-base text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.NUMEROS.INTRO') }}
    </p>
    <p
      v-if="contas.length > 1"
      data-varias-contas
      class="flex gap-2 p-4 mb-0 text-[0.9375rem] rounded-xl bg-n-blue-2 text-n-slate-12"
    >
      <span
        class="i-lucide-info size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ $t('MODELOS_WHATSAPP.NUMEROS.CADA_CONTA') }}
    </p>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li v-for="conta in contas" :key="conta.id">
        <button
          type="button"
          role="checkbox"
          :data-conta="conta.id"
          :aria-checked="marcada(conta)"
          class="flex items-start w-full gap-4 p-5 text-start transition rounded-2xl ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            marcada(conta)
              ? 'ring-2 ring-n-blue-8 bg-n-blue-2'
              : 'ring-n-weak bg-n-solid-1 hover:ring-n-blue-6'
          "
          @click="alternar(conta)"
        >
          <span
            class="grid mt-0.5 rounded-md place-items-center size-6 shrink-0 ring-1 ring-inset"
            :class="
              marcada(conta)
                ? 'bg-n-brand ring-n-brand text-white'
                : 'bg-n-solid-1 ring-n-slate-7'
            "
            aria-hidden="true"
          >
            <span v-if="marcada(conta)" class="i-lucide-check size-4" />
          </span>
          <span class="flex flex-col min-w-0 gap-2">
            <span class="text-lg font-semibold text-n-slate-12">
              {{ $t('MODELOS_WHATSAPP.NUMEROS.CONTA', { nome: conta.nome }) }}
            </span>
            <span class="flex flex-col gap-1.5">
              <span
                v-for="numero in conta.numeros"
                :key="numero.id"
                class="flex flex-wrap items-center gap-x-2 text-[0.9375rem] text-n-slate-12"
              >
                <span
                  class="i-lucide-smartphone size-4 text-n-slate-10"
                  aria-hidden="true"
                />
                {{ numero.nome }}
                <span class="text-sm text-n-slate-10">{{
                  numero.telefone
                }}</span>
              </span>
            </span>
            <span
              v-if="conta.numeros.length > 1"
              class="text-sm text-n-slate-11"
            >
              {{ $t('MODELOS_WHATSAPP.NUMEROS.VALE_PARA_TODOS') }}
            </span>
          </span>
        </button>
      </li>
    </ul>
    <p
      v-if="!rascunho.numeros.length"
      role="status"
      class="mb-0 text-sm text-n-ruby-11"
    >
      {{ $t('MODELOS_WHATSAPP.NUMEROS.ESCOLHA_UM') }}
    </p>
  </div>
</template>
