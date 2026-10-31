<script setup>
import { useRoute, useRouter } from 'vue-router';

// #2414 F0 — três portas para começar: contar com as próprias palavras (o Guia
// monta), partir de uma receita pronta ou montar do zero. Todas acabam no mesmo
// editor "Confira".
const route = useRoute();
const router = useRouter();

const PORTAS = [
  {
    chave: 'CONTE',
    icone: 'i-lucide-message-circle-heart',
    tom: 'bg-n-heroi text-white dark:bg-n-heroi-escuro',
    rota: 'automacoes_livre_conte',
  },
  {
    chave: 'RECEITAS',
    icone: 'i-lucide-book-open-check',
    tom: 'bg-n-teal-3 text-n-teal-11',
    rota: 'automacoes_livre_receitas',
  },
  {
    chave: 'ZERO',
    icone: 'i-lucide-blocks',
    tom: 'bg-n-slate-3 text-n-slate-11',
    rota: 'automacoes_livre_nova',
  },
];

const entrar = porta =>
  router.push({
    name: porta.rota,
    params: { accountId: route.params.accountId },
  });

const voltar = () =>
  router.push({
    name: 'automacoes_livre_lista',
    params: { accountId: route.params.accountId },
  });
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full max-w-5xl gap-8 px-5 py-8 pb-40 mx-auto md:px-8 md:py-10"
    >
      <button
        type="button"
        class="inline-flex items-center self-start gap-2 text-sm font-medium min-h-11 text-n-slate-11 hover:text-n-slate-12"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ $t('AUTOMACAO_LIVRE.VOLTAR_LISTA') }}
      </button>
      <header>
        <h1
          class="text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
        >
          {{ $t('AUTOMACAO_LIVRE.PORTAS.TITULO') }}
        </h1>
        <p class="mt-2 mb-0 text-base md:text-lg text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.PORTAS.SUBTITULO') }}
        </p>
      </header>
      <ul class="grid gap-4 p-0 m-0 list-none md:grid-cols-3">
        <li v-for="porta in PORTAS" :key="porta.chave">
          <button
            type="button"
            :data-porta="porta.chave"
            class="flex flex-col w-full h-full gap-4 p-6 transition border shadow-sm text-start rounded-3xl border-n-weak bg-n-solid-1 hover:border-n-blue-7 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="entrar(porta)"
          >
            <span
              class="grid place-items-center size-14 rounded-2xl"
              :class="porta.tom"
            >
              <span class="size-7" :class="porta.icone" aria-hidden="true" />
            </span>
            <span class="text-xl font-semibold text-n-slate-12">
              {{ $t(`AUTOMACAO_LIVRE.PORTAS.${porta.chave}.TITULO`) }}
            </span>
            <span class="text-[0.9375rem] text-n-slate-11">
              {{ $t(`AUTOMACAO_LIVRE.PORTAS.${porta.chave}.TEXTO`) }}
            </span>
            <span
              class="inline-flex items-center gap-2 mt-auto text-base font-semibold text-n-blue-11"
            >
              {{ $t(`AUTOMACAO_LIVRE.PORTAS.${porta.chave}.BOTAO`) }}
              <span
                class="i-lucide-arrow-right size-5 rtl:rotate-180"
                aria-hidden="true"
              />
            </span>
          </button>
        </li>
      </ul>
    </div>
  </main>
</template>
