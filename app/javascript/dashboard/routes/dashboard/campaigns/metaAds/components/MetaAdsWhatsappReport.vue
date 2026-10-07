<script setup>
import { computed, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import parsePhoneNumber from 'libphonenumber-js';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmMetaAdsWhatsappReportAPI from 'dashboard/api/crmMetaAdsWhatsappReport';
import { clockTime, intlLocale, relativeTime } from '../metaAdsHelpers';

// Anúncios da Meta (#1100, F4b): resumo diário e alerta no WhatsApp do dono (docs/crm/anuncios-meta-f4.md §2).
// Vem desligado. A pessoa escolhe de qual número sai (só os conectados que o servidor devolve) e para qual
// número vai. Quem valida o número, a origem e o modelo da Meta é o servidor; a tela mostra o código que ele
// devolve. "Enviar teste" usa só o que está salvo, nunca o rascunho.
const KINDS = ['whatsapp_cloud', 'waha'];
const TEMPLATE_KEYS = ['summary', 'alert'];
const STATUS_CLASSES = {
  approved: 'bg-n-teal-3 text-n-teal-11',
  pending: 'bg-n-amber-3 text-n-amber-11',
  rejected: 'bg-n-ruby-3 text-n-ruby-11',
  missing: 'bg-n-alpha-2 text-n-slate-11',
};
const KNOWN_ERRORS = [
  'invalid_phone',
  'phone_required',
  'origin_required',
  'inbox_not_connected',
  'template_not_approved',
  'not_connected',
  'rate_limited',
  'send_failed',
  'send_uncertain',
  'whatsapp_number_not_found',
];
// Erro que pertence a um campo aparece embaixo dele; o resto, junto do botão.
const FIELD_OF_ERROR = {
  invalid_phone: 'phone',
  phone_required: 'phone',
  origin_required: 'origin',
  inbox_not_connected: 'origin',
};

const { t, locale } = useI18n();
const uid = useId();
const ids = {
  title: `${uid}-title`,
  phone: `${uid}-phone`,
  phoneHint: `${uid}-phone-hint`,
  phoneError: `${uid}-phone-error`,
  originError: `${uid}-origin-error`,
};

const report = ref(null);
const loading = ref(true);
const loadFailed = ref(false);
const form = ref({
  enabled: false,
  alert_enabled: false,
  inbox_id: '',
  phone: '',
});
const saving = ref(false);
const saveError = ref(null);
const testing = ref(false);
const testResult = ref(null);

const errorText = code =>
  t(
    `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ERRORS.${KNOWN_ERRORS.includes(code) ? code.toUpperCase() : 'GENERIC'}`
  );
const errorCode = error => error?.response?.data?.error || 'generic';

const formatPhone = value =>
  parsePhoneNumber(value || '')?.formatInternational() || value;

const formFrom = data => ({
  enabled: Boolean(data.enabled),
  alert_enabled: Boolean(data.alert_enabled),
  inbox_id: data.inbox_id ?? '',
  // O servidor guarda E.164; a tela mostra no formato internacional legível.
  phone: formatPhone(data.phone) || '',
});

const origins = computed(() => report.value?.origins || []);
const originGroups = computed(() =>
  KINDS.map(kind => ({
    label: t(
      `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.KIND.${kind.toUpperCase()}`
    ),
    options: origins.value
      .filter(origin => origin.kind === kind)
      .map(origin => ({
        value: origin.inbox_id,
        label: `${origin.name} · ${formatPhone(origin.phone_number)}`,
      })),
  })).filter(group => group.options.length)
);
const origin = computed(() =>
  origins.value.find(item => item.inbox_id === form.value.inbox_id)
);
// A origem salva saiu da lista: a caixa foi desconectada depois que a pessoa a escolheu.
const originGone = computed(
  () =>
    Boolean(report.value?.inbox_id) &&
    !origins.value.some(item => item.inbox_id === report.value.inbox_id)
);
const isOfficial = computed(() => origin.value?.kind === 'whatsapp_cloud');

const timeZoneName = computed(() => {
  const timeZone = report.value?.schedule?.time_zone;
  if (!timeZone) return '';
  return (
    new Intl.DateTimeFormat(intlLocale(locale.value), {
      timeZone,
      timeZoneName: 'long',
    })
      .formatToParts(new Date())
      .find(part => part.type === 'timeZoneName')?.value || timeZone
  );
});

const toggles = computed(() => [
  {
    key: 'enabled',
    label: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.SUMMARY_TOGGLE'),
    hint: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.SUMMARY_TOGGLE_HINT', {
      time: report.value?.schedule?.summary_local_time || '',
      zone: timeZoneName.value,
    }),
    template: 'summary',
  },
  {
    key: 'alert_enabled',
    label: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ALERT_TOGGLE'),
    hint: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ALERT_TOGGLE_HINT', {
      time: report.value?.schedule?.alert_local_time || '',
      zone: timeZoneName.value,
    }),
    template: 'alert',
  },
]);

const templateStatus = key => {
  const status = origin.value?.templates?.[key];
  return STATUS_CLASSES[status] ? status : 'missing';
};
// No Oficial, ligar um envio sem o modelo dele aprovado não envia nada; a tela diz isso antes de salvar.
const blockedByTemplate = toggle =>
  isOfficial.value &&
  form.value[toggle.key] &&
  templateStatus(toggle.template) !== 'approved';

const templates = computed(() =>
  TEMPLATE_KEYS.map(key => ({
    key,
    name: report.value?.template_texts?.[key]?.name || '',
    body: report.value?.template_texts?.[key]?.body || '',
    status: templateStatus(key),
  }))
);

// Só as chaves que mudaram: as ausentes ficam como estão no servidor.
const changes = computed(() => {
  if (!report.value) return {};
  const saved = formFrom(report.value);
  const result = {};
  Object.keys(saved).forEach(key => {
    if (form.value[key] === saved[key]) return;
    if (key === 'inbox_id') result.inbox_id = form.value.inbox_id || null;
    else if (key === 'phone') result.phone = form.value.phone.trim() || null;
    else result[key] = form.value[key];
  });
  return result;
});
const dirty = computed(() => Object.keys(changes.value).length > 0);
// O que impede o teste agora, na ordem em que a pessoa resolve: números não salvos, origem desconectada,
// mudanças ainda não salvas. null = pode testar.
const testBlocker = computed(() => {
  if (!report.value?.inbox_id || !report.value?.phone) return 'NEEDS_SAVE';
  if (originGone.value) return 'NEEDS_ORIGIN';
  if (dirty.value) return 'NEEDS_SAVE_CHANGES';
  return null;
});
const canTest = computed(() => testBlocker.value === null);
const testHint = computed(
  () =>
    ({
      NEEDS_SAVE: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST_NEEDS_SAVE'),
      NEEDS_ORIGIN: t(
        'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST_NEEDS_ORIGIN'
      ),
      NEEDS_SAVE_CHANGES: t(
        'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST_NEEDS_SAVE_CHANGES'
      ),
    })[testBlocker.value]
);

const fieldError = field =>
  saveError.value && FIELD_OF_ERROR[saveError.value] === field
    ? errorText(saveError.value)
    : null;
const generalError = computed(() =>
  saveError.value && !FIELD_OF_ERROR[saveError.value]
    ? errorText(saveError.value)
    : null
);

const history = computed(() => {
  const data = report.value || {};
  const rows = [];
  const summary = relativeTime(data.last_summary_at, locale.value);
  const alert = relativeTime(data.last_alert_at, locale.value);
  if (summary)
    rows.push({
      key: 'summary',
      text: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.SUMMARY', {
        time: summary,
      }),
    });
  if (alert)
    rows.push({
      key: 'alert',
      text: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.ALERT', {
        time: alert,
      }),
    });
  return rows;
});
const lastError = computed(() => {
  const data = report.value;
  if (!data?.last_error) return null;
  const time = relativeTime(data.last_error_at, locale.value) || '';
  // Ontem sem gasto nem conversa não é falha: o servidor só registra que não houve o que mandar.
  if (data.last_error === 'nothing_to_report') {
    return {
      info: true,
      text: t(
        'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.NOTHING_TO_REPORT',
        { time }
      ),
    };
  }
  return {
    info: false,
    text: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.ERROR', {
      time,
      message: errorText(data.last_error),
    }),
  };
});

const apply = data => {
  report.value = data;
  if (data) form.value = formFrom(data);
};

const load = async () => {
  loading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await CrmMetaAdsWhatsappReportAPI.get();
    apply(data.whatsapp_report);
  } catch {
    loadFailed.value = true;
  } finally {
    loading.value = false;
  }
};

const toggle = key => {
  form.value = { ...form.value, [key]: !form.value[key] };
  saveError.value = null;
};

// Volta a tela para o que está salvo (por exemplo, depois de um Salvar recusado).
const discard = () => {
  form.value = formFrom(report.value);
  saveError.value = null;
};

const save = async () => {
  if (!dirty.value) return;
  saving.value = true;
  saveError.value = null;
  try {
    const { data } = await CrmMetaAdsWhatsappReportAPI.update(changes.value);
    apply(data.whatsapp_report);
    testResult.value = null;
    useAlert(t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.SAVED'));
  } catch (error) {
    saveError.value = errorCode(error);
  } finally {
    saving.value = false;
  }
};

const sendTest = async () => {
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await CrmMetaAdsWhatsappReportAPI.sendTest();
    testResult.value = {
      sent: true,
      text: t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST_SENT', {
        time: clockTime(data.sent_at, locale.value) || '',
      }),
    };
  } catch (error) {
    testResult.value = { sent: false, text: errorText(errorCode(error)) };
  } finally {
    testing.value = false;
  }
};

const copy = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert(t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.COPIED'));
  } catch {
    useAlert(
      t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.COPY_FAILED')
    );
  }
};

onMounted(load);
</script>

<template>
  <section
    data-meta-ads-whatsapp-report
    :aria-labelledby="ids.title"
    class="flex flex-col gap-5 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
  >
    <header class="flex flex-col gap-1.5">
      <span
        class="text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.EYEBROW') }}
      </span>
      <h4
        :id="ids.title"
        class="m-0 font-interDisplay text-xl font-520 tracking-[-0.02em] text-n-slate-12 text-balance"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TITLE') }}
      </h4>
      <p class="m-0 text-sm leading-6 font-420 text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HINT') }}
      </p>
    </header>

    <p
      v-if="loading"
      data-report-loading
      class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
      role="status"
    >
      <span
        class="i-lucide-loader-circle size-4 animate-spin"
        aria-hidden="true"
      />
      {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.LOADING') }}
    </p>

    <div
      v-else-if="loadFailed"
      data-report-load-error
      role="alert"
      class="flex flex-wrap items-center gap-3 text-sm text-n-ruby-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.LOAD_ERROR') }}
      <Button
        class="!min-h-11 !rounded-xl"
        variant="outline"
        color="slate"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="$t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.RETRY')"
        @click="load"
      />
    </div>

    <template v-else-if="report">
      <div class="flex flex-col gap-2">
        <button
          v-for="item in toggles"
          :key="item.key"
          type="button"
          role="switch"
          :data-report-toggle="item.key"
          :aria-checked="form[item.key]"
          class="flex items-center w-full gap-4 px-4 py-3 border border-solid text-start min-h-11 rounded-xl border-n-weak bg-n-solid-1 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="toggle(item.key)"
        >
          <span class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="text-sm font-520 text-n-slate-12">
              {{ item.label }}
            </span>
            <span class="text-xs leading-5 font-420 text-n-slate-11">
              {{ item.hint }}
            </span>
            <span
              v-if="blockedByTemplate(item)"
              :data-report-blocked="item.key"
              class="inline-flex items-center gap-1 text-xs leading-5 font-440 text-n-amber-11"
            >
              <span
                class="i-lucide-triangle-alert size-3.5 flex-none"
                aria-hidden="true"
              />
              {{
                $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.BLOCKED')
              }}
            </span>
          </span>
          <span
            aria-hidden="true"
            class="relative flex-none w-10 h-6 transition-colors rounded-full"
            :class="form[item.key] ? 'bg-n-brand' : 'bg-n-slate-6'"
          >
            <span
              class="absolute top-0.5 start-0.5 block bg-white rounded-full size-5 shadow-sm transition-transform"
              :class="
                form[item.key]
                  ? 'translate-x-4 rtl:-translate-x-4'
                  : 'translate-x-0'
              "
            />
          </span>
        </button>
      </div>

      <div class="grid gap-4 md:grid-cols-2">
        <div class="flex flex-col min-w-0 gap-1.5">
          <span class="text-sm font-520 text-n-slate-12" aria-hidden="true">
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ORIGIN_LABEL') }}
          </span>
          <p
            v-if="!origins.length"
            data-report-no-origins
            class="m-0 text-sm leading-6 font-420 text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ORIGIN_EMPTY') }}
          </p>
          <ChoiceSelect
            v-else
            v-model="form.inbox_id"
            data-report-origin
            class="w-full"
            :groups="originGroups"
            :placeholder="
              $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ORIGIN_PLACEHOLDER')
            "
            :aria-label="
              $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ORIGIN_LABEL')
            "
            :invalid="Boolean(fieldError('origin'))"
            @change="saveError = null"
          />
          <p
            v-if="fieldError('origin')"
            :id="ids.originError"
            data-report-origin-error
            role="alert"
            class="m-0 text-xs leading-5 text-n-ruby-11"
          >
            {{ fieldError('origin') }}
          </p>
          <p
            v-else-if="originGone && !origin"
            data-report-origin-gone
            class="m-0 text-xs leading-5 text-n-amber-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.ORIGIN_GONE') }}
          </p>
          <p
            v-else-if="origin"
            data-report-origin-kind
            class="flex items-start gap-1.5 m-0 text-xs leading-5 font-420 text-n-slate-11"
          >
            <span
              class="px-1.5 rounded-md font-520 flex-none"
              :class="
                isOfficial
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-blue-3 text-n-blue-11'
              "
            >
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.KIND.${origin.kind.toUpperCase()}`
                )
              }}
            </span>
            {{
              $t(
                `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.KIND_HINT.${origin.kind.toUpperCase()}`
              )
            }}
          </p>
        </div>

        <div class="flex flex-col min-w-0 gap-1.5">
          <label :for="ids.phone" class="text-sm font-520 text-n-slate-12">
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.PHONE_LABEL') }}
          </label>
          <input
            :id="ids.phone"
            v-model="form.phone"
            data-report-phone
            type="tel"
            inputmode="tel"
            autocomplete="tel"
            :placeholder="
              $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.PHONE_PLACEHOLDER')
            "
            :aria-invalid="Boolean(fieldError('phone')) || undefined"
            :aria-describedby="
              fieldError('phone') ? ids.phoneError : ids.phoneHint
            "
            class="block w-full px-3 text-sm border-0 rounded-lg reset-base min-h-11 !mb-0 bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10 outline outline-1 -outline-offset-1 focus:outline-2"
            :class="
              fieldError('phone')
                ? 'outline-n-ruby-8'
                : 'outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand'
            "
            @input="saveError = null"
          />
          <p
            v-if="fieldError('phone')"
            :id="ids.phoneError"
            data-report-phone-error
            role="alert"
            class="m-0 text-xs leading-5 text-n-ruby-11"
          >
            {{ fieldError('phone') }}
          </p>
          <p
            v-else
            :id="ids.phoneHint"
            class="m-0 text-xs leading-5 font-420 text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.PHONE_HINT') }}
          </p>
        </div>
      </div>

      <p
        v-if="origin"
        data-report-reply-note
        class="flex items-start gap-2 m-0 text-xs leading-5 font-420 text-n-slate-11"
      >
        <span class="i-lucide-info size-4 flex-none" aria-hidden="true" />
        {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.REPLY_NOTE') }}
      </p>

      <div
        v-if="isOfficial"
        data-report-templates
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1"
      >
        <div class="flex flex-col gap-1">
          <span
            class="text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.TITLE') }}
          </span>
          <p class="m-0 text-sm leading-6 font-420 text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.HINT') }}
          </p>
        </div>
        <article
          v-for="item in templates"
          :key="item.key"
          :data-report-template="item.key"
          class="flex flex-col gap-2 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm font-520 text-n-slate-12">
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.${item.key.toUpperCase()}`
                )
              }}
            </span>
            <span
              :data-report-template-status="item.status"
              class="px-2 py-0.5 text-xs rounded-full font-520"
              :class="STATUS_CLASSES[item.status]"
            >
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.STATUS.${item.status.toUpperCase()}`
                )
              }}
            </span>
          </div>
          <p class="m-0 text-xs font-420 text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.NAME') }}
            <code class="text-n-slate-12 break-all">{{ item.name }}</code>
          </p>
          <p class="m-0 text-sm leading-6 font-420 text-n-slate-12 break-words">
            {{ item.body }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              class="!min-h-11 !rounded-xl"
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-copy"
              :label="
                $t(
                  'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.COPY_NAME'
                )
              "
              @click="copy(item.name)"
            />
            <Button
              class="!min-h-11 !rounded-xl"
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-copy"
              :label="
                $t(
                  'CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEMPLATES.COPY_TEXT'
                )
              "
              @click="copy(item.body)"
            />
          </div>
        </article>
      </div>

      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-3">
          <Button
            data-report-save
            class="!min-h-11 !rounded-xl"
            icon="i-lucide-check"
            :is-loading="saving"
            :disabled="saving || !dirty"
            :label="$t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.SAVE')"
            @click="save"
          />
          <Button
            data-report-test
            class="!min-h-11 !rounded-xl"
            variant="outline"
            color="slate"
            icon="i-lucide-send"
            :is-loading="testing"
            :disabled="testing || !canTest"
            :label="$t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST')"
            @click="sendTest"
          />
          <Button
            v-if="dirty"
            data-report-discard
            class="!min-h-11 !rounded-xl"
            variant="ghost"
            color="slate"
            icon="i-lucide-undo-2"
            :disabled="saving"
            :label="$t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.DISCARD')"
            @click="discard"
          />
        </div>
        <p
          v-if="generalError"
          data-report-error
          role="alert"
          class="m-0 text-sm leading-6 text-n-ruby-11"
        >
          {{ generalError }}
        </p>
        <p
          v-if="testResult"
          data-report-test-result
          :role="testResult.sent ? 'status' : 'alert'"
          class="flex items-start gap-2 m-0 text-sm leading-6"
          :class="testResult.sent ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          <span
            class="flex-none mt-1 size-4"
            :class="
              testResult.sent ? 'i-lucide-circle-check' : 'i-lucide-circle-x'
            "
            aria-hidden="true"
          />
          {{ testResult.text }}
        </p>
        <p
          v-else-if="testBlocker"
          data-report-test-hint
          :data-test-blocker="testBlocker"
          class="m-0 text-xs leading-5 font-420 text-n-slate-11"
        >
          {{ testHint }}
        </p>
        <p v-else class="m-0 text-xs leading-5 font-420 text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.TEST_HINT') }}
        </p>
      </div>

      <div
        data-report-history
        class="flex flex-col gap-1.5 pt-4 border-0 border-t border-solid border-n-weak"
      >
        <span
          class="text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.TITLE') }}
        </span>
        <p
          v-for="row in history"
          :key="row.key"
          :data-report-history-row="row.key"
          class="m-0 text-sm font-420 text-n-slate-12"
        >
          {{ row.text }}
        </p>
        <p v-if="!history.length" class="m-0 text-sm font-420 text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.WHATSAPP_REPORT.HISTORY.NONE') }}
        </p>
        <p
          v-if="lastError"
          data-report-last-error
          class="flex items-start gap-2 m-0 text-sm leading-6"
          :class="lastError.info ? 'text-n-slate-11' : 'text-n-amber-11'"
        >
          <span
            class="flex-none mt-1 size-4"
            :class="
              lastError.info ? 'i-lucide-info' : 'i-lucide-triangle-alert'
            "
            aria-hidden="true"
          />
          {{ lastError.text }}
        </p>
      </div>
    </template>
  </section>
</template>
