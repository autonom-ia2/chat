<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadFormsAPI from 'dashboard/api/crmMetaAdsLeadForms';
import MetaAdsLeadFormPage from './MetaAdsLeadFormPage.vue';
import MetaAdsLeadFormDestination from './MetaAdsLeadFormDestination.vue';
import MetaAdsLeadsRecent from './MetaAdsLeadsRecent.vue';

// Anúncios da Meta › Formulários (#2195): quem preenche o formulário instantâneo do anúncio vira cliente no funil
// e na etapa escolhidos para aquele formulário. Os formulários das Páginas conectadas aparecem sempre; escolher o
// funil de um deles já liga o recebimento da Página (assina o leadgen dela). Parar fica no menu da Página.
const props = defineProps({
  readOnly: { type: Boolean, default: false },
});

const emit = defineEmits(['connect']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LEAD_FORMS';
const { t } = useI18n();

const loading = ref(true);
const failed = ref(false);
const data = ref({ pages: [], pipelines: [], recent_leads: [] });
const busyPage = ref(null);
const editing = ref(null);
// Escolher o funil com a Página parada liga a Página de novo: a janela avisa.
const editingPaused = ref(false);
const choose = (form, paused = false) => {
  editingPaused.value = paused;
  editing.value = form;
};
// Subtítulo e aviso do WhatsApp só fazem sentido com formulário na tela.
const hasPages = computed(() => !loading.value && data.value.pages.length > 0);

const load = async () => {
  failed.value = false;
  try {
    const response = await LeadFormsAPI.get();
    data.value = response.data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const stopReceiving = async page => {
  busyPage.value = page.id;
  try {
    const response = await LeadFormsAPI.stopReceiving(page.id);
    data.value = response.data;
    useAlert(t(`${KEY}.STOPPED`, { page: page.name }));
  } catch {
    useAlert(t(`${KEY}.ACTION_FAILED`));
  } finally {
    busyPage.value = null;
  }
};

const resumeReceiving = async page => {
  busyPage.value = page.id;
  try {
    const response = await LeadFormsAPI.receive(page.id);
    data.value = response.data;
    useAlert(t(`${KEY}.RESUMED`, { page: page.name }));
  } catch {
    useAlert(t(`${KEY}.ACTION_FAILED`));
  } finally {
    busyPage.value = null;
  }
};

// Quem já preencheu entra em segundo plano (importing): o aviso diz que os cards aparecem em alguns minutos.
const saved = async ({
  form,
  archived,
  destination,
  importing,
  ...brought
}) => {
  editing.value = null;
  const target = destination || brought;
  const where = t(`${KEY}.WHERE`, {
    pipeline: target.pipeline_name,
    stage: target.stage_name,
  });
  if (archived) {
    useAlert(t(`${KEY}.BRINGING`, { form: form.name, where }));
  } else if (importing) {
    useAlert(t(`${KEY}.SAVED_BRINGING`, { form: form.name, where }));
  } else {
    useAlert(t(`${KEY}.SAVED`, { form: form.name, where }));
  }
  await load();
};

const removed = async form => {
  editing.value = null;
  useAlert(t(`${KEY}.REMOVED`, { form: form.name }));
  await load();
};

onMounted(load);
</script>

<template>
  <section class="flex flex-col gap-5 pb-24" data-lead-forms>
    <header class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ $t(`${KEY}.TITLE`) }}
        </h2>
        <p v-if="hasPages" class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.SUBTITLE`) }}
        </p>
      </div>
      <p
        v-if="hasPages"
        class="flex items-start gap-2 px-3 py-2 m-0 text-sm rounded-lg bg-n-blue-2 text-n-blue-11"
        data-lead-forms-whatsapp
      >
        <span
          class="flex-none mt-0.5 i-lucide-message-circle size-4"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.WHATSAPP_RULE`) }}
      </p>
      <p
        v-if="props.readOnly"
        class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
        data-lead-forms-read-only
      >
        <span class="flex-none i-lucide-lock size-4" aria-hidden="true" />
        {{ $t(`${KEY}.READ_ONLY`) }}
      </p>
    </header>

    <div v-if="loading" class="flex justify-center p-10">
      <Spinner />
    </div>

    <div
      v-else-if="failed"
      role="alert"
      class="flex flex-col items-start gap-3 p-4 rounded-xl bg-n-ruby-2 text-n-ruby-11"
    >
      {{ $t(`${KEY}.LOAD_FAILED`) }}
      <Button
        :label="$t(`${KEY}.TRY_AGAIN`)"
        size="sm"
        variant="faded"
        class="!min-h-11"
        @click="load"
      />
    </div>

    <template v-else>
      <div
        v-if="!data.pages.length"
        data-lead-forms-no-page
        class="flex flex-col items-start gap-3 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1"
      >
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{ $t(`${KEY}.NO_PAGES`) }}
        </p>
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t(`${KEY}.NO_PAGES_HINT`) }}
        </p>
        <Button
          v-if="!props.readOnly"
          data-lead-forms-connect
          class="!min-h-11 !rounded-xl"
          icon="i-lucide-arrow-right"
          trailing-icon
          :label="$t(`${KEY}.CONNECT`)"
          @click="emit('connect')"
        />
      </div>

      <MetaAdsLeadFormPage
        v-for="page in data.pages"
        :key="page.id"
        :page="page"
        :read-only="props.readOnly"
        :busy="busyPage === page.id"
        @stop="stopReceiving(page)"
        @resume="resumeReceiving(page)"
        @choose="choose"
      />

      <MetaAdsLeadsRecent
        v-if="data.pages.length && data.recent_leads"
        :leads="data.recent_leads"
      />
    </template>

    <MetaAdsLeadFormDestination
      v-if="editing"
      :form="editing"
      :resumes-page="editingPaused"
      :pipelines="data.pipelines"
      :api="LeadFormsAPI"
      @saved="saved"
      @removed="removed"
      @close="editing = null"
    />
  </section>
</template>
