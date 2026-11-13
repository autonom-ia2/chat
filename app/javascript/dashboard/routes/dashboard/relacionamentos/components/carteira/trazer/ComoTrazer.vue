<script setup>
import { useI18n } from 'vue-i18n';

// #2897 — antes de enviar, na conta que tem a carteira de seguros: como a
// pessoa quer trazer as pessoas e os seguros. Hoje há um jeito só, a planilha;
// os outros entram aqui quando existirem, cada um num cartão.
const emit = defineEmits(['planilha']);

const { t } = useI18n();
</script>

<template>
  <section data-carteira="como-trazer" class="flex flex-col gap-6">
    <h1
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ t('RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.TITULO') }}
    </h1>
    <ul class="grid gap-3 p-0 m-0 list-none">
      <li>
        <button
          type="button"
          data-carteira="origem"
          data-origem="planilha"
          class="flex items-center w-full gap-4 p-5 border text-start min-h-16 rounded-2xl border-n-weak bg-n-solid-1 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="emit('planilha')"
        >
          <span
            class="i-lucide-file-spreadsheet size-8 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span class="flex flex-col min-w-0 gap-1">
            <span class="text-lg font-semibold text-n-slate-12">
              {{ t('RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.PLANILHA') }}
            </span>
            <span class="text-base text-n-slate-11">
              {{ t('RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.PLANILHA_APOIO') }}
            </span>
          </span>
          <span
            class="i-lucide-arrow-right size-5 ms-auto shrink-0 text-n-slate-10 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
  </section>
</template>
