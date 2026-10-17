<script setup>
// Contato enviado: `{ type: 'contact', name, phone, wa_id? }`, sem corpo. Nome e telefone como o cliente recebeu,
// sem "Salvar contato": o contato é nosso.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../../provider.js';
import SharedCard from '../SharedCard.vue';
import BaseBubble from '../../Base.vue';
import ContatoDoWhatsapp from '../../../../conversa-canal/midia/ContatoDoWhatsapp.vue';
import { usePele } from '../../../../conversa-canal/pele';

const { contentAttributes, sender } = useMessageContext();
const { t } = useI18n();
// #1702: com a pele do WhatsApp, o cartão de contato do app.
const pele = usePele();

// Nome e telefone vêm de quem chamou a API: só texto entra na tela.
const textOf = value => (typeof value === 'string' ? value : '');

const richMessage = computed(() => contentAttributes.value?.richMessage ?? {});

const heading = computed(() => {
  const name = sender?.value?.name;
  return name ? t('RICH_MESSAGE.CONTACT.SHARED', { sender: name }) : '';
});
</script>

<template>
  <BaseBubble v-if="pele" class="!p-[3px]" data-bubble-name="contact">
    <ContatoDoWhatsapp
      :nome="textOf(richMessage.name)"
      :telefone="textOf(richMessage.phone)"
    />
  </BaseBubble>
  <SharedCard
    v-else
    bubble-name="rich-contact"
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-ruby-9"
    :heading="heading"
    :title="textOf(richMessage.name)"
    :detail="textOf(richMessage.phone)"
  />
</template>
