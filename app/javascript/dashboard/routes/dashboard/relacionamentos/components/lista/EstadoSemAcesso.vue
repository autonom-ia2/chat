<script setup>
// #2894 — a pessoa não pode ver esta lista (o servidor recusou com 401 ou 403):
// uma frase só. Sem botão: tentar de novo não muda a resposta; quem resolve é
// quem administra a conta.
defineProps({
  frase: { type: String, required: true },
});
</script>

<template>
  <div
    role="alert"
    data-relacionamentos="sem-acesso"
    class="flex flex-col items-center gap-5 p-8 text-center border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <span
      class="flex items-center justify-center rounded-full size-12 bg-n-slate-3 text-n-slate-11"
      aria-hidden="true"
    >
      <span class="i-lucide-lock size-6" />
    </span>
    <p class="m-0 text-base text-n-slate-12">{{ frase }}</p>
  </div>
</template>
