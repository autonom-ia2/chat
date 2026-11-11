<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { usarDemo } from '../fonte/modoDemo';

// #2894 — casca da tela "lista" de Relacionamentos: só o título. O conteúdo vem na
// construção da tela. `usarDemo` guarda o ?demo= para as telas seguintes.
const { t } = useI18n();
usarDemo(useRoute().query);
</script>

<template>
  <section
    class="flex flex-col h-full bg-n-surface-1"
    data-relacionamentos="lista"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col max-w-6xl gap-8 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <h1
          class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
        >
          {{ t('RELACIONAMENTOS.LISTA.TITULO') }}
        </h1>
      </div>
    </main>
  </section>
</template>
