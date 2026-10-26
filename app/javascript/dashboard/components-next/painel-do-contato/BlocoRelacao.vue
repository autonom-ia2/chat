<script setup>
// #2084/#2085 — "Este contato é" no painel da conversa, atrás da chave `contato_relacao`.
import { useI18n } from 'vue-i18n';
import EscolhaDaRelacao from 'dashboard/components-next/contato-relacao/EscolhaDaRelacao.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';

defineProps({
  contactId: { type: [Number, String], required: true },
  podeEditar: { type: Boolean, default: false },
});

const { t } = useI18n();
</script>

<template>
  <BlocoDoPainel
    :titulo="t('PAINEL_DO_CONTATO.RELACAO.TITULO')"
    data-test-id="bloco-relacao"
  >
    <EscolhaDaRelacao :contact-id="contactId" :pode-editar="podeEditar" />
  </BlocoDoPainel>
</template>
