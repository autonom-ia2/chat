<script setup>
import { computed } from 'vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  LEVELS,
  SENSITIVE_EXTRAS,
  getLevel,
  isExtraLocked,
  levelSlots,
  visibleExtras,
  unmetSuggestion,
} from '../permissionMatrix';

const props = defineProps({
  module: { type: Object, required: true },
  permissions: { type: Array, required: true },
  isOpen: { type: Boolean, default: false },
});

const emit = defineEmits([
  'selectLevel',
  'toggleExtra',
  'toggleOpen',
  'grantSuggested',
]);

const level = computed(() => getLevel(props.module, props.permissions));
const hasAccess = computed(() => level.value !== LEVELS.NONE);
const slots = computed(() => levelSlots(props.module));
const extras = computed(() => visibleExtras(props.module, props.permissions));
const extrasOn = computed(
  () => extras.value.filter(key => props.permissions.includes(key)).length
);
const suggestion = computed(() =>
  unmetSuggestion(props.module, props.permissions)
);

const moduleKey = props.module.key;
const levelLabelKey = option =>
  option === LEVELS.NONE && props.module.baseline
    ? `CUSTOM_ROLE.MATRIX.BASELINE.${props.module.baseline}`
    : `CUSTOM_ROLE.MATRIX.LEVELS.${option.toUpperCase()}`;
const descriptionKey = computed(() =>
  hasAccess.value
    ? `CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.LEVEL_${level.value.toUpperCase()}`
    : `CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.HINT`
);

const options = computed(() => slots.value.filter(Boolean));
const onArrow = (event, option) => {
  const index = options.value.indexOf(option);
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
            :aria-checked="option === level"
            :tabindex="option === level ? 0 : -1"
            class="h-8 px-2 truncate rounded-md text-[13px] transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/60"
            :class="
              option !== level
                ? 'font-460 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2'
                : option === LEVELS.NONE
                  ? 'font-semibold shadow-sm ring-1 ring-inset ring-n-strong bg-n-solid-active dark:bg-n-solid-3 text-n-slate-12 motion-safe:animate-segment-select'
                  : 'font-semibold shadow-sm ring-1 ring-inset ring-n-brand/40 bg-n-brand/15 text-n-blue-11 motion-safe:animate-segment-select'
            "
            @click="emit('selectLevel', option)"
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
            —
          </span>
        </template>
      </div>
    </div>

    <div
      v-if="suggestion"
      class="flex flex-wrap items-center gap-2 mt-2 ps-11 text-label-small text-n-amber-11"
    >
      <span class="i-lucide-info size-3.5 shrink-0" />
      {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${moduleKey}.SUGGESTION`) }}
      <button
        type="button"
        class="font-medium underline"
        @click="emit('grantSuggested', suggestion)"
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
          </div>
          <Switch
            :model-value="permissions.includes(extra)"
            :disabled="isExtraLocked(extra, permissions)"
            :class="{
              'opacity-60 cursor-not-allowed': isExtraLocked(
                extra,
                permissions
              ),
            }"
            :aria-label="$t(`CUSTOM_ROLE.PERMISSIONS.${extra.toUpperCase()}`)"
            @update:model-value="emit('toggleExtra', extra)"
          />
        </li>
      </ul>
    </div>
  </div>
</template>
