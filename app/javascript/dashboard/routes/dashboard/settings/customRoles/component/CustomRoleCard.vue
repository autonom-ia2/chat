<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  MODULES,
  getLevel,
  hasAccess,
  sensitiveExtrasOn,
} from '../permissionMatrix';

const props = defineProps({
  role: { type: Object, required: true },
  agents: { type: Array, default: () => [] },
  isDeleting: { type: Boolean, default: false },
});

const emit = defineEmits(['edit', 'duplicate', 'delete']);

const MAX_AREAS = 4;
const MAX_AVATARS = 4;

const areas = computed(() =>
  MODULES.filter(module => hasAccess(module, props.role.permissions)).map(
    module => ({
      key: module.key,
      level: getLevel(module, props.role.permissions).toUpperCase(),
    })
  )
);
const hiddenAreas = computed(() => Math.max(areas.value.length - MAX_AREAS, 0));
const hasSensitive = computed(
  () => sensitiveExtrasOn(props.role.permissions).length > 0
);
</script>

<template>
  <article
    class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="m-0 truncate text-heading-2 text-n-slate-12">
          {{ role.name }}
        </h2>
        <p
          v-if="role.description"
          class="mb-0 line-clamp-2 text-body-main text-n-slate-11"
        >
          {{ role.description }}
        </p>
      </div>
      <div class="flex items-center shrink-0 -me-1.5">
        <Button
          v-tooltip.top="$t('CUSTOM_ROLE.LIST.DUPLICATE')"
          icon="i-lucide-copy"
          slate
          ghost
          sm
          :aria-label="$t('CUSTOM_ROLE.LIST.DUPLICATE')"
          @click="emit('duplicate', role)"
        />
        <Button
          v-tooltip.top="$t('CUSTOM_ROLE.EDIT.BUTTON_TEXT')"
          icon="i-lucide-pencil"
          slate
          ghost
          sm
          :aria-label="$t('CUSTOM_ROLE.EDIT.BUTTON_TEXT')"
          @click="emit('edit', role)"
        />
        <Button
          v-tooltip.top="$t('CUSTOM_ROLE.DELETE.BUTTON_TEXT')"
          icon="i-lucide-trash-2"
          ruby
          ghost
          sm
          :is-loading="isDeleting"
          :aria-label="$t('CUSTOM_ROLE.DELETE.BUTTON_TEXT')"
          @click="emit('delete', role)"
        />
      </div>
    </div>

    <div class="flex flex-wrap gap-1.5">
      <span
        v-for="area in areas.slice(0, MAX_AREAS)"
        :key="area.key"
        class="inline-flex items-center h-6 px-2 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${area.key}.NAME`) }}
        <span class="mx-1 text-n-slate-9">·</span>
        <span class="font-medium text-n-slate-12">
          {{ $t(`CUSTOM_ROLE.MATRIX.LEVELS.${area.level}`) }}
        </span>
      </span>
      <span
        v-if="hiddenAreas"
        class="inline-flex items-center h-6 px-2 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ $t('CUSTOM_ROLE.LIST.MORE_AREAS', { count: hiddenAreas }) }}
      </span>
      <span
        v-if="hasSensitive"
        class="inline-flex items-center h-6 gap-1 px-2 rounded-md text-label-small bg-n-ruby-9/10 text-n-ruby-11"
      >
        <span class="i-lucide-shield-alert size-3" />
        {{ $t('CUSTOM_ROLE.LIST.HAS_SENSITIVE') }}
      </span>
    </div>

    <div
      class="flex items-center justify-between pt-3 mt-auto border-t border-n-weak"
    >
      <div class="flex items-center gap-2">
        <div v-if="agents.length" class="flex -space-x-1.5">
          <Avatar
            v-for="agent in agents.slice(0, MAX_AVATARS)"
            :key="agent.id"
            :name="agent.name"
            :src="agent.thumbnail"
            :size="24"
            rounded-full
            class="ring-2 ring-n-solid-1"
          />
        </div>
        <span class="text-label-small text-n-slate-11">
          {{ $t('CUSTOM_ROLE.LIST.AGENT_COUNT', agents.length) }}
        </span>
      </div>
    </div>
  </article>
</template>
