<script setup>
// Conta cuja configuração nasceu no provider fictício antes da E0 (#683) recebe
// empresas inventadas mesmo com a chave da plataforma pronta. A tela avisa.
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    class="flex items-start gap-3 rounded-md border border-n-amber-5 bg-n-amber-2 p-3 text-sm"
  >
    <span
      class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
    />
    <div class="grid gap-1">
      <p class="font-medium text-n-amber-12">
        {{ t('PROSPECTING.MOCK_PROVIDER.TITLE') }}
      </p>
      <p class="text-n-amber-11">
        {{ t('PROSPECTING.MOCK_PROVIDER.DESCRIPTION') }}
      </p>
    </div>
  </div>
</template>
