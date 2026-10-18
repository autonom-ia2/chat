<script setup>
// No lugar da caixa de resposta para quem só lê a conversa (conversation_view, #1800): uma frase e nenhum botão,
// porque a pessoa não tem o que fazer aqui além de ler.
import Icon from 'next/icon/Icon.vue';
</script>

<template>
  <div
    role="status"
    class="flex items-start gap-3 m-2 px-4 py-3 rounded-lg border border-n-weak bg-n-solid-2 text-sm text-n-slate-11"
    data-aviso-so-leitura
  >
    <Icon icon="i-lucide-eye" class="mt-0.5 size-4 shrink-0 text-n-blue-11" />
    <p class="m-0">
      <span class="font-medium text-n-slate-12">
        {{ $t('CONVERSATION.SO_LEITURA.TITULO') }}
      </span>
      {{ $t('CONVERSATION.SO_LEITURA.TEXTO') }}
    </p>
  </div>
</template>
