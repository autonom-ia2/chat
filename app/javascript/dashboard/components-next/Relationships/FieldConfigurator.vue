<script setup>
import { computed, ref, watch, useId, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { selectDefinitions, attributeKey } from './presentation';

const props = defineProps({
  entity: { type: String, default: 'contact' },
  surface: { type: String, default: '' },
});
const { t } = useI18n();
const { accountId, attributesEnabled, companiesEnabled, state, load, save } =
  useRelationships();
const dialog = ref(null);
const inputId = useId();
const query = ref('');
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
const submit = async () => {
  if (busy.value || !attributesEnabled.value || !state.value.can_manage) return;
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
    class="px-2 py-1"
  >
    <Button
      v-if="state.can_manage"
      xs
      ghost
      :label="t('RELATIONSHIPS.CONFIGURE')"
      @click.stop="open"
    />
    <Button
      v-if="state.can_manage"
      xs
      ghost
      :label="t('RELATIONSHIPS.CREATE')"
      @click.stop="open(null, true)"
    />
    <p v-if="state.error" role="alert" class="text-xs text-n-ruby-11">
      {{ t('RELATIONSHIPS.LOAD_ERROR') }}
    </p>
    <Button
      v-if="state.error"
      xs
      ghost
      :label="t('RELATIONSHIPS.RETRY')"
      @click="load"
    />
    <Dialog
      ref="dialog"
      :title="t('RELATIONSHIPS.CONFIGURE')"
      :description="t('RELATIONSHIPS.GLOBAL')"
      :confirm-button-label="t('RELATIONSHIPS.SAVE')"
      :is-loading="busy"
      :disable-confirm-button="
        Boolean(
          draft &&
            (!draft.attribute_display_name.trim() ||
              (!draft.id && !draft.attribute_description.trim()))
        )
      "
      overflow-y-auto
      width="2xl"
      @confirm="submit"
      @close="onClose"
    >
      <div class="flex flex-col gap-4 max-h-[65vh] overflow-auto">
        <p v-if="state.stale" role="alert" class="text-n-ruby-11">
          {{ t('RELATIONSHIPS.LOAD_ERROR') }}
        </p>
        <Button
          v-if="state.stale"
          :label="t('RELATIONSHIPS.RETRY')"
          @click="load"
        />
        <p v-if="error" role="alert" class="text-n-ruby-11">{{ error }}</p>
        <p class="text-sm">
          {{
            t('RELATIONSHIPS.ENTITY_VALUE', {
              name: t(
                activeEntity === 'company'
                  ? 'RELATIONSHIPS.COMPANIES'
                  : activeEntity === 'contact'
                    ? 'RELATIONSHIPS.CONTACTS'
                    : 'ATTRIBUTES_MGMT.TABS.CONVERSATION'
              ),
            })
          }}
        </p>
        <template v-if="draft">
          <label :for="`${inputId}-name`">
            <span>{{ t('RELATIONSHIPS.NAME') }}</span>
            <Input
              :id="`${inputId}-name`"
              v-model="draft.attribute_display_name"
              autofocus
              required
              type="text"
            />
          </label>
          <label :for="`${inputId}-description`">
            <span>{{ t('RELATIONSHIPS.DESCRIPTION') }}</span>
            <TextArea
              :id="`${inputId}-description`"
              v-model="draft.attribute_description"
              :required="!draft.id"
            />
          </label>
          <ChoiceSelect
            v-model="draft.attribute_display_type"
            :options="types"
            :disabled="Boolean(draft.id)"
            :aria-label="t('RELATIONSHIPS.TYPE')"
          />
          <label
            v-if="draft.attribute_display_type === 'list'"
            :for="`${inputId}-options`"
          >
            <span>{{ t('RELATIONSHIPS.OPTIONS') }}</span>
            <TextArea
              :id="`${inputId}-options`"
              v-model="listOptions"
              :max-length="10000"
            />
          </label>
          <label
            v-for="surfaceName in surfaces"
            :key="surfaceName"
            class="flex gap-2 items-center"
          >
            <input v-model="displayOn" type="checkbox" :value="surfaceName" />
            <span>{{ t(`RELATIONSHIPS.SURFACES.${surfaceName}`) }}</span>
          </label>
          <Button
            type="button"
            faded
            :label="t('RELATIONSHIPS.BACK')"
            @click="draft = null"
          />
        </template>
        <template v-else>
          <label :for="`${inputId}-search`">
            <span>{{ t('RELATIONSHIPS.SEARCH') }}</span>
            <Input
              :id="`${inputId}-search`"
              v-model="query"
              type="search"
              autofocus
            />
          </label>
          <Button
            type="button"
            :label="t('RELATIONSHIPS.CREATE')"
            @click="edit(null)"
          />
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
          />
          <section
            v-for="surfaceName in visibleSurfaces"
            :key="surfaceName"
            class="flex flex-col gap-2"
          >
            <div class="flex items-center justify-between gap-2">
              <h4>{{ t(`RELATIONSHIPS.SURFACES.${surfaceName}`) }}</h4>
              <Button
                type="button"
                xs
                ghost
                :label="t('RELATIONSHIPS.RESTORE')"
                @click="layout[surfaceName] = { mode: 'legacy', ids: [] }"
              />
            </div>
            <div
              v-for="definition in definitions"
              :key="definition.id"
              class="flex items-center justify-between gap-2"
            >
              <label class="flex items-center gap-2">
                <input
                  type="checkbox"
                  :checked="selected(surfaceName, definition.id)"
                  @change="
                    toggle(surfaceName, definition.id, $event.target.checked)
                  "
                />
                <span>{{ definition.attribute_display_name }}</span>
              </label>
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
        </template>
      </div>
    </Dialog>
  </div>
  <template v-else />
</template>
