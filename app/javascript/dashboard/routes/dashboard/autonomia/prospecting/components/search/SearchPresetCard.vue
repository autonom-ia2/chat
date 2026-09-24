<script setup>
// Cartão de uma jogada na grade (#677). Botão de alternar (aria-pressed), com
// alvo de toque de 44 px. "Sem jogada" usa borda tracejada quando livre.
defineProps({
  name: { type: String, required: true },
  pitch: { type: String, required: true },
  icon: { type: String, required: true },
  iconClass: { type: String, required: true },
  selected: { type: Boolean, default: false },
  isEmptyChoice: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);
</script>

<template>
  <button
    type="button"
    :aria-pressed="selected ? 'true' : 'false'"
    class="relative grid min-h-11 content-start gap-1.5 rounded-xl px-3.5 py-3 text-left transition hover:-translate-y-0.5 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    :class="[
      selected
        ? 'border-2 border-n-brand bg-n-solid-1 shadow-sm'
        : 'border border-n-weak bg-n-solid-1 hover:border-n-slate-7',
      isEmptyChoice && !selected ? 'border-dashed bg-transparent' : '',
    ]"
    @click="emit('select')"
  >
    <span
      v-if="selected"
      class="absolute right-2 top-2 inline-flex size-[18px] items-center justify-center rounded-full bg-n-brand text-white"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-3" />
    </span>
    <span class="flex min-w-0 items-center gap-2 pr-5">
      <span
        class="inline-flex size-7 shrink-0 items-center justify-center rounded-lg"
        :class="iconClass"
        aria-hidden="true"
      >
        <span class="size-3.5" :class="icon" />
      </span>
      <strong class="truncate text-[13px] font-semibold text-n-slate-12">
        {{ name }}
      </strong>
    </span>
    <span class="line-clamp-2 text-xs leading-snug text-n-slate-10">
      {{ pitch }}
    </span>
  </button>
</template>
