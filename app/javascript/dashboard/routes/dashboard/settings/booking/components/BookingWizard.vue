<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingSteps from './BookingSteps.vue';
import StepTemplate from './steps/StepTemplate.vue';
import StepAbout from './steps/StepAbout.vue';
import StepWhere from './steps/StepWhere.vue';
import StepWhen from './steps/StepWhen.vue';
import StepLook from './steps/StepLook.vue';
import StepPreview from './steps/StepPreview.vue';
import { STEP } from '../constants';
import { useBookingWizard } from '../composables/useBookingWizard';

// Os seis passos da J3 (estado e chamadas em useBookingWizard). Só abre para
// quem pode mudar (agendamento_manage); quem só vê usa BookingPageView.
const props = defineProps({
  pageId: { type: Number, default: null },
});

const emit = defineEmits(['close']);
const { t } = useI18n();

const {
  step,
  page,
  form,
  loading,
  loadFailed,
  people,
  peopleState,
  busy,
  error,
  saveFailed,
  uploading,
  uploadError,
  missing,
  savingDestination,
  peopleNames,
  load,
  loadPeople,
  change,
  chooseTemplate,
  next,
  back,
  goTo,
  publish,
  upload,
  saveDestination,
} = useBookingWizard({ pageId: props.pageId, onClose: () => emit('close') });

onMounted(load);

// Uma ação principal por tela: Continuar, Ver como fica, Publicar ou, com a
// página no ar, Voltar para a lista.
const primary = computed(() => {
  if (step.value === STEP.PREVIA) {
    return page.value?.enabled
      ? { key: 'DONE', action: () => emit('close') }
      : { key: 'PUBLISH', action: publish };
  }
  return {
    key: step.value === STEP.CARA ? 'SEE_PREVIEW' : 'CONTINUE',
    action: next,
  };
});

const blockedByMissing = computed(
  () => primary.value.key === 'PUBLISH' && missing.value.length > 0
);
</script>

<template>
  <section data-wizard class="flex flex-col w-full gap-8">
    <BookingSteps :current="step" />

    <p v-if="loading" aria-busy="true" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.LIST.LOADING') }}
    </p>
    <div v-else-if="loadFailed" role="alert" class="flex flex-col gap-4">
      <p class="m-0 text-base text-n-ruby-11">
        {{ t('BOOKING.WIZARD.LOAD_ERROR') }}
      </p>
      <button
        type="button"
        class="self-start min-h-11 px-5 text-base font-medium rounded-xl ring-1 ring-inset ring-n-weak text-n-slate-12"
        @click="emit('close')"
      >
        {{ t('BOOKING.WIZARD.BACK_TO_LIST') }}
      </button>
    </div>

    <template v-else>
      <StepTemplate
        v-if="step === STEP.MODELO"
        :busy="busy"
        @choose="chooseTemplate"
      />
      <template v-else-if="form">
        <StepAbout
          v-if="step === STEP.CONTE"
          :form="form"
          :people="people"
          :people-state="peopleState"
          :error="error"
          @change="change"
          @retry-people="loadPeople"
        />
        <StepWhere
          v-else-if="step === STEP.ONDE"
          :form="form"
          :calendar-options="page.calendar_options || []"
          :error="error"
          @change="change"
        />
        <StepWhen
          v-else-if="step === STEP.QUANDO"
          :form="form"
          :error="error"
          @change="change"
        />
        <StepLook
          v-else-if="step === STEP.CARA"
          :form="form"
          :logo-url="page.logo_url || ''"
          :photo-url="page.photo_url || ''"
          :uploading="uploading"
          :upload-error="uploadError"
          @change="change"
          @upload="upload"
        />
        <StepPreview
          v-else
          :form="form"
          :page="page"
          :people-names="peopleNames"
          can-manage
          :publishing="busy"
          :saving-destination="savingDestination"
          :missing="missing"
          @fix="goTo"
          @save-destination="saveDestination"
        />
      </template>

      <p
        v-if="saveFailed"
        data-save-error
        role="alert"
        class="m-0 px-4 py-3 text-base rounded-xl bg-n-ruby-3 text-n-ruby-12"
      >
        {{
          step === STEP.MODELO
            ? t('BOOKING.TEMPLATE.CREATE_ERROR')
            : t('BOOKING.WIZARD.SAVE_ERROR')
        }}
      </p>

      <footer
        class="flex flex-wrap-reverse items-center justify-between gap-3 pt-6 border-t border-n-weak"
      >
        <button
          type="button"
          data-back
          :disabled="busy"
          class="inline-flex items-center gap-2 min-h-12 px-5 rounded-xl text-base font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="back"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{
            step <= STEP.CONTE
              ? t('BOOKING.WIZARD.BACK_TO_LIST')
              : t('BOOKING.WIZARD.BACK')
          }}
        </button>
        <button
          v-if="step !== STEP.MODELO"
          type="button"
          data-primary
          :data-action="primary.key"
          :disabled="busy || blockedByMissing"
          class="inline-flex items-center gap-2 min-h-12 px-6 rounded-xl text-base font-semibold text-white bg-n-blue-9 hover:bg-n-blue-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60 disabled:cursor-not-allowed"
          @click="primary.action"
        >
          <span
            v-if="busy"
            class="i-lucide-loader-circle size-4 animate-spin"
            aria-hidden="true"
          />
          {{ t(`BOOKING.WIZARD.${primary.key}`) }}
        </button>
      </footer>
    </template>
  </section>
</template>
