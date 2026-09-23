<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useTamanhoDaLetra } from '../composables/useTamanhoDaLetra';

const { t } = useI18n();
const { tamanho, podeDiminuir, podeAumentar, diminuir, aumentar } =
  useTamanhoDaLetra();
</script>

<template>
  <div
    role="group"
    :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.ROTULO')"
    class="flex items-center gap-2"
  >
    <span class="text-sm text-n-slate-11" aria-live="polite">
      {{
        t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.ATUAL', {
          tamanho: t(`HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.NOMES.${tamanho}`),
        })
      }}
    </span>
    <Button
      size="lg"
      color="slate"
      variant="outline"
      label="A-"
      class="min-w-11 min-h-11"
      :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.DIMINUIR')"
      :title="t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.DIMINUIR')"
      :disabled="!podeDiminuir"
      @click="diminuir"
    />
    <Button
      size="lg"
      color="slate"
      variant="outline"
      label="A+"
      class="min-w-11 min-h-11"
      :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.AUMENTAR')"
      :title="t('HELP_CENTER.CENTRAL_DE_AJUDA.LETRA.AUMENTAR')"
      :disabled="!podeAumentar"
      @click="aumentar"
    />
  </div>
</template>
