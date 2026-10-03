<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BLANK_PROFILE,
  MODULES,
  PROFILES,
  PROFILE_GROUPS,
  hasAccess,
  profilePermissions,
  sensitiveExtrasOn,
} from '../permissionMatrix';

const props = defineProps({
  isNewRole: { type: Boolean, default: true },
  initialProfile: { type: String, default: 'AGENT' },
});

const emit = defineEmits(['choose', 'back']);

const selected = ref(props.initialProfile);
const options = [...PROFILES.map(profile => profile.key), BLANK_PROFILE];

const profile = computed(() =>
  PROFILES.find(item => item.key === selected.value)
);
const areaCount = computed(() => {
  const permissions = profilePermissions(selected.value);
  return MODULES.filter(module => hasAccess(module, permissions)).length;
});
const sensitiveCount = computed(
  () => sensitiveExtrasOn(profilePermissions(selected.value)).length
);
const profileName = key => `CUSTOM_ROLE.PROFILES.${key}.NAME`;

const listRef = ref(null);
const move = step => {
  const index = options.indexOf(selected.value);
  selected.value = options[(index + step + options.length) % options.length];
  listRef.value?.querySelector(`[data-profile="${selected.value}"]`)?.focus();
};
</script>

<template>
  <div class="flex flex-col w-full gap-6 font-inter">
    <div class="flex flex-col items-start w-full">
      <button
        type="button"
        class="inline-flex items-center h-6 gap-1 my-1 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="emit('back')"
      >
        <span class="i-lucide-chevron-left size-4" />
        {{
          isNewRole
            ? $t('CUSTOM_ROLE.HEADER')
            : $t('CUSTOM_ROLE.PICKER.BACK_TO_ROLE')
        }}
      </button>
      <div
        v-if="isNewRole"
        class="flex items-center gap-2 mt-2 mb-3"
        :aria-label="$t('CUSTOM_ROLE.PICKER.STEP', { step: 1 })"
      >
        <span class="w-8 h-1 rounded-full bg-n-brand" />
        <span class="w-8 h-1 rounded-full bg-n-slate-5" />
        <span class="ms-1 text-label-small text-n-slate-10">
          {{ $t('CUSTOM_ROLE.PICKER.STEP', { step: 1 }) }}
        </span>
      </div>
      <h1 class="m-0 text-heading-1 text-n-slate-12">
        {{
          isNewRole
            ? $t('CUSTOM_ROLE.PICKER.TITLE')
            : $t('CUSTOM_ROLE.PICKER.APPLY_TITLE')
        }}
      </h1>
      <p class="max-w-2xl mt-1 mb-0 text-body-main text-n-slate-11">
        {{
          isNewRole
            ? $t('CUSTOM_ROLE.PICKER.DESCRIPTION')
            : $t('CUSTOM_ROLE.PICKER.APPLY_DESCRIPTION')
        }}
      </p>
    </div>

    <div class="grid items-start gap-6 lg:grid-cols-[17rem_minmax(0,1fr)]">
      <div
        ref="listRef"
        role="radiogroup"
        :aria-label="$t('CUSTOM_ROLE.PICKER.TITLE')"
        class="flex flex-col gap-4"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
      >
        <div v-for="group in PROFILE_GROUPS" :key="group.key">
          <div class="px-3 mb-1 text-label-small text-n-slate-10">
            {{ $t(`CUSTOM_ROLE.PROFILES.GROUPS.${group.key}`) }}
          </div>
          <div class="flex flex-col gap-0.5">
            <button
              v-for="item in group.profiles"
              :key="item.key"
              type="button"
              role="radio"
              :data-profile="item.key"
              :aria-checked="selected === item.key"
              :tabindex="selected === item.key ? 0 : -1"
              class="flex items-center w-full gap-3 px-3 py-2.5 rounded-lg text-start transition-colors"
              :class="
                selected === item.key ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
              "
              @click="selected = item.key"
            >
              <span
                class="grid rounded-full size-4 shrink-0 place-items-center"
                :class="
                  selected === item.key
                    ? 'bg-n-brand'
                    : 'outline outline-1 outline-n-strong'
                "
              >
                <span
                  v-if="selected === item.key"
                  class="rounded-full size-1.5 bg-white"
                />
              </span>
              <span class="flex-1 min-w-0">
                <span
                  class="block text-sm text-n-slate-12"
                  :class="
                    selected === item.key ? 'font-semibold' : 'font-medium'
                  "
                >
                  {{ $t(profileName(item.key)) }}
                </span>
                <span class="block truncate text-label-small text-n-slate-11">
                  {{ $t(`CUSTOM_ROLE.PROFILES.${item.key}.SHORT`) }}
                </span>
              </span>
            </button>
          </div>
        </div>
        <div class="pt-3 border-t border-n-weak">
          <button
            type="button"
            role="radio"
            :data-profile="BLANK_PROFILE"
            :aria-checked="selected === BLANK_PROFILE"
            :tabindex="selected === BLANK_PROFILE ? 0 : -1"
            class="flex items-center w-full gap-3 px-3 py-2.5 rounded-lg text-start transition-colors"
            :class="
              selected === BLANK_PROFILE ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
            "
            @click="selected = BLANK_PROFILE"
          >
            <span
              class="grid rounded-full size-4 shrink-0 place-items-center"
              :class="
                selected === BLANK_PROFILE
                  ? 'bg-n-brand'
                  : 'outline outline-1 outline-n-strong'
              "
            >
              <span
                v-if="selected === BLANK_PROFILE"
                class="rounded-full size-1.5 bg-white"
              />
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-sm font-medium text-n-slate-12">
                {{ $t(profileName(BLANK_PROFILE)) }}
              </span>
              <span class="block truncate text-label-small text-n-slate-11">
                {{ $t(`CUSTOM_ROLE.PROFILES.${BLANK_PROFILE}.SHORT`) }}
              </span>
            </span>
          </button>
        </div>
      </div>

      <div class="lg:sticky lg:top-4">
        <div
          class="flex flex-col gap-6 p-6 sm:p-8 rounded-2xl bg-n-solid-1 outline outline-1 outline-n-weak"
        >
          <div class="flex flex-col gap-2">
            <span class="text-label-small text-n-slate-10">
              <template v-if="profile">
                {{ $t('CUSTOM_ROLE.PICKER.AREAS', areaCount) }}
                <template v-if="sensitiveCount">
                  · {{ $t('CUSTOM_ROLE.SUMMARY.SENSITIVE', sensitiveCount) }}
                </template>
              </template>
              <template v-else>
                {{ $t('CUSTOM_ROLE.PICKER.BLANK_META') }}
              </template>
            </span>
            <h2
              class="m-0 text-2xl font-520 tracking-[-0.02em] text-n-slate-12"
            >
              {{ $t(profileName(selected)) }}
            </h2>
            <p class="max-w-md m-0 text-body-main text-n-slate-11">
              {{ $t(`CUSTOM_ROLE.PROFILES.${selected}.WHO`) }}
            </p>
          </div>
          <div v-if="profile" class="grid gap-6 sm:grid-cols-2">
            <div v-for="column in ['can', 'cannot']" :key="column">
              <h3
                class="mt-0 mb-3 font-medium tracking-wider uppercase text-label-small text-n-slate-10"
              >
                {{ $t(`CUSTOM_ROLE.PICKER.${column.toUpperCase()}`) }}
              </h3>
              <ul class="grid p-0 m-0 list-none gap-2.5">
                <li
                  v-for="phrase in profile[column]"
                  :key="phrase"
                  class="flex items-start gap-2.5 text-sm"
                  :class="
                    column === 'can' ? 'text-n-slate-12' : 'text-n-slate-11'
                  "
                >
                  <span
                    class="size-4 mt-0.5 shrink-0"
                    :class="
                      column === 'can'
                        ? 'i-lucide-check text-n-teal-11'
                        : 'i-lucide-minus text-n-slate-9'
                    "
                  />
                  {{ $t(`CUSTOM_ROLE.PROFILES.PHRASES.${phrase}`) }}
                </li>
              </ul>
            </div>
          </div>
          <div
            class="flex flex-wrap items-center justify-between gap-3 pt-5 border-t border-n-weak"
          >
            <span class="text-label-small text-n-slate-10">
              {{ $t('CUSTOM_ROLE.PICKER.ADJUST_LATER') }}
            </span>
            <Button
              :label="
                isNewRole
                  ? $t('CUSTOM_ROLE.PICKER.CONTINUE', {
                      name: $t(profileName(selected)),
                    })
                  : $t('CUSTOM_ROLE.PICKER.APPLY', {
                      name: $t(profileName(selected)),
                    })
              "
              icon="i-lucide-arrow-right"
              trailing-icon
              @click="emit('choose', selected)"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
