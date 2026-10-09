<script setup>
defineProps({
  checked: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  label: { type: String, required: true },
  ariaLabel: { type: String, default: '' },
});

const emit = defineEmits(['toggle']);
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="checked"
    :aria-label="ariaLabel || undefined"
    :disabled="disabled"
    class="inline-flex min-h-11 items-center gap-2 rounded-xl border px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
    :class="
      checked
        ? 'border-n-blue-7 bg-n-blue-3 text-n-blue-12'
        : 'border-n-weak bg-n-solid-1 text-n-slate-11'
    "
    @click="emit('toggle')"
  >
    <span
      class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors"
      :class="checked ? 'bg-n-blue-9' : 'bg-n-slate-6'"
      aria-hidden="true"
    >
      <span
        class="absolute size-4 rounded-full bg-white shadow transition-transform ltr:left-0.5 rtl:right-0.5"
        :class="checked ? 'ltr:translate-x-4 rtl:-translate-x-4' : ''"
      />
    </span>
    {{ label }}
  </button>
</template>
