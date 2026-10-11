<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingBrandSample from '../BookingBrandSample.vue';
import BookingField from '../BookingField.vue';
import BookingIdentity from '../BookingIdentity.vue';
import BookingImageUpload from '../BookingImageUpload.vue';
import BookingPhotoCard from '../BookingPhotoCard.vue';
import { BRAND_COLORS, LOGO_ALIGNS, MAX_TEXT } from '../../constants';
import { presetColor } from '../../bookingPageForm';

// Passo 5: a cara da página — logo (e de que lado ela fica), foto, cor (uma
// das prontas ou outra, escolhida pela pessoa) e a frase de boas-vindas, com
// uma amostra da página ao vivo. A identidade salva da conta (#1289) poupa
// refazer isso a cada página. Os avisos no WhatsApp têm passo próprio.
const props = defineProps({
  form: { type: Object, required: true },
  // A página como a API devolve: logo, foto, pessoas e a identidade salva.
  page: { type: Object, required: true },
  // 'logo' | 'photo' | null
  uploading: { type: String, default: null },
  // { kind, key } do último envio recusado.
  uploadError: { type: Object, default: null },
  // 'applied' | 'saved' | null
  identityState: { type: String, default: null },
  identityBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['change', 'upload', 'applyIdentity', 'saveIdentity']);
const { t } = useI18n();

const SELECTED = 'ring-2 ring-n-blue-9 bg-n-blue-2';
const IDLE = 'ring-1 ring-n-weak bg-n-solid-1 hover:ring-n-blue-7';

const errorFor = (kind, uploadError) =>
  uploadError?.kind === kind
    ? t(`BOOKING.WIZARD.ERRORS.${uploadError.key}`)
    : '';

const chosenPreset = computed(() => presetColor(props.form.color));
// A foto é de cada pessoa: a identidade só guarda a foto de página de uma
// pessoa fixa (não a de um link por pessoa) e com foto enviada
// (Crm::BookingV2::BrandIdentity#save_photo).
const savesPhoto = computed(
  () =>
    props.page.assignment_mode === 'fixed' &&
    !!props.page.photo_url &&
    !!props.page.host
);
</script>

<template>
  <section class="flex flex-col gap-6">
    <h2
      tabindex="-1"
      class="m-0 text-2xl font-semibold text-n-slate-12 focus:outline-none"
    >
      {{ t('BOOKING.LOOK.TITLE') }}
    </h2>

    <BookingIdentity
      :identity="page.identity || {}"
      :can-save="page.can_save_identity === true"
      :saves-photo="savesPhoto"
      :state="identityState"
      :busy="identityBusy"
      @apply="emit('applyIdentity')"
      @save="emit('saveIdentity')"
    >
      <div class="grid items-start gap-4 sm:grid-cols-2">
        <BookingImageUpload
          data-logo
          :label="t('BOOKING.LOOK.LOGO')"
          :alt="t('BOOKING.LOOK.LOGO_ALT')"
          :url="page.logo_url || ''"
          :busy="uploading === 'logo'"
          :error="errorFor('logo', uploadError)"
          :hint="t('BOOKING.LOOK.LOGO_HINT')"
          @pick="emit('upload', { kind: 'logo', file: $event })"
        />
        <BookingPhotoCard
          :page="page"
          :busy="uploading === 'photo'"
          :error="errorFor('photo', uploadError)"
          @upload="emit('upload', $event)"
        />
      </div>

      <fieldset
        v-if="page.logo_url"
        class="flex flex-col gap-3 p-0 m-0 border-0"
      >
        <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
          {{ t('BOOKING.LOOK.LOGO_ALIGN_LABEL') }}
        </legend>
        <div data-logo-aligns class="grid grid-cols-3 gap-2">
          <button
            v-for="align in LOGO_ALIGNS"
            :key="align.key"
            type="button"
            :data-logo-align="align.key"
            :aria-pressed="form.logoAlign === align.key ? 'true' : 'false'"
            class="inline-flex flex-col items-center justify-center gap-1 min-h-16 px-3 py-2 rounded-xl text-base font-medium text-n-slate-12 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="form.logoAlign === align.key ? SELECTED : IDLE"
            @click="emit('change', { logoAlign: align.key })"
          >
            <span class="size-5" :class="align.icon" aria-hidden="true" />
            {{ t(`BOOKING.LOOK.LOGO_ALIGN.${align.i18n}`) }}
          </button>
        </div>
      </fieldset>

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
            :aria-pressed="chosenPreset === color ? 'true' : 'false'"
            class="inline-flex items-center gap-2 min-h-11 ps-2 pe-4 rounded-xl text-base font-medium text-n-slate-12 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="chosenPreset === color ? SELECTED : IDLE"
            @click="emit('change', { color: color.hex })"
          >
            <span
              class="grid place-items-center size-8 rounded-lg text-white"
              :class="color.swatch"
              aria-hidden="true"
            >
              <span
                v-if="chosenPreset === color"
                class="i-lucide-check size-4"
              />
            </span>
            {{ t(`BOOKING.LOOK.COLORS.${color.key}`) }}
          </button>
          <label
            data-custom-color
            :data-selected="chosenPreset ? 'false' : 'true'"
            class="inline-flex items-center gap-2 min-h-11 ps-2 pe-4 m-0 rounded-xl text-base font-medium text-n-slate-12 ring-inset cursor-pointer has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
            :class="chosenPreset ? IDLE : SELECTED"
          >
            <input
              type="color"
              :value="form.color.toLowerCase()"
              class="size-8 p-0 m-0 bg-transparent border-0 rounded-lg cursor-pointer shrink-0"
              @input="emit('change', { color: $event.target.value })"
            />
            <span class="flex flex-col leading-tight">
              {{ t('BOOKING.LOOK.CUSTOM_COLOR') }}
              <span
                v-if="!chosenPreset"
                data-custom-color-value
                class="text-sm font-normal uppercase text-n-slate-11"
              >
                {{ form.color }}
              </span>
            </span>
          </label>
        </div>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('BOOKING.LOOK.COLOR_HINT') }}
        </p>
      </fieldset>

      <BookingField
        data-headline
        :maxlength="MAX_TEXT"
        :model-value="form.headline"
        :label="t('BOOKING.LOOK.HEADLINE_LABEL')"
        :placeholder="t('BOOKING.LOOK.HEADLINE_PLACEHOLDER')"
        @update:model-value="emit('change', { headline: $event })"
      />

      <BookingBrandSample :form="form" :page="page" />
    </BookingIdentity>
  </section>
</template>
