<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

// #1601 — a linha de origem de um campo do card (memoriaDoCampo.js): "cliente
// informou em 17/10, 14:02 · ver mensagem" ou "corrigido por Ana em 17/10,
// 14:02". Só texto; o "ver mensagem" abre a conversa na mensagem de prova.
const props = defineProps({
  origem: { type: Object, required: true },
});

const { t } = useI18n();
const route = useRoute();
const O = 'CRM_KANBAN.DRAWER.CARD_FIELDS.ORIGEM';

const texto = computed(() =>
  t(`${O}.${props.origem.texto}`, {
    quando: props.origem.quando,
    nome: props.origem.nome,
  })
);
const destino = computed(() => {
  if (!props.origem.conversa || !props.origem.mensagem) return null;
  return {
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: props.origem.conversa,
    },
    query: { messageId: props.origem.mensagem },
  };
});
</script>

<template>
  <p
    class="mb-0 text-xs leading-5 text-n-slate-11"
    data-testid="crm-card-field-origem"
  >
    {{ texto }}
    <template v-if="destino">
      <span class="mx-1" aria-hidden="true">{{ t(`${O}.SEPARADOR`) }}</span>
      <router-link
        :to="destino"
        class="text-n-blue-11 hover:underline"
        data-testid="crm-card-field-origem-link"
      >
        {{ t(`${O}.VER_MENSAGEM`) }}
      </router-link>
    </template>
  </p>
</template>
