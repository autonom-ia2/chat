<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { errorMessageKey } from '../metaAdsHelpers';

// Anúncios da Meta (#1047), passo 4: um funil ligado ao WhatsApp oficial. Mostra o que falta, deixa
// escolher "Como a Meta entende" cada etapa (o mesmo campo de Editar funil) e grava no funil por aqui.
// A IA sugere os tipos quando nenhuma etapa tem um; a pessoa revisa antes de gravar.
const props = defineProps({
  funnel: { type: Object, required: true },
  aiAvailable: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const NO_TYPE = 'none';
const CHOICES = [
  { value: 'lead', key: 'INTEREST' },
  { value: 'qualified', key: 'QUALIFIED' },
  { value: 'opportunity', key: 'PROPOSAL' },
  { value: 'negotiation', key: 'NEGOTIATION' },
  { value: NO_TYPE, key: 'NONE' },
];
const MISSING_KEYS = {
  sending_off: 'SENDING_OFF',
  sales_off: 'SALES_OFF',
  moves_off: 'MOVES_OFF',
  stages: 'STAGES',
};

const { t } = useI18n();

const progressStages = computed(() =>
  props.funnel.stages.filter(stage => !stage.result)
);
const ready = computed(() => props.funnel.missing.length === 0);
const open = ref(!ready.value);
const types = ref(
  Object.fromEntries(
    progressStages.value.map(stage => [
      stage.id,
      stage.funnel_stage_type || NO_TYPE,
    ])
  )
);
// { stage_id: motivo } da última sugestão da IA, mostrado embaixo de cada escolha.
const reasons = ref({});
const suggesting = ref(false);
const saving = ref(false);
const stopping = ref(false);

const options = CHOICES.map(choice => ({
  value: choice.value,
  label: t(`CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.${choice.key}.TITLE`),
}));
const numbers = computed(() =>
  props.funnel.numbers.map(number => number.name).join(', ')
);
const hasAnyType = computed(() =>
  progressStages.value.some(stage => stage.funnel_stage_type)
);

const suggest = async () => {
  suggesting.value = true;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.suggestStages(
      props.funnel.id
    );
    const suggestions = data?.suggestions || [];
    types.value = {
      ...types.value,
      ...Object.fromEntries(suggestions.map(row => [row.stage_id, row.type])),
    };
    reasons.value = Object.fromEntries(
      suggestions.map(row => [row.stage_id, row.reason])
    );
  } catch {
    useAlert(t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SUGGEST_ERROR'));
  } finally {
    suggesting.value = false;
  }
};

const save = async () => {
  saving.value = true;
  try {
    const stages = Object.entries(types.value).map(([id, type]) => ({
      id: Number(id),
      funnel_stage_type: type,
    }));
    const { data } = await CrmMetaAdsConnectionAPI.saveFunnel(
      props.funnel.id,
      stages
    );
    useAlert(
      t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SAVED', { name: props.funnel.name })
    );
    emit('updated', data);
  } catch (error) {
    useAlert(t(errorMessageKey(error)));
  } finally {
    saving.value = false;
  }
};

const stop = async () => {
  stopping.value = true;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.stopFunnel(props.funnel.id);
    useAlert(
      t('CRM_KANBAN.META_ADS_HUB.FUNNEL.STOPPED', { name: props.funnel.name })
    );
    emit('updated', data);
  } catch (error) {
    useAlert(t(errorMessageKey(error)));
  } finally {
    stopping.value = false;
  }
};

onMounted(() => {
  if (props.aiAvailable && !hasAnyType.value && progressStages.value.length) {
    suggest();
  }
});
</script>

<template>
  <article
    :data-funnel="funnel.id"
    class="flex flex-col gap-4 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-5"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex items-start min-w-0 gap-3">
        <span
          class="grid flex-none rounded-xl size-9 place-items-center bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-kanban size-5" />
        </span>
        <div class="flex flex-col min-w-0 gap-0.5">
          <span class="flex flex-wrap items-center gap-2">
            <h4 class="m-0 text-base font-semibold text-n-slate-12">
              {{ funnel.name }}
            </h4>
            <span
              data-funnel-status
              class="px-2 py-0.5 text-xs font-semibold rounded-full"
              :class="
                ready
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-amber-3 text-n-amber-11'
              "
            >
              {{
                ready
                  ? $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.READY')
                  : $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.NEEDS')
              }}
            </span>
          </span>
          <span class="text-xs text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.NUMBERS', { numbers }) }}
          </span>
        </div>
      </div>
      <button
        type="button"
        data-funnel-toggle
        :aria-expanded="open"
        class="inline-flex items-center gap-1 px-3 text-sm font-semibold bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="open = !open"
      >
        {{
          open
            ? $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.HIDE')
            : $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SHOW')
        }}
        <span
          class="size-4"
          :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          aria-hidden="true"
        />
      </button>
    </header>

    <ul
      v-if="funnel.missing.length"
      data-funnel-missing
      class="flex flex-col gap-1 p-0 m-0 list-none"
    >
      <li
        v-for="code in funnel.missing"
        :key="code"
        class="flex items-center gap-2 text-sm text-n-amber-11"
      >
        <span
          class="flex-none i-lucide-circle-alert size-4"
          aria-hidden="true"
        />
        {{ $t(`CRM_KANBAN.META_ADS_HUB.FUNNEL.MISSING.${MISSING_KEYS[code]}`) }}
      </li>
    </ul>

    <div v-if="open" class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.STAGES_TITLE') }}
        </span>
        <Button
          v-if="aiAvailable"
          data-funnel-suggest
          class="!min-h-11 !rounded-xl"
          variant="faded"
          color="blue"
          size="sm"
          icon="i-lucide-sparkles"
          :is-loading="suggesting"
          :disabled="suggesting"
          :label="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SUGGEST')"
          @click="suggest"
        />
      </div>
      <p
        v-if="suggesting"
        role="status"
        class="px-3 py-2 m-0 text-sm rounded-lg bg-n-blue-2 text-n-blue-11"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SUGGESTING') }}
      </p>
      <ol class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="(stage, index) in progressStages"
          :key="stage.id"
          :data-funnel-stage="stage.id"
          class="flex flex-col gap-2 px-3 py-3 rounded-xl bg-n-alpha-1 sm:flex-row sm:items-center sm:justify-between"
        >
          <span class="flex items-start min-w-0 gap-3">
            <span
              class="grid flex-none text-xs font-semibold rounded-full size-6 place-items-center bg-n-alpha-2 text-n-slate-11"
              aria-hidden="true"
            >
              {{ index + 1 }}
            </span>
            <span class="flex flex-col min-w-0 gap-0.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ stage.name }}
              </span>
              <span
                v-if="reasons[stage.id]"
                data-funnel-reason
                class="inline-flex items-start gap-1 text-xs text-n-slate-11"
              >
                <span
                  class="flex-none mt-0.5 i-lucide-sparkles size-3 text-n-blue-11"
                  :title="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SUGGESTED')"
                  aria-hidden="true"
                />
                {{ reasons[stage.id] }}
              </span>
            </span>
          </span>
          <ChoiceSelect
            v-model="types[stage.id]"
            class="sm:w-60"
            :options="options"
            :disabled="suggesting"
            :aria-label="
              $t('CRM_KANBAN.META_ADS_HUB.FUNNEL.STAGE_LABEL', {
                stage: stage.name,
              })
            "
          />
        </li>
      </ol>

      <div class="flex flex-wrap items-center gap-3">
        <Button
          data-funnel-save
          class="!min-h-11 !rounded-xl"
          icon="i-lucide-check"
          :is-loading="saving"
          :disabled="saving || suggesting"
          :label="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.SAVE')"
          @click="save"
        />
        <Button
          v-if="funnel.enabled"
          data-funnel-stop
          class="!min-h-11 !rounded-xl"
          variant="ghost"
          color="ruby"
          size="sm"
          :is-loading="stopping"
          :label="$t('CRM_KANBAN.META_ADS_HUB.FUNNEL.STOP')"
          @click="stop"
        />
      </div>
    </div>
  </article>
</template>
