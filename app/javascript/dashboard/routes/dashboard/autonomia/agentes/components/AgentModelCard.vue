<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  model: { type: Object, required: true },
  selected: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);
const { t } = useI18n();

const title = computed(
  () =>
    props.model.title ||
    (props.model.titleKey ? t(props.model.titleKey) : props.model.t || '')
);
const description = computed(
  () =>
    props.model.description ||
    (props.model.descriptionKey
      ? t(props.model.descriptionKey)
      : props.model.d || '')
);
const example = computed(
  () =>
    props.model.example ||
    (props.model.exampleKey ? t(props.model.exampleKey) : '')
);

const selectModel = () => emit('select', props.model.id);
</script>

<template>
  <button
    type="button"
    class="rounded-xl border bg-n-solid-1 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :class="[
      compact
        ? 'flex min-h-20 items-center gap-4 p-4'
        : 'grid min-h-52 gap-3 p-5',
      selected ? 'border-n-brand ring-2 ring-n-brand/20' : 'border-n-weak',
    ]"
    data-model-card
    :data-model-id="model.id"
    :aria-label="title"
    :aria-pressed="selected"
    @click="selectModel"
  >
    <span
      class="flex size-[3.25rem] shrink-0 items-center justify-center rounded-2xl"
      :class="model.tileClass || 'bg-n-slate-3'"
      aria-hidden="true"
    >
      <span
        class="size-[1.6rem]"
        :class="[
          model.icon || 'i-lucide-sparkles',
          model.iconClass || 'text-n-slate-11',
        ]"
      />
    </span>
    <span class="flex min-w-0 flex-col gap-1">
      <span class="text-sm font-semibold text-n-slate-12">{{ title }}</span>
      <span class="text-sm leading-relaxed text-n-slate-11">{{
        description
      }}</span>
    </span>
    <span
      v-if="example"
      class="border-t border-dashed border-n-weak pt-3 text-xs text-n-slate-11"
      :class="compact ? 'ms-auto hidden max-w-xs text-end sm:block' : 'mt-auto'"
    >
      {{ example }}
    </span>
  </button>
</template>
