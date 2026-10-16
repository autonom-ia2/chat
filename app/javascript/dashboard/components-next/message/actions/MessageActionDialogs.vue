<script setup>
// Reagir e editar pelo painel (chat#1709, fase 3). Message.vue abre um dos dois pelo menu da mensagem
// (`openReaction` / `openEdit`). A reação usa as seis do WhatsApp e o seletor de emoji do painel; a edição troca o
// texto no próprio diálogo. Quem atualiza a bolha é o evento `message.updated` do servidor.
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
import WahaMessageActionsApi from 'dashboard/api/wahaMessageActions';
import {
  businessReaction,
  EDIT_MAX_LENGTH,
  EDIT_WINDOW_MINUTES,
} from './messageActions.js';

const props = defineProps({
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
  content: { type: String, default: '' },
  reactions: { type: Array, default: () => [] },
});

const QUICK_REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const { t } = useI18n();
const reactionDialog = ref(null);
const editDialog = ref(null);
const showPicker = ref(false);
const draft = ref('');
const isSaving = ref(false);

// A reação da empresa (uma só por mensagem, de qualquer atendente ou do celular): trocar ou tirar vale para ela.
const current = computed(() => businessReaction(props.reactions));
const canSaveEdit = computed(
  () =>
    draft.value.trim().length > 0 &&
    draft.value !== props.content &&
    !isSaving.value
);

const errorOf = error =>
  error?.response?.data?.error || t('MESSAGE_ACTIONS.ERROR');

const react = async emoji => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    await WahaMessageActionsApi.react(
      props.conversationId,
      props.messageId,
      emoji
    );
    reactionDialog.value?.close();
  } catch (error) {
    useAlert(errorOf(error));
  } finally {
    isSaving.value = false;
  }
};

const saveEdit = async () => {
  if (!canSaveEdit.value) return;
  isSaving.value = true;
  try {
    await WahaMessageActionsApi.edit(
      props.conversationId,
      props.messageId,
      draft.value
    );
    editDialog.value?.close();
  } catch (error) {
    useAlert(errorOf(error));
  } finally {
    isSaving.value = false;
  }
};

const openReaction = () => {
  showPicker.value = false;
  reactionDialog.value?.open();
};

const openEdit = async () => {
  draft.value = props.content;
  await nextTick();
  editDialog.value?.open();
};

defineExpose({ openReaction, openEdit });
</script>

<template>
  <Dialog
    ref="reactionDialog"
    :title="t('MESSAGE_ACTIONS.REACT_TITLE')"
    :show-confirm-button="false"
    width="md"
  >
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap gap-2" data-quick-reactions>
        <button
          v-for="emoji in QUICK_REACTIONS"
          :key="emoji"
          type="button"
          class="flex items-center justify-center text-2xl rounded-lg min-w-11 min-h-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="{
            'bg-n-alpha-2 outline outline-1 outline-n-brand': emoji === current,
          }"
          :aria-pressed="emoji === current"
          :aria-label="t('MESSAGE_ACTIONS.REACT_WITH', { emoji })"
          :disabled="isSaving"
          @click="react(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          type="button"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-smile-plus"
          :label="t('MESSAGE_ACTIONS.MORE_EMOJIS')"
          @click="showPicker = !showPicker"
        />
        <Button
          v-if="current"
          type="button"
          variant="faded"
          color="ruby"
          size="sm"
          :label="t('MESSAGE_ACTIONS.REMOVE_REACTION')"
          :disabled="isSaving"
          @click="react('')"
        />
      </div>
      <div v-if="showPicker" class="relative h-[24rem]">
        <EmojiPicker class="!static" @select="item => react(item.value)" />
      </div>
    </div>
  </Dialog>
  <Dialog
    ref="editDialog"
    :title="t('MESSAGE_ACTIONS.EDIT_TITLE')"
    :description="
      t('MESSAGE_ACTIONS.EDIT_DESCRIPTION', { minutes: EDIT_WINDOW_MINUTES })
    "
    :confirm-button-label="t('MESSAGE_ACTIONS.EDIT_SAVE')"
    :disable-confirm-button="!canSaveEdit"
    :is-loading="isSaving"
    @confirm="saveEdit"
  >
    <TextArea
      v-model="draft"
      :label="t('MESSAGE_ACTIONS.EDIT_LABEL')"
      :max-length="EDIT_MAX_LENGTH"
      show-character-count
      auto-height
      autofocus
    />
  </Dialog>
</template>
