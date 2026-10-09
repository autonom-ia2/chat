<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingPreviewCard from '../BookingPreviewCard.vue';
import BookingDestination from '../BookingDestination.vue';
import BookingLinkActions from '../BookingLinkActions.vue';
import BookingNoticesSummary from '../BookingNoticesSummary.vue';
import BookingPostMeeting from '../BookingPostMeeting.vue';
import BookingTestInvite from '../BookingTestInvite.vue';
import { MISSING_STEP, STEP } from '../../constants';

// Último passo: a prévia, para onde vai quem marcar, os avisos no WhatsApp e
// Publicar. Se a publicação voltar com pendências, cada uma vira uma linha com
// "Resolver", que leva ao passo certo; a do funil abre o "Alterar" daqui
// mesmo. "Depois da reunião" (#1193) diz para onde vai o card depois de
// "Aconteceu". Publicada: link, QR code, Copiar link e, com número de avisos,
// "Testar no meu WhatsApp" (J3-A11).
defineProps({
  form: { type: Object, required: true },
  page: { type: Object, required: true },
  peopleNames: { type: String, default: '' },
  canManage: { type: Boolean, default: false },
  publishing: { type: Boolean, default: false },
  savingDestination: { type: Boolean, default: false },
  missing: { type: Array, default: () => [] },
});

const emit = defineEmits(['fix', 'saveDestination', 'pageUpdated']);
const { t } = useI18n();
const destination = ref(null);

const fix = item => {
  if (MISSING_STEP[item] === STEP.PREVIA) {
    destination.value?.startEditing();
    return;
  }
  if (MISSING_STEP[item]) emit('fix', MISSING_STEP[item]);
};
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2
      tabindex="-1"
      class="m-0 text-2xl font-semibold text-n-slate-12 focus:outline-none"
    >
      {{ t('BOOKING.PREVIEW.TITLE') }}
    </h2>

    <BookingPreviewCard
      :form="form"
      :logo-url="page.logo_url || ''"
      :photo-url="page.photo_url || ''"
      :host-name="peopleNames"
    />

    <BookingDestination
      ref="destination"
      :pipeline-id="form.pipelineId"
      :stage-id="form.stageId"
      :people-names="peopleNames"
      :can-manage="canManage"
      :saving="savingDestination"
      @save="emit('saveDestination', $event)"
    />

    <BookingNoticesSummary
      :form="form"
      :inbox-options="page.notice_inbox_options || []"
      :can-manage="canManage"
      @alter="emit('fix', STEP.AVISOS)"
    />

    <BookingPostMeeting
      :page-id="page.id"
      :post-meeting="page.post_meeting || {}"
      :can-manage="canManage"
      @saved="emit('pageUpdated', $event)"
    />

    <div
      v-if="missing.length"
      data-missing
      role="alert"
      class="flex flex-col gap-3 p-5 rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6"
    >
      <p class="m-0 text-base font-semibold text-n-amber-12">
        {{ t('BOOKING.PREVIEW.MISSING_TITLE') }}
      </p>
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="item in missing"
          :key="item"
          :data-missing-item="item"
          class="flex flex-wrap items-center justify-between gap-3"
        >
          <span class="text-base text-n-amber-12">
            {{ t(`BOOKING.PREVIEW.MISSING.${item.toUpperCase()}`) }}
          </span>
          <button
            v-if="MISSING_STEP[item]"
            type="button"
            :data-fix="item"
            class="inline-flex items-center min-h-11 px-4 rounded-xl text-base font-semibold text-n-amber-12 bg-n-solid-1 ring-1 ring-inset ring-n-amber-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="fix(item)"
          >
            {{ t('BOOKING.PREVIEW.FIX') }}
          </button>
        </li>
      </ul>
    </div>

    <div
      v-if="page.enabled"
      data-published
      class="flex flex-col gap-4 p-5 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
    >
      <div class="flex flex-col gap-1">
        <p class="m-0 text-lg font-semibold text-n-teal-12">
          {{ t('BOOKING.PREVIEW.PUBLISHED_TITLE') }}
        </p>
        <p class="m-0 text-base text-n-teal-12">
          {{ t('BOOKING.PREVIEW.PUBLISHED_TEXT') }}
        </p>
      </div>
      <BookingLinkActions v-if="page.public_url" :url="page.public_url" />
      <BookingTestInvite
        v-if="canManage && page.notice_inbox_id"
        :page-id="page.id"
      />
    </div>
    <span v-else-if="publishing" class="sr-only" role="status">
      {{ t('BOOKING.PREVIEW.PUBLISHING') }}
    </span>
  </section>
</template>
