<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import RelationshipActionMenu from './RelationshipActionMenu.vue';

const props = defineProps({
  contact: { type: Object, required: true },
  isUpdating: { type: Boolean, default: false },
});
const emit = defineEmits(['toggleBlock']);
const { t } = useI18n();
const actions = computed(() => [
  {
    key: 'block',
    label: t(
      props.contact.blocked
        ? 'CONTACTS_LAYOUT.HEADER.UNBLOCK_CONTACT'
        : 'CONTACTS_LAYOUT.HEADER.BLOCK_CONTACT'
    ),
    icon: props.contact.blocked
      ? 'i-lucide-shield-check'
      : 'i-lucide-shield-ban',
    disabled: props.isUpdating,
  },
]);
</script>

<template>
  <div data-profile-actions class="flex w-full flex-wrap items-center gap-2">
    <ComposeConversation :contact-id="String(contact.id)">
      <template #trigger>
        <Button
          type="button"
          sm
          class="min-h-11"
          icon="i-lucide-message-square"
          :label="t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
        />
      </template>
    </ComposeConversation>
    <VoiceCallButton
      :phone="contact.phoneNumber"
      :contact-id="contact.id"
      :label="t('CONTACT_PANEL.CALL')"
      size="sm"
      class="min-h-11"
    />
    <RelationshipActionMenu
      :actions="actions"
      @select="emit('toggleBlock', contact.blocked)"
    />
  </div>
</template>
