<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { dayLabel, slotLabel } from '../helpers/datetime';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ZoneNote from './ZoneNote.vue';

// Hora: só horários livres viram botão (ocupados não vêm da API). Tocar no horário já avança: o cliente
// chega à confirmação em até 4 toques (J1-A4, J2-A8). Dia vazio ou erro sempre oferece saída (RA-17). As horas
// estão no relógio de quem abre; se uma delas cai em outro dia ali, o botão mostra o dia junto.
const {
  page,
  slots,
  selectedDate,
  clientZone,
  isOtherClock,
  slotNotice,
  chooseDay,
  chooseSlot,
  goBack,
  openNoSlot,
} = useFlow();
const { t, locale } = useI18n();

const subtitle = computed(() =>
  selectedDate.value ? dayLabel(selectedDate.value, locale.value).full : ''
);
const isLoading = computed(() => slots.isLoading.value);
const hasFailed = computed(() => slots.hasFailed.value);
const items = computed(() =>
  slots.slots.value.map(iso => ({
    iso,
    label: slotLabel(iso, locale.value, clientZone, selectedDate.value),
  }))
);
const isEmpty = computed(
  () => !isLoading.value && !hasFailed.value && !items.value.length
);
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" :subtitle="subtitle" />
    <h1
      id="step-heading"
      data-step-heading
      tabindex="-1"
      class="text-2xl font-bold text-slate-900 focus:outline-none"
    >
      {{ t('BOOKING_V2.TIME.TITLE') }}
    </h1>

    <p
      v-if="slotNotice"
      role="alert"
      class="rounded-xl bg-yellow-100 p-4 text-base font-medium text-yellow-900"
    >
      {{ t(slotNotice) }}
    </p>

    <p
      v-if="isLoading"
      role="status"
      aria-live="polite"
      class="text-base text-slate-600"
    >
      {{ t('BOOKING_V2.TIME.LOADING') }}
    </p>

    <div v-else-if="hasFailed" role="alert" class="flex flex-col gap-3">
      <p class="text-base text-slate-800">{{ t('BOOKING_V2.TIME.FAILED') }}</p>
      <ActionButton variant="secondary" @click="chooseDay(selectedDate)">
        {{ t('BOOKING_V2.TIME.RETRY') }}
      </ActionButton>
    </div>

    <p v-else-if="isEmpty" class="text-base text-slate-800">
      {{ t('BOOKING_V2.TIME.EMPTY') }}
    </p>

    <ul
      v-else
      class="grid grid-cols-[repeat(auto-fill,minmax(6.5rem,1fr))] gap-2"
    >
      <li v-for="item in items" :key="item.iso">
        <button
          type="button"
          class="min-h-12 w-full rounded-xl border-2 border-slate-200 bg-white px-2 py-3 text-base font-semibold text-slate-900 hover:border-[var(--brand)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--brand)]"
          @click="chooseSlot(item.iso)"
        >
          {{ item.label }}
        </button>
      </li>
    </ul>

    <ZoneNote v-if="isOtherClock" />

    <div class="flex flex-col gap-2">
      <ActionButton
        :variant="isEmpty || hasFailed ? 'primary' : 'secondary'"
        @click="goBack"
      >
        {{ t('BOOKING_V2.TIME.OTHER_DAY') }}
      </ActionButton>
      <ActionButton variant="ghost" @click="openNoSlot">
        {{ t('BOOKING_V2.NO_SLOT.LINK') }}
      </ActionButton>
    </div>
  </section>
</template>
