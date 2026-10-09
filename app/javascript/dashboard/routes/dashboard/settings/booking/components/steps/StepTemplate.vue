<script setup>
import { useI18n } from 'vue-i18n';
import { TEMPLATES } from '../../constants';

// Passo 1: escolher um modelo. O cartão inteiro é o botão; escolher já cria a
// página com nome, duração, local e horários preenchidos (J3-A8).
defineProps({
  busy: { type: Boolean, default: false },
});

const emit = defineEmits(['choose']);
const { t } = useI18n();
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2 class="m-0 text-2xl font-semibold text-n-slate-12">
      {{ t('BOOKING.TEMPLATE.TITLE') }}
    </h2>
    <ul
      class="grid gap-4 p-0 m-0 list-none grid-cols-[repeat(auto-fit,minmax(min(100%,16rem),1fr))]"
    >
      <li v-for="item in TEMPLATES" :key="item.key" class="flex">
        <button
          type="button"
          :data-template="item.key"
          :disabled="busy"
          class="group flex flex-col w-full gap-4 p-6 text-start rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:translate-y-0"
          @click="emit('choose', item.key)"
        >
          <span class="flex items-center justify-between w-full gap-3">
            <span
              class="grid place-items-center size-14 rounded-2xl"
              :class="item.tone"
            >
              <span class="size-7" :class="item.icon" aria-hidden="true" />
            </span>
            <span
              v-if="item.popular"
              class="px-3 py-1 text-sm font-semibold rounded-full bg-n-blue-3 text-n-blue-11"
            >
              {{ t('BOOKING.TEMPLATE.POPULAR') }}
            </span>
          </span>
          <span class="flex flex-col gap-1">
            <span class="text-lg font-semibold text-n-slate-12">
              {{ t(`BOOKING.TEMPLATE.${item.i18n}.NAME`) }}
            </span>
            <span class="text-base text-n-slate-11">
              {{ t(`BOOKING.TEMPLATE.${item.i18n}.HINT`) }}
            </span>
          </span>
          <span
            class="inline-flex items-center gap-1.5 mt-auto text-base font-medium text-n-blue-11"
          >
            {{ t('BOOKING.TEMPLATE.USE') }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </span>
        </button>
      </li>
    </ul>
  </section>
</template>
