<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// #2895 — uma parte da ficha (conversas, cards, notas...) que não carregou: uma
// frase e "Tentar de novo", dentro do cartão da própria parte. O resto da ficha
// segue na tela. Quem usa relê a parte ao ouvir `tentar`.
const emit = defineEmits(['tentar']);

const { t } = useI18n();
</script>

<template>
  <div
    data-relacionamentos="falha-da-parte"
    role="alert"
    class="flex flex-col items-start gap-3"
  >
    <p class="m-0 text-base text-n-slate-11">
      {{ t('RELACIONAMENTOS_FICHA.ESTADOS.ERRO_DA_PARTE') }}
    </p>
    <Button
      slate
      faded
      :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
      @click="emit('tentar')"
    />
  </div>
</template>
