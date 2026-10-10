<script setup>
// chat#1217 — Trocar a caixa de WhatsApp de conta (outra WABA / outro portfólio da Meta)
// sem perder a caixa. Roda o cadastro completo do Facebook e manda para o backend os IDs
// que a Meta devolve; o Reauthorize.vue do Chatwoot reenvia os IDs guardados e não serve
// para trocar de conta. A escolha entre app do celular (coexistência) e número direto
// acontece dentro da janela da Meta.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import InboxHealthAPI from 'dashboard/api/inboxHealth';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { setupFacebookSdk } from './utils';

const props = defineProps({
  inbox: { type: Object, required: true },
  healthData: { type: Object, default: null },
});

const emit = defineEmits(['switched']);

const PHONE_MISMATCH = 'phone_number_mismatch';

const { t } = useI18n();
const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

const dialogRef = ref(null);
const isDialogOpen = ref(false);
const isFlowRunning = ref(false);
const sdkState = ref('idle');
const step = ref('checklist');
const numberLeftOldAccount = ref(false);
const phoneAtHand = ref(false);
const showHowTo = ref(false);
const receivedNumber = ref('');
const isRetryingWebhook = ref(false);
const retryFailed = ref(false);

const phoneLabel = computed(
  () => props.healthData?.display_phone_number || props.inbox.phone_number
);
const ownerName = computed(() => props.healthData?.business_portfolio_name);
const displayName = computed(() => props.healthData?.verified_name);
const canOpenFacebook = computed(
  () =>
    numberLeftOldAccount.value &&
    phoneAtHand.value &&
    sdkState.value === 'ready'
);

const showDialog = () => {
  if (isDialogOpen.value) return;
  isDialogOpen.value = true;
  dialogRef.value?.open();
};

// O SDK carrega antes do clique: o navegador só abre a janela do Facebook se ela
// nascer do clique, sem espera longa no meio. O botão só libera com o SDK pronto.
const loadFacebookSdk = async () => {
  if (['loading', 'ready'].includes(sdkState.value)) return;
  sdkState.value = 'loading';
  try {
    await setupFacebookSdk(
      window.chatwootConfig?.whatsappAppId,
      window.chatwootConfig?.whatsappApiVersion
    );
    sdkState.value = 'ready';
  } catch {
    sdkState.value = 'error';
  }
};

// Fechar o diálogo não fecha a janela do Facebook. Enquanto o fluxo estiver vivo,
// reabrir mostra onde ele está, e o resultado reabre o diálogo sozinho.
const open = () => {
  if (!isFlowRunning.value) {
    step.value = 'checklist';
    numberLeftOldAccount.value = false;
    phoneAtHand.value = false;
    showHowTo.value = false;
    retryFailed.value = false;
  }
  showDialog();
  loadFacebookSdk();
};

const close = () => dialogRef.value?.close();
const onDialogClose = () => {
  isDialogOpen.value = false;
};

const saveNewAccount = async credentials => {
  step.value = 'connecting';
  try {
    const { data } = await whatsappChannel.reauthorizeWhatsApp({
      inboxId: props.inbox.id,
      ...credentials,
    });
    step.value = data.ready_to_receive === false ? 'not_ready' : 'done';
    emit('switched');
  } catch (error) {
    const body = error.response?.data || {};
    if (body.error_code === PHONE_MISMATCH) {
      receivedNumber.value = body.received_phone_number || '';
      step.value = 'mismatch';
    } else if (!error.response || error.response.status >= 500) {
      // Sem resposta não dá para saber se a troca foi gravada: recarrega a saúde da caixa.
      step.value = 'unknown';
      emit('switched');
    } else {
      step.value = 'failed';
    }
  }
};

const openFacebook = async () => {
  if (isFlowRunning.value) return;
  isFlowRunning.value = true;
  step.value = 'facebook';
  try {
    const credentials = await runEmbeddedSignup();
    if (credentials) {
      await saveNewAccount(credentials);
    } else {
      step.value = 'cancelled';
    }
  } catch {
    step.value = 'failed';
  } finally {
    isFlowRunning.value = false;
    showDialog();
  }
};

const retryWebhook = async () => {
  isRetryingWebhook.value = true;
  retryFailed.value = false;
  try {
    await InboxHealthAPI.registerWebhook(props.inbox.id);
    step.value = 'done';
    emit('switched');
  } catch {
    retryFailed.value = true;
  } finally {
    isRetryingWebhook.value = false;
  }
};

const RESULT_STEPS = [
  'done',
  'not_ready',
  'mismatch',
  'cancelled',
  'failed',
  'unknown',
];
const isResult = computed(() => RESULT_STEPS.includes(step.value));

const WARNING_LOOK = {
  icon: 'i-lucide-circle-alert',
  tone: 'bg-n-amber-3 text-n-amber-11',
};
const RESULT_LOOK = {
  done: { icon: 'i-lucide-check', tone: 'bg-n-teal-3 text-n-teal-11' },
  not_ready: WARNING_LOOK,
  mismatch: WARNING_LOOK,
  unknown: WARNING_LOOK,
  cancelled: { icon: 'i-lucide-info', tone: 'bg-n-slate-3 text-n-slate-11' },
  failed: { icon: 'i-lucide-x', tone: 'bg-n-ruby-3 text-n-ruby-11' },
};
const resultLook = computed(() => RESULT_LOOK[step.value]);

const tryAgain = () => {
  if (['failed', 'unknown'].includes(step.value)) {
    step.value = 'checklist';
    return;
  }
  openFacebook();
};

const resultKey = computed(() => step.value.toUpperCase());
</script>

<template>
  <section
    class="flex flex-col gap-4 p-5 mx-6 mb-6 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-wrap items-center gap-3">
      <span
        class="flex items-center justify-center flex-none rounded-xl size-11 bg-[#1FA855]"
      >
        <span class="text-white i-ri-whatsapp-fill size-6" />
      </span>
      <div class="flex flex-col min-w-0">
        <h3 class="text-base font-semibold text-n-slate-12">
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CARD.TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">{{ phoneLabel }}</p>
      </div>
    </div>
    <dl class="grid gap-3 m-0 sm:grid-cols-2">
      <div class="flex flex-col gap-0.5 px-4 py-3 rounded-lg bg-n-alpha-1">
        <dt class="text-xs text-n-slate-11">
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CARD.DISPLAY_NAME') }}
        </dt>
        <dd class="m-0 text-sm font-semibold text-n-slate-12">
          {{ displayName || '—' }}
        </dd>
      </div>
      <div class="flex flex-col gap-0.5 px-4 py-3 rounded-lg bg-n-alpha-1">
        <dt class="text-xs text-n-slate-11">
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CARD.OWNER') }}
        </dt>
        <dd class="m-0 text-sm font-semibold text-n-slate-12">
          {{ ownerName || '—' }}
        </dd>
      </div>
    </dl>
    <div
      class="flex flex-wrap items-center justify-between gap-3 pt-4 border-t border-n-weak"
    >
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CARD.HINT') }}
      </p>
      <Button
        :label="t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CARD.ACTION')"
        variant="outline"
        color="slate"
        class="min-h-11"
        data-test="switch-account-open"
        @click="open"
      />
    </div>
  </section>

  <Dialog
    ref="dialogRef"
    width="xl"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="onDialogClose"
  >
    <div class="flex flex-col gap-5">
      <header class="flex flex-col gap-1 px-5 py-4 rounded-xl bg-[#0D2344]">
        <span class="text-sm text-[#AFC0DA]">
          {{
            t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.DIALOG.KICKER', {
              phone: phoneLabel,
            })
          }}
        </span>
        <h2 class="text-xl font-semibold text-white">
          {{
            t(`INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.TITLES.${step.toUpperCase()}`)
          }}
        </h2>
      </header>

      <template v-if="step === 'checklist'">
        <p
          class="flex items-center gap-2 px-4 py-3 mb-0 text-sm rounded-lg bg-n-teal-3 text-n-teal-11"
        >
          <span class="flex-none i-lucide-check size-4" />
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.KEEP') }}
        </p>
        <label
          class="flex items-start gap-3 p-4 border cursor-pointer rounded-xl min-h-11"
          :class="
            numberLeftOldAccount
              ? 'border-n-brand bg-n-blue-2'
              : 'border-n-weak'
          "
          data-test="check-left-old-account"
        >
          <Checkbox v-model="numberLeftOldAccount" class="flex-none mt-1" />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-semibold text-n-slate-12">
              {{
                t(
                  'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.LEFT_OLD_ACCOUNT'
                )
              }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{
                t(
                  'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.LEFT_OLD_ACCOUNT_WHY'
                )
              }}
            </span>
          </span>
        </label>
        <div
          v-if="showHowTo"
          class="flex flex-col gap-2 px-4 py-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12"
        >
          <span class="font-semibold">
            {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_TITLE') }}
          </span>
          <ol class="flex flex-col gap-1 mb-0 ltr:pl-5 rtl:pr-5 list-decimal">
            <li>
              {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_1') }}
            </li>
            <li>
              {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_2') }}
            </li>
            <li>
              {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_3') }}
            </li>
          </ol>
          <span class="text-n-slate-11">
            {{
              t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_WARNING')
            }}
          </span>
        </div>
        <Button
          v-else
          variant="link"
          class="self-center min-h-11"
          :label="
            t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.HOW_TO_TITLE')
          "
          type="button"
          @click="showHowTo = true"
        />
        <label
          class="flex items-start gap-3 p-4 border cursor-pointer rounded-xl min-h-11"
          :class="phoneAtHand ? 'border-n-brand bg-n-blue-2' : 'border-n-weak'"
          data-test="check-phone-at-hand"
        >
          <Checkbox v-model="phoneAtHand" class="flex-none mt-1" />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-semibold text-n-slate-12">
              {{
                t(
                  'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.PHONE_AT_HAND',
                  { phone: phoneLabel }
                )
              }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{
                t(
                  'INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.PHONE_AT_HAND_WHY'
                )
              }}
            </span>
          </span>
        </label>
        <p
          v-if="sdkState === 'error'"
          class="mb-0 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CHECKLIST.SDK_ERROR') }}
        </p>
        <div class="flex flex-wrap justify-end gap-3">
          <Button
            :label="t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.NOT_NOW')"
            variant="faded"
            color="slate"
            type="button"
            class="min-h-11"
            @click="close"
          />
          <Button
            :label="
              t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.OPEN_FACEBOOK')
            "
            :disabled="!canOpenFacebook"
            type="button"
            class="min-h-11"
            data-test="switch-account-open-facebook"
            @click="openFacebook"
          />
        </div>
      </template>

      <ol
        v-else-if="step === 'facebook'"
        class="flex flex-col gap-4 mb-0 list-none ltr:pl-0 rtl:pr-0"
      >
        <li
          v-for="(item, index) in ['COMPANY', 'WHERE', 'COME_BACK']"
          :key="item"
          class="flex items-start gap-3"
        >
          <span
            class="flex items-center justify-center flex-none text-sm font-bold rounded-full size-8 bg-n-blue-3 text-n-blue-11"
          >
            {{ index + 1 }}
          </span>
          <span class="flex flex-col gap-1">
            <span class="text-sm font-semibold text-n-slate-12">
              {{ t(`INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.FACEBOOK.${item}`) }}
            </span>
            <span v-if="item !== 'WHERE'" class="text-sm text-n-slate-11">
              {{
                t(`INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.FACEBOOK.${item}_HINT`)
              }}
            </span>
            <span v-else class="grid gap-2 mt-1">
              <span
                v-for="option in ['APP', 'DIRECT']"
                :key="option"
                class="flex flex-col px-3 py-2 text-sm border rounded-lg border-n-weak"
              >
                <span class="font-semibold text-n-slate-12">
                  {{
                    t(`INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.FACEBOOK.${option}`)
                  }}
                </span>
                <span class="text-n-slate-11">
                  {{
                    t(
                      `INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.FACEBOOK.${option}_HINT`
                    )
                  }}
                </span>
              </span>
            </span>
          </span>
        </li>
      </ol>

      <div
        v-else-if="step === 'connecting'"
        class="flex flex-col items-center gap-3 py-6 text-center"
        role="status"
      >
        <span
          class="i-lucide-loader-circle animate-spin size-10 text-n-brand"
        />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.CONNECTING') }}
        </p>
      </div>

      <div
        v-else-if="isResult"
        class="flex flex-col items-center gap-3 py-2 text-center"
        :data-test="`switch-account-${step}`"
      >
        <span
          class="flex items-center justify-center rounded-full size-14"
          :class="resultLook.tone"
        >
          <span class="size-7" :class="resultLook.icon" />
        </span>
        <p class="max-w-md mb-0 text-sm text-n-slate-11">
          {{
            t(`INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.RESULTS.${resultKey}`, {
              phone: phoneLabel,
              received: receivedNumber,
            })
          }}
        </p>
        <p
          v-if="step === 'done'"
          class="w-full px-4 py-3 mb-0 text-sm rounded-lg text-start bg-n-alpha-1 text-n-slate-12"
        >
          {{
            t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.RESULTS.TEST_TIP', {
              phone: phoneLabel,
            })
          }}
        </p>
        <p
          v-if="step === 'not_ready' && retryFailed"
          class="mb-0 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.RESULTS.RETRY_FAILED') }}
        </p>
        <div class="flex flex-wrap justify-end w-full gap-3 pt-2">
          <Button
            v-if="step !== 'done'"
            :label="t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.CLOSE')"
            variant="faded"
            color="slate"
            type="button"
            class="min-h-11"
            @click="close"
          />
          <Button
            v-if="step === 'done'"
            :label="t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.FINISH')"
            type="button"
            class="min-h-11"
            @click="close"
          />
          <Button
            v-else-if="step === 'not_ready'"
            :label="
              t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.RETRY_RECEIVING')
            "
            :is-loading="isRetryingWebhook"
            type="button"
            class="min-h-11"
            @click="retryWebhook"
          />
          <Button
            v-else
            :label="t('INBOX_MGMT.WHATSAPP_SWITCH_ACCOUNT.ACTIONS.TRY_AGAIN')"
            type="button"
            class="min-h-11"
            data-test="switch-account-try-again"
            @click="tryAgain"
          />
        </div>
      </div>
    </div>
  </Dialog>
</template>
