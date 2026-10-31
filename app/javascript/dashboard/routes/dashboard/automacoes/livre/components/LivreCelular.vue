<script setup>
import LivreValor from './LivreValor.vue';

// #2414 F0 — um celular simulado: o que o cliente veria no WhatsApp. Só mostra;
// nada é enviado.
defineProps({
  contato: { type: String, required: true },
  mensagens: { type: Array, default: () => [] },
  valores: { type: Object, default: () => ({}) },
});
</script>

<template>
  <figure
    data-celular
    class="flex flex-col w-full max-w-[18rem] mx-auto m-0 overflow-hidden border-8 shadow-xl rounded-[2.25rem] border-n-slate-12 bg-n-teal-2"
  >
    <div class="flex items-center gap-2 px-4 py-3 text-white bg-n-teal-10">
      <span
        class="grid text-xs font-bold rounded-full place-items-center size-8 bg-white/20"
        aria-hidden="true"
      >
        {{ contato.slice(0, 1) }}
      </span>
      <span class="text-sm font-semibold truncate">{{ contato }}</span>
    </div>
    <div class="flex flex-col gap-2 px-3 py-4 min-h-[14rem]">
      <p
        v-for="(mensagem, indice) in mensagens"
        :key="indice"
        data-balao
        class="self-end max-w-[90%] px-3 py-2 mb-0 text-sm leading-relaxed rounded-xl rounded-br-sm shadow-sm bg-n-solid-1 text-n-slate-12"
      >
        <LivreValor :pedacos="mensagem" :valores="valores" />
      </p>
      <p
        v-if="!mensagens.length"
        class="m-auto text-sm text-center text-n-slate-11"
      >
        {{ $t('AUTOMACAO_LIVRE.ENSAIO.CELULAR_VAZIO') }}
      </p>
    </div>
    <figcaption
      class="px-3 py-2 text-xs text-center text-n-slate-11 bg-n-solid-1"
    >
      {{ $t('AUTOMACAO_LIVRE.ENSAIO.CELULAR_LEGENDA') }}
    </figcaption>
  </figure>
</template>
