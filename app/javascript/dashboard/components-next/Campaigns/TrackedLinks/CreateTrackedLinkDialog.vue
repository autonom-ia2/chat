<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import TrackedLinkWebsitePreview from './TrackedLinkWebsitePreview.vue';
import AllowedOriginsField from './AllowedOriginsField.vue';
import { parseAllowedOrigins } from './trackedLinkWebsite';

const props = defineProps({
  inboxes: { type: Array, required: true },
  isSaving: { type: Boolean, default: false },
  error: { type: String, default: '' },
});
const emit = defineEmits(['create', 'open']);
const { t, locale } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const USAGES = [
  { id: 'direct', icon: 'i-lucide-qr-code' },
  { id: 'website', icon: 'i-lucide-globe' },
];
const dialog = ref(null);
const inboxField = ref(null);
const usage = ref('direct');
const name = ref('');
const inboxId = ref('');
const message = ref('');
const originsText = ref('');
const originsTouched = ref(false);
const isWebsite = computed(() => usage.value === 'website');
const options = computed(() =>
  props.inboxes.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);
const inboxName = computed(
  () => props.inboxes.find(inbox => inbox.id === inboxId.value)?.name
);
const origins = computed(() => parseAllowedOrigins(originsText.value));
const canCreate = computed(
  () =>
    name.value.trim() &&
    inboxId.value &&
    !props.isSaving &&
    (!isWebsite.value || origins.value.isValid)
);
// A disabled button says nothing on its own: list what is still missing next to
// it, in the order of the form.
const missingFields = computed(() => {
  if (props.isSaving) return [];
  return [
    !name.value.trim() && 'MISSING_NAME',
    !inboxId.value && 'MISSING_INBOX',
    isWebsite.value && !origins.value.isValid && 'MISSING_ORIGINS',
  ].filter(Boolean);
});
const missingHint = computed(() => {
  if (!missingFields.value.length) return '';
  const list = new Intl.ListFormat(locale.value.replace('_', '-'), {
    type: 'conjunction',
  }).format(missingFields.value.map(key => t(`${NS}.${key}`)));
  return t(`${NS}.CREATE_MISSING`, { list });
});
// ChoiceSelect names its combobox with aria-label (same text as this label);
// clicking the visible label moves focus to it, as a native <label for> would.
const focusInbox = () =>
  inboxField.value?.querySelector('[role="combobox"]')?.focus();
const close = () => dialog.value.close();
const open = async () => {
  usage.value = 'direct';
  name.value = '';
  inboxId.value = '';
  message.value = '';
  originsText.value = '';
  originsTouched.value = false;
  emit('open');
  dialog.value.showModal();
  await nextTick();
  dialog.value.querySelector('input:checked').focus();
};
const create = () => {
  originsTouched.value = true;
  if (!canCreate.value) return;
  const base = { name: name.value.trim(), inbox_id: inboxId.value };
  emit(
    'create',
    isWebsite.value
      ? { ...base, usage: 'website', allowed_origins: origins.value.origins }
      : { ...base, usage: 'direct', prefilled_text: message.value.trim() }
  );
};
const cancel = event => {
  if (props.isSaving) event.preventDefault();
};
defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection>
    <dialog
      ref="dialog"
      aria-labelledby="tracked-link-create-title"
      class="w-[min(60rem,calc(100vw-2rem))] max-h-[92vh] p-0 overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-xl backdrop:bg-modal-backdrop-light backdrop:backdrop-blur-[4px] dark:backdrop:bg-modal-backdrop-dark"
      @cancel="cancel"
    >
      <form @submit.prevent="create">
        <header
          class="flex items-center justify-between gap-4 px-7 py-5 border-b border-n-weak"
        >
          <div>
            <p class="m-0 text-xs font-medium text-n-slate-11">
              {{ t(`${NS}.TITLE`) }}
            </p>
            <h2
              id="tracked-link-create-title"
              class="m-0 mt-1 text-xl font-semibold"
            >
              {{ t(`${NS}.NEW`) }}
            </h2>
          </div>
          <Button
            icon="i-lucide-x"
            slate
            ghost
            :aria-label="t(`${NS}.CLOSE`)"
            type="button"
            :disabled="isSaving"
            @click="close"
          />
        </header>
        <div class="grid md:grid-cols-[minmax(0,1fr)_22rem]">
          <div class="flex flex-col gap-6 p-7 min-w-0">
            <fieldset class="m-0 min-w-0 border-0 p-0">
              <legend class="mb-3 p-0 text-base font-semibold">
                {{ t(`${NS}.USAGE_LEGEND`) }}
              </legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <label
                  v-for="option in USAGES"
                  :key="option.id"
                  :data-testid="`tracked-link-usage-${option.id}`"
                  class="flex min-h-11 cursor-pointer items-start gap-3 rounded-xl p-4 outline -outline-offset-1 transition-colors ring-offset-2 ring-offset-n-solid-1 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
                  :class="
                    usage === option.id
                      ? 'bg-n-blue-2 outline-2 outline-n-blue-9'
                      : 'bg-n-solid-1 outline-1 outline-n-weak hover:outline-n-strong'
                  "
                >
                  <input
                    v-model="usage"
                    type="radio"
                    name="tracked-link-usage"
                    :value="option.id"
                    :disabled="isSaving"
                    class="sr-only"
                  />
                  <span
                    class="flex size-9 shrink-0 items-center justify-center rounded-lg"
                    :class="
                      usage === option.id
                        ? 'bg-n-solid-1 text-n-blue-11'
                        : 'bg-n-alpha-2 text-n-slate-11'
                    "
                  >
                    <span class="size-5" :class="option.icon" />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block text-sm font-semibold">
                      {{ t(`${NS}.USAGE_${option.id.toUpperCase()}`) }}
                    </span>
                    <span class="mt-1 block text-xs text-n-slate-11">
                      {{ t(`${NS}.USAGE_${option.id.toUpperCase()}_HINT`) }}
                    </span>
                  </span>
                  <span
                    aria-hidden="true"
                    data-testid="tracked-link-usage-check"
                    class="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border"
                    :class="
                      usage === option.id
                        ? 'border-n-blue-9 bg-n-blue-9 text-white'
                        : 'border-n-slate-7'
                    "
                  >
                    <span
                      v-if="usage === option.id"
                      class="i-lucide-check size-3.5"
                    />
                  </span>
                </label>
              </div>
            </fieldset>
            <Input
              v-model="name"
              :label="t(`${NS}.NAME`)"
              :placeholder="
                t(
                  isWebsite
                    ? `${NS}.WEBSITE_NAME_PLACEHOLDER`
                    : `${NS}.NAME_PLACEHOLDER`
                )
              "
              required
              :disabled="isSaving"
            />
            <div ref="inboxField">
              <label
                id="tracked-link-inbox-label"
                class="block mb-2 text-sm font-medium"
                @click="focusInbox"
              >
                {{ t(`${NS}.DESTINATION`) }}
              </label>
              <ChoiceSelect
                v-model="inboxId"
                :options="options"
                :aria-label="t(`${NS}.DESTINATION`)"
                :placeholder="t(`${NS}.CHOOSE_INBOX`)"
                :disabled="isSaving"
                class="w-full [&>button]:w-full"
              />
              <p class="m-0 mt-2 text-xs text-n-slate-11">
                {{ t(`${NS}.DESTINATION_HINT`) }}
              </p>
            </div>
            <AllowedOriginsField
              v-if="isWebsite"
              id="tracked-link-origins"
              v-model="originsText"
              :disabled="isSaving"
              :touched="originsTouched"
              @blur="originsTouched = true"
            />
            <div v-else>
              <label
                for="tracked-link-message"
                class="block mb-2 text-sm font-medium"
              >
                {{ t(`${NS}.MESSAGE_OPTIONAL`) }}
              </label>
              <textarea
                id="tracked-link-message"
                v-model="message"
                rows="3"
                :placeholder="t(`${NS}.MESSAGE_PLACEHOLDER`)"
                :disabled="isSaving"
                class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-3 text-sm text-n-slate-12 focus:ring-2 focus:ring-n-brand focus:outline-none"
              />
              <p class="m-0 mt-2 text-xs text-n-slate-11">
                {{ t(`${NS}.MESSAGE_HINT`) }}
              </p>
            </div>
            <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
              {{ error }}
            </p>
          </div>
          <!-- The website preview is illustrative and tall: below md it would push
               the Create button off screen, so phones skip it. QR stays as before. -->
          <aside
            class="p-7 bg-n-slate-2 md:border-s border-n-weak"
            :class="{ 'hidden md:block': isWebsite }"
          >
            <p class="m-0 text-xs font-medium tracking-wide text-n-slate-11">
              {{ t(`${NS}.PREVIEW`) }}
            </p>
            <TrackedLinkWebsitePreview
              v-if="isWebsite"
              :origin="origins.origins[0]"
              :inbox-name="inboxName"
              class="mt-5"
            />
            <template v-else>
              <div
                class="mt-5 p-5 text-center rounded-xl border border-n-weak bg-n-solid-1"
              >
                <div
                  class="mx-auto flex items-center justify-center size-36 rounded-xl bg-white text-slate-800"
                >
                  <span class="i-lucide-qr-code size-24" />
                </div>
                <h3 class="m-0 mt-4 text-base font-semibold break-words">
                  {{ name || t(`${NS}.YOUR_CAMPAIGN`) }}
                </h3>
                <p class="m-0 mt-1 text-xs text-n-slate-11">
                  {{ t(`${NS}.QR_AFTER_CREATE`) }}
                </p>
              </div>
              <div class="mt-6 rounded-xl bg-n-teal-3 p-4">
                <p class="m-0 mb-3 text-xs font-medium text-n-teal-11">
                  {{ inboxName || t(`${NS}.DESTINATION`) }}
                </p>
                <p
                  class="m-0 p-3 rounded-lg rounded-ss-none bg-n-solid-1 text-sm text-n-slate-12 whitespace-pre-wrap break-words"
                >
                  {{ message || t(`${NS}.MESSAGE_PLACEHOLDER`) }}
                </p>
                <p class="m-0 mt-3 text-xs text-n-slate-11">
                  {{ t(`${NS}.MESSAGE_PREVIEW`) }}
                </p>
              </div>
            </template>
          </aside>
        </div>
        <footer
          class="sticky bottom-0 z-10 flex flex-wrap items-center justify-between gap-3 border-t border-n-weak bg-n-solid-1 px-7 py-5"
        >
          <p class="m-0 text-xs text-n-slate-11">
            {{
              t(
                isWebsite
                  ? `${NS}.WEBSITE_CREATED_NOTE`
                  : `${NS}.CREATED_TOGETHER`
              )
            }}
          </p>
          <div class="flex flex-wrap items-center justify-end gap-3">
            <p
              v-if="missingHint"
              id="tracked-link-create-missing"
              data-testid="tracked-link-create-missing"
              class="m-0 flex basis-full items-center justify-end gap-1.5 text-xs text-n-slate-11"
            >
              <span
                class="i-lucide-info size-3.5 shrink-0"
                aria-hidden="true"
              />
              {{ missingHint }}
            </p>
            <Button
              :label="t(`${NS}.CANCEL`)"
              slate
              outline
              type="button"
              :disabled="isSaving"
              @click="close"
            />
            <Button
              :label="t(isWebsite ? `${NS}.CREATE_WEBSITE` : `${NS}.CREATE`)"
              type="submit"
              :disabled="!canCreate"
              :aria-describedby="
                missingHint ? 'tracked-link-create-missing' : undefined
              "
              :is-loading="isSaving"
            />
          </div>
        </footer>
      </form>
    </dialog>
  </TeleportWithDirection>
</template>
