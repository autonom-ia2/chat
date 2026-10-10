<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ManageError from './ManageError.vue';

// Parar avisos (RA-18, J5-A7): diz que as mensagens automáticas param e que o horário continua valendo. Também é a
// tela de abertura do link de "Parar avisos" das mensagens (`?stop_notices=1`): parar pede um toque (useManage).
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
      {{ t('BOOKING_V2.MANAGE.STOP_SCREEN.TITLE') }}
    </h1>
    <p class="text-base text-slate-800">
      {{ t('BOOKING_V2.MANAGE.STOP_SCREEN.BODY') }}
    </p>
    <p
      v-if="!manage.isCanceled.value"
      data-testid="stop-keeps-meeting"
      class="text-base font-semibold text-slate-900"
    >
      {{ t('BOOKING_V2.MANAGE.STOP_SCREEN.KEEPS') }}
    </p>
    <ManageError />
    <div class="flex flex-col gap-3">
      <ActionButton
        :disabled="manage.isWorking.value"
        @click="manage.stopNotices"
      >
        {{
          manage.isWorking.value
            ? t('BOOKING_V2.DETAILS.SENDING')
            : t('BOOKING_V2.MANAGE.STOP_SCREEN.YES')
        }}
      </ActionButton>
      <ActionButton variant="ghost" @click="manage.back">
        {{ t('BOOKING_V2.MANAGE.STOP_SCREEN.NO') }}
      </ActionButton>
    </div>
  </section>
</template>
