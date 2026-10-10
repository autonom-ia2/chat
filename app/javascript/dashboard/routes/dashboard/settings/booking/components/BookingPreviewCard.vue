<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { brandSwatch } from '../bookingPageForm';
import { formatHour, formatMinutes, formatWeekdays } from '../bookingFormat';

// "Assim o cliente vai ver": a página com o que acabou de ser preenchido —
// cor, logo, foto, nome, frase, local e horário. É uma imagem da página, não a
// página: os botões aqui não fazem nada.
const props = defineProps({
  form: { type: Object, required: true },
  logoUrl: { type: String, default: '' },
  photoUrl: { type: String, default: '' },
  hostName: { type: String, default: '' },
});

const { t } = useI18n();

const swatch = computed(() => brandSwatch(props.form.color));
const locations = computed(() =>
  props.form.locations.map(item =>
    t(`BOOKING.WHERE.${item.type.toUpperCase()}.NAME`)
  )
);
const schedule = computed(() =>
  props.form.weekdays.length
    ? t('BOOKING.PREVIEW.SCHEDULE', {
        days: formatWeekdays(t, props.form.weekdays),
        from: formatHour(t, props.form.startHour),
        to: formatHour(t, props.form.endHour),
      })
    : ''
);
</script>

<template>
  <figure
    data-preview
    class="flex flex-col m-0 overflow-hidden rounded-3xl ring-1 ring-inset ring-n-weak bg-n-solid-1 shadow-lg"
  >
    <figcaption class="sr-only">{{ t('BOOKING.PREVIEW.TITLE') }}</figcaption>
    <div class="flex items-center gap-3 px-6 py-5 text-white" :class="swatch">
      <img
        v-if="logoUrl"
        :src="logoUrl"
        :alt="t('BOOKING.LOOK.LOGO_ALT')"
        class="object-contain h-10 max-w-32 rounded-md bg-white/90 p-1"
      />
      <p class="m-0 text-lg font-semibold break-words">
        {{ form.headline || t('BOOKING.PREVIEW.DEFAULT_HEADLINE') }}
      </p>
    </div>
    <div class="flex flex-col gap-4 p-6">
      <div class="flex items-center gap-4">
        <img
          v-if="photoUrl"
          :src="photoUrl"
          :alt="t('BOOKING.LOOK.PHOTO_ALT')"
          class="object-cover rounded-full size-14"
        />
        <div class="flex flex-col gap-0.5 min-w-0">
          <p
            data-preview-title
            class="m-0 text-xl font-semibold text-n-slate-12 break-words"
          >
            {{ form.title }}
          </p>
          <p v-if="hostName" class="m-0 text-base text-n-slate-11">
            {{ t('BOOKING.PREVIEW.WITH', { name: hostName }) }}
          </p>
        </div>
      </div>
      <ul
        class="flex flex-col gap-2 p-0 m-0 text-base list-none text-n-slate-12"
      >
        <li class="flex items-center gap-3">
          <span
            class="i-lucide-clock size-5 text-n-slate-11"
            aria-hidden="true"
          />
          {{ formatMinutes(t, form.durationMinutes) }}
        </li>
        <li v-if="locations.length" class="flex items-center gap-3">
          <span
            class="i-lucide-map-pin size-5 text-n-slate-11"
            aria-hidden="true"
          />
          {{ locations.join(' · ') }}
        </li>
        <li v-if="schedule" class="flex items-center gap-3">
          <span
            class="i-lucide-calendar size-5 text-n-slate-11"
            aria-hidden="true"
          />
          {{ schedule }}
        </li>
      </ul>
      <span
        aria-hidden="true"
        class="inline-flex items-center justify-center min-h-12 px-6 rounded-xl text-base font-semibold text-white"
        :class="swatch"
      >
        {{ t('BOOKING.PREVIEW.PICK_TIME') }}
      </span>
    </div>
  </figure>
</template>
