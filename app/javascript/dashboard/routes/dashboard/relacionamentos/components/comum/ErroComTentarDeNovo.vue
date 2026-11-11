<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2894 — erro de carregamento: uma frase e um botão (o principal: sólido, azul). Quem usa recarrega ao
// ouvir `tentar`. Sem `mensagem`, a frase é a genérica do catálogo.
defineProps({
  mensagem: { type: String, default: '' },
});
const emit = defineEmits(['tentar']);

const { t } = useI18n();
</script>

<template>
  <div
    data-erro
    role="alert"
    class="flex flex-col items-center gap-5 p-8 text-center border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <span
      class="flex items-center justify-center rounded-full size-12 bg-n-ruby-3 text-n-ruby-11"
      aria-hidden="true"
    >
      <span class="i-lucide-triangle-alert size-6" />
    </span>
    <p class="m-0 text-base text-n-slate-12">
      {{ mensagem || t('RELACIONAMENTOS.COMUM.ERRO_GENERICO') }}
    </p>
    <Button
      class="min-h-11"
      :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
      @click="emit('tentar')"
    />
  </div>
</template>
