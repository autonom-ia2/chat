<script setup>
import { computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  CONVERSATION_LEVELS,
  LEVELS,
  SENSITIVE_EXTRAS,
  getLevel,
  isExtraLocked,
  levelSlots,
  setLevel,
  slotLevel,
  toggleExtra,
  visibleExtras,
  unmetSuggestion,
  suggestedLevel,
} from '../permissionMatrix';

const props = defineProps({
  module: { type: Object, required: true },
  permissions: { type: Array, required: true },
  isOpen: { type: Boolean, default: false },
  // key => null | 'MISSING' | 'DELEGATION': por que quem edita não pode pôr esta chave na função (#1931).
  keyLock: { type: Function, default: () => null },
});

const emit = defineEmits([
  'selectLevel',
  'toggleExtra',
  'toggleOpen',
  'grantSuggested',
]);

const level = computed(() => getLevel(props.module, props.permissions));
const hasAccess = computed(() => level.value !== LEVELS.NONE);
const activeSlot = computed(() => slotLevel(props.module, level.value));
// Conversas em "Atender": escolher entre as próprias e todas (#1800).
const isConversations = props.module.type === 'conversations';
const reachOptions = [CONVERSATION_LEVELS.LIMITED, CONVERSATION_LEVELS.ALL];
const showReach = computed(
  () => isConversations && activeSlot.value === LEVELS.MANAGE
);
const slots = computed(() => levelSlots(props.module, level.value));
const extras = computed(() => visibleExtras(props.module, props.permissions));
const extrasOn = computed(
  () => extras.value.filter(key => props.permissions.includes(key)).length
);
const suggestion = computed(() =>
  unmetSuggestion(props.module, props.permissions)
);

// Uma escolha que acrescentaria chave fora do alcance de quem edita fica travada, com o motivo.
// Tirar chave nunca trava. A chave de delegação tem o motivo mais específico.
const lockOf = next => {
  const reasons = next
    .filter(key => !props.permissions.includes(key))
    .map(props.keyLock)
    .filter(Boolean);
  return reasons.includes('DELEGATION') ? 'DELEGATION' : reasons[0] || null;
};
const levelLock = option =>
  option === activeSlot.value || option === level.value
    ? null
    : lockOf(setLevel(props.module, option, props.permissions));
const extraLock = key =>
  props.permissions.includes(key)
    ? null
    : lockOf(toggleExtra(props.module, key, props.permissions));
const suggestionLock = computed(
  () =>
    suggestion.value &&
    lockOf(
      setLevel(
        suggestion.value,
        suggestedLevel(props.module),
        props.permissions
      )
    )
);
const lockHint = reason => (reason ? `CUSTOM_ROLE.EDITOR.LOCK.${reason}` : '');
// O motivo aparece também por escrito embaixo da linha, não só no passar do mouse.
const rowLock = computed(
  () =>
    [...slots.value, ...(isConversations ? reachOptions : [])]
      .filter(Boolean)
      .map(levelLock)
      .find(Boolean) || null
);
const pickLevel = option => {
  if (!levelLock(option)) emit('selectLevel', option);
};

const moduleKey = props.module.key;
const levelLabelKey = option => {
  if (option === LEVELS.NONE && props.module.baseline)
    return `CUSTOM_ROLE.MATRIX.BASELINE.${props.module.baseline}`;
  if (isConversations && option !== LEVELS.NONE)
    return `CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.SLOT_${option.toUpperCase()}`;
  return `CUSTOM_ROLE.MATRIX.LEVELS.${option.toUpperCase()}`;
};
const descriptionKey = computed(() =>
  hasAccess.value
    ? `CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.LEVEL_${level.value.toUpperCase()}`
    : `CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.HINT`
);

const options = computed(() =>
  slots.value.filter(option => option && !levelLock(option))
);
const onArrow = (event, option) => {
  const index = options.value.indexOf(option);
  if (index < 0) return;
  const step = event.key === 'ArrowRight' ? 1 : -1;
  const next =
    options.value[(index + step + options.value.length) % options.value.length];
  emit('selectLevel', next);
  event.currentTarget.parentElement
    .querySelector(`[data-level="${next}"]`)
    ?.focus();
};
</script>

<template>
  <div class="px-4 py-3.5 border-t border-n-weak first:border-t-0">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-start">
      <div class="flex items-start flex-1 min-w-0 gap-3">
        <span
          class="grid transition-colors rounded-lg size-8 shrink-0 place-items-center"
          :class="
            hasAccess
              ? 'bg-n-brand/10 text-n-blue-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <span :class="module.icon" class="size-4" />
        </span>
        <div class="min-w-0">
          <span class="text-heading-3 text-n-slate-12">
            {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.NAME`) }}
          </span>
          <p class="mb-0 mt-0.5 text-label-small text-n-slate-11">
            {{ $t(descriptionKey) }}
          </p>
        </div>
      </div>
      <div
        role="radiogroup"
        :aria-label="$t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.NAME`)"
        class="grid grid-cols-3 gap-0.5 p-0.5 rounded-lg h-9 w-full sm:w-[19.5rem] shrink-0 bg-n-alpha-1 dark:bg-n-solid-2"
      >
        <template v-for="(option, index) in slots" :key="index">
          <button
            v-if="option"
            type="button"
            role="radio"
            :data-level="option"
            :aria-checked="option === activeSlot"
            :tabindex="option === activeSlot ? 0 : -1"
            :aria-disabled="!!levelLock(option) || undefined"
            :title="
              levelLock(option) ? $t(lockHint(levelLock(option))) : undefined
            "
            class="h-8 px-2 truncate rounded-md text-[13px] transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/60"
            :class="
              levelLock(option)
                ? 'font-460 text-n-slate-9 cursor-not-allowed'
                : option !== activeSlot
                  ? 'font-460 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2'
                  : option === LEVELS.NONE
                    ? 'font-semibold shadow-sm ring-1 ring-inset ring-n-strong bg-n-solid-active dark:bg-n-solid-3 text-n-slate-12 motion-safe:animate-segment-select'
                    : 'font-semibold shadow-sm ring-1 ring-inset ring-n-brand/40 bg-n-brand/15 text-n-blue-11 motion-safe:animate-segment-select'
            "
            @click="pickLevel(option)"
            @keydown.left.prevent="onArrow($event, option)"
            @keydown.right.prevent="onArrow($event, option)"
          >
            {{ $t(levelLabelKey(option)) }}
          </button>
          <span
            v-else
            aria-hidden="true"
            class="grid h-8 text-xs select-none place-items-center text-n-slate-8"
          >
            {{ $t('CUSTOM_ROLE.SEPARATORS.NONE') }}
          </span>
        </template>
      </div>
    </div>

    <div
      v-if="showReach"
      role="radiogroup"
      :aria-label="$t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.REACH`)"
      class="flex flex-wrap items-center gap-2 mt-2 ps-11"
    >
      <span class="text-label-small text-n-slate-11">
        {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.REACH`) }}
      </span>
      <button
        v-for="option in reachOptions"
        :key="option"
        type="button"
        role="radio"
        :data-reach="option"
        :aria-checked="option === level"
        :aria-disabled="!!levelLock(option) || undefined"
        :title="levelLock(option) ? $t(lockHint(levelLock(option))) : undefined"
        class="h-8 px-3 rounded-md text-[13px] ring-1 ring-inset transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/60"
        :class="
          option === level
            ? 'font-semibold ring-n-brand/40 bg-n-brand/15 text-n-blue-11'
            : levelLock(option)
              ? 'font-460 ring-n-weak text-n-slate-9 cursor-not-allowed'
              : 'font-460 ring-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2'
        "
        @click="pickLevel(option)"
      >
        {{ $t(`CUSTOM_ROLE.MATRIX.LEVELS.${option.toUpperCase()}`) }}
      </button>
    </div>

    <div
      v-if="rowLock"
      data-row-lock
      class="flex items-center gap-1.5 mt-2 ps-11 text-label-small text-n-amber-11"
    >
      <span class="i-lucide-lock size-3.5 shrink-0" />
      {{ $t(lockHint(rowLock)) }}
    </div>

    <div
      v-if="suggestion"
      class="flex flex-wrap items-center gap-2 mt-2 ps-11 text-label-small text-n-amber-11"
    >
      <span class="i-lucide-info size-3.5 shrink-0" />
      {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.SUGGESTION`) }}
      <button
        v-if="!suggestionLock"
        type="button"
        class="font-medium underline"
        @click="emit('grantSuggested', suggestion, suggestedLevel(module))"
      >
        {{ $t('CUSTOM_ROLE.EDITOR.GRANT_SUGGESTED') }}
      </button>
    </div>

    <div v-if="extras.length" class="mt-2 ps-11">
      <button
        type="button"
        class="inline-flex items-center gap-1 text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
        :aria-expanded="isOpen"
        @click="emit('toggleOpen')"
      >
        <span
          class="i-lucide-chevron-right size-3.5 transition-transform"
          :class="{ 'rotate-90': isOpen }"
        />
        {{ $t('CUSTOM_ROLE.EDITOR.FINE_TUNING') }}
        <span class="text-n-slate-10 font-420">
          {{
            $t('CUSTOM_ROLE.EDITOR.FINE_TUNING_COUNT', {
              on: extrasOn,
              total: extras.length,
            })
          }}
        </span>
      </button>
      <ul
        v-if="isOpen"
        class="grid p-0 m-0 mt-2 overflow-hidden list-none rounded-lg gap-px bg-n-weak outline outline-1 outline-n-weak"
      >
        <li
          v-for="extra in extras"
          :key="extra"
          class="flex items-center gap-3 px-3 py-2.5 bg-n-solid-1"
        >
          <div class="flex-1 min-w-0">
            <div
              class="flex flex-wrap items-center gap-1.5 text-sm text-n-slate-12"
            >
              <span :class="{ 'font-medium': permissions.includes(extra) }">
                {{ $t(`CUSTOM_ROLE.PERMISSIONS.${extra.toUpperCase()}`) }}
              </span>
              <span
                v-if="SENSITIVE_EXTRAS.includes(extra)"
                class="inline-flex items-center h-5 gap-1 px-1.5 rounded-md text-label-small bg-n-ruby-9/10 text-n-ruby-11"
              >
                <span class="i-lucide-shield-alert size-3" />
                {{ $t('CUSTOM_ROLE.EDITOR.SENSITIVE') }}
              </span>
            </div>
            <div class="text-label-small text-n-slate-11">
              {{
                isExtraLocked(extra, permissions)
                  ? $t('CUSTOM_ROLE.EDITOR.INCLUDED_IN_ADMIN')
                  : $t(`CUSTOM_ROLE.EXTRAS.${extra.toUpperCase()}`)
              }}
            </div>
            <div
              v-if="extraLock(extra)"
              class="flex items-center gap-1 text-label-small text-n-amber-11"
            >
              <span class="i-lucide-lock size-3" />
              {{ $t(lockHint(extraLock(extra))) }}
            </div>
          </div>
          <Switch
            :model-value="permissions.includes(extra)"
            :disabled="isExtraLocked(extra, permissions) || !!extraLock(extra)"
            :class="{
              'opacity-60 cursor-not-allowed':
                isExtraLocked(extra, permissions) || extraLock(extra),
            }"
            :aria-label="$t(`CUSTOM_ROLE.PERMISSIONS.${extra.toUpperCase()}`)"
            @update:model-value="emit('toggleExtra', extra)"
          />
        </li>
      </ul>
    </div>
  </div>
</template>
