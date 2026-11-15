<script setup>
import { useI18n } from 'vue-i18n';

// #2899 (E6.4) — a primeira pergunta de "Trazer" na conta que lê PDF: trazer
// por planilha (o caminho de sempre) ou por PDFs das apólices. São dois links
// grandes; o caminho escolhido fica no endereço (`?como=`), e voltar do
// navegador traz a pergunta de novo.
defineProps({
  // { planilha, pdfs }: as rotas de cada caminho.
  rotas: { type: Object, required: true },
});

const { t } = useI18n();
const tw = chave => t(`RELACIONAMENTOS_CARTEIRA.PDFS.COMO.${chave}`);
const CAMINHOS = [
  { id: 'planilha', icone: 'i-lucide-sheet' },
  { id: 'pdfs', icone: 'i-lucide-files' },
];
</script>

<template>
  <section
    data-carteira="como-trazer"
    class="flex flex-col w-full max-w-3xl gap-6 px-5 pt-8 mx-auto md:px-8 md:pt-10"
  >
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-2xl font-semibold text-n-slate-12"
    >
      {{ tw('TITULO') }}
    </h1>
    <ul class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2">
      <li v-for="caminho in CAMINHOS" :key="caminho.id">
        <router-link
          :to="rotas[caminho.id]"
          :data-como="caminho.id"
          class="flex flex-col h-full gap-3 p-6 border rounded-3xl border-n-weak bg-n-solid-1 text-n-slate-12 hover:border-n-blue-8 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        >
          <span
            class="flex items-center justify-center rounded-full size-12 bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            <span class="size-6" :class="caminho.icone" />
          </span>
          <span class="text-lg font-semibold">
            {{ tw(`${caminho.id.toUpperCase()}.TITULO`) }}
          </span>
          <span class="text-base text-n-slate-11">
            {{ tw(`${caminho.id.toUpperCase()}.APOIO`) }}
          </span>
        </router-link>
      </li>
    </ul>
  </section>
</template>
