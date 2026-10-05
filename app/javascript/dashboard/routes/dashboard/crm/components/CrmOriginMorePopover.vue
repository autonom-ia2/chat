<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { CRM_ORIGIN_MAX_TOUCHES } from '../composables/useCrmOrigin';
import CrmOriginList from './CrmOriginList.vue';

// The "+N" next to the Kanban origin pill: a button that opens every touch of
// the contact in the shared components-next Popover (docs/crm/origens-nomes-meta.md §5).
// It lives inside a clickable card, so its clicks never reach the card.
const props = defineProps({
  campaigns: {
    type: Array,
    default: () => [],
  },
  extraCount: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
const shownCount = computed(() =>
  Math.min(props.campaigns.length, CRM_ORIGIN_MAX_TOUCHES)
);
const contentId = `crm-origin-more-${useId()}`;
const triggerRef = ref(null);
const isOpen = ref(false);
let returnFocusOnHide = false;

// Popover closes itself on Escape; note it first (capture runs before its
// document listener) so focus goes back to the "+N" — a click elsewhere keeps
// the focus where the person clicked.
useEventListener(
  window,
  'keydown',
  event => {
    if (event.key === 'Escape' && isOpen.value) returnFocusOnHide = true;
  },
  { capture: true }
);

const onShow = async () => {
  isOpen.value = true;
  returnFocusOnHide = false;
  // The content is teleported to the end of the page: move focus into it so
  // the links inside are reachable with Tab.
  await nextTick();
  document.getElementById(contentId)?.focus();
};

const onHide = () => {
  isOpen.value = false;
  if (returnFocusOnHide) triggerRef.value?.focus();
  returnFocusOnHide = false;
};

// Being teleported, the content has no place in the card's tab order: Tab past
// the last link (or Shift+Tab before the first) would leave the board. Close
// there and hand the focus back to the "+N", where the person was.
const onContentTab = (event, hide) => {
  const container = event.currentTarget;
  const stops = [container, ...container.querySelectorAll('a[href]')];
  const edge = event.shiftKey ? stops[0] : stops[stops.length - 1];
  if (document.activeElement !== edge) return;

  event.preventDefault();
  returnFocusOnHide = true;
  hide();
};
</script>

<template>
  <span class="inline-flex shrink-0" @click.stop>
    <Popover align="start" @show="onShow" @hide="onHide">
      <template #default="{ isOpen: expanded }">
        <button
          ref="triggerRef"
          type="button"
          class="group/more -my-3 inline-flex min-h-11 min-w-11 items-center justify-center rounded-md focus-visible:outline-none"
          :aria-expanded="expanded ? 'true' : 'false'"
          :aria-controls="contentId"
          aria-haspopup="dialog"
          :aria-label="
            t('CRM_KANBAN.ORIGIN.LIST.MORE_ARIA', { count: extraCount })
          "
          data-crm-origin-more
        >
          <span
            class="inline-flex h-5 items-center rounded-md px-1.5 text-[11px] font-semibold leading-4 tabular-nums transition-colors group-hover/more:bg-n-teal-4 group-focus-visible/more:outline group-focus-visible/more:outline-2 group-focus-visible/more:outline-n-brand"
            :class="
              expanded ? 'bg-n-teal-9 text-white' : 'bg-n-teal-3 text-n-teal-11'
            "
          >
            {{ `+${extraCount}` }}
          </span>
        </button>
      </template>
      <template #content="{ hide }">
        <div
          :id="contentId"
          role="dialog"
          tabindex="-1"
          :aria-label="t('CRM_KANBAN.ORIGIN.LIST.TITLE')"
          class="w-full p-4 text-start outline-none md:w-80"
          data-crm-origin-popover
          @keydown.tab="onContentTab($event, hide)"
        >
          <p
            class="m-0 mb-3 flex items-baseline justify-between gap-2 text-sm font-semibold text-n-slate-12"
          >
            {{ t('CRM_KANBAN.ORIGIN.LIST.TITLE') }}
            <span class="text-xs font-normal tabular-nums text-n-slate-11">
              {{
                t(
                  'CRM_KANBAN.ORIGIN.LIST.COUNT',
                  { count: shownCount },
                  shownCount
                )
              }}
            </span>
          </p>
          <CrmOriginList :campaigns="campaigns" />
        </div>
      </template>
    </Popover>
  </span>
</template>
