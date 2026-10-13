<script setup>
// Link de agenda por cliente (#1190, J1): "Agendar" na conversa gera (ou reaproveita) o link do cliente,
// com o texto pronto para enviar na conversa ou copiar para qualquer canal. Autocontido: só aparece com a
// flag da conta `crm_booking_v2` e o calendário de reuniões da instalação ligados, e para quem vê os cards
// do CRM (mesma régua do backend, `HostEligibility`: administrador, agente sem função ou função com
// `crm_view`/`crm_admin`). A lógica mora em `useBookingInvite`, a mesma da tela "Mandar o link" do card do
// funil (#1423); aqui ela aparece numa janela.
import { computed, ref, toRef, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useBookingInvite } from './useBookingInvite';
import { stateLabelKey, stateToneClass } from './bookingInvite';

const props = defineProps({
  // Um dos dois: a conversa aberta (cabeçalho) ou o card.
  conversation: { type: Object, default: null },
  card: { type: Object, default: null },
  // Selo com o estado do último link ao lado do botão (card).
  showStatus: { type: Boolean, default: false },
});

const { t } = useI18n();
const textId = useId();

const dialogRef = ref(null);
const cancelConfirmRef = ref(null);

const {
  isLoading,
  isSending,
  isCanceling,
  isDisabledOnServer,
  isEnabled,
  hasNoPage,
  hasScope,
  invite,
  pageId,
  text,
  conversationId,
  contactName,
  pageOptions,
  pageTitle,
  validUntil,
  isInviteActive,
  shownState,
  textHasLink,
  badgeState,
  canOpenSettings,
  showSettingsShortcut,
  prepareInvite,
  changePage,
  newLink,
  copyLink,
  sendInConversation,
  cancelLink,
  openSettings,
} = useBookingInvite({
  conversation: toRef(props, 'conversation'),
  card: toRef(props, 'card'),
  withStatus: toRef(props, 'showStatus'),
});

const title = computed(() =>
  contactName.value
    ? t('CRM_KANBAN.BOOKING_INVITE.TITLE', { name: contactName.value })
    : t('CRM_KANBAN.BOOKING_INVITE.TITLE_NO_NAME')
);

const openPanel = () => {
  dialogRef.value?.open();
  prepareInvite();
};

const closePanel = () => dialogRef.value?.close();

// O servidor desligou o link: a janela fecha e o botão some.
watch(isDisabledOnServer, disabled => {
  if (disabled) closePanel();
});

const send = async () => {
  if (await sendInConversation()) closePanel();
};

// Cancelar é definitivo: pede confirmação num diálogo por cima (foco nele; Esc ou "Voltar" desistem).
const askCancel = () => cancelConfirmRef.value?.open();

const confirmCancel = async () => {
  await cancelLink();
  cancelConfirmRef.value?.close();
};

const goToSettings = () => {
  closePanel();
  openSettings();
};

// Separador visual entre dois trechos já traduzidos (não é texto a traduzir).
const SEPARATOR = ' · ';
</script>

<template>
  <div class="contents">
    <div v-if="isEnabled && hasScope" class="flex items-center gap-2">
      <NextButton
        type="button"
        icon="i-lucide-calendar-plus"
        :label="t('CRM_KANBAN.BOOKING_INVITE.BUTTON')"
        :title="t('CRM_KANBAN.BOOKING_INVITE.BUTTON_HINT')"
        aria-haspopup="dialog"
        slate
        faded
        sm
        class="relative before:absolute before:inset-x-0 before:-inset-y-1.5"
        data-booking-invite-trigger
        @click="openPanel"
      />
      <span
        v-if="showStatus && badgeState"
        class="rounded-full px-2 py-0.5 text-xs font-medium"
        :class="stateToneClass(badgeState)"
        data-booking-invite-badge
      >
        {{ t(stateLabelKey(badgeState)) }}
      </span>

      <Dialog
        ref="dialogRef"
        :title="title"
        :show-cancel-button="false"
        :show-confirm-button="false"
        width="md"
      >
        <div
          v-if="isLoading && !invite"
          role="status"
          class="py-6 text-center text-sm text-n-slate-11"
        >
          {{ t('CRM_KANBAN.BOOKING_INVITE.LOADING') }}
        </div>

        <div
          v-else-if="hasNoPage"
          class="flex flex-col gap-4"
          data-booking-empty
        >
          <p class="mb-0 text-sm text-n-slate-12">
            {{
              canOpenSettings
                ? t('CRM_KANBAN.BOOKING_INVITE.EMPTY.ADMIN')
                : t('CRM_KANBAN.BOOKING_INVITE.EMPTY.AGENT')
            }}
          </p>
          <NextButton
            v-if="showSettingsShortcut"
            type="button"
            lg
            icon="i-lucide-settings"
            :label="t('CRM_KANBAN.BOOKING_INVITE.EMPTY.OPEN_SETTINGS')"
            data-booking-open-settings
            @click="goToSettings"
          />
        </div>

        <div v-else-if="invite" class="flex flex-col gap-4">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p class="mb-0 text-sm text-n-slate-11">
              <template v-if="pageOptions.length <= 1">
                {{ t('CRM_KANBAN.BOOKING_INVITE.PAGE', { title: pageTitle })
                }}{{ SEPARATOR }}
              </template>
              {{
                t('CRM_KANBAN.BOOKING_INVITE.VALID_UNTIL', { date: validUntil })
              }}
            </p>
            <span
              role="status"
              class="rounded-full px-2 py-0.5 text-xs font-medium"
              :class="stateToneClass(shownState)"
              data-booking-invite-state
            >
              {{ t(stateLabelKey(shownState)) }}
            </span>
          </div>

          <ChoiceSelect
            v-if="pageOptions.length > 1"
            v-model="pageId"
            :options="pageOptions"
            :aria-label="t('CRM_KANBAN.BOOKING_INVITE.PAGE_LABEL')"
            :disabled="isLoading"
            @change="changePage"
          />

          <template v-if="isInviteActive">
            <div class="flex flex-col gap-1">
              <label :for="textId" class="text-sm font-medium text-n-slate-12">
                {{ t('CRM_KANBAN.BOOKING_INVITE.TEXT_LABEL') }}
              </label>
              <textarea
                :id="textId"
                v-model="text"
                rows="4"
                class="w-full resize-y rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2 text-sm text-n-slate-12 focus:outline-2 focus:outline-n-brand"
                :aria-describedby="textHasLink ? undefined : `${textId}-hint`"
                data-booking-invite-text
              />
              <p
                v-if="!textHasLink"
                :id="`${textId}-hint`"
                class="mb-0 text-xs text-n-ruby-11"
              >
                {{ t('CRM_KANBAN.BOOKING_INVITE.TEXT_NEEDS_LINK') }}
              </p>
            </div>

            <div class="flex flex-col gap-2 sm:flex-row">
              <NextButton
                v-if="conversationId"
                type="button"
                lg
                class="w-full sm:flex-1"
                icon="i-lucide-send"
                :label="t('CRM_KANBAN.BOOKING_INVITE.SEND')"
                :is-loading="isSending"
                :disabled="!textHasLink || isSending"
                data-booking-send
                @click="send"
              />
              <NextButton
                type="button"
                lg
                class="w-full sm:flex-1"
                :variant="conversationId ? 'outline' : 'solid'"
                :color="conversationId ? 'slate' : 'blue'"
                icon="i-lucide-copy"
                :label="t('CRM_KANBAN.BOOKING_INVITE.COPY')"
                data-booking-copy
                @click="copyLink"
              />
            </div>
          </template>

          <NextButton
            v-else
            type="button"
            lg
            icon="i-lucide-refresh-cw"
            :label="t('CRM_KANBAN.BOOKING_INVITE.NEW_LINK')"
            :is-loading="isLoading"
            data-booking-new
            @click="newLink"
          />
        </div>

        <div class="flex items-center justify-between gap-2">
          <NextButton
            v-if="invite && isInviteActive && !hasNoPage"
            type="button"
            ghost
            ruby
            class="min-h-11"
            :label="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_LINK')"
            :is-loading="isCanceling"
            data-booking-cancel
            @click="askCancel"
          />
          <span v-else />
          <NextButton
            type="button"
            ghost
            slate
            class="min-h-11"
            :label="t('CRM_KANBAN.BOOKING_INVITE.CLOSE')"
            data-booking-close
            @click="closePanel"
          />
        </div>
      </Dialog>

      <Dialog
        ref="cancelConfirmRef"
        type="alert"
        :title="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.TITLE')"
        :description="t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.DESCRIPTION')"
        :cancel-button-label="
          t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.BACK')
        "
        :confirm-button-label="
          t('CRM_KANBAN.BOOKING_INVITE.CANCEL_CONFIRM.YES')
        "
        :is-loading="isCanceling"
        width="sm"
        @confirm="confirmCancel"
      />
    </div>
  </div>
</template>
