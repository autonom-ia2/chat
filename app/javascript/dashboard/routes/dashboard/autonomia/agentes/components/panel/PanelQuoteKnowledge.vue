<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  agent: { type: Object, required: true },
});

const { t } = useI18n();
const branches = computed(() => props.agent.quote_branches);

const branchName = branch =>
  typeof branch === 'string'
    ? branch
    : branch.name || branch.label || branch.slug;
</script>

<template>
  <section
    class="flex flex-col w-full max-w-3xl gap-5 px-4 py-6 mx-auto sm:px-6"
    data-testid="agent-quote-knowledge"
  >
    <div>
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_QUOTE_KNOWLEDGE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm leading-5 text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_QUOTE_KNOWLEDGE.DESCRIPTION') }}
      </p>
    </div>

    <div
      v-if="!branches.length"
      class="p-5 text-sm leading-6 border border-dashed rounded-xl border-n-weak text-n-slate-11"
      data-state="empty"
    >
      {{ t('AGENTS.PANEL.REDESIGN_QUOTE_KNOWLEDGE.EMPTY') }}
    </div>
    <ul
      v-else
      class="grid gap-2 sm:grid-cols-2"
      :aria-label="t('AGENTS.PANEL.REDESIGN_QUOTE_KNOWLEDGE.TITLE')"
    >
      <li
        v-for="branch in branches"
        :key="branch.id || branch.slug || branchName(branch)"
        class="flex items-start gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <span
          class="flex items-center justify-center shrink-0 rounded-lg size-8 bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
        >
          <span class="i-lucide-shield-check size-4" />
        </span>
        <span class="text-sm font-medium text-n-slate-12">
          {{ branchName(branch) }}
        </span>
      </li>
    </ul>
  </section>
</template>
