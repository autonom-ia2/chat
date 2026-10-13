<script setup>
import { I18nT } from 'vue-i18n';
import FunilResumoCartao from './FunilResumoCartao.vue';

// #1384 — "Quando usar este funil" em uma frase, no resumo e no Confira.
defineProps({
  texto: { type: String, default: '' },
});

defineEmits(['alterar']);
</script>

<template>
  <FunilResumoCartao
    parte="about"
    icone="i-lucide-message-square-text"
    tom="bg-n-violet-3 text-n-violet-11"
    :titulo="$t('CRM_FUNIL.SOBRE.ROTULO')"
    :falta="!texto.trim()"
    @alterar="$emit('alterar')"
  >
    <I18nT
      v-if="texto.trim()"
      keypath="CRM_FUNIL.RESUMO.SOBRE"
      tag="span"
      scope="global"
    >
      <template #texto>
        <strong class="font-semibold">{{ texto.trim() }}</strong>
      </template>
    </I18nT>
    <template v-else>{{ $t('CRM_FUNIL.RESUMO.SOBRE_FALTA') }}</template>
  </FunilResumoCartao>
</template>
