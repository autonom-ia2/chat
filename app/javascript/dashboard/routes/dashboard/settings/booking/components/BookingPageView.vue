<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingPreviewCard from './BookingPreviewCard.vue';
import BookingDestination from './BookingDestination.vue';
import BookingLinkActions from './BookingLinkActions.vue';
import { pageToForm } from '../bookingPageForm';
import { joinNames } from '../bookingFormat';

// Para quem só vê (agendamento_view): a página como o cliente vê, para onde vai
// quem marcar e o link. Nenhum botão muda nada (J8-A4).
const props = defineProps({
  pageId: { type: Number, required: true },
});

const emit = defineEmits(['close']);
const { t } = useI18n();

const page = ref(null);
const failed = ref(false);

onMounted(async () => {
  try {
    const { data } = await BookingPagesAPI.show(props.pageId);
    page.value = data.payload;
  } catch {
    failed.value = true;
  }
});

const form = computed(() => (page.value ? pageToForm(page.value) : null));
const peopleNames = computed(() =>
  joinNames((page.value?.people || []).map(person => person.name))
);
</script>

<template>
  <section data-page-view class="flex flex-col w-full gap-6">
    <p class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.VIEW.READ_ONLY') }}
    </p>
    <p v-if="failed" role="alert" class="m-0 text-base text-n-ruby-11">
      {{ t('BOOKING.WIZARD.LOAD_ERROR') }}
    </p>
    <p v-else-if="!page" aria-busy="true" class="m-0 text-base text-n-slate-11">
      {{ t('BOOKING.LIST.LOADING') }}
    </p>
    <template v-else>
      <BookingPreviewCard
        :form="form"
        :logo-url="page.logo_url || ''"
        :photo-url="page.photo_url || ''"
        :host-name="peopleNames"
      />
      <BookingDestination
        :pipeline-id="form.pipelineId"
        :stage-id="form.stageId"
        :people-names="peopleNames"
      />
      <BookingLinkActions v-if="page.public_url" :url="page.public_url" />
    </template>
    <button
      type="button"
      data-back
      class="self-start inline-flex items-center gap-2 min-h-12 px-5 rounded-xl text-base font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('close')"
    >
      <span
        class="i-lucide-arrow-left size-4 rtl:rotate-180"
        aria-hidden="true"
      />
      {{ t('BOOKING.WIZARD.BACK_TO_LIST') }}
    </button>
  </section>
</template>
