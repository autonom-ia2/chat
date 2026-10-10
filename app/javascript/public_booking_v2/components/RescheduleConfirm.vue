<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { whenLabel } from '../helpers/datetime';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ManageError from './ManageError.vue';
import MeetingCard from './MeetingCard.vue';

// Mudar o horário (J5 "Escolhe outro horário"): confirma antes de trocar. O cartão mostra o horário novo com o
// local da reunião; a linha de baixo lembra o horário de agora, que fica livre quando o novo é confirmado.
const { page, selectedSlot, clientZone, manage, goBack } = useFlow();
const { t, locale } = useI18n();

const current = computed(() => manage.meeting.value);
const proposed = computed(() => ({
  ...current.value,
  starts_at: selectedSlot.value,
}));
const before = computed(() =>
  current.value.starts_at
    ? whenLabel(current.value.starts_at, locale.value, clientZone)
    : ''
);
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-slate-900 focus:outline-none"
    >
      {{ t('BOOKING_V2.RESCHEDULE.CONFIRM_TITLE') }}
    </h1>
    <MeetingCard :meeting="proposed" :show-join="false" />
    <p
      v-if="before"
      data-testid="reschedule-before"
      class="text-base text-slate-700"
    >
      {{ t('BOOKING_V2.RESCHEDULE.BEFORE', { when: before }) }}
    </p>
    <ManageError />
    <div class="flex flex-col gap-3">
      <ActionButton
        :disabled="manage.isWorking.value"
        @click="manage.submitReschedule"
      >
        {{
          manage.isWorking.value
            ? t('BOOKING_V2.DETAILS.SENDING')
            : t('BOOKING_V2.RESCHEDULE.SUBMIT')
        }}
      </ActionButton>
      <ActionButton variant="ghost" @click="goBack">
        {{ t('BOOKING_V2.BACK') }}
      </ActionButton>
    </div>
  </section>
</template>
