<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// Erro de rede ao abrir as funções (#2308, especificação 5.A): nunca aparece como lista vazia. Vale para a lista e
// para a conversa guiada (Alterar, Duplicar e a Escolha).
const emit = defineEmits(['tentar']);
</script>

<template>
  <div
    data-erro
    role="alert"
    class="flex flex-col items-center gap-4 px-6 text-center border py-14 rounded-2xl border-n-weak bg-n-solid-1"
  >
    <span
      class="grid place-items-center size-11 rounded-xl bg-n-ruby-3 text-n-ruby-11"
    >
      <span class="i-lucide-wifi-off size-6" aria-hidden="true" />
    </span>
    <p class="m-0 text-xl font-semibold leading-snug text-n-slate-12">
      {{ $t('FUNCOES_EQUIPE.ERRO.TITULO') }}
    </p>
    <p class="m-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('FUNCOES_EQUIPE.ERRO.TEXTO') }}
    </p>
    <Button
      data-tentar-de-novo
      :label="$t('FUNCOES_EQUIPE.ERRO.TENTAR')"
      icon="i-lucide-refresh-cw"
      slate
      faded
      class="min-h-11"
      @click="emit('tentar')"
    />
  </div>
</template>
