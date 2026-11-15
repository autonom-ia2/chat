<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2899 (E6.4) — a primeira pergunta de "Trazer" na conta que lê PDF: trazer
// por planilha (o caminho de sempre) ou por PDFs das apólices. São dois links
// grandes; o caminho escolhido fica no endereço (`?como=`), e voltar do
// navegador traz a pergunta de novo.
//
// #2900 (E7.3) — na conta que pode trazer do Agger, o caminho "Do Agger"
// (`?como=agger`). A porta passa os caminhos que a conta tem.
const props = defineProps({
  // { planilha, pdfs, agger }: as rotas de cada caminho.
  rotas: { type: Object, required: true },
  // Os caminhos que a conta tem, na ordem da tela.
  caminhos: { type: Array, default: () => ['planilha', 'pdfs'] },
});

const { t } = useI18n();
const CAMINHOS = [
  {
    id: 'planilha',
    icone: 'i-lucide-sheet',
    titulo: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.PLANILHA.TITULO'),
    apoio: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.PLANILHA.APOIO'),
  },
  {
    id: 'pdfs',
    icone: 'i-lucide-files',
    titulo: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.PDFS.TITULO'),
    apoio: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.PDFS.APOIO'),
  },
  {
    id: 'agger',
    icone: 'i-lucide-cloud-download',
    titulo: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.AGGER.TITULO'),
    apoio: () => t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.AGGER.APOIO'),
  },
];
const daConta = computed(() =>
  CAMINHOS.filter(caminho => props.caminhos.includes(caminho.id))
);
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
      {{ t('RELACIONAMENTOS_CARTEIRA.PDFS.COMO.TITULO') }}
    </h1>
    <ul
      class="grid gap-4 p-0 m-0 list-none sm:grid-cols-2"
      :class="{ 'lg:grid-cols-3': daConta.length > 2 }"
    >
      <li v-for="caminho in daConta" :key="caminho.id">
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
            {{ caminho.titulo() }}
          </span>
          <span class="text-base text-n-slate-11">
            {{ caminho.apoio() }}
          </span>
        </router-link>
      </li>
    </ul>
  </section>
</template>
