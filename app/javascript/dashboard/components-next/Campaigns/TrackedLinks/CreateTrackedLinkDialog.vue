<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  inboxes: { type: Array, required: true },
  isSaving: { type: Boolean, default: false },
  error: { type: String, default: '' },
});
const emit = defineEmits(['create', 'open']);
const { t } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const dialog = ref(null);
const name = ref('');
const inboxId = ref('');
const message = ref('');
const options = computed(() =>
  props.inboxes.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);
const inboxName = computed(
  () => props.inboxes.find(inbox => inbox.id === inboxId.value)?.name
);
const canCreate = computed(
  () => name.value.trim() && inboxId.value && !props.isSaving
);
const close = () => dialog.value.close();
const open = async () => {
  name.value = '';
  inboxId.value = '';
  message.value = '';
  emit('open');
  dialog.value.showModal();
  await nextTick();
  dialog.value.querySelector('input').focus();
};
const create = () => {
  if (!canCreate.value) return;
  emit('create', {
    name: name.value.trim(),
    inbox_id: inboxId.value,
    prefilled_text: message.value.trim(),
  });
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
      class="w-[min(64rem,calc(100vw-2rem))] max-h-[92vh] p-0 overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-xl backdrop:bg-black/50"
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
            <div>
              <h3 class="m-0 text-base font-semibold">
                {{ t(`${NS}.CREATE_HEADING`) }}
              </h3>
              <p class="m-0 mt-1 text-sm text-n-slate-11">
                {{ t(`${NS}.CREATE_HINT`) }}
              </p>
            </div>
            <Input
              v-model="name"
              :label="t(`${NS}.NAME`)"
              :placeholder="t(`${NS}.NAME_PLACEHOLDER`)"
              required
              :disabled="isSaving"
            />
            <div>
              <label
                id="tracked-link-inbox-label"
                class="block mb-2 text-sm font-medium"
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
            <div>
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
          <aside class="p-7 bg-n-slate-2 md:border-s border-n-weak">
            <p class="m-0 text-xs font-medium tracking-wide text-n-slate-11">
              {{ t(`${NS}.PREVIEW`) }}
            </p>
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
          </aside>
        </div>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 px-7 py-5 border-t border-n-weak"
        >
          <p class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.CREATED_TOGETHER`) }}
          </p>
          <div class="flex gap-3">
            <Button
              :label="t(`${NS}.CANCEL`)"
              slate
              outline
              type="button"
              :disabled="isSaving"
              @click="close"
            />
            <Button
              :label="t(`${NS}.CREATE`)"
              type="submit"
              :disabled="!canCreate"
              :is-loading="isSaving"
            />
          </div>
        </footer>
      </form>
    </dialog>
  </TeleportWithDirection>
</template>
