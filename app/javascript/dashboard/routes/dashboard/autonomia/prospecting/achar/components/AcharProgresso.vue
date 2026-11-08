<script setup>
// #2692 — a faixa "Procurando os donos: {feitos} de {total}" enquanto a lista
// se completa (v4, T1). Saiu de AcharConfiraPage.vue (trava de tamanho, #677).
import AcharBarra from './AcharBarra.vue';

defineProps({
  progresso: { type: Object, required: true },
});

const NS = 'PROSPECTING_ACHAR.CONFIRA';
</script>

<template>
  <section
    class="flex flex-col gap-2 p-4 border rounded-2xl border-n-blue-6 bg-n-blue-2"
    role="status"
    data-progresso
  >
    <p class="m-0 text-base font-semibold text-n-blue-11">
      {{ $t(`${NS}.PROGRESSO`, progresso) }}
    </p>
    <AcharBarra
      :valor="progresso.feitos"
      :total="progresso.total"
      :rotulo="$t(`${NS}.PROGRESSO`, progresso)"
    />
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t(`${NS}.PROGRESSO_DICA`) }}
    </p>
  </section>
</template>
