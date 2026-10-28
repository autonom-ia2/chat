<script setup>
// The in/out switch of the search by conversation (#2277): the same control everywhere a person can be put in
// or taken out (the list and the conversation beside it), with a 44 px touch target.
defineProps({
  on: { type: Boolean, default: false },
  label: { type: String, required: true },
});
const emit = defineEmits(['toggle']);
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="on"
    :aria-label="label"
    class="grid h-11 w-14 shrink-0 place-items-center rounded-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    data-test="toggle"
    @click="emit('toggle')"
  >
    <span
      class="relative h-6 w-11 rounded-full transition-colors"
      :class="on ? 'bg-n-blue-9' : 'bg-n-slate-6'"
      aria-hidden="true"
    >
      <span
        class="absolute top-0.5 size-5 rounded-full bg-white shadow transition-all"
        :class="on ? 'start-[1.375rem]' : 'start-0.5'"
      />
    </span>
  </button>
</template>
