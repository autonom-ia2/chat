<script setup>
// Contato enviado: `{ type: 'contact', name, phone, wa_id? }`, sem corpo. Nome e telefone como o cliente recebeu,
// sem "Salvar contato": o contato é nosso.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import SharedCard from '../SharedCard.vue';

const { contentAttributes, sender } = useMessageContext();
const { t } = useI18n();

// Nome e telefone vêm de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});

const heading = computed(() => {
  const name = sender?.value?.name;
  return name ? t('RICH_MESSAGE.CONTACT.SHARED', { sender: name }) : '';
});
</script>

<template>
  <SharedCard
    bubble-name="rich-contact"
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-[#D6409F]"
    :heading="heading"
    :title="textOf(richMessage.name)"
    :detail="textOf(richMessage.phone)"
  />
</template>
