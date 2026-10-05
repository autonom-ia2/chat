<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  buildCrmOrigin,
  CRM_ORIGIN_MAX_TOUCHES,
  useCrmOrigin,
} from '../composables/useCrmOrigin';

// Every touch that brought the contact, first to last (docs/crm/origens-nomes-meta.md §5).
const props = defineProps({
  // card.campaigns: touches as the payload sends them, already in order.
  campaigns: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
const { originLabelOverHierarchy, hierarchyItems, touchDate, sourceUrlLabel } =
  useCrmOrigin();

const rows = computed(() => {
  const origins = props.campaigns
    .map(buildCrmOrigin)
    .filter(Boolean)
    .slice(0, CRM_ORIGIN_MAX_TOUCHES);
  const lastIndex = origins.length - 1;

  return origins.map((origin, index) => {
    let marker = '';
    if (lastIndex > 0 && index === 0) {
      marker = t('CRM_KANBAN.ORIGIN.LIST.FIRST');
    } else if (lastIndex > 0 && index === lastIndex) {
      marker = t('CRM_KANBAN.ORIGIN.LIST.LAST');
    }

    return {
      key: `${index}-${origin.sourceId || origin.headline}`,
      origin,
      label: originLabelOverHierarchy(origin),
      date: touchDate(origin),
      levels: hierarchyItems(origin),
      linkLabel: sourceUrlLabel(origin),
      marker,
      isLast: index === lastIndex,
    };
  });
});
</script>

<template>
  <ol class="m-0 grid list-none gap-0 p-0" data-testid="crm-origin-list">
    <li
      v-for="row in rows"
      :key="row.key"
      class="grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-2.5"
      data-crm-origin-touch
    >
      <span aria-hidden="true" class="relative flex justify-center">
        <span
          class="relative z-[1] mt-0.5 flex size-5 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
        >
          <span :class="row.origin.icon" class="size-3" />
        </span>
        <span
          v-if="!row.isLast"
          class="absolute inset-y-0 top-6 w-px bg-n-strong"
        />
      </span>

      <div class="min-w-0" :class="row.isLast ? '' : 'pb-3.5'">
        <div class="flex min-w-0 items-baseline justify-between gap-2">
          <p
            class="m-0 min-w-0 truncate text-sm font-medium leading-6 text-n-slate-12"
            :title="row.label"
          >
            {{ row.label }}
          </p>
          <time
            v-if="row.date"
            :datetime="row.date.iso"
            :title="row.date.title"
            class="shrink-0 text-xs tabular-nums text-n-slate-11"
          >
            {{ row.date.label }}
          </time>
        </div>

        <p
          v-if="row.marker"
          class="m-0 text-[11px] font-medium uppercase leading-4 tracking-wide text-n-slate-10"
        >
          {{ row.marker }}
        </p>

        <dl
          v-if="row.levels.length"
          class="m-0 mt-1 grid grid-cols-[4.75rem_minmax(0,1fr)] gap-x-2 gap-y-0.5 text-xs leading-5"
        >
          <template v-for="level in row.levels" :key="level.field">
            <dt class="text-n-slate-11">{{ level.level }}</dt>
            <dd
              class="m-0 min-w-0 truncate text-n-slate-12"
              :title="level.title"
              :data-crm-origin-level="level.field"
            >
              {{ level.value }}
            </dd>
          </template>
        </dl>

        <a
          v-if="row.origin.sourceUrl && row.linkLabel"
          :href="row.origin.sourceUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="-my-3 inline-flex min-h-11 max-w-full items-center gap-1 rounded text-xs font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :title="row.origin.sourceUrl"
        >
          <span class="truncate">{{ row.linkLabel }}</span>
          <span
            class="i-lucide-arrow-up-right size-3 shrink-0"
            aria-hidden="true"
          />
          <span class="sr-only">{{ t('CRM_KANBAN.ORIGIN.LIST.NEW_TAB') }}</span>
        </a>
      </div>
    </li>
  </ol>
</template>
