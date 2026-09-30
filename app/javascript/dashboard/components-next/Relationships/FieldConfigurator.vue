<script setup>
import { computed, ref, watch, useId, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { selectDefinitions, attributeKey } from './presentation';

const props = defineProps({
  entity: { type: String, default: 'contact' },
  surface: { type: String, default: '' },
  compact: { type: Boolean, default: false },
  showActions: { type: Boolean, default: true },
});
const { t } = useI18n();
const { accountId, attributesEnabled, companiesEnabled, state, load, save } =
  useRelationships();
const dialog = ref(null);
const inputId = useId();
const query = ref('');
const directEntry = ref(false);
const draft = ref(null);
const layout = ref({});
const revision = ref(0);
const openedAccount = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
const onClose = () => {
  generation += 1;
  busy.value = false;
};
const displayOn = ref([]);
const selectedSurface = ref(props.surface);
const activeEntity = ref(props.entity);
const model = computed(() => `${activeEntity.value}_attribute`);
const surfaces = computed(() => {
  if (activeEntity.value === 'company') return ['company_details'];
  if (activeEntity.value === 'contact')
    return ['contact_sidebar', 'contact_details'];
  return [];
});
const visibleSurfaces = computed(() =>
  surfaces.value.filter(surface => surface === selectedSurface.value)
);
const definitions = computed(() =>
  state.value.definitions.filter(
    item =>
      item.attribute_model === model.value &&
      item.attribute_display_name
        .toLowerCase()
        .includes(query.value.toLowerCase())
  )
);
const types = computed(() => {
  const values = ['text', 'number', 'link', 'date', 'list', 'checkbox'];
  if (draft.value?.id && !values.includes(draft.value.attribute_display_type))
    values.push(draft.value.attribute_display_type);
  return values.map(value => ({
    value,
    label: t(`RELATIONSHIPS.TYPES.${value}`),
  }));
});
const key = computed(
  () =>
    draft.value?.attribute_key ||
    attributeKey(draft.value?.attribute_display_name || '')
);
const listOptions = ref('');
let initialOptions = '';
let initialDisplayOn = [];

const edit = definition => {
  draft.value = definition
    ? { ...definition }
    : {
        attribute_display_name: '',
        attribute_description: '',
        attribute_display_type: 'text',
      };
  listOptions.value = (definition?.attribute_values || []).join('\n');
  initialOptions = listOptions.value;
  displayOn.value = definition
    ? surfaces.value.filter(
        surface =>
          selectDefinitions([definition], { surfaces: layout.value }, surface)
            .length
      )
    : [props.surface].filter(Boolean);
  initialDisplayOn = [...displayOn.value];
};
const open = async (definition, create = false) => {
  generation += 1;
  const current = generation;
  const openingAccount = accountId.value;
  await load();
  if (openingAccount !== accountId.value || current !== generation) return;
  if (state.value.error || !state.value.can_manage) return;
  openedAccount.value = accountId.value;
  activeEntity.value = props.entity;
  directEntry.value = create || Boolean(definition?.id);
  selectedSurface.value = props.surface || surfaces.value[0] || '';
  revision.value = state.value.configuration.revision;
  layout.value = JSON.parse(JSON.stringify(state.value.configuration.surfaces));
  query.value = '';
  error.value = '';
  draft.value = null;
  dialog.value.open();
  if (create) edit(null);
  else if (definition?.id)
    edit(state.value.definitions.find(item => item.id === definition.id));
};
const selected = (surface, id) =>
  selectDefinitions(
    state.value.definitions.filter(
      item => item.attribute_model === model.value
    ),
    { surfaces: layout.value },
    surface
  ).some(item => item.id === id);
const toggle = (surface, id, checked) => {
  const ids = selectDefinitions(
    state.value.definitions.filter(
      item => item.attribute_model === model.value
    ),
    { surfaces: layout.value },
    surface
  )
    .map(item => item.id)
    .filter(value => value !== id);
  if (checked) ids.push(id);
  layout.value[surface] = { mode: 'custom', ids };
};
const invalidDraft = computed(() =>
  Boolean(
    draft.value &&
      (!draft.value.attribute_display_name.trim() ||
        (!draft.value.id && !draft.value.attribute_description.trim()))
  )
);
const dialogTitle = computed(() => {
  if (!draft.value) return t('RELATIONSHIPS.CONFIGURE');
  if (activeEntity.value === 'company')
    return t(
      draft.value.id
        ? 'RELATIONSHIPS.EDIT_COMPANY_ATTRIBUTE'
        : 'RELATIONSHIPS.CREATE_COMPANY_ATTRIBUTE'
    );
  return t(
    draft.value.id ? 'RELATIONSHIPS.EDIT_ATTRIBUTE' : 'RELATIONSHIPS.CREATE'
  );
});
const dialogDescription = computed(() => {
  if (!draft.value) return t('RELATIONSHIPS.CONFIGURE_DESCRIPTION');
  return t(
    draft.value.id
      ? 'RELATIONSHIPS.EDIT_DESCRIPTION'
      : 'RELATIONSHIPS.CREATE_DESCRIPTION'
  );
});
const confirmLabel = computed(() =>
  t(
    draft.value
      ? 'RELATIONSHIPS.SAVE_ATTRIBUTE'
      : 'RELATIONSHIPS.SAVE_CONFIGURATION'
  )
);
const displayToggle = (surfaceName, enabled) => {
  displayOn.value = displayOn.value.filter(value => value !== surfaceName);
  if (enabled) displayOn.value.push(surfaceName);
};
const selectionSummary = surfaceName =>
  t('RELATIONSHIPS.SELECTION_SUMMARY', {
    selected: definitions.value.filter(definition =>
      selected(surfaceName, definition.id)
    ).length,
    total: definitions.value.length,
  });
const submit = async () => {
  if (
    busy.value ||
    invalidDraft.value ||
    !attributesEnabled.value ||
    !state.value.can_manage
  )
    return;
  const current = generation;
  busy.value = true;
  error.value = '';
  const payload = {
    revision: revision.value,
    surfaces: Object.fromEntries(
      surfaces.value
        .filter(surface => layout.value[surface])
        .map(surface => [surface, layout.value[surface]])
    ),
  };
  if (draft.value) {
    const value = draft.value;
    payload.definition = {
      attribute_display_name: value.attribute_display_name,
      attribute_description: value.attribute_description,
      ...(value.id
        ? { id: value.id, revision: value.revision }
        : {
            attribute_key: key.value,
            attribute_model: model.value,
            attribute_display_type: value.attribute_display_type,
          }),
    };
    if (
      !value.id ||
      (value.attribute_display_type === 'list' &&
        listOptions.value !== initialOptions)
    ) {
      payload.definition.attribute_values =
        value.attribute_display_type === 'list'
          ? listOptions.value
              .split('\n')
              .map(option => option.trim())
              .filter(Boolean)
          : [];
    }
    if (
      !value.id ||
      JSON.stringify(displayOn.value) !== JSON.stringify(initialDisplayOn)
    )
      payload.display_on = displayOn.value;
  }
  try {
    await save(payload, openedAccount.value);
    if (current === generation && accountId.value === openedAccount.value)
      dialog.value.close();
  } catch (e) {
    if (current !== generation) return;
    error.value =
      e.response?.status === 409
        ? t('RELATIONSHIPS.CONFLICT')
        : t('RELATIONSHIPS.ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  [
    accountId,
    attributesEnabled,
    companiesEnabled,
    () => props.entity,
    () => state.value.can_manage,
  ],
  () => {
    onClose();
    dialog.value?.close();
    draft.value = null;
  }
);
onBeforeUnmount(onClose);
defineExpose({ open });
</script>

<template>
  <div
    v-if="attributesEnabled && (entity !== 'company' || companiesEnabled)"
    :class="showActions ? (compact ? 'px-2 py-1' : 'min-w-0') : 'contents'"
  >
    <div
      v-if="showActions && state.can_manage"
      class="flex flex-wrap items-center gap-2"
    >
      <Button
        type="button"
        :size="compact ? 'xs' : 'sm'"
        :variant="compact ? 'ghost' : 'outline'"
        :icon="compact ? '' : 'i-lucide-settings-2'"
        :label="t('RELATIONSHIPS.CONFIGURE')"
        @click.stop="open"
      />
      <Button
        type="button"
        :size="compact ? 'xs' : 'sm'"
        :variant="compact ? 'ghost' : 'solid'"
        :icon="compact ? '' : 'i-lucide-plus'"
        :label="t('RELATIONSHIPS.CREATE')"
        @click.stop="open(null, true)"
      />
    </div>
    <p v-if="state.error" role="alert" class="mt-2 text-xs text-n-ruby-11">
      {{ t('RELATIONSHIPS.LOAD_ERROR') }}
    </p>
    <Button
      v-if="state.error"
      type="button"
      xs
      ghost
      :label="t('RELATIONSHIPS.RETRY')"
      @click="load"
    />
    <Dialog
      ref="dialog"
      :title="dialogTitle"
      :description="dialogDescription"
      :confirm-button-label="confirmLabel"
      :is-loading="busy"
      :disable-confirm-button="invalidDraft"
      overflow-y-auto
      width="xl"
      @confirm="submit"
      @close="onClose"
    >
      <fieldset
        :disabled="busy"
        class="m-0 flex max-h-[65vh] min-w-0 flex-col gap-4 overflow-y-auto border-0 p-0"
      >
        <div v-if="state.stale" class="rounded-lg bg-n-amber-3 p-3">
          <p role="alert" class="text-sm text-n-amber-11">
            {{ t('RELATIONSHIPS.LOAD_ERROR') }}
          </p>
          <Button
            type="button"
            xs
            ghost
            :label="t('RELATIONSHIPS.RETRY')"
            @click="load"
          />
        </div>
        <p
          v-if="error"
          role="alert"
          class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ error }}
        </p>
        <div
          class="flex items-start gap-3 rounded-lg bg-n-blue-3 p-3 text-n-blue-11"
        >
          <Icon icon="i-lucide-info" class="mt-0.5 size-5 shrink-0" />
          <p class="text-xs leading-relaxed">
            {{ t('RELATIONSHIPS.GLOBAL_NOTE') }}
          </p>
        </div>
        <div class="flex items-center justify-between gap-3 text-sm">
          <span class="text-n-slate-11">{{ t('RELATIONSHIPS.ENTITY') }}</span>
          <span
            class="flex items-center gap-2 rounded-lg bg-n-slate-3 px-3 py-2 font-medium text-n-slate-12"
          >
            <Icon
              :icon="
                activeEntity === 'company'
                  ? 'i-lucide-building-2'
                  : activeEntity === 'contact'
                    ? 'i-lucide-user-round'
                    : 'i-lucide-message-square'
              "
              class="size-4"
            />
            {{ t(`RELATIONSHIPS.ENTITY_LABELS.${activeEntity}`) }}
          </span>
        </div>
        <template v-if="draft">
          <Button
            v-if="!directEntry"
            type="button"
            ghost
            xs
            icon="i-lucide-arrow-left"
            class="self-start"
            :label="t('RELATIONSHIPS.BACK')"
            @click="draft = null"
          />
          <label
            :for="`${inputId}-name`"
            class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          >
            <span>{{ t('RELATIONSHIPS.NAME') }}</span>
            <Input
              :id="`${inputId}-name`"
              v-model="draft.attribute_display_name"
              autofocus
              required
              type="text"
            />
          </label>
          <label
            :for="`${inputId}-description`"
            class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          >
            <span>{{ t('RELATIONSHIPS.DESCRIPTION') }}</span>
            <TextArea
              :id="`${inputId}-description`"
              v-model="draft.attribute_description"
              :required="!draft.id"
              :placeholder="t('RELATIONSHIPS.DESCRIPTION_HINT')"
            />
          </label>
          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">{{
              t('RELATIONSHIPS.TYPE')
            }}</span>
            <ChoiceSelect
              v-model="draft.attribute_display_type"
              :options="types"
              :disabled="Boolean(draft.id) || busy"
              :aria-label="t('RELATIONSHIPS.TYPE')"
              class="w-full"
            />
            <p class="text-xs text-n-slate-11">
              {{ t('RELATIONSHIPS.TYPE_HINT') }}
            </p>
          </div>
          <label
            v-if="draft.attribute_display_type === 'list'"
            :for="`${inputId}-options`"
            class="flex flex-col gap-2 text-sm font-medium text-n-slate-12"
          >
            <span>{{ t('RELATIONSHIPS.OPTIONS') }}</span>
            <TextArea
              :id="`${inputId}-options`"
              v-model="listOptions"
              :max-length="10000"
            />
          </label>
          <section
            v-if="surfaces.length"
            class="flex flex-col gap-3 border-t border-n-weak pt-4"
          >
            <h4 class="text-sm font-medium text-n-slate-12">
              {{ t('RELATIONSHIPS.DISPLAY_TITLE') }}
            </h4>
            <div
              v-for="surfaceName in surfaces"
              :key="surfaceName"
              class="flex items-start gap-3 py-1"
            >
              <Switch
                :model-value="displayOn.includes(surfaceName)"
                :disabled="busy"
                :aria-label="t(`RELATIONSHIPS.SURFACES.${surfaceName}`)"
                :aria-describedby="`${inputId}-${surfaceName}-help`"
                class="mt-1"
                @update:model-value="value => displayToggle(surfaceName, value)"
              />
              <div class="min-w-0">
                <p class="text-sm font-medium text-n-slate-12">
                  {{ t(`RELATIONSHIPS.SURFACES.${surfaceName}`) }}
                </p>
                <p
                  :id="`${inputId}-${surfaceName}-help`"
                  class="mt-1 text-xs leading-relaxed text-n-slate-11"
                >
                  {{ t(`RELATIONSHIPS.SURFACE_HELP.${surfaceName}`) }}
                </p>
              </div>
            </div>
          </section>
        </template>
        <template v-else>
          <div class="flex flex-col gap-2">
            <label
              :for="`${inputId}-search`"
              class="text-sm font-medium text-n-slate-12"
              >{{ t('RELATIONSHIPS.SEARCH') }}</label
            >
            <Input
              :id="`${inputId}-search`"
              v-model="query"
              type="search"
              autofocus
            />
          </div>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <ChoiceSelect
              v-if="surfaces.length"
              v-model="selectedSurface"
              :options="
                surfaces.map(value => ({
                  value,
                  label: t(`RELATIONSHIPS.SURFACES.${value}`),
                }))
              "
              :aria-label="t('RELATIONSHIPS.LOCATION')"
              :disabled="busy"
              class="min-w-0 max-w-full"
            />
            <Button
              type="button"
              sm
              icon="i-lucide-plus"
              :label="t('RELATIONSHIPS.CREATE')"
              @click="edit(null)"
            />
          </div>
          <section
            v-for="surfaceName in visibleSurfaces"
            :key="surfaceName"
            class="flex flex-col gap-3"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h4 class="text-sm font-medium text-n-slate-12">
                {{ t(`RELATIONSHIPS.SURFACES.${surfaceName}`) }}
              </h4>
              <p class="text-xs text-n-slate-11">
                {{ selectionSummary(surfaceName) }}
              </p>
              <Button
                type="button"
                xs
                ghost
                icon="i-lucide-rotate-ccw"
                :label="t('RELATIONSHIPS.RESTORE')"
                @click="layout[surfaceName] = { mode: 'legacy', ids: [] }"
              />
            </div>
            <div
              v-for="definition in definitions"
              :key="definition.id"
              class="flex items-center gap-3 rounded-lg border border-n-weak bg-n-background p-3"
            >
              <Switch
                :model-value="selected(surfaceName, definition.id)"
                :disabled="busy"
                :aria-label="definition.attribute_display_name"
                @update:model-value="
                  value => toggle(surfaceName, definition.id, value)
                "
              />
              <div class="min-w-0 flex-1">
                <p class="break-words text-sm font-medium text-n-slate-12">
                  {{ definition.attribute_display_name }}
                </p>
                <p
                  v-if="definition.attribute_description"
                  class="mt-1 line-clamp-2 text-xs leading-relaxed text-n-slate-11"
                >
                  {{ definition.attribute_description }}
                </p>
              </div>
              <Button
                type="button"
                xs
                ghost
                :label="t('RELATIONSHIPS.EDIT')"
                @click="edit(definition)"
              />
            </div>
          </section>
          <div v-if="!surfaces.length" class="flex flex-col gap-2">
            <Button
              v-for="definition in definitions"
              :key="definition.id"
              type="button"
              faded
              :label="definition.attribute_display_name"
              @click="edit(definition)"
            />
          </div>
          <p
            v-if="!definitions.length"
            class="py-5 text-center text-sm text-n-slate-11"
          >
            {{ t('RELATIONSHIPS.NO_DEFINITIONS') }}
          </p>
        </template>
      </fieldset>
      <template #footer>
        <div
          class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak pt-4"
        >
          <Button
            type="button"
            faded
            slate
            :label="t('DIALOG.BUTTONS.CANCEL')"
            @click="dialog.close()"
          />
          <Button
            type="submit"
            :label="confirmLabel"
            :is-loading="busy"
            :disabled="busy || invalidDraft"
          />
        </div>
      </template>
    </Dialog>
  </div>
  <template v-else />
</template>
