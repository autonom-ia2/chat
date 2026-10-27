<script setup>
// #2084/#2085 — "Este contato é" no painel da conversa, atrás da chave `contato_relacao`.
// Sem acesso, o bloco inteiro some (e não só a escolha, deixando o título sozinho).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import EscolhaDaRelacao from 'dashboard/components-next/contato-relacao/EscolhaDaRelacao.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';
import { ESTADO } from './useParteDoPainel';

defineProps({
  contactId: { type: [Number, String], required: true },
  podeEditar: { type: Boolean, default: false },
});

const { t } = useI18n();
const estado = ref(ESTADO.CARREGANDO);
const visivel = computed(
  () => ![ESTADO.ESCONDIDO, ESTADO.VAZIO].includes(estado.value)
);
</script>

<template>
  <BlocoDoPainel
    v-show="visivel"
    :titulo="t('PAINEL_DO_CONTATO.RELACAO.TITULO')"
    data-test-id="bloco-relacao"
  >
    <EscolhaDaRelacao
      :contact-id="contactId"
      :pode-editar="podeEditar"
      @estado="estado = $event"
    />
  </BlocoDoPainel>
</template>
