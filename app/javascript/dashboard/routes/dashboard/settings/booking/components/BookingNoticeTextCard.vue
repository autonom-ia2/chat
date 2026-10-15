<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import {
  noticeTextHasLink,
  noticeTextPreview,
  noticeTextProblem,
  toFriendly,
  toKeys,
} from '../bookingNoticeTexts';

// O texto de UM aviso (#1354): parte do texto padrão, a pessoa edita, pede à
// IA (que só preenche o campo; salvar é o botão da página) ou volta ao padrão.
// Ao lado, a prévia como o cliente vê, com nome e horário de exemplo e a saída
// de parar que o sistema sempre põe (linha no texto, ou botão à parte, #1562).
// Os campos aparecem pelo rótulo leigo.
const props = defineProps({
  kind: { type: String, required: true },
  // Texto próprio salvo/editado, com as chaves; vazio = texto padrão.
  text: { type: String, default: '' },
  // notice_text_setup da página: defaults, fields, samples, stop_line,
  // manage_line e notice_channel (tipo da caixa de avisos salva).
  setup: { type: Object, required: true },
  tone: { type: String, default: '' },
  pageId: { type: Number, default: null },
});

const emit = defineEmits(['change']);
const { t } = useI18n();
const textareaId = useId();
const errorId = useId();
const hintId = useId();

const fields = computed(() => props.setup.fields || []);
const defaultText = computed(() => props.setup.defaults?.[props.kind] || '');
const effective = computed(() => props.text || defaultText.value);
const isCustom = computed(() => Boolean(props.text));

const draft = ref(toFriendly(effective.value, fields.value));
// O que este cartão mandou por último: só mudança de fora (outra página
// carregada) reescreve o campo enquanto a pessoa digita.
let lastEmitted = props.text;

// Igual ao padrão vai vazio: a página segue o texto padrão.
const emitText = keysText => {
  lastEmitted = keysText === defaultText.value ? '' : keysText;
  emit('change', lastEmitted);
};
const showText = keysText => {
  draft.value = toFriendly(keysText || defaultText.value, fields.value);
  emitText(keysText);
};
watch(
  () => props.text,
  value => {
    if (value === lastEmitted) return;
    lastEmitted = value;
    draft.value = toFriendly(value || defaultText.value, fields.value);
  }
);

const onInput = event => {
  draft.value = event.target.value;
  emitText(toKeys(draft.value, fields.value));
};

const options = ref([]);
const writing = ref(false);
const aiError = ref('');

const problem = computed(() =>
  isCustom.value ? noticeTextProblem(props.text) : null
);
// Sem o link no texto, o sistema o manda: no WhatsApp oficial (whatsapp_cloud,
// o único que mostra o botão), num botão. Nas outras caixas, só a linha.
// #1562: a prévia mostra sempre o caso de texto (com a linha de parar), que vale
// em qualquer caixa; o botão depende da janela aberta, do Híbrido e do limite,
// que a tela não sabe. A nota explica o caso com botão ("Parar avisos" à parte).
const showButtonNote = computed(
  () =>
    props.setup.notice_channel === 'whatsapp_cloud' &&
    !noticeTextHasLink(effective.value)
);
const preview = computed(() =>
  noticeTextPreview(
    effective.value,
    props.setup.samples || {},
    props.setup.stop_line,
    props.setup.manage_line
  )
);

// Põe o campo onde está o cursor.
const textarea = ref(null);
const insertField = field => {
  const element = textarea.value;
  const token = `[${field.label}]`;
  const start = element?.selectionStart ?? draft.value.length;
  const end = element?.selectionEnd ?? draft.value.length;
  draft.value = `${draft.value.slice(0, start)}${token}${draft.value.slice(end)}`;
  emitText(toKeys(draft.value, fields.value));
  // O cursor fica logo depois do campo posto, para o próximo ir em seguida.
  nextTick(() => {
    const caret = start + token.length;
    element?.focus();
    element?.setSelectionRange(caret, caret);
  });
};

const resetToDefault = () => {
  options.value = [];
  showText('');
};

// "Escrever com IA": até 2 opções; escolher uma só preenche o campo.
const writeWithAi = async () => {
  writing.value = true;
  aiError.value = '';
  options.value = [];
  try {
    const { data } = await BookingPagesAPI.noticeTextSuggestions(
      props.pageId,
      props.kind,
      props.tone
    );
    options.value = data?.payload?.options || [];
    if (!options.value.length)
      aiError.value = t('BOOKING.NOTICES.TEXTS.AI_FAILED');
  } catch (error) {
    aiError.value =
      error?.response?.data?.message || t('BOOKING.NOTICES.TEXTS.AI_FAILED');
  } finally {
    writing.value = false;
  }
};
const useOption = option => {
  showText(option.text);
  options.value = [];
};
const optionPreview = option =>
  noticeTextPreview(
    option.text,
    props.setup.samples || {},
    '',
    props.setup.manage_line
  );

const buttonClass =
  'inline-flex items-center gap-2 px-4 text-base font-semibold min-h-11 rounded-xl text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed';
</script>

<template>
  <section
    :data-notice-text="kind"
    class="flex flex-col gap-4 p-5 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-wrap items-center gap-2">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`BOOKING.NOTICES.KINDS.${kind.toUpperCase()}`) }}
      </h3>
      <span
        data-text-origin
        class="px-2 py-0.5 text-sm font-medium rounded-full"
        :class="
          isCustom
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-alpha-2 text-n-slate-11'
        "
      >
        {{
          isCustom
            ? t('BOOKING.NOTICES.TEXTS.CUSTOM')
            : t('BOOKING.NOTICES.TEXTS.DEFAULT')
        }}
      </span>
    </div>
    <p v-if="kind === 'booked'" class="m-0 text-sm text-n-slate-11">
      {{ t('BOOKING.NOTICES.TEXTS.TEAM_BOOKED') }}
    </p>

    <div class="grid gap-4 md:grid-cols-2">
      <div class="flex flex-col gap-2">
        <label :for="textareaId" class="text-base font-medium text-n-slate-12">
          {{ t('BOOKING.NOTICES.TEXTS.TEXT_LABEL') }}
        </label>
        <textarea
          :id="textareaId"
          ref="textarea"
          data-text-input
          rows="5"
          :value="draft"
          :aria-invalid="problem ? 'true' : 'false'"
          :aria-describedby="problem ? `${errorId} ${hintId}` : hintId"
          class="w-full min-h-36 px-3 py-2 text-base rounded-xl resize-y bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand"
          @input="onInput"
        />
        <p
          v-if="problem"
          :id="errorId"
          data-text-error
          role="alert"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{
            t(`BOOKING.NOTICES.TEXTS.ERRORS.${problem}`, {
              max: setup.max_length,
            })
          }}
        </p>
        <p :id="hintId" class="m-0 text-sm text-n-slate-11">
          {{ t('BOOKING.NOTICES.TEXTS.FIELDS_HINT') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="field in fields"
            :key="field.key"
            type="button"
            :data-insert-field="field.key"
            class="inline-flex items-center px-3 text-sm font-medium min-h-11 rounded-xl text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="insertField(field)"
          >
            {{ t('BOOKING.NOTICES.TEXTS.INSERT', { field: field.label }) }}
          </button>
        </div>
      </div>

      <figure class="flex flex-col gap-2 m-0">
        <figcaption class="text-base font-medium text-n-slate-12">
          {{ t('BOOKING.NOTICES.SAMPLE_LABEL') }}
        </figcaption>
        <p
          data-text-preview
          class="m-0 px-4 py-3 text-base whitespace-pre-line break-words rounded-2xl rounded-ss-sm bg-n-teal-2 text-n-slate-12 ring-1 ring-inset ring-n-teal-6"
        >
          {{ preview }}
        </p>
        <p
          v-if="showButtonNote"
          data-button-note
          class="m-0 text-sm text-n-slate-11"
        >
          {{ t('BOOKING.NOTICES.TEXTS.BUTTON_NOTE') }}
        </p>
      </figure>
    </div>

    <div class="flex flex-wrap items-center gap-3">
      <button
        type="button"
        data-write-ai
        :class="buttonClass"
        :disabled="writing || !pageId"
        :aria-busy="writing ? 'true' : 'false'"
        @click="writeWithAi"
      >
        <span class="i-lucide-sparkles size-4" aria-hidden="true" />
        {{
          writing
            ? t('BOOKING.NOTICES.TEXTS.WRITING')
            : t('BOOKING.NOTICES.TEXTS.WRITE_AI')
        }}
      </button>
      <button
        type="button"
        data-reset-default
        :class="buttonClass"
        :disabled="!isCustom"
        @click="resetToDefault"
      >
        {{ t('BOOKING.NOTICES.TEXTS.RESET') }}
      </button>
    </div>
    <p
      v-if="aiError"
      data-ai-error
      role="alert"
      class="m-0 text-base text-n-ruby-11"
    >
      {{ aiError }}
    </p>

    <div
      v-if="options.length"
      data-ai-options
      role="group"
      aria-live="polite"
      :aria-label="t('BOOKING.NOTICES.TEXTS.OPTIONS_LABEL')"
      class="flex flex-col gap-3"
    >
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ t('BOOKING.NOTICES.TEXTS.OPTIONS_LABEL') }}
      </p>
      <div
        v-for="(option, index) in options"
        :key="index"
        data-ai-option
        class="flex flex-col items-start gap-3 p-4 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <p class="m-0 text-base whitespace-pre-line text-n-slate-12">
          {{ optionPreview(option) }}
        </p>
        <button
          type="button"
          data-use-option
          :class="buttonClass"
          @click="useOption(option)"
        >
          {{ t('BOOKING.NOTICES.TEXTS.USE_OPTION') }}
        </button>
      </div>
    </div>
  </section>
</template>
