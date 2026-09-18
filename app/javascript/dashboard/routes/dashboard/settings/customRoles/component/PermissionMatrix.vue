<script setup>
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import {
  MODULE_GROUPS,
  PRESETS,
  getLevel,
  setLevel,
  levelOptions,
  visibleExtras,
  toggleExtra,
} from '../permissionMatrix';

const permissions = defineModel({ type: Array, default: () => [] });

const { t } = useI18n();

const tabsFor = module =>
  levelOptions(module).map(level => ({
    level,
    label: t(`CUSTOM_ROLE.MATRIX.LEVELS.${level.toUpperCase()}`),
  }));

const activeIndex = module =>
  levelOptions(module).indexOf(getLevel(module, permissions.value));

const changeLevel = (module, tab) => {
  permissions.value = setLevel(module, tab.level, permissions.value);
};

const changeExtra = (module, key) => {
  permissions.value = toggleExtra(module, key, permissions.value);
};

const applyPreset = key => {
  permissions.value = PRESETS[key]();
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm text-n-slate-11">
        {{ $t('CUSTOM_ROLE.MATRIX.PRESETS.LABEL') }}
      </span>
      <button
        v-for="preset in Object.keys(PRESETS)"
        :key="preset"
        type="button"
        class="px-3 py-1 text-xs rounded-full border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="applyPreset(preset)"
      >
        {{ $t(`CUSTOM_ROLE.MATRIX.PRESETS.${preset}`) }}
      </button>
    </div>

    <div v-for="group in MODULE_GROUPS" :key="group.key" class="flex flex-col">
      <span class="text-xs font-medium uppercase text-n-slate-11 mb-1">
        {{ $t(`CUSTOM_ROLE.MATRIX.GROUPS.${group.key}`) }}
      </span>
      <div
        v-for="module in group.modules"
        :key="module.key"
        class="flex flex-col gap-2 py-2.5 border-t border-n-weak"
      >
        <div class="flex items-center justify-between gap-4">
          <div class="flex flex-col min-w-0">
            <span class="text-sm text-n-slate-12">
              {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.HINT`) }}
            </span>
          </div>
          <TabBar
            class="shrink-0"
            :tabs="tabsFor(module)"
            :initial-active-tab="activeIndex(module)"
            @tab-changed="tab => changeLevel(module, tab)"
          />
        </div>
        <div
          v-if="visibleExtras(module, permissions).length"
          class="flex flex-wrap gap-1.5"
        >
          <button
            v-for="extra in visibleExtras(module, permissions)"
            :key="extra"
            type="button"
            class="px-2.5 py-0.5 text-xs rounded-full border"
            :class="
              permissions.includes(extra)
                ? 'border-n-brand bg-n-brand/10 text-n-blue-11'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
            "
            :aria-pressed="permissions.includes(extra)"
            @click="changeExtra(module, extra)"
          >
            {{ $t(`CUSTOM_ROLE.PERMISSIONS.${extra.toUpperCase()}`) }}
          </button>
        </div>
      </div>
    </div>

    <p class="text-xs text-n-slate-11">
      {{ $t('CUSTOM_ROLE.MATRIX.FOOTNOTE') }}
    </p>
  </div>
</template>
