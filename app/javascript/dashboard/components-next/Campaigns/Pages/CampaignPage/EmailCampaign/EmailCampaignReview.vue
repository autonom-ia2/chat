<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useAlert } from 'dashboard/composables';
import { safeError } from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import RecipientImportStatus from './RecipientImportStatus.vue';

const props = defineProps({ campaign: { type: Object, required: true } });
const emit = defineEmits(['edit', 'recipients', 'sender', 'done']);
const { t, locale } = useI18n();
const store = useStore();
const canManage = useCanManage('campaign_manage');
const UX = 'CAMPAIGN.EMAIL_CAMPAIGN.WORKSPACE';
const delivery = ref('now');
const scheduleDate = ref('');
const scheduleTime = ref('');
const isLoading = ref(true);
const isSending = ref(false);
const errorMessage = ref('');
const confirmation = ref(null);
const preview = ref(null);
const validation = ref(null);
const readiness = computed(() => props.campaign.send_readiness);
const checks = computed(() => readiness.value?.checks || {});
const number = value => new Intl.NumberFormat(locale.value).format(value);
const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
const scheduledAt = computed(() => {
  if (!scheduleDate.value || !scheduleTime.value) return null;
  const date = new Date(`${scheduleDate.value}T${scheduleTime.value}`);
  return Number.isNaN(date.getTime()) ? null : date;
});
const canConfirm = computed(
  () =>
    readiness.value?.can_send &&
    !isLoading.value &&
    !isSending.value &&
    !errorMessage.value &&
    (delivery.value === 'now' || scheduledAt.value?.getTime() > Date.now())
);
const reload = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    await store.dispatch('emailCampaigns/getOne', props.campaign.id);
    validation.value = await store.dispatch(
      'emailCampaigns/validateTemplate',
      props.campaign.id
    );
  } catch (error) {
    errorMessage.value = safeError(t, error);
  } finally {
    isLoading.value = false;
  }
};
const openPreview = () => preview.value.open();
const confirm = async () => {
  await reload();
  if (!canConfirm.value) return;
  await nextTick();
  confirmation.value.open();
};
const send = async () => {
  isSending.value = true;
  errorMessage.value = '';
  try {
    await store.dispatch(
      delivery.value === 'now'
        ? 'emailCampaigns/sendNow'
        : 'emailCampaigns/schedule',
      delivery.value === 'now'
        ? props.campaign.id
        : {
            id: props.campaign.id,
            scheduledAt: scheduledAt.value.toISOString(),
          }
    );
    confirmation.value.close();
    useAlert(
      t(
        `${UX}.${delivery.value === 'now' ? 'SEND_SUCCESS' : 'SCHEDULE_SUCCESS'}`
      )
    );
    emit('done');
  } catch (error) {
    confirmation.value.close();
    errorMessage.value = safeError(t, error);
  } finally {
    isSending.value = false;
  }
};
onMounted(reload);
</script>

<template>
  <div class="min-h-0 flex-1 overflow-y-auto bg-n-slate-2">
    <div class="mx-auto w-full max-w-[90rem] p-5 lg:p-8">
      <p class="mb-5 flex items-center gap-2 text-xs text-n-slate-11">
        {{ t(`${UX}.CAMPAIGNS`)
        }}<span class="i-lucide-chevron-right size-3.5" />{{
          t(`${UX}.REVIEW_SEND`)
        }}
      </p>
      <header class="mb-7 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1
            class="mb-0 text-[1.75rem] font-semibold tracking-tight text-n-slate-12"
          >
            {{ t(`${UX}.REVIEW_TITLE`) }}
          </h1>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`${UX}.REVIEW_SUBTITLE`) }}
          </p>
        </div>
        <Button
          :label="t(`${UX}.BACK_EDITOR`)"
          icon="i-lucide-arrow-left"
          slate
          outline
          class="!min-h-11 !rounded-xl"
          @click="emit('edit')"
        />
      </header>
      <nav
        class="mb-6 flex flex-wrap gap-2 text-xs"
        :aria-label="t(`${UX}.STEPS`)"
      >
        <button
          class="flex min-h-11 items-center gap-2 rounded-lg px-3 text-n-slate-11"
          @click="emit('edit')"
        >
          <span
            class="flex size-6 items-center justify-center rounded-full bg-n-alpha-2"
            >{{ 1 }}</span
          >{{ t(`${UX}.CONTENT`) }}
        </button>
        <button
          class="flex min-h-11 items-center gap-2 rounded-lg px-3 text-n-slate-11"
          @click="emit('recipients', false)"
        >
          <span
            class="flex size-6 items-center justify-center rounded-full bg-n-alpha-2"
            >{{ 2 }}</span
          >{{ t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS') }}
        </button>
        <span
          class="flex min-h-11 items-center gap-2 rounded-lg bg-n-blue-3 px-3 font-medium text-n-blue-11"
          ><span
            class="flex size-6 items-center justify-center rounded-full bg-n-brand text-white"
            >{{ 3 }}</span
          >{{ t(`${UX}.REVIEW_SEND`) }}</span
        >
      </nav>
      <p
        v-if="errorMessage"
        role="alert"
        class="mb-5 rounded-xl bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>
      <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-5">
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
          >
            <header class="mb-5 flex items-center justify-between gap-3">
              <h2 class="mb-0 text-base font-semibold text-n-slate-12">
                {{ t(`${UX}.MESSAGE`) }}
              </h2>
              <Button
                :label="t(`${UX}.PREVIEW`)"
                icon="i-lucide-eye"
                slate
                ghost
                class="!min-h-11"
                :disabled="!campaign.body_html"
                @click="openPreview"
              />
            </header>
            <dl class="space-y-4 text-sm">
              <div>
                <dt class="text-xs text-n-slate-11">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SUBJECT_LABEL') }}
                </dt>
                <dd class="m-0 mt-1.5 font-medium text-n-slate-12">
                  {{ campaign.subject || t(`${UX}.NO_SUBJECT`) }}
                </dd>
              </div>
              <div>
                <dt class="text-xs text-n-slate-11">
                  {{ t(`${UX}.PREHEADER`) }}
                </dt>
                <dd class="m-0 mt-1.5 text-n-slate-11">
                  {{ campaign.preheader || '—' }}
                </dd>
              </div>
            </dl>
            <Button
              :label="t(`${UX}.EDIT_CONTENT`)"
              icon="i-lucide-pencil"
              slate
              outline
              class="mt-5 !min-h-11 !rounded-xl"
              @click="emit('edit')"
            />
          </section>
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
          >
            <header class="mb-5 flex items-center justify-between gap-3">
              <h2 class="mb-0 text-base font-semibold text-n-slate-12">
                {{ t(`${UX}.SENDER`) }}
              </h2>
              <Button
                v-if="canManage && campaign.status === 'draft'"
                :label="t('CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.EDIT')"
                slate
                ghost
                class="!min-h-11"
                @click="emit('sender')"
              />
            </header>
            <div class="grid gap-5 sm:grid-cols-2">
              <div>
                <p class="mb-1 text-xs text-n-slate-11">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_LABEL') }}
                </p>
                <p class="mb-0 break-words text-sm font-medium text-n-slate-12">
                  {{ campaign.from_name }} &lt;{{ campaign.from_email }}&gt;
                </p>
              </div>
              <div>
                <p class="mb-1 text-xs text-n-slate-11">
                  {{ t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_LABEL') }}
                </p>
                <p class="mb-0 break-words text-sm text-n-slate-12">
                  {{ campaign.reply_to || campaign.from_email }}
                </p>
              </div>
            </div>
            <p
              class="mb-0 mt-5 flex items-center gap-2 rounded-xl bg-n-alpha-1 p-3 text-xs text-n-slate-11"
            >
              <span class="i-lucide-shield-check size-4 shrink-0" />{{
                campaign.delivery_mode === 'direct_inbox'
                  ? t('CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.DIRECT_OPTION')
                  : campaign.sender_domain
              }}
            </p>
          </section>
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
          >
            <header class="mb-5 flex items-center justify-between gap-3">
              <h2 class="mb-0 text-base font-semibold text-n-slate-12">
                {{ t(`${UX}.AUDIENCE`) }}
              </h2>
              <Button
                :label="t(`${UX}.SEE_LIST`)"
                icon="i-lucide-users"
                slate
                ghost
                class="!min-h-11"
                @click="emit('recipients', false)"
              />
            </header>
            <div class="flex flex-wrap items-center gap-6">
              <div class="flex items-center gap-3">
                <span
                  class="flex size-11 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
                  ><span class="i-lucide-users size-5"
                /></span>
                <div>
                  <p
                    class="mb-0 text-2xl font-semibold tabular-nums text-n-slate-12"
                  >
                    {{
                      readiness ? number(readiness.eligible_recipients) : '—'
                    }}
                  </p>
                  <p class="mb-0 mt-1 text-xs text-n-slate-11">
                    {{ t(`${UX}.ELIGIBLE`) }}
                  </p>
                </div>
              </div>
              <button
                class="min-h-11 text-start"
                @click="emit('recipients', true)"
              >
                <p class="mb-0 text-sm font-medium text-n-slate-12">
                  {{ readiness ? number(readiness.protected_recipients) : '—' }}
                  {{ t(`${UX}.EXCLUDED`) }}
                </p>
                <p class="mb-0 mt-1 text-xs text-n-blue-11">
                  {{ t(`${UX}.REVIEW_EXCLUSIONS`) }}
                  <span class="i-lucide-arrow-right ms-1 inline-block size-3" />
                </p>
              </button>
            </div>
            <p
              class="mb-0 mt-5 rounded-xl bg-n-alpha-1 p-4 text-xs leading-5 text-n-slate-11"
            >
              {{ t(`${UX}.PROTECTION_NOTE`) }}
            </p>
            <RecipientImportStatus
              :campaign="campaign"
              :can-recover="canManage"
            />
          </section>
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
          >
            <h2 class="mb-4 text-base font-semibold text-n-slate-12">
              {{ t(`${UX}.WHEN`) }}
            </h2>
            <div class="grid gap-3 sm:grid-cols-2">
              <button
                v-for="option in ['now', 'later']"
                :key="option"
                class="flex min-h-20 items-start gap-3 rounded-xl border p-4 text-start"
                :class="
                  delivery === option
                    ? 'border-n-brand bg-n-blue-3'
                    : 'border-n-weak'
                "
                :aria-pressed="delivery === option"
                @click="delivery = option"
              >
                <span
                  class="mt-1 size-4 shrink-0 rounded-full border"
                  :class="
                    delivery === option
                      ? 'border-n-brand bg-n-brand'
                      : 'border-n-strong'
                  "
                /><span class="text-sm font-medium text-n-slate-12"
                  >{{ t(`${UX}.DELIVERY.${option}`)
                  }}<span
                    class="mt-1 block text-xs font-normal leading-5 text-n-slate-11"
                    >{{ t(`${UX}.DELIVERY_HINT.${option}`) }}</span
                  ></span
                >
              </button>
            </div>
            <div v-if="delivery === 'later'" class="mt-4 flex flex-wrap gap-3">
              <label class="text-xs text-n-slate-11"
                >{{ t(`${UX}.DATE`)
                }}<input
                  v-model="scheduleDate"
                  type="date"
                  :aria-label="t(`${UX}.DATE`)"
                  class="mt-2 block min-h-11 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12" /></label
              ><label class="text-xs text-n-slate-11"
                >{{ t(`${UX}.TIME`)
                }}<input
                  v-model="scheduleTime"
                  type="time"
                  :aria-label="t(`${UX}.TIME`)"
                  class="mt-2 block min-h-11 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
              /></label>
              <p class="mb-0 self-end py-3 text-xs text-n-slate-11">
                {{ timeZone }}
              </p>
            </div>
          </section>
        </div>
        <aside class="space-y-4">
          <section
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
          >
            <h2 class="mb-0 text-base font-semibold text-n-slate-12">
              {{ t(`${UX}.REVIEW_TITLE`) }}
            </h2>
            <p class="mb-0 mt-2 text-xs leading-5 text-n-slate-11">
              {{ campaign.name }}
            </p>
            <div class="my-5 border-y border-n-weak py-4">
              <p class="mb-0 text-xs text-n-slate-11">
                {{ t(`${UX}.FINAL_AUDIENCE`) }}
              </p>
              <p
                class="mb-0 mt-2 text-3xl font-semibold tabular-nums text-n-slate-12"
              >
                {{ readiness ? number(readiness.eligible_recipients) : '—' }}
                <span class="text-xs font-normal text-n-slate-11">{{
                  t('CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS')
                }}</span>
              </p>
            </div>
            <Spinner v-if="isLoading" />
            <ul v-else class="m-0 list-none space-y-4 p-0 text-xs">
              <li
                v-for="(ready, check) in checks"
                :key="check"
                class="flex items-start gap-2"
                :class="
                  ready ? 'text-n-slate-11' : 'font-medium text-n-amber-11'
                "
              >
                <span
                  class="size-4 shrink-0"
                  :class="
                    ready
                      ? 'i-lucide-circle-check text-n-teal-11'
                      : 'i-lucide-circle-alert text-n-amber-11'
                  "
                />{{ t(`${UX}.CHECKS.${check}`) }}
              </li>
            </ul>
            <div
              v-if="validation?.missing?.length"
              class="mt-4 rounded-xl bg-n-amber-3 p-3 text-xs leading-5 text-n-amber-11"
            >
              {{
                t(`${UX}.UNKNOWN_VARIABLES`, {
                  fields: validation.missing.join(', '),
                })
              }}
            </div>
            <div
              v-if="!isLoading && !readiness?.can_send"
              class="mt-5 rounded-xl bg-n-amber-3 p-4 text-xs leading-5 text-n-amber-11"
            >
              <p class="mb-0">{{ t(`${UX}.CORRECT_PENDING`) }}</p>
              <Button
                :label="t(`${UX}.COMPLETE_EMAIL`)"
                variant="link"
                amber
                class="mt-2 !min-h-11 !text-n-amber-11"
                @click="emit('edit')"
              />
            </div>
            <p
              v-else
              class="mb-0 mt-5 rounded-xl bg-n-blue-3 p-3 text-xs leading-5 text-n-blue-11"
            >
              {{ t(`${UX}.FINAL_CONFIRMATION_HINT`) }}
            </p>
            <Button
              v-if="canManage"
              :label="
                t(
                  `${UX}.${delivery === 'now' ? 'SEND_CAMPAIGN' : 'REVIEW_SCHEDULE'}`
                )
              "
              :icon="
                delivery === 'now' ? 'i-lucide-send' : 'i-lucide-calendar-days'
              "
              class="mt-4 !min-h-12 w-full !rounded-xl"
              :disabled="!canConfirm"
              @click="confirm"
            />
            <Button
              :label="t('EMAIL_CAMPAIGN_PROTECTION.REFRESH')"
              icon="i-lucide-refresh-cw"
              slate
              ghost
              class="mt-2 !min-h-11 w-full"
              :disabled="isLoading"
              @click="reload"
            />
          </section>
        </aside>
      </div>
    </div>
    <Dialog
      ref="confirmation"
      :title="
        t(`${UX}.${delivery === 'now' ? 'CONFIRM_SEND' : 'CONFIRM_SCHEDULE'}`)
      "
      :confirm-button-label="
        t(`${UX}.${delivery === 'now' ? 'CONFIRM_SEND' : 'CONFIRM_SCHEDULE'}`)
      "
      :is-loading="isSending"
      :disable-confirm-button="!canConfirm"
      @confirm="send"
    >
      <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-5 text-sm">
        <p class="mb-2 font-semibold text-n-slate-12">{{ campaign.name }}</p>
        <p class="mb-4 text-n-slate-11">{{ campaign.subject }}</p>
        <p class="mb-0 text-n-slate-12">
          {{
            t(`${UX}.CONFIRM_AUDIENCE`, {
              count: readiness?.eligible_recipients,
            })
          }}
        </p>
        <p v-if="delivery === 'later'" class="mb-0 mt-3 text-n-slate-11">
          {{ scheduledAt?.toLocaleString(locale) }} · {{ timeZone }}
        </p>
      </div>
    </Dialog>
    <Dialog
      ref="preview"
      :title="t(`${UX}.PREVIEW`)"
      width="3xl"
      :show-confirm-button="false"
      overflow-y-auto
      ><iframe
        :srcdoc="campaign.body_html"
        sandbox=""
        referrerpolicy="no-referrer"
        :title="t(`${UX}.PREVIEW`)"
        class="h-[60vh] w-full rounded-xl border border-n-weak bg-white"
    /></Dialog>
  </div>
</template>
