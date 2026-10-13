<script setup>
// #1459 — o envio falhou: aviso âmbar no topo, com o que o servidor disse. O
// que a pessoa escreveu continua na tela.
defineProps({
  texto: { type: String, required: true },
});
</script>

<template>
  <div
    role="alert"
    data-nova-conversa-erro
    class="flex items-start gap-3 rounded-2xl border border-dashed border-n-amber-8 bg-n-amber-2 p-4"
  >
    <span
      class="i-lucide-triangle-alert mt-0.5 size-5 shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    <span class="flex min-w-0 flex-col gap-1">
      <strong class="text-[0.9375rem] font-semibold text-n-slate-12">
        {{ $t('NOVA_CONVERSA.ERRO.TITULO') }}
      </strong>
      <span class="break-words text-[0.9375rem] text-n-slate-12">
        {{ texto }}
      </span>
    </span>
  </div>
</template>
