<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ManageError from './ManageError.vue';
import MeetingCard from './MeetingCard.vue';

// Cancelar (J5-A3): confirmação de um passo, com o horário na tela para a pessoa ter certeza de qual é.
const { page, manage } = useFlow();
const { t } = useI18n();
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
      {{ t('BOOKING_V2.MANAGE.CANCEL_SCREEN.TITLE') }}
    </h1>
    <MeetingCard :meeting="manage.meeting.value" :show-join="false" />
    <p class="text-base text-slate-800">
      {{ t('BOOKING_V2.MANAGE.CANCEL_SCREEN.BODY') }}
    </p>
    <ManageError />
    <div class="flex flex-col gap-3">
      <ActionButton :disabled="manage.isWorking.value" @click="manage.cancel">
        {{
          manage.isWorking.value
            ? t('BOOKING_V2.DETAILS.SENDING')
            : t('BOOKING_V2.MANAGE.CANCEL_SCREEN.YES')
        }}
      </ActionButton>
      <ActionButton variant="ghost" @click="manage.back">
        {{ t('BOOKING_V2.MANAGE.CANCEL_SCREEN.NO') }}
      </ActionButton>
    </div>
  </section>
</template>
