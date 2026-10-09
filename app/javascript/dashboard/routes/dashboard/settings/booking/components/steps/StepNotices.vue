<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BookingChoiceCards from '../BookingChoiceCards.vue';
import {
  CANCEL_UNTIL_OPTIONS,
  DEFAULT_CANCEL_UNTIL,
  NOTICE_PRESETS,
} from '../../constants';
import {
  templateChoice,
  templateKinds,
  usableTemplates,
} from '../../bookingNotices';
import { formatMinutes } from '../../bookingFormat';

// Passo 6: avisos no WhatsApp (#1192, J5-A8). Por qual número sai, qual jogo
// de avisos (cartões prontos, sem digitar horário), a mensagem aprovada de cada
// aviso quando o WhatsApp oficial pede, e até quando o cliente pode mudar.
const props = defineProps({
  form: { type: Object, required: true },
  // notice_inbox_options do GET da página: [{ id, name, provider, needs_templates }]
  inboxOptions: { type: Array, default: () => [] },
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

// Trocar de número apaga os modelos: cada número tem a sua lista aprovada.
const chooseInbox = value => {
  const noticeInboxId = value === NO_INBOX ? null : value;
  if (noticeInboxId === props.form.noticeInboxId) return;
  emit('change', { noticeInboxId, noticeTemplates: {} });
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

// Modelos aprovados do número escolhido (lista sincronizada da caixa).
const templates = computed(() => {
  const inbox = chosenInbox.value;
  if (!inbox?.needs_templates) return [];
  return usableTemplates(
    store.getters['inboxes/getFilteredWhatsAppTemplates'](inbox.id)
  );
});

const templateOptionsFor = kind => {
  const options = templates.value.map(template => ({
    value: templateChoice(template),
    label: t('BOOKING.NOTICES.TEMPLATE_OPTION', {
      name: template.name,
      language: template.language,
    }),
  }));
  const saved = props.form.noticeTemplates[kind];
  const savedChoice = saved?.name ? templateChoice(saved) : '';
  if (savedChoice && !options.some(option => option.value === savedChoice)) {
    options.push({
      value: savedChoice,
      label: t('BOOKING.NOTICES.TEMPLATE_OPTION', saved),
    });
  }
  return [{ value: '', label: t('BOOKING.NOTICES.TEMPLATE_NONE') }, ...options];
};

const templateValue = kind => {
  const saved = props.form.noticeTemplates[kind];
  return saved?.name ? templateChoice(saved) : '';
};

const chooseTemplate = (kind, choice) => {
  const others = Object.fromEntries(
    Object.entries(props.form.noticeTemplates).filter(([key]) => key !== kind)
  );
  const template = templates.value.find(
    item => templateChoice(item) === choice
  );
  emit('change', {
    noticeTemplates: template
      ? {
          ...others,
          [kind]: { name: template.name, language: template.language },
        }
      : others,
  });
};

const kinds = computed(() => templateKinds(props.form.noticePreset));
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
        v-if="!inboxOptions.length"
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

      <figure class="flex flex-col gap-2 m-0">
        <figcaption class="text-base font-semibold text-n-slate-12">
          {{ t('BOOKING.NOTICES.SAMPLE_LABEL') }}
        </figcaption>
        <p
          data-notice-sample
          class="m-0 max-w-md px-4 py-3 text-base whitespace-pre-line rounded-2xl rounded-ss-sm bg-n-teal-2 text-n-slate-12 ring-1 ring-inset ring-n-teal-6"
        >
          {{ t('BOOKING.NOTICES.SAMPLE_TEXT') }}
        </p>
      </figure>

      <div
        v-if="chosenInbox?.needs_templates"
        data-notice-templates
        role="group"
        :aria-labelledby="templatesTitleId"
        class="flex flex-col gap-4 p-5 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
      >
        <p
          :id="templatesTitleId"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t('BOOKING.NOTICES.TEMPLATES_LABEL') }}
        </p>
        <p class="m-0 text-base text-n-slate-11">
          {{ t('BOOKING.NOTICES.TEMPLATES_HINT', TEMPLATE_VARIABLES) }}
        </p>
        <p
          v-if="!templates.length"
          data-no-templates
          class="m-0 text-base text-n-amber-12"
        >
          {{ t('BOOKING.NOTICES.TEMPLATES_EMPTY') }}
        </p>
        <div
          v-for="kind in kinds"
          :key="kind"
          :data-template-kind="kind"
          class="flex flex-col gap-2"
        >
          <p class="m-0 text-base font-medium text-n-slate-12">
            {{ t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`) }}
          </p>
          <ChoiceSelect
            :model-value="templateValue(kind)"
            :options="templateOptionsFor(kind)"
            :aria-label="
              t('BOOKING.NOTICES.TEMPLATE_FOR', {
                notice: t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`),
              })
            "
            @update:model-value="chooseTemplate(kind, $event)"
          />
        </div>
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
