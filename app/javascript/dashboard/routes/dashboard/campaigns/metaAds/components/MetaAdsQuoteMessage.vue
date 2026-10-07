<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MessageApi from 'dashboard/api/inbox/message';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

// Mensagem sugerida para retomar uma proposta parada (#1100, F4a). A IA escreve; a pessoa lê, edita e só então
// clica em "Enviar na conversa". Nada sai sozinho, e a tela não reenvia: depois de enviada, o botão some.
const props = defineProps({
  // A linha da proposta parada do painel: { id, conversation_id }.
  card: { type: Object, required: true },
});

const { t } = useI18n();
const state = ref('idle'); // idle | writing | ready | declined | error | sent
const suggestion = ref(null);
const draft = ref('');
const sending = ref(false);

const fieldId = computed(() => `meta-ads-quote-message-${props.card.id}`);

const suggest = async () => {
  state.value = 'writing';
  try {
    const { data } = await CrmMetaAdsConnectionAPI.quoteMessage(props.card.id);
    suggestion.value = data.quote_message;
    if (suggestion.value.applies) {
      draft.value = suggestion.value.message;
      state.value = 'ready';
    } else {
      state.value = 'declined';
    }
  } catch {
    state.value = 'error';
  }
};

const reasonText = computed(() => {
  const reason = suggestion.value?.reason || 'ai_error';
  return t(`CRM_KANBAN.META_ADS_HUB.AI.QUOTE.REASONS.${reason.toUpperCase()}`);
});

const conversationId = computed(
  () => suggestion.value?.conversation_id || props.card.conversation_id
);

const send = async () => {
  const message = draft.value.trim();
  if (!message || sending.value) return;
  sending.value = true;
  try {
    await MessageApi.create({ conversationId: conversationId.value, message });
    state.value = 'sent';
    useAlert(t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SENT'));
  } catch {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SEND_FAILED'));
  } finally {
    sending.value = false;
  }
};

// O navegador pode negar a área de transferência (permissão, iframe, página sem foco): a pessoa fica sabendo.
const copy = async () => {
  try {
    await copyTextToClipboard(draft.value);
    useAlert(t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.COPIED'));
  } catch {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.COPY_FAILED'));
  }
};
</script>

<template>
  <button
    v-if="['idle', 'writing', 'error'].includes(state)"
    type="button"
    data-quote-suggest
    :disabled="state === 'writing'"
    :aria-busy="state === 'writing'"
    class="inline-flex items-center gap-1.5 px-3 text-[13px] font-440 border border-solid rounded-lg min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
    @click="suggest"
  >
    <span
      class="size-3.5"
      :class="
        state === 'writing'
          ? 'i-lucide-loader-circle animate-spin'
          : 'i-lucide-sparkles'
      "
      aria-hidden="true"
    />
    {{
      state === 'writing'
        ? $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.WRITING')
        : $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SUGGEST')
    }}
  </button>

  <div
    v-if="state === 'ready' || state === 'sent'"
    data-quote-ready
    class="flex flex-col w-full gap-3 pt-3 border-0 border-t border-solid basis-full border-n-weak"
  >
    <label
      :for="fieldId"
      class="text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.LABEL') }}
    </label>
    <textarea
      :id="fieldId"
      v-model="draft"
      data-quote-draft
      rows="6"
      maxlength="700"
      :readonly="state === 'sent'"
      class="w-full !h-auto min-h-40 sm:min-h-32 px-3 py-2 m-0 text-sm font-420 leading-relaxed border border-solid rounded-lg resize-y border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:outline-none"
    />
    <p
      v-if="suggestion.source_quote"
      data-quote-source
      class="m-0 text-xs font-420 leading-relaxed text-n-slate-11"
    >
      {{
        $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SOURCE', {
          quote: suggestion.source_quote,
        })
      }}
    </p>
    <div class="flex flex-wrap items-center gap-2">
      <button
        v-if="state === 'ready'"
        type="button"
        data-quote-send
        :disabled="sending || !draft.trim()"
        class="inline-flex items-center gap-1.5 px-4 text-[13px] font-520 border-0 rounded-lg min-h-11 bg-n-brand text-white hover:opacity-90 disabled:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2"
        @click="send"
      >
        <span class="i-lucide-send size-3.5" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SEND') }}
      </button>
      <span
        v-else
        data-quote-sent
        role="status"
        class="inline-flex items-center gap-1.5 text-[13px] font-440 text-n-teal-11"
      >
        <span class="i-lucide-check size-3.5" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SENT_STATE') }}
      </span>
      <button
        type="button"
        data-quote-copy
        class="inline-flex items-center gap-1.5 px-3 text-[13px] font-440 border border-solid rounded-lg min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="copy"
      >
        <span class="i-lucide-copy size-3.5" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.COPY') }}
      </button>
    </div>
  </div>

  <p
    v-if="state === 'declined' || state === 'error'"
    data-quote-declined
    role="status"
    class="flex items-start w-full gap-1.5 pt-3 m-0 text-[13px] font-420 leading-relaxed border-0 border-t border-solid basis-full border-n-weak text-n-slate-11"
  >
    <span class="i-lucide-info size-3.5 mt-0.5 flex-none" aria-hidden="true" />
    <span>
      {{
        state === 'error'
          ? $t('CRM_KANBAN.META_ADS_HUB.AI.QUOTE.FAILED')
          : reasonText
      }}
    </span>
  </p>
</template>
