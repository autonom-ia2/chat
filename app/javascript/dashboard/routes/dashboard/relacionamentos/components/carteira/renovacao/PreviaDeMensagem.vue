<script setup>
// #2897 — a prévia de uma mensagem como ela chega no WhatsApp: o balão com o
// texto, o arquivo que vai junto (se houver) e os botões de resposta (se
// houver). É só desenho: nada aqui é clicável.
defineProps({
  texto: { type: String, required: true },
  arquivo: { type: String, default: '' },
  botoes: { type: Array, default: () => [] },
  // Uma linha pequena acima do balão ("30 dias antes").
  legenda: { type: String, default: '' },
});
</script>

<template>
  <figure data-carteira="previa-de-mensagem" class="flex flex-col gap-1 m-0">
    <figcaption v-if="legenda" class="text-sm text-n-slate-11">
      {{ legenda }}
    </figcaption>
    <div
      class="flex flex-col self-start max-w-full gap-2 px-4 py-3 text-base break-words rounded-2xl ltr:rounded-tl-md rtl:rounded-tr-md bg-n-teal-3 text-n-slate-12"
    >
      <p class="m-0 whitespace-pre-line">{{ texto }}</p>
      <p
        v-if="arquivo"
        class="flex items-center gap-2 px-3 py-2 m-0 text-sm rounded-xl bg-n-alpha-black2"
      >
        <span class="i-lucide-file-text size-4 shrink-0" aria-hidden="true" />
        {{ arquivo }}
      </p>
      <ul v-if="botoes.length" class="flex flex-wrap gap-2 p-0 m-0 list-none">
        <li
          v-for="botao in botoes"
          :key="botao"
          class="px-3 py-1.5 text-sm font-medium rounded-full bg-n-solid-1 text-n-blue-11 ring-1 ring-inset ring-n-weak"
        >
          {{ botao }}
        </li>
      </ul>
    </div>
  </figure>
</template>
