<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { dayLabel, whenLabel } from '../helpers/datetime';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ChoiceCards from './ChoiceCards.vue';
import ZoneNote from './ZoneNote.vue';

// Dia (J1 "Escolhe o dia", J2 "Abre a página"): atalho do horário mais cedo no topo (J1-A13, J2-A8) e os dias
// da janela em que a página atende (dia fechado não vira botão). Os dias são do fuso da página; os horários aparecem
// no relógio de quem abre (RA-08). Ao mudar o horário de uma reunião (J5) a duração é a dela, e a saída é manter o
// horário de agora em vez de pedir contato.
const {
  page,
  slots,
  days,
  durations,
  duration,
  greetingName,
  clientZone,
  isOtherClock,
  chooseDay,
  chooseDuration,
  chooseEarliest,
  openNoSlot,
  manage,
} = useFlow();
const { t, locale } = useI18n();

const isRescheduling = computed(() => manage.isRescheduling.value);
const heading = computed(() => {
  if (isRescheduling.value) return t('BOOKING_V2.RESCHEDULE.DATE_TITLE');
  return greetingName.value
    ? t('BOOKING_V2.DATE.HELLO', { name: greetingName.value })
    : t('BOOKING_V2.DATE.TITLE');
});
const earliest = computed(() =>
  slots.nextSlot.value
    ? whenLabel(slots.nextSlot.value, locale.value, clientZone)
    : ''
);
const dayItems = computed(() =>
  days.value.map(iso => ({ iso, ...dayLabel(iso, locale.value) }))
);
const durationOptions = computed(() =>
  durations.value.map(minutes => ({
    value: minutes,
    label: t('BOOKING_V2.DATE.DURATION_OPTION', { minutes }),
  }))
);
const selectedDuration = computed({
  get: () => duration.value,
  set: minutes => chooseDuration(minutes),
});
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <p v-if="page.description" class="text-base text-slate-700">
      {{ page.description }}
    </p>
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-slate-900 focus:outline-none"
    >
      {{ heading }}
    </h1>

    <ChoiceCards
      v-if="durationOptions.length > 1 && !isRescheduling"
      v-model="selectedDuration"
      name="booking-duration"
      :legend="t('BOOKING_V2.DATE.DURATION_TITLE')"
      :options="durationOptions"
    />

    <div
      v-if="earliest"
      class="flex flex-col gap-3 rounded-2xl border-2 border-[var(--brand)] bg-white p-4"
    >
      <p class="text-lg font-semibold text-slate-900">
        {{ t('BOOKING_V2.DATE.EARLIEST', { when: earliest }) }}
      </p>
      <ActionButton variant="secondary" @click="chooseEarliest">
        {{ t('BOOKING_V2.DATE.PICK_EARLIEST') }}
      </ActionButton>
    </div>

    <div class="flex flex-col gap-3">
      <h2 v-if="earliest" class="text-lg font-semibold text-slate-900">
        {{ t('BOOKING_V2.DATE.OTHER_DAY') }}
      </h2>
      <ul class="grid grid-cols-[repeat(auto-fill,minmax(5rem,1fr))] gap-2">
        <li v-for="item in dayItems" :key="item.iso">
          <button
            type="button"
            class="flex min-h-16 w-full flex-col items-center justify-center rounded-xl border-2 border-slate-200 bg-white px-1 py-2 text-slate-900 hover:border-[var(--brand)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--brand)]"
            :aria-label="item.full"
            @click="chooseDay(item.iso)"
          >
            <span class="text-base capitalize text-slate-600">
              {{ item.weekday }}
            </span>
            <span class="text-xl font-bold">{{ item.day }}</span>
            <span class="text-base text-slate-600">{{ item.month }}</span>
          </button>
        </li>
      </ul>
      <ZoneNote v-if="isOtherClock" />
    </div>

    <ActionButton
      v-if="isRescheduling"
      variant="ghost"
      @click="manage.returnToManage"
    >
      {{ t('BOOKING_V2.RESCHEDULE.KEEP') }}
    </ActionButton>
    <ActionButton v-else variant="ghost" @click="openNoSlot">
      {{ t('BOOKING_V2.NO_SLOT.LINK') }}
    </ActionButton>
  </section>
</template>
