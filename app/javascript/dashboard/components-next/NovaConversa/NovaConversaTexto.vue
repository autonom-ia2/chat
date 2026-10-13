<script setup>
// #1459 — o campo de escrever: grande, sem barra de formatação e com o rótulo
// à vista. Enter quebra a linha; quem envia é o botão (ou Ctrl/Cmd+Enter,
// tratado na gaveta). Os "!" vencem o estilo global de <textarea> do painel,
// que tira a borda e fixa a altura.
defineProps({
  comRotulo: { type: Boolean, default: true },
});

const texto = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-col gap-2">
    <label
      for="nova-conversa-texto"
      class="mb-0 text-base font-semibold text-n-slate-12"
      :class="{ 'sr-only': !comRotulo }"
    >
      {{ $t('NOVA_CONVERSA.MENSAGEM.CAMPO') }}
    </label>
    <textarea
      id="nova-conversa-texto"
      v-model="texto"
      data-foco
      rows="6"
      :placeholder="$t('NOVA_CONVERSA.MENSAGEM.PLACEHOLDER')"
      class="!mb-0 !h-auto min-h-40 w-full resize-y !rounded-2xl !border !border-solid !border-n-weak !bg-n-solid-1 !px-4 !py-3 !text-base leading-relaxed text-n-slate-12 shadow-sm !outline-none transition placeholder:text-n-slate-10 hover:!border-n-slate-7 focus:!border-n-blue-8 focus:shadow-md"
    />
  </div>
</template>
