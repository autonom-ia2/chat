<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import FunilInterruptor from './funil/FunilInterruptor.vue';
import { diasEmFaixa, tempoAte } from './funil/funil';

// #1384 — "Lembretes e retornos" do funil. Abre no resumo (duas frases
// prontas, cada uma com liga/desliga); "Alterar" leva ao detalhe das
// tentativas, que a gaveta mostra numa tela própria (`detalhe`).
const props = defineProps({
  pipelineId: { type: [String, Number], required: true },
  detalhe: { type: Boolean, default: false },
});

const emit = defineEmits(['alterar']);

const { t, locale } = useI18n();
const STALE_HOURS = 168;

const isLoading = ref(false);
const isSaving = ref(false);
const loadFailed = ref(false);
const form = reactive({
  callbackMode: 'reminder',
  stageCriteria: {},
  autoFollowup: {
    enabled: false,
    mode: 'auto_send',
    allowedDays: [1, 2, 3, 4, 5],
    maxTouches: 3,
    intervalsHours: [20, 72, 168],
    quietHours: { start: 8, end: 20, tz: 'contact' },
    toneInstructions: '',
  },
});

// Keep the editable interval list in sync with the requested number of touches,
// padding new slots after the previous one and trimming extras.
const FOLLOWUP_DEFAULT_INTERVALS = [20, 72, 168];
const HOURS_PER_DAY = 24;
const syncIntervals = () => {
  const count = Math.max(
    1,
    Math.min(3, Number(form.autoFollowup.maxTouches) || 1)
  );
  const next = [];
  for (let index = 0; index < count; index += 1) {
    const existing = form.autoFollowup.intervalsHours[index];
    const previous = next[index - 1] ?? 0;
    const fallback = Math.max(
      FOLLOWUP_DEFAULT_INTERVALS[index] ?? 168,
      previous + HOURS_PER_DAY
    );
    next.push(Number.isFinite(existing) ? existing : fallback);
  }
  form.autoFollowup.maxTouches = count;
  form.autoFollowup.intervalsHours = next;
};

const followupModes = ['auto_send', 'ai_reminder'];
const weekdays = [1, 2, 3, 4, 5, 6, 0];
const isReminder = computed(() => form.autoFollowup.mode === 'ai_reminder');
const toggleDay = day => {
  const days = form.autoFollowup.allowedDays;
  if (days.includes(day)) {
    if (days.length > 1)
      form.autoFollowup.allowedDays = days.filter(value => value !== day);
  } else {
    form.autoFollowup.allowedDays = [...days, day];
  }
};
const intervalAfterPrevious = (hours, index) =>
  !index || hours > form.autoFollowup.intervalsHours[index - 1];
const scheduleValid = computed(() => {
  const { allowedDays, quietHours, intervalsHours, maxTouches } =
    form.autoFollowup;
  return (
    allowedDays.length > 0 &&
    Number.isInteger(quietHours.start) &&
    Number.isInteger(quietHours.end) &&
    quietHours.start >= 0 &&
    quietHours.end <= 24 &&
    quietHours.start < quietHours.end &&
    maxTouches >= 1 &&
    maxTouches <= 3 &&
    intervalsHours.length === maxTouches &&
    intervalsHours.every(
      (hours, index) =>
        Number.isInteger(hours) &&
        hours > 0 &&
        intervalAfterPrevious(hours, index)
    )
  );
});

// #1384: cada tentativa é "Depois de [tempo] sem resposta", escolhido numa
// lista de tempos redondos. O servidor continua recebendo horas.
const UX = 'CRM_FUNIL.RETORNO';
// "Também mandar mensagem ao cliente nesse dia": o interruptor do cartão.
const mensagemNoDia = computed({
  get: () => form.callbackMode !== 'reminder',
  set: valor => {
    form.callbackMode = valor ? 'both' : 'reminder';
  },
});
const HOURS_PER_WEEK = 168;
const INTERVAL_CHOICES = [2, 4, 8, 12, 20, 24, 48, 72, 96, 120, 168, 336];
const intervalLabel = hours => {
  if (hours % HOURS_PER_WEEK === 0) {
    const weeks = hours / HOURS_PER_WEEK;
    return t('CRM_FUNIL.RETORNO.SEMANAS', { n: weeks }, weeks);
  }
  if (hours % HOURS_PER_DAY === 0) {
    const days = hours / HOURS_PER_DAY;
    return t('CRM_FUNIL.RETORNO.DIAS', { n: days }, days);
  }
  return t('CRM_FUNIL.RETORNO.HORAS', { n: hours }, hours);
};
// A lista de cada tentativa só oferece tempo depois da anterior (o valor atual
// fica, mesmo fora da ordem, para a pessoa ver o que corrigir).
const intervalChoices = index => {
  const current = form.autoFollowup.intervalsHours[index];
  const previous = index ? form.autoFollowup.intervalsHours[index - 1] : 0;
  const values = [...new Set([...INTERVAL_CHOICES, current])]
    .filter(Number.isFinite)
    .filter(hours => hours > previous || hours === current)
    .sort((a, b) => a - b);
  return values.map(hours => ({ value: hours, label: intervalLabel(hours) }));
};
const setTouchInterval = (index, hours) => {
  const next = [...form.autoFollowup.intervalsHours];
  next[index] = hours;
  form.autoFollowup.intervalsHours = next;
};
const setTouches = count => {
  form.autoFollowup.maxTouches = count;
  syncIntervals();
};
const touchOptions = [1, 2, 3];
const hourChoices = (from, to) =>
  Array.from({ length: to - from + 1 }, (_, index) => ({
    value: from + index,
    label: t('CRM_FUNIL.RETORNO.HORA', { hora: from + index }),
  }));
const startHourChoices = computed(() => hourChoices(0, 23));
const endHourChoices = computed(() => hourChoices(1, 24));

// O resumo de "quando o cliente para de responder" em duas frases prontas:
// quantas vezes e quando, depois em que dias e horários.
const listFormat = items =>
  new Intl.ListFormat(locale.value.replace('_', '-'), {
    style: 'long',
    type: 'conjunction',
  }).format(items);
const dayName = day => t(`${UX}.DIA_NOME.${day}`);
const followupSummary = computed(() => {
  const { enabled, maxTouches, intervalsHours, allowedDays, quietHours } =
    form.autoFollowup;
  if (!enabled) return { quando: t(`${UX}.SUMIU_DESLIGADO`), onde: '' };
  const tempos = listFormat(
    intervalsHours.map(hours => {
      const { chave, n } = tempoAte(hours);
      return t(`${UX}.${chave}`, { n }, n);
    })
  );
  const faixa = diasEmFaixa(allowedDays);
  let dias = t(`${UX}.TODOS_OS_DIAS`);
  if (faixa.tipo === 'FAIXA')
    dias = t(`${UX}.DE_A`, { de: dayName(faixa.de), ate: dayName(faixa.ate) });
  if (faixa.tipo === 'LISTA') dias = listFormat(faixa.dias.map(dayName));
  return {
    quando: t(
      isReminder.value ? `${UX}.RESUMO_EQUIPE` : `${UX}.RESUMO_MENSAGEM`,
      { n: maxTouches, tempos },
      maxTouches
    ),
    onde: t(`${UX}.RESUMO_HORARIO`, {
      dias: dias.charAt(0).toUpperCase() + dias.slice(1),
      inicio: quietHours.start,
      fim: quietHours.end,
    }),
  };
});

const canSave = computed(
  () =>
    !isLoading.value &&
    !loadFailed.value &&
    Boolean(props.pipelineId) &&
    (!form.autoFollowup.enabled || scheduleValid.value)
);

const loadSettings = async () => {
  if (!props.pipelineId) return;
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const response = await CrmKanbanAPI.getAiSettings(props.pipelineId);
    const payload = response.data.payload || {};
    form.callbackMode = ['message', 'both'].includes(payload.callback_mode)
      ? 'both'
      : 'reminder';
    form.stageCriteria = Object.fromEntries(
      (payload.stages || []).map(stage => [stage.id, stage.ai_criteria || ''])
    );
    const followup = payload.auto_followup || {};
    const intervals = Array.isArray(followup.intervals_hours)
      ? followup.intervals_hours.map(Number)
      : [20, 72, 168];
    form.autoFollowup = {
      enabled: followup.enabled === true,
      mode: followup.mode || 'auto_send',
      allowedDays: followup.allowed_days || [0, 1, 2, 3, 4, 5, 6],
      maxTouches: Number(followup.max_touches ?? 3),
      intervalsHours: intervals,
      quietHours: {
        start: Number(followup.quiet_hours?.start ?? 8),
        end: Number(followup.quiet_hours?.end ?? 20),
        tz: followup.quiet_hours?.tz || 'contact',
      },
      toneInstructions: followup.tone_instructions || '',
    };
    syncIntervals();
  } catch {
    loadFailed.value = true;
    useAlert(t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

// `silent` is set when the parent pipeline drawer's "Salvar funil" (master save)
// triggers this — it shows its own success alert and rethrows so the parent can
// react, avoiding a duplicate toast.
const saveSettings = async ({ silent = false } = {}) => {
  if (isLoading.value || isSaving.value || loadFailed.value) return false;
  if (!canSave.value) {
    useAlert(t('CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.INVALID_SCHEDULE'));
    return false;
  }
  isSaving.value = true;
  try {
    const response = await CrmKanbanAPI.updateAiSettings(props.pipelineId, {
      ai_settings: {
        enabled: true,
        auto_move_enabled: true,
        attribute_extraction_enabled: true,
        score_enabled: true,
        callback_enabled: true,
        callback_mode: form.callbackMode,
        stale_hours: STALE_HOURS,
        auto_followup: form.autoFollowup.enabled
          ? {
              enabled: form.autoFollowup.enabled,
              mode: form.autoFollowup.mode,
              allowed_days: form.autoFollowup.allowedDays,
              max_touches: form.autoFollowup.maxTouches,
              intervals_hours: form.autoFollowup.intervalsHours,
              quiet_hours: {
                start: form.autoFollowup.quietHours.start,
                end: form.autoFollowup.quietHours.end,
                tz: form.autoFollowup.quietHours.tz,
              },
              tone_instructions: form.autoFollowup.toneInstructions,
            }
          : { enabled: false },
      },
      stage_criteria: form.stageCriteria,
    });
    const payload = response.data.payload || {};
    form.callbackMode = ['message', 'both'].includes(payload.callback_mode)
      ? 'both'
      : 'reminder';
    if (!silent) useAlert(t('CRM_KANBAN.AI_SETTINGS.SAVE_SUCCESS'));
    return true;
  } catch {
    // Keep the drawer open when AI settings could not be saved.
    useAlert(t('CRM_KANBAN.AI_SETTINGS.SAVE_ERROR'));
    return false;
  } finally {
    isSaving.value = false;
  }
};

// Let the parent pipeline drawer save this panel as part of "Salvar funil".
defineExpose({
  saveSettings,
  loadSettings,
  form,
  isLoading,
  isSaving,
  loadFailed,
  scheduleValid,
});

watch(
  () => props.pipelineId,
  () => {
    loadSettings();
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-5">
    <p v-if="isLoading" class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ t('CRM_KANBAN.AI_SETTINGS.LOADING') }}
    </p>

    <p v-else-if="loadFailed" class="mb-0 text-[0.9375rem] text-n-ruby-11">
      {{ t('CRM_KANBAN.AI_SETTINGS.LOAD_ERROR') }}
    </p>

    <!-- Resumo: as duas situações em frases, já prontas. -->
    <template v-else-if="!detalhe">
      <section
        data-callback
        class="flex flex-col gap-4 rounded-2xl border bg-n-solid-1 p-5"
        :class="mensagemNoDia ? 'border-n-blue-7' : 'border-n-weak'"
      >
        <label class="flex cursor-pointer items-start gap-4">
          <span
            class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-iris-3 text-n-iris-11"
            aria-hidden="true"
          >
            <span class="i-lucide-calendar-clock size-6" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-11">
              {{ t(`${UX}.DEPOIS_TITULO`) }}
            </span>
            <span
              data-callback-resumo
              class="text-base font-semibold leading-relaxed text-n-slate-12"
            >
              {{
                t(
                  mensagemNoDia
                    ? `${UX}.DEPOIS_FRASE_MENSAGEM`
                    : `${UX}.DEPOIS_FRASE`
                )
              }}
            </span>
            <span class="text-[0.9375rem] text-n-slate-11">
              {{ t(`${UX}.DEPOIS_EXEMPLO`) }}
            </span>
          </span>
          <FunilInterruptor
            v-model="mensagemNoDia"
            :rotulo="t(`${UX}.DEPOIS_MENSAGEM`)"
          />
        </label>
      </section>

      <section
        data-auto-followup
        class="flex flex-col gap-4 rounded-2xl border bg-n-solid-1 p-5"
        :class="form.autoFollowup.enabled ? 'border-n-blue-7' : 'border-n-weak'"
      >
        <label class="flex cursor-pointer items-start gap-4">
          <span
            class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            <span class="i-lucide-rotate-ccw size-6" />
          </span>
          <span class="flex min-w-0 flex-1 flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-11">
              {{ t(`${UX}.SUMIU_TITULO`) }}
            </span>
            <span
              data-followup-resumo
              class="text-base font-semibold leading-relaxed text-n-slate-12"
            >
              {{ followupSummary.quando }}
            </span>
            <span
              v-if="followupSummary.onde"
              class="text-[0.9375rem] text-n-slate-11"
            >
              {{ followupSummary.onde }}
            </span>
          </span>
          <FunilInterruptor v-model="form.autoFollowup.enabled" />
        </label>
        <Button
          v-if="form.autoFollowup.enabled"
          data-followup-alterar
          :label="t('CRM_FUNIL.ALTERAR')"
          :aria-label="t(`${UX}.ALTERAR_SUMIU`)"
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 w-fit sm:ms-16"
          @click="emit('alterar')"
        />
      </section>
    </template>

    <!-- Detalhe: como, quantas vezes, quando e em que dias. -->
    <template v-else>
      <div
        class="grid gap-3 sm:grid-cols-2"
        role="radiogroup"
        :aria-label="t(`${UX}.COMO`)"
      >
        <label
          v-for="mode in followupModes"
          :key="mode"
          class="flex min-h-11 cursor-pointer items-start gap-3 rounded-2xl border-2 p-4 transition focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-n-brand"
          :class="
            form.autoFollowup.mode === mode
              ? 'border-n-blue-8 bg-n-blue-2'
              : 'border-n-weak bg-n-solid-1 hover:border-n-slate-7'
          "
        >
          <input
            v-model="form.autoFollowup.mode"
            type="radio"
            :name="`followup-mode-${pipelineId}`"
            :value="mode"
            class="sr-only"
          />
          <span
            class="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border-2"
            :class="
              form.autoFollowup.mode === mode
                ? 'border-n-blue-9 bg-n-blue-9 text-white'
                : 'border-n-slate-7'
            "
            aria-hidden="true"
          >
            <span
              v-if="form.autoFollowup.mode === mode"
              class="i-lucide-check size-3"
            />
          </span>
          <span class="flex min-w-0 flex-col gap-1">
            <span class="text-base font-semibold text-n-slate-12">
              {{ t(`${UX}.MODOS.${mode}.TITULO`) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t(`${UX}.MODOS.${mode}.TEXTO`) }}
            </span>
          </span>
        </label>
      </div>

      <section
        class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 sm:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h5
            id="followup-touches-label"
            class="mb-0 text-base font-semibold text-n-slate-12"
          >
            {{ t(`${UX}.QUANDO`) }}
          </h5>
          <div
            class="inline-flex gap-1 rounded-xl bg-n-alpha-2 p-1"
            role="group"
            aria-labelledby="followup-touches-label"
          >
            <button
              v-for="count in touchOptions"
              :key="count"
              type="button"
              :data-vezes="count"
              :aria-pressed="form.autoFollowup.maxTouches === count"
              class="min-h-11 rounded-lg px-4 text-[0.9375rem] font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :class="
                form.autoFollowup.maxTouches === count
                  ? 'bg-n-blue-3 text-n-blue-11 shadow-sm ring-1 ring-inset ring-n-blue-7'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="setTouches(count)"
            >
              {{ t(`${UX}.VEZES`, { n: count }, count) }}
            </button>
          </div>
        </div>
        <ol class="m-0 flex list-none flex-col p-0">
          <li
            v-for="(hours, index) in form.autoFollowup.intervalsHours"
            :key="index"
            data-followup-touch
            class="relative flex gap-2 pb-3 last:pb-0 sm:gap-3"
          >
            <span
              v-if="index < form.autoFollowup.intervalsHours.length - 1"
              class="absolute bottom-0 start-[1.0625rem] top-10 w-0.5 bg-n-blue-6"
              aria-hidden="true"
            />
            <span
              class="relative grid size-9 shrink-0 place-items-center rounded-full bg-n-blue-3 text-sm font-bold text-n-blue-11"
            >
              {{ t(`${UX}.ORDEM`, { n: index + 1 }) }}
            </span>
            <div
              class="flex min-w-0 flex-1 flex-col gap-2 rounded-xl bg-n-alpha-2 p-2.5 sm:p-3"
            >
              <div
                class="flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-12"
              >
                {{ t(`${UX}.SEM_RESPOSTA_POR`) }}
                <ChoiceSelect
                  :model-value="hours"
                  :options="intervalChoices(index)"
                  :aria-label="t(`${UX}.TEMPO_DA`, { n: index + 1 })"
                  :invalid="!intervalAfterPrevious(hours, index)"
                  class="w-28 sm:w-32"
                  @update:model-value="setTouchInterval(index, $event)"
                />
              </div>
              <p
                v-if="!intervalAfterPrevious(hours, index)"
                role="alert"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ t(`${UX}.DEPOIS_DA_ANTERIOR`) }}
              </p>
            </div>
          </li>
        </ol>
      </section>

      <section
        class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <h5
          id="followup-days-label"
          class="mb-0 text-base font-semibold text-n-slate-12"
        >
          {{ t(`${UX}.DIAS_TITULO`) }}
        </h5>
        <div
          class="grid grid-cols-4 gap-2 sm:flex sm:flex-wrap"
          role="group"
          aria-labelledby="followup-days-label"
        >
          <button
            v-for="day in weekdays"
            :key="day"
            type="button"
            :aria-pressed="form.autoFollowup.allowedDays.includes(day)"
            :aria-label="
              t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS_FULL.${day}`)
            "
            class="min-h-11 min-w-0 rounded-xl px-2 text-[0.9375rem] font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand sm:min-w-12"
            :class="
              form.autoFollowup.allowedDays.includes(day)
                ? 'bg-n-blue-3 text-n-blue-11 ring-1 ring-inset ring-n-blue-7'
                : 'bg-n-solid-1 text-n-slate-11 ring-1 ring-inset ring-n-weak hover:ring-n-slate-7'
            "
            @click="toggleDay(day)"
          >
            {{ t(`CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS.${day}`) }}
          </button>
        </div>
        <div
          class="flex flex-wrap items-center gap-2 text-[0.9375rem] text-n-slate-12"
        >
          {{ t(`${UX}.DAS`) }}
          <ChoiceSelect
            v-model="form.autoFollowup.quietHours.start"
            :options="startHourChoices"
            :aria-label="t(`${UX}.HORA_INICIO`)"
            class="w-24"
          />
          {{ t(`${UX}.ATE`) }}
          <ChoiceSelect
            v-model="form.autoFollowup.quietHours.end"
            :options="endHourChoices"
            :aria-label="t(`${UX}.HORA_FIM`)"
            class="w-24"
          />
        </div>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t(`${UX}.HORARIO_AJUDA`) }}
        </p>
      </section>

      <label
        v-if="!isReminder"
        class="flex flex-col gap-1 rounded-2xl border border-n-weak bg-n-solid-1 p-5"
      >
        <span class="text-base font-semibold text-n-slate-12">
          {{ t(`${UX}.TOM`) }}
        </span>
        <textarea
          v-model="form.autoFollowup.toneInstructions"
          rows="2"
          class="reset-base !mb-0 mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-base text-n-slate-12 placeholder:text-n-slate-10 focus:outline focus:outline-2 focus:outline-n-brand"
          :placeholder="t(`${UX}.TOM_EXEMPLO`)"
        />
      </label>

      <p
        v-if="!scheduleValid"
        role="alert"
        class="mb-0 rounded-xl bg-n-ruby-2 p-3 text-[0.9375rem] text-n-ruby-11"
      >
        {{ t(`${UX}.INVALIDO`) }}
      </p>
    </template>
  </section>
</template>
