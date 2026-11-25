<script setup>
import { useI18n } from 'vue-i18n';

// #3211 — a página de um agente pronto que a pessoa contrata (rota autonomia_contratado_modelo). A Tarefa 27 a completa
// com o que o agente faz, o que ele pede e o formulário dos três campos.
defineProps({
  modelo: { type: String, required: true },
});

const { t } = useI18n();
</script>

<template>
  <section :data-modelo="modelo" class="w-full max-w-5xl px-4 py-6 mx-auto">
    <h1 class="m-0 text-2xl font-semibold text-n-slate-12">
      {{ t('AGENTS.CONTRATADOS.MODELO.TITULO') }}
    </h1>
  </section>
</template>
