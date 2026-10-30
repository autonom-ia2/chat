<script setup>
// Who matches but will not receive (#2277): no WhatsApp, or asked not to receive. One quiet line at the end of
// the list, counted by reason, with "Ver quem" for the names. They never count in the audience.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  leftAside: { type: Array, default: () => [] },
});

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const REASONS = { sem_contato: 'OUT_NO_CONTACT', nao_quer: 'OUT_OPTED_OUT' };
const { t } = useI18n();
const showWho = ref(false);

const groups = computed(() =>
  Object.keys(REASONS)
    .map(reason => ({
      reason,
      names: props.leftAside
        .filter(([, why]) => why === reason)
        .map(([name]) => name),
    }))
    .filter(group => group.names.length)
);
</script>

<template>
  <section
    v-show="groups.length"
    class="flex flex-col gap-1 border-t border-n-weak pt-4"
    data-test="left-aside"
  >
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.OUT_TITLE`) }}
      </span>
      <span
        v-for="group in groups"
        :key="group.reason"
        class="text-sm text-n-slate-11"
      >
        {{ t(`${NS}.${REASONS[group.reason]}`, { count: group.names.length }) }}
      </span>
      <button
        type="button"
        class="min-h-11 rounded-xl px-2 text-sm font-medium text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="showWho"
        @click="showWho = !showWho"
      >
        {{ showWho ? t(`${NS}.HIDE_WHO`) : t(`${NS}.SEE_WHO`) }}
      </button>
    </div>
    <ul v-if="showWho" class="m-0 flex list-none flex-col gap-1 p-0">
      <li
        v-for="group in groups"
        :key="group.reason"
        class="text-sm text-n-slate-11"
      >
        {{
          t(`${NS}.OUT_NAMES`, {
            reason: t(`${NS}.${REASONS[group.reason]}`, {
              count: group.names.length,
            }),
            names: group.names.join(', '),
          })
        }}
      </li>
    </ul>
  </section>
</template>
