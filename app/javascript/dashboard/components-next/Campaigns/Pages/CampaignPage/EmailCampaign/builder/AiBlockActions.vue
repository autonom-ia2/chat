<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';

import EmailCampaignAiAPI from 'dashboard/api/emailCampaignAi';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useEmailEditor } from './composables/useEmailEditor';

// SEM props: a fonte da verdade do editor e o singleton useEmailEditor().
// A top bar monta `<AiBlockActions v-if="isReady" />` (sem prop `editor`).
// Contrato congelado em /tmp/uxshot/contracts/FE-AI.md §2.
const { t } = useI18n();

const isMenuOpen = ref(false);
const isRewriting = ref(false);
let rewriteRequestId = 0;

const { selectedComponent, isTextSelected, getSelectedText, setSelectedText } =
  useEmailEditor();
// #1093: only a text or a button can be improved; otherwise the button is off with a hint.
const canImprove = computed(() => isTextSelected.value && !isRewriting.value);

const INSTRUCTIONS = {
  rewrite: 'Reescreva o texto mantendo o sentido e o tom.',
  shorten: 'Encurte o texto mantendo a mensagem principal.',
  persuasive:
    'Reescreva o texto de forma mais persuasiva, com foco em conversão.',
};

const menuItems = computed(() => [
  {
    label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.REWRITE'),
    value: 'rewrite',
    action: 'rewrite',
    icon: 'i-lucide-refresh-cw',
  },
  {
    label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.SHORTEN'),
    value: 'shorten',
    action: 'shorten',
    icon: 'i-lucide-scissors',
  },
  {
    label: t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.PERSUASIVE'),
    value: 'persuasive',
    action: 'persuasive',
    icon: 'i-lucide-megaphone',
  },
]);

const humanizeError = error => {
  if (error?.response?.data?.error === 'ai_not_configured') {
    return t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.NOT_CONFIGURED');
  }
  return t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.ERROR');
};

const handleAction = async ({ action }) => {
  isMenuOpen.value = false;

  const text = getSelectedText().trim();
  if (!text) {
    useAlert(t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.NO_TEXT'));
    return;
  }

  rewriteRequestId += 1;
  const requestId = rewriteRequestId;
  const requestComponent = selectedComponent.value;
  isRewriting.value = true;
  try {
    const { data } = await EmailCampaignAiAPI.rewrite({
      text,
      instruction: INSTRUCTIONS[action],
    });
    if (
      requestId !== rewriteRequestId ||
      requestComponent !== selectedComponent.value ||
      text !== getSelectedText().trim()
    )
      return;
    setSelectedText(data.text);
  } catch (error) {
    if (
      requestId !== rewriteRequestId ||
      requestComponent !== selectedComponent.value ||
      text !== getSelectedText().trim()
    )
      return;
    useAlert(humanizeError(error));
  } finally {
    if (requestId === rewriteRequestId) isRewriting.value = false;
  }
};

watch(selectedComponent, () => {
  rewriteRequestId += 1;
  isRewriting.value = false;
  isMenuOpen.value = false;
});

onBeforeUnmount(() => {
  rewriteRequestId += 1;
});
</script>

<template>
  <div class="relative">
    <OnClickOutside @trigger="isMenuOpen = false">
      <Button
        icon="i-lucide-sparkles"
        color="blue"
        variant="solid"
        size="sm"
        type="button"
        class="!min-h-11 w-full justify-center"
        :label="t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.TRIGGER')"
        :is-loading="isRewriting"
        :disabled="!canImprove"
        :aria-describedby="isTextSelected ? undefined : 'ai-block-hint'"
        data-test="ai-block-trigger"
        @click="isMenuOpen = !isMenuOpen"
      />
      <DropdownMenu
        v-if="isMenuOpen"
        :menu-items="menuItems"
        class="z-50 w-56 mt-2 ltr:right-0 rtl:left-0 top-full"
        @action="handleAction"
      />
    </OnClickOutside>
    <p
      v-if="!isTextSelected"
      id="ai-block-hint"
      class="m-0 mt-2 text-sm leading-5 text-n-slate-11"
      data-test="ai-block-hint"
    >
      {{ t('CAMPAIGN.EMAIL_CAMPAIGN.AI.BLOCK_ACTIONS.HINT') }}
    </p>
  </div>
</template>
