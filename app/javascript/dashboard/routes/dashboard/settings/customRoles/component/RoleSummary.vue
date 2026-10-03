<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  MODULE_GROUPS,
  LEVELS,
  getLevel,
  hasAccess,
  visibleExtras,
  sensitiveExtrasOn,
} from '../permissionMatrix';

const props = defineProps({
  permissions: { type: Array, required: true },
});

const { t } = useI18n();

const levelKey = module => getLevel(module, props.permissions).toUpperCase();

// Mid-sentence labels start lowercase but keep acronyms like CRM intact.
const lowerFirst = text => text.charAt(0).toLowerCase() + text.slice(1);

// Built in one string so the template whitespace never lands before the comma.
const detailOf = (module, extras) =>
  [
    t(`CUSTOM_ROLE.MATRIX.LEVELS.${levelKey(module)}`),
    ...extras.map(key => t(`CUSTOM_ROLE.PERMISSIONS.${key.toUpperCase()}`)),
  ]
    .map(lowerFirst)
    .join(`${t('CUSTOM_ROLE.SEPARATORS.COMMA')} `);

// What the person can do, grouped like the editor, in plain words.
const groups = computed(() =>
  MODULE_GROUPS.map(group => ({
    key: group.key,
    modules: group.modules
      .filter(module => hasAccess(module, props.permissions))
      .map(module => ({
        key: module.key,
        detail: detailOf(
          module,
          visibleExtras(module, props.permissions).filter(key =>
            props.permissions.includes(key)
          )
        ),
      })),
  })).filter(group => group.modules.length)
);

const sensitive = computed(() => sensitiveExtrasOn(props.permissions));

const allModules = MODULE_GROUPS.flatMap(group => group.modules);
const menuItems = computed(() =>
  allModules
    .filter(module => !module.settings)
    .map(module => ({
      key: module.key,
      icon: module.icon,
      visible: hasAccess(module, props.permissions),
      viewOnly: getLevel(module, props.permissions) === LEVELS.VIEW,
    }))
);
const settingsItems = computed(() =>
  allModules
    .filter(module => module.settings && hasAccess(module, props.permissions))
    .map(module => ({
      key: module.key,
      viewOnly: getLevel(module, props.permissions) === LEVELS.VIEW,
    }))
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <section
      class="p-3 rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
    >
      <h4
        class="flex items-center gap-1.5 mt-0 mb-2 font-medium text-label-small text-n-slate-11"
      >
        <span class="i-lucide-user-check size-3.5" />
        {{ $t('CUSTOM_ROLE.SUMMARY.CAN_TITLE') }}
      </h4>
      <p v-if="!groups.length" class="m-0 text-label-small text-n-slate-11">
        {{ $t('CUSTOM_ROLE.SUMMARY.EMPTY') }}
      </p>
      <div v-else class="grid gap-2.5">
        <div v-for="group in groups" :key="group.key">
          <div class="mb-1 text-[11px] uppercase tracking-wide text-n-slate-10">
            {{ $t(`CUSTOM_ROLE.MATRIX.GROUPS.${group.key}`) }}
          </div>
          <ul class="grid p-0 m-0 list-none gap-0.5">
            <li
              v-for="module in group.modules"
              :key="module.key"
              class="text-xs leading-5 text-n-slate-11"
            >
              <span class="font-medium text-n-slate-12">
                {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`) }}
              </span>
              {{ $t('CUSTOM_ROLE.SEPARATORS.DOT') }}
              {{ module.detail }}
            </li>
          </ul>
        </div>
      </div>
    </section>

    <section
      v-if="sensitive.length"
      class="p-3 rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
    >
      <h4
        class="flex items-center gap-1.5 mt-0 mb-2 font-medium text-label-small text-n-ruby-11"
      >
        <span class="i-lucide-shield-alert size-3.5" />
        {{ $t('CUSTOM_ROLE.SUMMARY.SENSITIVE', sensitive.length) }}
      </h4>
      <ul class="grid gap-1 p-0 m-0 list-none">
        <li
          v-for="key in sensitive"
          :key="key"
          class="flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <span class="rounded-full size-1.5 bg-n-ruby-9" />
          {{ $t(`CUSTOM_ROLE.PERMISSIONS.${key.toUpperCase()}`) }}
        </li>
      </ul>
    </section>

    <details
      class="p-3 group rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
    >
      <summary
        class="flex items-center gap-1.5 font-medium list-none cursor-pointer text-label-small text-n-slate-11 [&::-webkit-details-marker]:hidden"
      >
        <span class="i-lucide-eye size-3.5" />
        {{ $t('CUSTOM_ROLE.SUMMARY.MENU_TITLE') }}
        <span
          class="i-lucide-chevron-down size-3.5 ms-auto transition-transform group-open:rotate-180"
        />
      </summary>
      <div
        class="grid gap-0.5 p-1.5 mt-2 text-[13px] rounded-lg bg-n-background outline outline-1 outline-n-weak"
      >
        <div
          v-for="item in menuItems"
          :key="item.key"
          class="flex items-center h-7 gap-2 px-1.5 rounded-md"
          :class="
            item.visible
              ? 'text-n-slate-11'
              : 'text-n-slate-8 line-through opacity-60'
          "
        >
          <span :class="item.icon" class="size-3.5 shrink-0" />
          <span class="truncate">
            {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${item.key}.NAME`) }}
          </span>
          <span
            v-if="item.visible && item.viewOnly"
            class="ms-auto text-[10px] px-1.5 rounded bg-n-alpha-2 text-n-slate-11"
          >
            {{ $t('CUSTOM_ROLE.MATRIX.LEVELS.VIEW').toLowerCase() }}
          </span>
        </div>
        <div
          class="flex items-center h-7 gap-2 px-1.5 rounded-md"
          :class="
            settingsItems.length
              ? 'font-medium text-n-slate-12'
              : 'text-n-slate-8 line-through opacity-60'
          "
        >
          <span class="i-lucide-bolt size-3.5" />
          {{ $t('CUSTOM_ROLE.SUMMARY.SETTINGS') }}
        </div>
        <div
          v-for="item in settingsItems"
          :key="item.key"
          class="flex items-center h-6 text-xs ms-5 ps-2 border-s-2 border-n-slate-4 text-n-slate-11"
        >
          {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${item.key}.NAME`) }}
          <span
            v-if="item.viewOnly"
            class="ms-auto text-[10px] px-1.5 rounded bg-n-alpha-2 text-n-slate-11"
          >
            {{ $t('CUSTOM_ROLE.MATRIX.LEVELS.VIEW').toLowerCase() }}
          </span>
        </div>
      </div>
    </details>
  </div>
</template>
