<script setup>
import { ref, watch, computed, onBeforeUnmount, useId, nextTick } from 'vue';
import axios from 'dashboard/api/relationships';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useCompaniesStore } from 'dashboard/stores/companies';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CustomAttribute from 'dashboard/components/CustomAttribute.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import {
  attributeDate,
  formatAttributeDate,
} from 'dashboard/helper/attributeDate';
import { beginFieldWrite } from './confirmedValues';
import { fieldValue } from './presentation';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  definition: { type: Object, required: true },
  record: { type: Object, required: true },
  entity: { type: String, required: true },
  compact: { type: Boolean, default: false },
});
const fieldIcon = computed(
  () =>
    ({
      text: 'i-lucide-text',
      number: 'i-lucide-hash',
      currency: 'i-lucide-coins',
      percent: 'i-lucide-percent',
      date: 'i-lucide-calendar-days',
      link: 'i-lucide-link',
      list: 'i-lucide-list',
      checkbox: 'i-lucide-check-check',
    })[props.definition.attribute_display_type] || 'i-lucide-text'
);
const { t } = useI18n();
const { accountId } = useAccount();
const store = useStore();
const companies = useCompaniesStore();
const editing = ref(false);
const inputId = useId();
const editor = ref(null);
const editButton = ref(null);
const finishEditing = () => {
  editing.value = false;
  nextTick(() => editButton.value?.$el?.focus());
};
const focusInput = () =>
  nextTick(() =>
    editor.value?.querySelector('input, [role=combobox]')?.focus()
  );
const draft = ref('');
const previous = ref(null);
const busy = ref(false);
const error = ref('');
const saved = ref(false);
let generation = 0;
const value = computed(
  () =>
    (props.record.customAttributes || props.record.custom_attributes || {})[
      props.definition.attribute_key
    ]
);
const inputType = computed(
  () =>
    ({
      number: 'number',
      currency: 'number',
      percent: 'number',
      date: 'date',
      link: 'url',
    })[props.definition.attribute_display_type] || 'text'
);
const choices = computed(() =>
  (props.definition.attribute_values || []).map(option => ({
    value: option,
    label: option,
  }))
);
const hasValue = computed(
  () => value.value !== undefined && value.value !== null && value.value !== ''
);
const safeLink = computed(() => {
  if (props.definition.attribute_display_type !== 'link' || !hasValue.value)
    return '';
  try {
    const url = new URL(value.value);
    return ['http:', 'https:'].includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
});
const copy = async () => {
  try {
    await copyTextToClipboard(String(value.value));
  } catch {
    error.value = t('RELATIONSHIPS.ERROR');
  }
};
const start = () => {
  if (busy.value) return;
  previous.value = value.value ?? null;
  draft.value =
    value.value ??
    (props.definition.attribute_display_type === 'checkbox' ? false : '');
  if (props.definition.attribute_display_type === 'date')
    draft.value = attributeDate(value.value);
  editing.value = true;
  error.value = '';
  saved.value = false;
  focusInput();
};
const save = async () => {
  if (busy.value) return;
  generation += 1;
  const current = generation;
  const id = props.record.id;
  const account = accountId.value;
  const key = props.definition.attribute_key;
  const entity = props.entity;
  const submitted = fieldValue(
    props.definition.attribute_display_type,
    draft.value
  );
  const user = store.getters.getCurrentUserID;
  const confirm = beginFieldWrite(
    store,
    `${user}:${account}:${entity}:${id}:${key}`
  );
  let confirmed = submitted;
  busy.value = true;
  error.value = '';
  try {
    if (props.definition.regex_pattern) {
      const url = `/api/v1/accounts/${account}/${entity === 'contact' ? 'contacts' : 'companies'}/${id}`;
      if (submitted === null) {
        await axios.post(`${url}/destroy_custom_attributes`, {
          custom_attributes: [key],
        });
      } else {
        const patch = { custom_attributes: { [key]: submitted } };
        await axios.patch(
          url,
          entity === 'company' ? { company: patch } : patch
        );
      }
    } else {
      const { data } = await axios.patch(
        `/api/v1/accounts/${account}/relationships/${entity}/${id}/values`,
        { field: { key, value: submitted, previous: previous.value } }
      );
      confirmed = data.custom_attributes[key] ?? null;
    }
    if (
      current !== generation ||
      account !== accountId.value ||
      id !== props.record.id ||
      entity !== props.entity ||
      key !== props.definition.attribute_key ||
      user !== store.getters.getCurrentUserID ||
      !confirm()
    )
      return;
    // Read the live store after the response; a response for A must never replace B.
    const record =
      entity === 'contact'
        ? store.getters['contacts/getContact'](id)
        : companies.getRecord(id);
    const attributes = {
      ...(record.custom_attributes || record.customAttributes || {}),
    };
    if (confirmed === null) delete attributes[key];
    else attributes[key] = confirmed;
    if (entity === 'contact')
      store.commit('contacts/SET_CONTACT_ITEM', {
        id,
        custom_attributes: attributes,
      });
    else record.customAttributes = attributes;
    finishEditing();
    saved.value = true;
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
    () => store.getters.getCurrentUserID,
    () => props.record.id,
    () => props.definition.id,
    () => props.definition.attribute_key,
    () => props.entity,
  ],
  () => {
    generation += 1;
    editing.value = false;
    busy.value = false;
    error.value = '';
    saved.value = false;
  }
);
const saveLegacy = (_key, nextValue) => {
  start();
  draft.value = nextValue;
  return save();
};

onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <div
    ref="editor"
    :class="
      compact
        ? 'px-4 py-3 text-sm'
        : 'min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm'
    "
    role="group"
    :aria-label="definition.attribute_display_name"
    class="flex flex-col gap-1"
  >
    <fieldset
      v-if="definition.regex_pattern"
      :disabled="busy"
      class="border-0 p-0 m-0 min-w-0"
    >
      <CustomAttribute
        :key="`${accountId}-${entity}-${record.id}-${definition.id}`"
        :attribute-key="definition.attribute_key"
        :attribute-type="definition.attribute_display_type"
        :label="definition.attribute_display_name"
        :description="definition.attribute_description"
        :attribute-regex="definition.regex_pattern"
        :regex-cue="definition.regex_cue"
        :value="value ?? ''"
        :show-actions="!busy"
        @update="saveLegacy"
        @delete="saveLegacy(definition.attribute_key, null)"
        @copy="copy"
      />
    </fieldset>
    <template v-else>
      <div class="flex items-center gap-2">
        <div
          v-if="!compact"
          class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
        >
          <Icon :icon="fieldIcon" class="size-4" />
        </div>
        <span
          :id="`${inputId}-label`"
          class="min-w-0 break-words font-medium text-n-slate-12"
          >{{ definition.attribute_display_name }}</span
        >
        <details v-if="definition.attribute_description" class="relative">
          <summary
            class="list-none cursor-pointer rounded focus-visible:ring-2"
            :aria-label="definition.attribute_description"
          >
            <span class="i-lucide-info size-3.5 block text-n-slate-11" />
          </summary>
          <p
            :id="`${inputId}-description`"
            class="absolute z-20 start-0 top-5 w-48 p-2 text-xs rounded border border-n-weak bg-n-solid-2 shadow-md"
          >
            {{ definition.attribute_description }}
          </p>
        </details>
      </div>
      <template v-if="editing">
        <ChoiceSelect
          v-if="definition.attribute_display_type === 'list'"
          v-model="draft"
          :options="choices"
          :disabled="busy"
          :aria-label="definition.attribute_display_name"
        />
        <input
          v-else-if="definition.attribute_display_type === 'checkbox'"
          :id="`${inputId}-field`"
          v-model="draft"
          :disabled="busy"
          type="checkbox"
          :aria-label="definition.attribute_display_name"
          :aria-describedby="
            definition.attribute_description
              ? `${inputId}-description`
              : undefined
          "
        />
        <Input
          v-else
          :id="`${inputId}-field`"
          v-model="draft"
          :type="inputType"
          :disabled="busy"
          step="any"
          :aria-label="definition.attribute_display_name"
          :aria-describedby="
            definition.attribute_description
              ? `${inputId}-description`
              : undefined
          "
        />
        <div class="flex gap-2">
          <Button
            xs
            :label="t('RELATIONSHIPS.SAVE')"
            :disabled="busy"
            @click="save"
          />
          <Button
            xs
            ghost
            :label="t('RELATIONSHIPS.CANCEL')"
            :disabled="busy"
            @click="finishEditing"
          />
          <Button
            xs
            ghost
            :label="t('RELATIONSHIPS.CLEAR')"
            :disabled="busy"
            @click="draft = null"
          />
        </div>
      </template>
      <div v-else class="flex flex-wrap items-center justify-between gap-2">
        <a
          v-if="safeLink"
          :href="safeLink"
          target="_blank"
          rel="noopener noreferrer"
          class="break-all underline"
        >
          {{ value }}
        </a>
        <span
          v-else
          class="min-w-0 break-words"
          :class="
            typeof value === 'boolean'
              ? value
                ? 'rounded-md bg-n-teal-3 px-2 py-1 text-xs font-medium text-n-teal-11'
                : 'rounded-md bg-n-slate-3 px-2 py-1 text-xs font-medium text-n-slate-11'
              : hasValue
                ? 'text-n-slate-12'
                : 'text-n-slate-10'
          "
          >{{
            value === undefined || value === null || value === ''
              ? t('RELATIONSHIPS.EMPTY')
              : typeof value === 'boolean'
                ? t(value ? 'RELATIONSHIPS.YES' : 'RELATIONSHIPS.NO')
                : definition.attribute_display_type === 'date'
                  ? formatAttributeDate(value)
                  : value
          }}</span
        >
        <div class="flex gap-1 shrink-0">
          <Button
            v-if="hasValue"
            xs
            ghost
            icon="i-lucide-clipboard"
            :aria-label="t('RELATIONSHIPS.COPY')"
            @click="copy"
          />
          <Button
            ref="editButton"
            xs
            ghost
            icon="i-lucide-pen"
            :title="t('RELATIONSHIPS.EDIT')"
            :aria-label="t('RELATIONSHIPS.EDIT')"
            @click="start"
          />
          <Button
            v-if="hasValue"
            xs
            ghost
            icon="i-lucide-trash-2"
            :aria-label="t('RELATIONSHIPS.CLEAR')"
            @click="
              start();
              draft = null;
            "
          />
        </div>
      </div>
    </template>
    <p v-if="error" role="alert" class="text-n-ruby-11">{{ error }}</p>
    <p v-if="saved" role="status" class="text-n-slate-11">
      {{ t('RELATIONSHIPS.SAVED') }}
    </p>
  </div>
</template>
