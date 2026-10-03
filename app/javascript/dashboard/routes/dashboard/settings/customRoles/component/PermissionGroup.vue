<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PermissionRow from './PermissionRow.vue';
import { LEVELS, getLevel, hasAccess } from '../permissionMatrix';

const props = defineProps({
  group: { type: Object, required: true },
  modules: { type: Array, required: true },
  permissions: { type: Array, required: true },
  isOpen: { type: Boolean, default: false },
  openRows: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'toggle',
  'clear',
  'selectLevel',
  'toggleExtra',
  'toggleRow',
  'grantSuggested',
]);

const withAccess = computed(() =>
  props.group.modules.filter(module => hasAccess(module, props.permissions))
);

const levelLabel = module => {
  const level = getLevel(module, props.permissions);
  return level === LEVELS.NONE ? '' : level.toUpperCase();
};
</script>

<template>
  <section
    class="overflow-hidden rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
  >
    <div
      class="flex items-center gap-2 pe-3"
      :class="{
        'border-b border-n-weak bg-n-alpha-1 dark:bg-n-solid-2/50': isOpen,
      }"
    >
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-3 px-4 py-3 text-start"
        :aria-expanded="isOpen"
        @click="emit('toggle')"
      >
        <span
          class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-11 transition-transform"
          :class="{ 'rotate-90': isOpen }"
        />
        <span class="flex-1 min-w-0">
          <span class="flex items-center gap-2">
            <span class="text-heading-3 text-n-slate-12">
              {{ $t(`CUSTOM_ROLE.MATRIX.GROUPS.${group.key}`) }}
            </span>
            <span class="text-label-small text-n-slate-10">
              {{
                $t('CUSTOM_ROLE.EDITOR.GROUP_COUNT', {
                  on: withAccess.length,
                  total: group.modules.length,
                })
              }}
            </span>
          </span>
          <span
            v-if="!isOpen"
            class="flex flex-wrap items-center mt-1 text-xs gap-x-2 gap-y-1"
          >
            <span v-if="!withAccess.length" class="text-n-slate-10">
              {{ $t('CUSTOM_ROLE.EDITOR.NOTHING_GRANTED') }}
            </span>
            <span
              v-for="module in withAccess"
              :key="module.key"
              class="inline-flex items-center gap-1 whitespace-nowrap"
            >
              <span class="text-n-slate-11">
                {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`) }}
              </span>
              <span class="font-semibold text-n-blue-11">
                {{ $t(`CUSTOM_ROLE.MATRIX.LEVELS.${levelLabel(module)}`) }}
              </span>
            </span>
          </span>
        </span>
      </button>
      <Button
        v-if="isOpen && withAccess.length"
        :label="$t('CUSTOM_ROLE.EDITOR.CLEAR_GROUP')"
        slate
        ghost
        xs
        class="shrink-0"
        @click="emit('clear')"
      />
    </div>
    <template v-if="isOpen">
      <PermissionRow
        v-for="module in modules"
        :key="module.key"
        :module="module"
        :permissions="permissions"
        :is-open="openRows.includes(module.key)"
        @select-level="level => emit('selectLevel', module, level)"
        @toggle-extra="key => emit('toggleExtra', module, key)"
        @toggle-open="emit('toggleRow', module.key)"
        @grant-suggested="target => emit('grantSuggested', target)"
      />
    </template>
  </section>
</template>
