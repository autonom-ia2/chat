<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import Button from 'dashboard/components-next/button/Button.vue';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { parseAllowedOrigins, signalStatus } from './trackedLinkWebsite';

const props = defineProps({
  link: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['updated']);
const { t, locale } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const SIGNAL_TONES = {
  recent: { dot: 'bg-n-teal-9', text: 'text-n-teal-11', box: 'bg-n-teal-2' },
  stale: { dot: 'bg-n-amber-9', text: 'text-n-amber-11', box: 'bg-n-amber-2' },
  never: { dot: 'bg-n-slate-8', text: 'text-n-slate-11', box: 'bg-n-slate-2' },
};
const isEditing = ref(false);
const isSaving = ref(false);
const draft = ref('');
const saveError = ref('');

const status = computed(() => signalStatus(props.link.last_signal_at));
const tone = computed(() => SIGNAL_TONES[status.value]);
const signalLabel = computed(() =>
  status.value === 'never'
    ? t(`${NS}.SIGNAL_NEVER`)
    : t(`${NS}.SIGNAL_LAST`, {
        time: relativeTimeFromISO(props.link.last_signal_at, locale.value),
      })
);
const allowedOrigins = computed(() => props.link.allowed_origins || []);
const parsedDraft = computed(() => parseAllowedOrigins(draft.value));
const draftError = computed(() => {
  const parsed = parsedDraft.value;
  if (parsed.invalid.length) {
    return t(`${NS}.ORIGINS_INVALID`, { list: parsed.invalid.join(', ') });
  }
  if (parsed.isTooMany) return t(`${NS}.ORIGINS_TOO_MANY`);
  if (parsed.isEmpty) return t(`${NS}.ORIGINS_REQUIRED`);
  return '';
});

watch(
  () => props.link.id,
  () => {
    isEditing.value = false;
    saveError.value = '';
  }
);

const copy = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.COPIED'));
  } catch {
    useAlert(t(`${NS}.COPY_FAILED`));
  }
};
const startEditing = () => {
  draft.value = allowedOrigins.value.join('\n');
  saveError.value = '';
  isEditing.value = true;
};
const saveOrigins = async () => {
  if (!parsedDraft.value.isValid || isSaving.value) return;
  isSaving.value = true;
  saveError.value = '';
  try {
    const { data } = await CtwaTrackedLinksAPI.update(props.link.id, {
      allowed_origins: parsedDraft.value.origins,
    });
    emit('updated', data.payload);
    isEditing.value = false;
    useAlert(t(`${NS}.ORIGINS_SAVED`));
  } catch {
    saveError.value = t(`${NS}.ORIGINS_SAVE_ERROR`);
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="grid gap-6 px-6 py-5">
    <div
      role="status"
      class="flex items-center gap-2 rounded-lg px-3 py-2.5 text-xs font-medium"
      :class="[tone.box, tone.text]"
    >
      <span class="size-2 shrink-0 rounded-full" :class="tone.dot" />
      {{ signalLabel }}
    </div>
    <p
      v-if="link.signals_blocked"
      role="alert"
      data-testid="tracked-link-signals-blocked"
      class="m-0 -mt-3 flex items-start gap-2 rounded-lg bg-n-ruby-2 px-3 py-2.5 text-xs leading-relaxed text-n-ruby-11"
    >
      <span class="i-lucide-octagon-alert mt-0.5 size-4 shrink-0" />
      {{ t(`${NS}.SIGNALS_BLOCKED`) }}
    </p>

    <section>
      <h3 class="m-0 text-sm font-semibold">
        {{ t(`${NS}.AD_PARAMS_TITLE`) }}
      </h3>
      <p class="m-0 mt-1 text-xs leading-relaxed text-n-slate-11">
        {{ t(`${NS}.AD_PARAMS_HINT`) }}
      </p>
      <p
        class="m-0 mt-3 break-all rounded-lg border border-n-weak bg-n-slate-2 p-3 font-mono text-xs leading-relaxed"
      >
        {{ link.ad_url_params }}
      </p>
      <Button
        :label="t(`${NS}.COPY_AD_PARAMS`)"
        icon="i-lucide-copy"
        faded
        class="mt-3 h-11 w-full"
        @click="copy(link.ad_url_params)"
      />
    </section>

    <section>
      <div class="flex items-center justify-between gap-3">
        <h3 class="m-0 text-sm font-semibold">
          {{ t(`${NS}.ORIGINS_LABEL`) }}
        </h3>
        <Button
          v-if="canManage && !isEditing"
          :label="t(`${NS}.EDIT`)"
          slate
          ghost
          sm
          class="min-h-11"
          @click="startEditing"
        />
      </div>
      <form v-if="isEditing" class="mt-3" @submit.prevent="saveOrigins">
        <label for="tracked-link-origins-edit" class="sr-only">
          {{ t(`${NS}.ORIGINS_LABEL`) }}
        </label>
        <textarea
          id="tracked-link-origins-edit"
          v-model="draft"
          rows="3"
          spellcheck="false"
          autocapitalize="off"
          :placeholder="t(`${NS}.ORIGINS_PLACEHOLDER`)"
          :disabled="isSaving"
          :aria-invalid="!!draftError"
          aria-describedby="tracked-link-origins-edit-hint"
          class="w-full rounded-lg border bg-n-solid-2 px-3 py-3 font-mono text-xs text-n-slate-12 focus:ring-2 focus:ring-n-brand focus:outline-none"
          :class="draftError ? 'border-n-ruby-8' : 'border-n-weak'"
        />
        <p
          id="tracked-link-origins-edit-hint"
          class="m-0 mt-2 text-xs"
          :class="draftError ? 'text-n-ruby-11' : 'text-n-slate-11'"
        >
          {{ draftError || t(`${NS}.ORIGINS_HINT`) }}
        </p>
        <p
          v-if="saveError"
          role="alert"
          class="m-0 mt-2 text-xs text-n-ruby-11"
        >
          {{ saveError }}
        </p>
        <div class="mt-3 grid grid-cols-2 gap-2">
          <Button
            :label="t(`${NS}.CANCEL`)"
            slate
            outline
            type="button"
            class="h-11"
            :disabled="isSaving"
            @click="isEditing = false"
          />
          <Button
            :label="t(`${NS}.SAVE`)"
            type="submit"
            class="h-11"
            :disabled="!parsedDraft.isValid"
            :is-loading="isSaving"
          />
        </div>
      </form>
      <ul v-else-if="allowedOrigins.length" class="m-0 mt-3 grid gap-2 p-0">
        <li
          v-for="origin in allowedOrigins"
          :key="origin"
          class="flex min-w-0 list-none items-center gap-2 text-sm"
        >
          <span class="i-lucide-globe size-4 shrink-0 text-n-slate-10" />
          <span class="truncate" :title="origin">{{ origin }}</span>
        </li>
      </ul>
      <p v-else class="m-0 mt-3 text-sm text-n-amber-11">
        {{ t(`${NS}.ORIGINS_NONE`) }}
      </p>
    </section>

    <details class="group rounded-lg border border-n-weak">
      <summary
        class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 px-3 text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
      >
        <span class="flex items-center gap-2">
          <span class="i-lucide-code-xml size-4 text-n-slate-10" />
          {{ t(`${NS}.DEVELOPER_TITLE`) }}
        </span>
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
        />
      </summary>
      <div class="border-t border-n-weak px-3 pb-3 pt-3">
        <p class="m-0 text-xs leading-relaxed text-n-slate-11">
          {{ t(`${NS}.DEVELOPER_HINT`) }}
        </p>
        <p class="mb-1 mt-3 text-xs font-medium text-n-slate-11">
          {{ t(`${NS}.SIGNAL_URL`) }}
        </p>
        <p class="m-0 break-all rounded-lg bg-n-slate-2 p-3 font-mono text-xs">
          {{ link.signal_url }}
        </p>
        <p class="mb-1 mt-3 text-xs font-medium text-n-slate-11">
          {{ t(`${NS}.SOURCE_CODE`) }}
        </p>
        <p class="m-0 font-mono text-sm font-semibold">{{ link.code }}</p>
        <Button
          :label="t(`${NS}.COPY_SIGNAL_URL`)"
          icon="i-lucide-copy"
          slate
          outline
          class="mt-3 h-11 w-full"
          @click="copy(link.signal_url)"
        />
      </div>
    </details>
  </div>
</template>
