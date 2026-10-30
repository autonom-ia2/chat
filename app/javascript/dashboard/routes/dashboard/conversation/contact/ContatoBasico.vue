<script setup>
// Contato da conversa para quem não pode ver contatos (#1849, decisão D7): nome, telefone e e-mail, que já vêm com a
// conversa, mais nova mensagem e ligar. A ficha completa fica com quem tem "Ver contatos".
import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import ComposeConversation from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import ContactInfoRow from './ContactInfoRow.vue';
import { nomeDoContatoNaTela } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

defineProps({
  contact: { type: Object, required: true },
  conversationId: { type: [Number, String], default: undefined },
});
</script>

<template>
  <div class="flex flex-col w-full gap-3 p-4" data-contato-basico>
    <Avatar
      :src="contact.thumbnail"
      :name="contact.name"
      :size="48"
      hide-offline-status
    />
    <h3
      class="my-0 text-base font-medium break-words text-n-slate-12 capitalize"
    >
      {{ nomeDoContatoNaTela(contact) }}
    </h3>
    <div class="flex flex-col items-start w-full gap-2">
      <ContactInfoRow
        :href="contact.email ? `mailto:${contact.email}` : ''"
        :value="contact.email"
        icon="mail"
        emoji="✉️"
        :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
        show-copy
      />
      <ContactInfoRow
        :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
        :value="contact.phone_number"
        icon="call"
        emoji="📞"
        :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
        show-copy
      />
    </div>
    <div class="flex items-center w-full gap-2">
      <ComposeConversation :contact-id="String(contact.id)">
        <template #trigger>
          <NextButton
            v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
            :aria-label="$t('CONTACT_PANEL.NEW_MESSAGE')"
            icon="i-ph-chat-circle-dots"
            slate
            faded
            sm
          />
        </template>
      </ComposeConversation>
      <VoiceCallButton
        :phone="contact.phone_number"
        :contact-id="contact.id"
        :conversation-id="conversationId"
        icon="i-lucide-phone"
        sm
        faded
        slate
        :tooltip-label="$t('CONTACT_PANEL.CALL')"
      />
    </div>
  </div>
</template>
