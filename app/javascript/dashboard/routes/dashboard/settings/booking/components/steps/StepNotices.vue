<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import WhatsappApiMessageTemplatesAPI from 'dashboard/api/whatsappApiMessageTemplates';
import BookingChoiceCards from '../BookingChoiceCards.vue';
import BookingNoticeTexts from '../BookingNoticeTexts.vue';
import BookingNoticeAutorizacao from '../BookingNoticeAutorizacao.vue';
import {
  CANCEL_UNTIL_OPTIONS,
  DEFAULT_CANCEL_UNTIL,
  NOTICE_PRESETS,
} from '../../constants';
import {
  kindsWithoutTemplate,
  templateChoice,
  templateKinds,
  templatePreview,
  usableTemplates,
} from '../../bookingNotices';
import { formatMinutes } from '../../bookingFormat';
import { useNoticeTemplateSuggestions } from '../../useNoticeTemplateSuggestions';

// Passo 6: avisos no WhatsApp (#1192, J5-A8). Por qual número sai, qual jogo
// de avisos (cartões prontos, sem digitar horário), a mensagem de cada aviso
// quando o número pede (WhatsApp oficial: mensagem aprovada pela Meta; canal API
// de campanhas: modelo de texto do canal), e até quando o cliente pode mudar.
const props = defineProps({
  form: { type: Object, required: true },
  // notice_inbox_options do GET da página: [{ id, name, provider, needs_templates }]
  inboxOptions: { type: Array, default: () => [] },
  // Modelos já gravados na página: voltam quando a pessoa volta ao número salvo.
  savedInboxId: { type: Number, default: null },
  savedTemplates: { type: Object, default: () => ({}) },
  // Página do assistente: a sugestão de modelo da IA é pedida por ela (#1272).
  pageId: { type: Number, default: null },
  // Texto próprio dos avisos (#1354): notice_text_setup da página.
  textSetup: { type: Object, default: null },
});

const emit = defineEmits(['change']);
const { t } = useI18n();
const store = useStore();

const NO_INBOX = '';
// As variáveis do modelo da Meta, como a pessoa as vê ao criar o modelo.
const TEMPLATE_VARIABLES = { name: '{{1}}', when: '{{2}}', link: '{{3}}' };
const templatesTitleId = useId();

const chosenInbox = computed(() =>
  props.inboxOptions.find(inbox => inbox.id === props.form.noticeInboxId)
);
const isOfficial = computed(() => !!chosenInbox.value?.needs_templates);
const isApiChannel = computed(() => chosenInbox.value?.provider === 'api');

// A caixa salva entra na lista mesmo quando a pessoa não a enxerga (escolhida
// por outra pessoa): a escolha não some sem ninguém mexer.
const inboxChoices = computed(() => {
  const choices = [
    { value: NO_INBOX, label: t('BOOKING.NOTICES.INBOX_NONE') },
    ...props.inboxOptions.map(inbox => ({
      value: inbox.id,
      label: inbox.name,
    })),
  ];
  const { noticeInboxId } = props.form;
  if (noticeInboxId && !chosenInbox.value) {
    choices.push({
      value: noticeInboxId,
      label: t('BOOKING.NOTICES.INBOX_CURRENT'),
    });
  }
  return choices;
});

// Trocar de número apaga os modelos: cada número tem a sua lista. Voltar ao
// número salvo devolve as mensagens que já estavam escolhidas para ele.
const chooseInbox = value => {
  const noticeInboxId = value === NO_INBOX ? null : value;
  if (noticeInboxId === props.form.noticeInboxId) return;
  const noticeTemplates =
    noticeInboxId && noticeInboxId === props.savedInboxId
      ? { ...props.savedTemplates }
      : {};
  emit('change', { noticeInboxId, noticeTemplates });
};

// Texto curto do que vale para o número escolhido.
const channelHint = computed(() => {
  const inbox = chosenInbox.value;
  if (!inbox) return '';
  if (inbox.needs_templates) return t('BOOKING.NOTICES.CHANNEL.OFFICIAL');
  if (inbox.provider === 'waha') return t('BOOKING.NOTICES.CHANNEL.WAHA');
  return t('BOOKING.NOTICES.CHANNEL.API');
});

const presetChoices = computed(() =>
  NOTICE_PRESETS.map(preset => ({
    value: preset.key,
    label: t(`BOOKING.NOTICES.PRESETS.${preset.key.toUpperCase()}.LABEL`),
    hint: t(`BOOKING.NOTICES.PRESETS.${preset.key.toUpperCase()}.HINT`),
    badge: preset.recommended ? t('BOOKING.NOTICES.RECOMMENDED') : '',
  }))
);

const cancelChoices = computed(() => {
  const values = CANCEL_UNTIL_OPTIONS.includes(props.form.cancelUntilMinutes)
    ? CANCEL_UNTIL_OPTIONS
    : [...CANCEL_UNTIL_OPTIONS, props.form.cancelUntilMinutes].sort(
        (a, b) => a - b
      );
  return values.map(value => ({
    value,
    label: value
      ? t('BOOKING.NOTICES.CANCEL_VALUE', { value: formatMinutes(t, value) })
      : t('BOOKING.NOTICES.CANCEL_ANYTIME'),
    badge:
      value === DEFAULT_CANCEL_UNTIL ? t('BOOKING.NOTICES.RECOMMENDED') : '',
  }));
});

// Mensagens do canal API de campanhas: lidas do canal quando ele é escolhido.
// Quem não pode ver as campanhas recebe recusa: a tela diz que não deu para ver.
const apiTemplates = ref([]);
const apiTemplatesFailed = ref(false);
const loadApiTemplates = async inbox => {
  apiTemplates.value = [];
  apiTemplatesFailed.value = false;
  if (inbox?.provider !== 'api') return;
  try {
    const { data } = await WhatsappApiMessageTemplatesAPI.get(inbox.id);
    if (chosenInbox.value?.id !== inbox.id) return;
    apiTemplates.value = Array.isArray(data?.payload) ? data.payload : [];
  } catch (error) {
    apiTemplatesFailed.value = true;
  }
};
watch(chosenInbox, loadApiTemplates, { immediate: true });

// Mensagens que a pessoa pode escolher para o número.
const templates = computed(() => {
  const inbox = chosenInbox.value;
  if (isApiChannel.value) return apiTemplates.value;
  if (!inbox?.needs_templates) return [];
  return usableTemplates(
    store.getters['inboxes/getConversationWhatsAppTemplates'](inbox.id)
  );
});

const samples = computed(() => ({
  name: t('BOOKING.NOTICES.SAMPLE_NAME'),
  when: t('BOOKING.NOTICES.SAMPLE_WHEN'),
  link: t('BOOKING.NOTICES.SAMPLE_LINK'),
}));

// A opção mostra como a mensagem chega (nunca o nome técnico); o idioma só
// aparece quando a lista tem mais de um.
const hasManyLanguages = computed(
  () => new Set(templates.value.map(item => item.language)).size > 1
);
const optionLabel = template => {
  if (isApiChannel.value) return template.name;
  const preview = templatePreview(template, samples.value) || template.name;
  return hasManyLanguages.value
    ? t('BOOKING.NOTICES.TEMPLATE_OPTION_LANGUAGE', {
        preview,
        language: template.language,
      })
    : preview;
};

const templateOptionsFor = kind => {
  const options = templates.value.map(template => ({
    value: templateChoice(template),
    label: optionLabel(template),
  }));
  const savedChoice = templateChoice(props.form.noticeTemplates[kind]);
  if (savedChoice && !options.some(option => option.value === savedChoice)) {
    options.push({
      value: savedChoice,
      label: t('BOOKING.NOTICES.TEMPLATE_SAVED'),
    });
  }
  // Canal API: "modelo de texto" (salvo pela conta); oficial: "mensagem aprovada".
  const none = isApiChannel.value
    ? t('BOOKING.NOTICES.API_TEMPLATE_NONE')
    : t('BOOKING.NOTICES.TEMPLATE_NONE');
  return [{ value: '', label: none }, ...options];
};

const templateLabelFor = kind => {
  const notice = t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`);
  return isApiChannel.value
    ? t('BOOKING.NOTICES.API_TEMPLATE_FOR', { notice })
    : t('BOOKING.NOTICES.TEMPLATE_FOR', { notice });
};

const templateValue = kind => templateChoice(props.form.noticeTemplates[kind]);

const chooseTemplate = (kind, choice) => {
  const others = Object.fromEntries(
    Object.entries(props.form.noticeTemplates).filter(([key]) => key !== kind)
  );
  const template = templates.value.find(
    item => templateChoice(item) === choice
  );
  if (!template) {
    emit('change', { noticeTemplates: others });
    return;
  }
  const value = isApiChannel.value
    ? { id: template.id }
    : { name: template.name, language: template.language };
  emit('change', { noticeTemplates: { ...others, [kind]: value } });
};

const kinds = computed(() => templateKinds(props.form.noticePreset));

// WhatsApp oficial (#1272): a IA sugere a mensagem de cada aviso vazio. Criar
// na Meta pela página (v1) saiu em #1612: no Cloud, o sistema cria os modelos
// v2 com a autorização do dono (BookingNoticeAutorizacao).
const {
  suggestions,
  loading: suggesting,
  isSuggested,
  markTouched,
} = useNoticeTemplateSuggestions({
  pageId: () => props.pageId,
  form: () => props.form,
  inbox: computed(() => (isOfficial.value ? chosenInbox.value : null)),
  kinds,
  onChange: change => emit('change', change),
});
// Escolha da pessoa (inclusive "nenhuma"): a sugestão não mexe mais no aviso.
const chooseByHand = (kind, choice) => {
  markTouched(kind);
  chooseTemplate(kind, choice);
};
// Os modelos v2 só existem no WhatsApp oficial Cloud (MetaClient.supported?).
const isCloud = computed(
  () => chosenInbox.value?.provider === 'whatsapp_cloud'
);

// Avisos sem mensagem escolhida: a pessoa sabe antes de salvar que esses só saem
// para quem falou com a empresa nas últimas 24 horas.
const missingKinds = computed(() =>
  kindsWithoutTemplate(props.form, chosenInbox.value)
    .map(kind => t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`))
    .join(', ')
);
const missingText = computed(() =>
  isApiChannel.value
    ? t('BOOKING.NOTICES.API_MISSING_TEMPLATES', { kinds: missingKinds.value })
    : t('BOOKING.NOTICES.MISSING_TEMPLATES', { kinds: missingKinds.value })
);
const emptyText = computed(() => {
  if (isApiChannel.value) {
    return apiTemplatesFailed.value
      ? t('BOOKING.NOTICES.API_TEMPLATES_FAILED')
      : t('BOOKING.NOTICES.API_TEMPLATES_EMPTY');
  }
  return t('BOOKING.NOTICES.TEMPLATES_EMPTY');
});
</script>

<template>
  <section class="flex flex-col gap-6">
    <div class="flex flex-col gap-2">
      <h2
        tabindex="-1"
        class="m-0 text-2xl font-semibold text-n-slate-12 focus:outline-none"
      >
        {{ t('BOOKING.NOTICES.TITLE') }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.NOTICES.INTRO') }}
      </p>
    </div>

    <div class="flex flex-col gap-2">
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.NOTICES.INBOX_LABEL') }}
      </p>
      <ChoiceSelect
        data-notice-inbox
        :model-value="form.noticeInboxId ?? NO_INBOX"
        :options="inboxChoices"
        :aria-label="t('BOOKING.NOTICES.INBOX_LABEL')"
        @update:model-value="chooseInbox"
      />
      <p
        v-if="!inboxOptions.length && !form.noticeInboxId"
        data-no-inboxes
        class="m-0 text-base text-n-slate-11"
      >
        {{ t('BOOKING.NOTICES.NO_INBOXES') }}
      </p>
      <p
        v-else-if="channelHint"
        data-channel-hint
        class="m-0 text-base text-n-slate-11"
      >
        {{ channelHint }}
      </p>
    </div>

    <template v-if="form.noticeInboxId">
      <BookingChoiceCards
        data-notice-preset
        :legend="t('BOOKING.NOTICES.PRESET_LABEL')"
        :options="presetChoices"
        :model-value="form.noticePreset"
        @update:model-value="emit('change', { noticePreset: $event })"
      />

      <BookingNoticeTexts
        v-if="textSetup"
        :form="form"
        :kinds="kinds"
        :setup="textSetup"
        :page-id="pageId"
        @change="emit('change', $event)"
      />

      <div
        v-if="isOfficial || isApiChannel"
        data-notice-templates
        role="group"
        :aria-labelledby="templatesTitleId"
        class="flex flex-col gap-4 p-5 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <p
          :id="templatesTitleId"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{
            isApiChannel
              ? t('BOOKING.NOTICES.API_TEMPLATES_LABEL')
              : t('BOOKING.NOTICES.TEMPLATES_LABEL')
          }}
        </p>
        <p class="m-0 text-base text-n-slate-11">
          {{
            isApiChannel
              ? t('BOOKING.NOTICES.API_TEMPLATES_HINT')
              : t('BOOKING.NOTICES.TEMPLATES_HINT', TEMPLATE_VARIABLES)
          }}
        </p>
        <p
          v-if="!templates.length"
          data-no-templates
          class="m-0 text-base text-n-amber-12"
        >
          {{ emptyText }}
        </p>
        <div
          v-for="kind in kinds"
          :key="kind"
          :data-template-kind="kind"
          class="flex flex-col gap-2"
        >
          <div class="flex flex-wrap items-center gap-2">
            <p class="m-0 text-base font-medium text-n-slate-12">
              {{ t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`) }}
            </p>
            <span
              v-if="isOfficial && isSuggested(kind)"
              data-suggested
              class="px-2 py-0.5 text-sm font-medium rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ t('BOOKING.NOTICES.AUTO.SUGGESTED') }}
            </span>
          </div>
          <ChoiceSelect
            :model-value="templateValue(kind)"
            :options="templateOptionsFor(kind)"
            :aria-label="templateLabelFor(kind)"
            @update:model-value="chooseByHand(kind, $event)"
          />
          <p
            v-if="isOfficial && isSuggested(kind) && suggestions[kind].reason"
            data-suggested-reason
            class="m-0 text-sm text-n-slate-11"
          >
            {{ suggestions[kind].reason }}
          </p>
        </div>
        <p
          v-if="isOfficial && suggesting"
          data-suggesting
          role="status"
          class="m-0 text-sm text-n-slate-11"
        >
          {{ t('BOOKING.NOTICES.AUTO.SUGGESTING') }}
        </p>
        <p
          v-if="templates.length && missingKinds"
          data-missing-templates
          class="m-0 text-base text-n-amber-12"
        >
          {{ missingText }}
        </p>
        <BookingNoticeAutorizacao v-if="isCloud" />
      </div>
    </template>

    <BookingChoiceCards
      data-cancel-until
      :legend="t('BOOKING.NOTICES.CANCEL_LABEL')"
      :hint="t('BOOKING.NOTICES.CANCEL_HINT')"
      :options="cancelChoices"
      :model-value="form.cancelUntilMinutes"
      @update:model-value="emit('change', { cancelUntilMinutes: $event })"
    />
  </section>
</template>
