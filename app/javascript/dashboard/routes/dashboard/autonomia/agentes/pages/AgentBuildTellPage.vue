<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import BuilderChat from '../../components/builder/BuilderChat.vue';
import BuildKnowsPanel from '../components/BuildKnowsPanel.vue';
import BuildMaterialsPanel from '../components/BuildMaterialsPanel.vue';

const props = defineProps({
  agentId: { type: [String, Number], default: null },
  messages: { type: Array, default: () => [] },
  knows: { type: Object, default: () => ({}) },
  suggestedLinks: { type: Array, default: () => [] },
  reusableSources: { type: Array, default: () => [] },
  reusableSourcesLoaded: { type: Boolean, default: false },
  reusableSourcesLoading: { type: Boolean, default: false },
  reusableSourcesError: { type: Boolean, default: false },
  isInternal: { type: Boolean, default: false },
  isSending: { type: Boolean, default: false },
  isAttaching: { type: Boolean, default: false },
  canContinue: { type: Boolean, default: false },
  error: { type: [String, Object], default: null },
  isCopying: { type: Boolean, default: false },
});

const emit = defineEmits([
  'send',
  'attach',
  'copy-source',
  'useLink',
  'continue',
  'retry',
  'leave',
]);
const { t } = useI18n();

const dismissedLinks = ref(new Set());
const visibleSuggestedLinks = computed(() =>
  props.suggestedLinks.filter(link => {
    const value = link?.url || link?.reference || link;
    return !dismissedLinks.value.has(value);
  })
);
const hasSuggestedLinks = computed(
  () => visibleSuggestedLinks.value.length > 0
);
const errorText = computed(() =>
  typeof props.error === 'string'
    ? props.error
    : t('AGENTS.CREATION.errors.tell')
);

const useSuggestedLink = link => {
  const value = link?.url || link?.reference || link;
  emit('useLink', link);
  dismissedLinks.value = new Set([...dismissedLinks.value, value]);
};

const dismissSuggestedLink = link => {
  const value = link?.url || link?.reference || link;
  dismissedLinks.value = new Set([...dismissedLinks.value, value]);
};
</script>

<template>
  <main
    data-testid="agent-creation-tell"
    class="flex flex-col w-full max-w-6xl gap-6 px-4 py-6 mx-auto sm:px-6 lg:py-8"
  >
    <header class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-3">
        <div>
          <p
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t('AGENTS.CREATION.tell.eyebrow') }}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.tell.title') }}
          </h1>
        </div>
        <NextButton
          ghost
          slate
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.leave')"
          data-action="creation-save-exit"
          @click="emit('leave')"
        />
      </div>
      <p class="max-w-2xl text-sm leading-6 text-n-slate-11">
        {{ t('AGENTS.CREATION.tell.description') }}
      </p>
    </header>

    <div
      v-if="error"
      class="flex items-start gap-3 p-4 border rounded-xl border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
      role="alert"
    >
      <i
        class="mt-0.5 i-lucide-circle-alert size-5 shrink-0"
        aria-hidden="true"
      />
      <div class="flex flex-col flex-1 gap-1">
        <strong class="text-sm">{{ errorText }}</strong>
        <span class="text-xs">{{ t('AGENTS.CREATION.errors.tellHint') }}</span>
      </div>
      <NextButton
        ghost
        slate
        xs
        class="min-h-11"
        :label="t('AGENTS.CREATION.actions.retry')"
        @click="emit('retry')"
      />
    </div>

    <div
      class="grid min-h-[34rem] gap-5 lg:grid-cols-[minmax(0,1.2fr)_minmax(20rem,0.8fr)]"
    >
      <section
        class="flex flex-col min-h-0 gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        :aria-label="t('AGENTS.CREATION.tell.conversation')"
      >
        <div
          class="flex items-center justify-between gap-3 pb-3 border-b border-n-weak"
        >
          <div class="flex items-center gap-2">
            <span
              class="flex items-center justify-center rounded-lg size-8 bg-n-iris-3 text-n-iris-11"
            >
              <i class="i-lucide-sparkles size-4" aria-hidden="true" />
            </span>
            <span class="text-sm font-semibold text-n-slate-12">
              {{ t('AGENTS.CREATION.tell.conversation') }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11">
            {{ t('AGENTS.CREATION.tell.conversationHint') }}
          </span>
        </div>
        <div class="flex-1 min-h-0">
          <div
            class="[&_button]:!min-h-11 [&_button]:!min-w-11 [&_textarea]:!min-h-11"
          >
            <BuilderChat
              :messages="messages"
              :is-sending="isSending"
              :can-attach="Boolean(agentId)"
              :is-attaching="isAttaching"
              @send="emit('send', $event)"
              @attach="emit('attach', $event)"
            />
          </div>
        </div>
      </section>

      <aside class="flex flex-col min-w-0 gap-4">
        <BuildKnowsPanel :knows="knows" :is-internal="isInternal" />
        <BuildMaterialsPanel
          :agent-id="agentId"
          :reusable-sources="reusableSources"
          :reusable-sources-loaded="reusableSourcesLoaded"
          :reusable-sources-loading="reusableSourcesLoading"
          :reusable-sources-error="reusableSourcesError"
          :is-copying="isCopying"
          @copy="emit('copy-source', $event)"
        />
        <div
          v-if="hasSuggestedLinks"
          class="flex flex-col gap-3 p-4 border rounded-2xl border-n-iris-5 bg-n-iris-2"
        >
          <div class="flex items-start gap-2">
            <i
              class="mt-0.5 i-lucide-link size-4 text-n-iris-11"
              aria-hidden="true"
            />
            <div>
              <h2 class="text-sm font-semibold text-n-iris-12">
                {{ t('AGENTS.CREATION.tell.suggestedLinks') }}
              </h2>
              <p class="mt-1 text-xs leading-5 text-n-iris-11">
                {{ t('AGENTS.CREATION.tell.suggestedLinksHint') }}
              </p>
            </div>
          </div>
          <ul class="flex flex-col gap-2" role="list">
            <li
              v-for="link in visibleSuggestedLinks"
              :key="link.url || link.reference || link"
              class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-lg bg-n-solid-1"
            >
              <span class="min-w-0 text-xs truncate text-n-slate-12">
                {{ link.title || link.url || link.reference || link }}
              </span>
              <span class="flex gap-2 ms-auto">
                <NextButton
                  ghost
                  slate
                  class="min-h-11"
                  :label="t('AGENTS.CREATION.actions.useLink')"
                  @click="useSuggestedLink(link)"
                />
                <NextButton
                  ghost
                  slate
                  class="min-h-11"
                  :label="t('AGENTS.CREATION.actions.notNow')"
                  @click="dismissSuggestedLink(link)"
                />
              </span>
            </li>
          </ul>
        </div>

        <div
          class="flex flex-col gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-start gap-2">
            <i
              class="mt-0.5 i-lucide-arrow-right size-4 text-n-slate-10"
              aria-hidden="true"
            />
            <p class="text-xs leading-5 text-n-slate-11">
              {{ t('AGENTS.CREATION.tell.continueHint') }}
            </p>
          </div>
          <NextButton
            solid
            slate
            block
            class="min-h-11"
            :label="t('AGENTS.CREATION.actions.continueToTest')"
            :disabled="!canContinue || isSending"
            data-action="creation-continue"
            data-testid="creation-tell-next"
            @click="emit('continue')"
          />
        </div>
      </aside>
    </div>
  </main>
</template>
