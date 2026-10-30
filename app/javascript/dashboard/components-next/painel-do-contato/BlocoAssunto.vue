<script setup>
// #2138 — "Assunto", só para quem não opera (o topo esconde o botão do assunto para
// essa pessoa). Uma frase, sem "etapa", "funil" nem "card". Sem assunto, some.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import BlocoDoPainel from './BlocoDoPainel.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const selo = useCrmConversationStage(computed(() => props.conversation.id));

// Igual ao botão do topo: título que repete o nome ou o telefone não é assunto.
const assunto = computed(() => {
  const titulo = String(selo.value?.title || '').trim();
  const pessoa = props.conversation?.meta?.sender || {};
  return [pessoa.name, pessoa.phone_number].includes(titulo) ? '' : titulo;
});

const frase = computed(() => {
  const etapa = selo.value?.stage_name;
  if (!etapa) return '';
  return assunto.value
    ? t('PAINEL_DO_CONTATO.ASSUNTO.FRASE', { assunto: assunto.value, etapa })
    : t('PAINEL_DO_CONTATO.ASSUNTO.SEM_NOME', { etapa });
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <BlocoDoPainel v-if="frase" :titulo="t('PAINEL_DO_CONTATO.ASSUNTO.TITULO')">
    <p class="m-0 text-sm text-n-slate-12">{{ frase }}</p>
  </BlocoDoPainel>
</template>
