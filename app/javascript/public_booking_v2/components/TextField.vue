<script setup>
import { computed } from 'vue';

const props = defineProps({
  id: { type: String, required: true },
  label: { type: String, required: true },
  hint: { type: String, default: '' },
  error: { type: String, default: '' },
  type: { type: String, default: 'text' },
  autocomplete: { type: String, default: 'off' },
  inputmode: { type: String, default: undefined },
  required: { type: Boolean, default: false },
});

const model = defineModel({ type: String, default: '' });

const describedBy = computed(
  () =>
    [props.hint && `${props.id}-hint`, props.error && `${props.id}-error`]
      .filter(Boolean)
      .join(' ') || undefined
);
</script>

<template>
  <div class="flex flex-col gap-1">
    <label :for="id" class="text-base font-medium text-slate-800">
      {{ label }}
    </label>
    <input
      :id="id"
      v-model="model"
      :type="type"
      :autocomplete="autocomplete"
      :inputmode="inputmode"
      :required="required"
      :aria-invalid="error ? 'true' : undefined"
      :aria-describedby="describedBy"
      class="min-h-12 w-full rounded-xl border-2 bg-white px-4 py-3 text-base text-slate-900 focus:border-[var(--brand)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
      :class="error ? 'border-red-600' : 'border-slate-300'"
    />
    <p v-if="hint" :id="`${id}-hint`" class="text-base text-slate-600">
      {{ hint }}
    </p>
    <p
      v-if="error"
      :id="`${id}-error`"
      role="alert"
      class="text-base font-medium text-red-700"
    >
      {{ error }}
    </p>
  </div>
</template>
