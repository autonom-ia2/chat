<script setup>
// #2202 — o selo "IA" ao lado do nome do robô (decisão 3). Só visual: o leitor de tela
// ouve "Gabriela, assistente de IA" pelo aria-label de quem usa.
</script>

<template>
  <span
    aria-hidden="true"
    data-selo-ia
    class="inline-flex items-center flex-shrink-0 px-1 text-[10px] font-medium leading-4 rounded bg-n-alpha-2 text-n-slate-11"
  >
    {{ $t('LISTA_DE_CONVERSAS.PREFIXO.SELO_IA') }}
  </span>
</template>
