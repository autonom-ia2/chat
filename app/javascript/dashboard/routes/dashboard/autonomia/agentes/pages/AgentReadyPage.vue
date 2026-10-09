<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { RouterLink, useRoute } from 'vue-router';

import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agent: { type: Object, default: null },
  channelNames: { type: Array, default: () => [] },
});

const emit = defineEmits(['open', 'list']);
const { t } = useI18n();
const route = useRoute();
const isInternal = computed(() => props.agent?.actuation === 'internal');
const isPublished = computed(
  () => props.agent?.status === 'active' && props.agent?.enabled === true
);
const name = computed(
  () =>
    props.agent?.name ||
    props.agent?.config?.name ||
    t('AGENTS.CREATION.test.agentFallback')
);
</script>

<template>
  <main
    data-testid="agent-creation-ready"
    class="flex flex-col w-full max-w-4xl gap-8 px-4 py-8 mx-auto sm:px-6 lg:py-14"
  >
    <section
      class="flex flex-col items-center gap-4 p-8 text-center border rounded-3xl border-n-teal-6 bg-n-teal-2"
      role="status"
    >
      <span
        class="flex items-center justify-center rounded-full size-14 bg-n-teal-9 text-n-slate-1"
      >
        <i class="i-lucide-check size-7" aria-hidden="true" />
      </span>
      <div class="flex flex-col gap-2">
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{
            !isPublished
              ? t('AGENTS.CREATION.ready.offTitle', { name })
              : isInternal
                ? t('AGENTS.CREATION.ready.internalTitle', { name })
                : channelNames.length > 1
                  ? t('AGENTS.CREATION.ready.multiTitle', {
                      name,
                      count: channelNames.length,
                    })
                  : t('AGENTS.CREATION.ready.title', {
                      name,
                      channel: channelNames[0],
                    })
          }}
        </h1>
        <ul
          v-if="isPublished && !isInternal && channelNames.length > 1"
          class="flex flex-wrap justify-center gap-2 p-0 list-none"
          :aria-label="t('AGENTS.CREATION.ready.channelsLabel')"
        >
          <li
            v-for="(channel, index) in channelNames"
            :key="index"
            class="px-3 py-1 text-sm rounded-lg bg-n-teal-3 text-n-teal-12"
          >
            {{ channel }}
          </li>
        </ul>
        <p class="max-w-xl text-sm leading-6 text-n-slate-11">
          {{
            !isPublished
              ? t('AGENTS.CREATION.ready.offDescription')
              : isInternal
                ? t('AGENTS.CREATION.ready.internalDescription')
                : t('AGENTS.CREATION.ready.description')
          }}
        </p>
      </div>
    </section>

    <section class="grid gap-4 sm:grid-cols-2">
      <RouterLink
        v-if="isPublished && isInternal"
        :to="{ name: 'home', params: { accountId: route.params.accountId } }"
        class="flex flex-col gap-2 p-5 text-left border rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-brand"
        @click="emit('open')"
      >
        <i
          class="i-lucide-message-circle size-5 text-n-iris-11"
          aria-hidden="true"
        />
        <strong class="text-sm text-n-slate-12">{{
          t('AGENTS.CREATION.ready.openConversation')
        }}</strong>
        <span class="text-xs leading-5 text-n-slate-11">{{
          t('AGENTS.CREATION.ready.openConversationHint')
        }}</span>
      </RouterLink>
      <RouterLink
        :to="{
          name: 'autonomia_agents_index',
          params: { accountId: route.params.accountId },
        }"
        class="flex flex-col gap-2 p-5 text-left border rounded-2xl border-n-weak bg-n-solid-1 hover:border-n-brand"
        @click="emit('list')"
      >
        <i
          class="i-lucide-layout-list size-5 text-n-slate-11"
          aria-hidden="true"
        />
        <strong class="text-sm text-n-slate-12">{{
          t('AGENTS.CREATION.ready.backToAgents')
        }}</strong>
        <span class="text-xs leading-5 text-n-slate-11">{{
          t('AGENTS.CREATION.ready.backToAgentsHint')
        }}</span>
      </RouterLink>
    </section>

    <div class="flex justify-center">
      <NextButton
        ghost
        slate
        class="min-h-11"
        :label="t('AGENTS.CREATION.ready.openPerformance')"
        :to="{
          name: 'autonomia_agent_panel',
          params: {
            accountId: route.params.accountId,
            agentId: agent?.id,
            tab: 'performance',
          },
        }"
      />
    </div>
  </main>
</template>
