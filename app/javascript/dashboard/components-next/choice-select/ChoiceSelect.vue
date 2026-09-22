<script setup>
// Escolha única do produto. Não usamos <select> nativo: a lista dele ignora o design
// system e muda de navegador para navegador. Teclado segue o padrão WAI-ARIA
// "select-only combobox" (dashboard/helper/choiceKeys.js). Portado do ChoiceSelect do Bio.
import { computed, nextTick, ref, useId, useTemplateRef, watch } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { choiceKeyAction, typeaheadIndex } from 'dashboard/helper/choiceKeys';

const props = defineProps({
  options: {
    type: Array,
    required: true,
    validator: options =>
      options.every(option => 'value' in option && 'label' in option),
  },
  ariaLabel: { type: String, required: true },
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const modelValue = defineModel({ type: [String, Number], default: '' });

const TYPEAHEAD_MS = 600;
const LIST_MAX_HEIGHT = 320;
const OPTION_HEIGHT = 44;

const id = useId();
const listId = `${id}-list`;
const optionId = index => `${id}-option-${index}`;

const root = useTemplateRef('root');
const trigger = useTemplateRef('trigger');
const list = useTemplateRef('list');

const isOpen = ref(false);
const active = ref(-1);
const opensUpward = ref(false);
const typed = { text: '', at: 0, from: -1 };

const selected = computed(() =>
  props.options.findIndex(option => option.value === modelValue.value)
);
const selectedLabel = computed(
  () => props.options[selected.value]?.label ?? props.placeholder
);

const show = index => {
  const rect = trigger.value?.getBoundingClientRect();
  if (rect) {
    const below = window.innerHeight - rect.bottom;
    const needed = Math.min(
      LIST_MAX_HEIGHT,
      props.options.length * OPTION_HEIGHT
    );
    // Abre para cima só quando não cabe embaixo e há mais espaço em cima.
    opensUpward.value = below < needed && rect.top > below;
  }
  active.value = index;
  isOpen.value = true;
};

function close(focus = true) {
  isOpen.value = false;
  active.value = -1;
  if (focus) trigger.value?.focus({ preventScroll: true });
}

const commit = (index, focus = true) => {
  const option = props.options[index];
  close(focus);
  if (option && option.value !== modelValue.value)
    modelValue.value = option.value;
};

const toggle = () => {
  if (props.disabled) return;
  if (isOpen.value) close();
  else show(selected.value >= 0 ? selected.value : 0);
};

const onTypeahead = event => {
  const now = Date.now();
  if (now - typed.at > TYPEAHEAD_MS) {
    typed.text = '';
    typed.from = isOpen.value ? active.value : selected.value;
  }
  typed.text += event.key;
  typed.at = now;
  const typingStart = isOpen.value ? active.value : selected.value;
  const from = typed.text.length === 1 ? typingStart : typed.from;
  const match = typeaheadIndex(
    props.options.map(option => option.label),
    typed.text,
    from
  );
  if (match >= 0) {
    if (isOpen.value) active.value = match;
    else show(match);
  }
};

const onKeydown = event => {
  if (props.disabled) return;
  const isModified = event.ctrlKey || event.metaKey || event.altKey;
  const isSpaceInsideTyping =
    event.key === ' ' && typed.text && Date.now() - typed.at <= TYPEAHEAD_MS;
  if (
    (event.key.length === 1 && !isModified && event.key !== ' ') ||
    isSpaceInsideTyping
  ) {
    event.preventDefault();
    onTypeahead(event);
    return;
  }
  const action = choiceKeyAction({
    key: event.key,
    altKey: event.altKey,
    open: isOpen.value,
    active: active.value,
    selected: selected.value,
    count: props.options.length,
  });
  if (action.type === 'none') return;
  if (action.type === 'commit' && action.keepDefault) {
    commit(action.active, false);
    return;
  }
  event.preventDefault();
  if (action.type === 'open') show(action.active);
  else if (action.type === 'move') active.value = action.active;
  else if (action.type === 'commit') commit(action.active);
  else close();
};

const onBlur = event => {
  if (isOpen.value && !root.value?.contains(event.relatedTarget)) close(false);
};

watch([isOpen, active], async () => {
  if (!isOpen.value || active.value < 0) return;
  await nextTick();
  list.value?.children[active.value]?.scrollIntoView({ block: 'nearest' });
});

onClickOutside(root, () => {
  if (isOpen.value) close(false);
});
</script>

<template>
  <div ref="root" class="relative min-w-40">
    <button
      ref="trigger"
      type="button"
      role="combobox"
      :aria-label="ariaLabel"
      aria-haspopup="listbox"
      :aria-expanded="isOpen"
      :aria-controls="listId"
      :aria-activedescendant="
        isOpen && active >= 0 ? optionId(active) : undefined
      "
      :disabled="disabled"
      class="flex items-center justify-between w-full gap-2 px-3 text-sm text-start rounded-lg min-h-11 bg-n-surface-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak hover:enabled:outline-n-slate-6 focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
      @click="toggle"
      @keydown="onKeydown"
      @blur="onBlur"
    >
      <span class="truncate">{{ selectedLabel }}</span>
      <span
        class="flex-shrink-0 size-4 text-n-slate-11"
        :class="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        aria-hidden="true"
      />
    </button>
    <ul
      v-show="isOpen"
      :id="listId"
      ref="list"
      role="listbox"
      :aria-label="ariaLabel"
      tabindex="-1"
      class="absolute z-50 w-full py-1 mb-0 overflow-y-auto rounded-lg shadow-lg max-h-80 bg-n-solid-2 outline outline-1 outline-n-container"
      :class="opensUpward ? 'bottom-full mb-1' : 'top-full mt-1'"
    >
      <li
        v-for="(option, index) in options"
        :id="optionId(index)"
        :key="option.value"
        role="option"
        :aria-selected="index === selected"
        class="flex items-center justify-between gap-2 px-3 text-sm cursor-pointer min-h-11 text-n-slate-12"
        :class="{
          'bg-n-alpha-2': index === active,
          'font-medium': index === selected,
        }"
        @pointerdown.prevent
        @pointermove="active = index"
        @click="commit(index)"
      >
        <span class="truncate">{{ option.label }}</span>
        <span
          v-if="index === selected"
          class="flex-shrink-0 i-lucide-check size-4 text-n-slate-11"
          aria-hidden="true"
        />
      </li>
    </ul>
  </div>
</template>
