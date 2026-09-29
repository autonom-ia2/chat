<script setup>
import { ref, computed, watch } from 'vue';
import {
  attributeDate,
  formatAttributeDate,
} from 'dashboard/helper/attributeDate';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  attribute: {
    type: Object,
    required: true,
  },
  isEditingView: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update', 'delete']);

const { t } = useI18n();

const isEditingValue = ref(false);
const editedValue = ref(attributeDate(props.attribute.value));

watch(
  () => props.attribute.value,
  value => {
    if (!isEditingValue.value) editedValue.value = attributeDate(value);
  }
);

const rules = {
  editedValue: {
    required,
    isDate: value => Boolean(attributeDate(value)),
  },
};

const v$ = useVuelidate(rules, { editedValue });

const formattedDate = computed(() => {
  return props.attribute.value
    ? formatAttributeDate(props.attribute.value)
    : t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.TRIGGER.INPUT');
});

const hasError = computed(() => v$.value.$errors.length > 0);

const defaultDateValue = computed({
  get() {
    const existingDate = editedValue.value ?? props.attribute.value;
    if (existingDate) return attributeDate(existingDate);
    return isEditingValue.value && !hasError.value
      ? new Date().toISOString().slice(0, 10)
      : '';
  },
  set(value) {
    editedValue.value = value;
  },
});

const toggleEditValue = value => {
  isEditingValue.value =
    typeof value === 'boolean' ? value : !isEditingValue.value;

  if (isEditingValue.value) {
    v$.value.$reset();
    editedValue.value =
      attributeDate(props.attribute.value) ||
      new Date().toISOString().slice(0, 10);
  }
};

const handleInputUpdate = async () => {
  const isValid = await v$.value.$validate();
  if (!isValid) return;

  emit('update', attributeDate(editedValue.value));
  isEditingValue.value = false;
};
</script>

<template>
  <div
    class="flex items-center w-full min-w-0 gap-2"
    :class="{
      'justify-start': isEditingView,
      'justify-end': !isEditingView,
    }"
  >
    <span
      v-if="!isEditingValue"
      class="min-w-0 text-sm"
      :class="{
        'cursor-pointer text-n-slate-11 hover:text-n-slate-12 py-2 select-none font-medium':
          !isEditingView,
        'text-n-slate-12 truncate': isEditingView,
      }"
      @click="toggleEditValue(!isEditingView)"
    >
      {{ formattedDate }}
    </span>

    <div
      v-if="isEditingView && !isEditingValue"
      class="flex items-center gap-1"
    >
      <Button
        variant="faded"
        color="slate"
        icon="i-lucide-pencil"
        size="xs"
        class="flex-shrink-0 opacity-0 group-hover/attribute:opacity-100 hover:no-underline"
        @click="toggleEditValue(true)"
      />
      <Button
        variant="faded"
        color="ruby"
        icon="i-lucide-trash"
        size="xs"
        class="flex-shrink-0 opacity-0 group-hover/attribute:opacity-100 hover:no-underline"
        @click="emit('delete')"
      />
    </div>

    <div
      v-if="isEditingValue"
      v-on-clickaway="() => toggleEditValue(false)"
      class="flex items-center w-full"
    >
      <Input
        v-model="defaultDateValue"
        type="date"
        class="w-full [&>p]:absolute [&>p]:mt-0.5 [&>p]:top-8 ltr:[&>p]:left-0 rtl:[&>p]:right-0"
        :message="
          hasError
            ? t('CONTACTS_LAYOUT.SIDEBAR.ATTRIBUTES.VALIDATIONS.INVALID_DATE')
            : ''
        "
        :message-type="hasError ? 'error' : 'info'"
        autofocus
        custom-input-class="h-8 ltr:rounded-r-none rtl:rounded-l-none"
        @enter="handleInputUpdate"
      />
      <Button
        icon="i-lucide-check"
        :color="hasError ? 'ruby' : 'blue'"
        size="sm"
        class="flex-shrink-0 ltr:rounded-l-none rtl:rounded-r-none"
        @click="handleInputUpdate"
      />
    </div>
  </div>
</template>
