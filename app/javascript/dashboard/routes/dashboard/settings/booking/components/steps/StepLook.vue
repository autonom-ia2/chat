<script setup>
import { useI18n } from 'vue-i18n';
import BookingField from '../BookingField.vue';
import BookingImageUpload from '../BookingImageUpload.vue';
import { BRAND_COLORS, MAX_TEXT } from '../../constants';

// Passo 5: a cara da página — logo, foto, cor (entre opções prontas) e a frase
// de boas-vindas. Os avisos por WhatsApp chegam numa fase seguinte (F2-A) e
// por isso não aparecem aqui.
defineProps({
  form: { type: Object, required: true },
  logoUrl: { type: String, default: '' },
  photoUrl: { type: String, default: '' },
  // 'logo' | 'photo' | null
  uploading: { type: String, default: null },
  // { kind, key } do último envio recusado.
  uploadError: { type: Object, default: null },
});

const emit = defineEmits(['change', 'upload']);
const { t } = useI18n();

const errorFor = (kind, uploadError) =>
  uploadError?.kind === kind
    ? t(`BOOKING.WIZARD.ERRORS.${uploadError.key}`)
    : '';
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2 class="m-0 text-2xl font-semibold text-n-slate-12">
      {{ t('BOOKING.LOOK.TITLE') }}
    </h2>

    <div class="grid gap-4 sm:grid-cols-2">
      <BookingImageUpload
        data-logo
        :label="t('BOOKING.LOOK.LOGO')"
        :alt="t('BOOKING.LOOK.LOGO_ALT')"
        :url="logoUrl"
        :busy="uploading === 'logo'"
        :error="errorFor('logo', uploadError)"
        @pick="emit('upload', { kind: 'logo', file: $event })"
      />
      <BookingImageUpload
        data-photo
        round
        :label="t('BOOKING.LOOK.PHOTO')"
        :alt="t('BOOKING.LOOK.PHOTO_ALT')"
        :url="photoUrl"
        :busy="uploading === 'photo'"
        :error="errorFor('photo', uploadError)"
        @pick="emit('upload', { kind: 'photo', file: $event })"
      />
    </div>

    <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.LOOK.COLOR_LABEL') }}
      </legend>
      <div data-colors class="flex flex-wrap gap-2">
        <button
          v-for="color in BRAND_COLORS"
          :key="color.key"
          type="button"
          :data-color="color.hex"
          :aria-pressed="form.color === color.hex ? 'true' : 'false'"
          class="inline-flex items-center gap-2 min-h-11 ps-2 pe-4 rounded-xl text-base font-medium text-n-slate-12 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            form.color === color.hex
              ? 'ring-2 ring-n-blue-9 bg-n-blue-2'
              : 'ring-1 ring-n-weak bg-n-solid-1 hover:ring-n-blue-7'
          "
          @click="emit('change', { color: color.hex })"
        >
          <span
            class="grid place-items-center size-8 rounded-lg text-white"
            :class="color.swatch"
            aria-hidden="true"
          >
            <span
              v-if="form.color === color.hex"
              class="i-lucide-check size-4"
            />
          </span>
          {{ t(`BOOKING.LOOK.COLORS.${color.key}`) }}
        </button>
      </div>
    </fieldset>

    <BookingField
      data-headline
      :maxlength="MAX_TEXT"
      :model-value="form.headline"
      :label="t('BOOKING.LOOK.HEADLINE_LABEL')"
      :placeholder="t('BOOKING.LOOK.HEADLINE_PLACEHOLDER')"
      @update:model-value="emit('change', { headline: $event })"
    />
  </section>
</template>
