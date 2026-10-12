<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { IMAGE_TYPES } from '../constants';
import { logoDarkLook, logoDarkOrigin } from '../bookingLogo';

// A logo da página, nas duas versões (#1295): "Em fundo claro" e "Em fundo
// escuro", cada uma sobre o fundo de verdade da página (`data-booking-theme`),
// com um "Trocar" em cada. Quem só envia uma logo não precisa fazer mais nada:
// o servidor cria a de fundo escuro na hora, e uma linha diz de onde ela veio
// (criada por nós, a mesma, na placa ou enviada pela pessoa). A conferência de
// tipo e tamanho é de quem usa (o assistente), que devolve o aviso em `errors`.
const props = defineProps({
  // A página como a API devolve: logo_url, logo_dark_url, brand.logo_dark_source.
  page: { type: Object, required: true },
  // 'logo' | 'logo_dark' | 'photo' | null
  uploading: { type: String, default: null },
  // Avisos já traduzidos: { logo, logoDark }.
  errors: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['pick', 'removeDark']);
const { t } = useI18n();
const lightInput = useTemplateRef('lightInput');
const darkInput = useTemplateRef('darkInput');

const BUTTON =
  'inline-flex items-center justify-center gap-2 min-h-11 px-4 rounded-xl text-base font-medium text-n-slate-12 bg-n-solid-1 ring-1 ring-inset ring-n-weak hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60';
const FRAME =
  'grid place-items-center h-28 px-4 rounded-xl bg-bk-card ring-1 ring-inset ring-bk-line';
const IMAGE = 'max-h-14 w-auto h-auto max-w-[min(12rem,100%)] object-contain';
const PLATE = 'rounded-lg bg-[var(--bk-plate)] p-[var(--bk-plate-pad)]';

const hasLogo = computed(() => !!props.page.logo_url);
const lightAction = computed(() =>
  hasLogo.value ? t('BOOKING.LOOK.CHANGE') : t('BOOKING.LOOK.UPLOAD')
);
const busyLight = computed(() => props.uploading === 'logo');
const busyDark = computed(() => props.uploading === 'logo_dark');
const origin = computed(() => logoDarkOrigin(props.page));
const dark = computed(() => logoDarkLook(props.page));
// Enquanto a logo nova sobe, a de fundo escuro está sendo criada junto.
const originKey = computed(() => (busyLight.value ? 'CREATING' : origin.value));
const canRemoveDark = computed(() => origin.value === 'UPLOADED');

const onFile = (kind, event) => {
  const [file] = event.target.files || [];
  // Limpa para o mesmo arquivo poder ser escolhido de novo depois de um erro.
  event.target.value = '';
  if (file) emit('pick', { kind, file });
};
</script>

<template>
  <div
    data-logo-card
    class="flex flex-col gap-4 p-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-base font-semibold text-n-slate-12">
      {{ t('BOOKING.LOOK.LOGO') }}
    </p>
    <div class="grid gap-4 sm:grid-cols-2">
      <div data-logo class="flex flex-col gap-3">
        <div data-booking-theme="light" :class="FRAME">
          <img
            v-if="hasLogo"
            :src="page.logo_url"
            :alt="t('BOOKING.LOOK.LOGO_ALT')"
            :class="IMAGE"
          />
          <span
            v-else
            class="i-lucide-image size-7 text-bk-soft"
            aria-hidden="true"
          />
        </div>
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{ t('BOOKING.LOOK.LOGO_LIGHT.TITLE') }}
        </p>
        <button
          type="button"
          data-upload
          :disabled="busyLight || busyDark"
          :aria-label="`${t('BOOKING.LOOK.LOGO_LIGHT.TITLE')}: ${lightAction}`"
          class="self-start"
          :class="BUTTON"
          @click="lightInput?.click()"
        >
          <span
            class="size-4"
            :class="
              busyLight
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-upload'
            "
            aria-hidden="true"
          />
          {{ busyLight ? t('BOOKING.LOOK.UPLOADING') : lightAction }}
        </button>
        <input
          ref="lightInput"
          data-file
          type="file"
          :accept="IMAGE_TYPES.join(',')"
          class="hidden"
          @change="onFile('logo', $event)"
        />
        <p v-if="errors.logo" role="alert" class="m-0 text-base text-n-ruby-11">
          {{ errors.logo }}
        </p>
      </div>

      <div data-logo-dark class="flex flex-col gap-3">
        <div data-booking-theme="dark" :class="FRAME">
          <img
            v-if="hasLogo"
            :src="dark.url"
            :alt="t('BOOKING.LOOK.LOGO_DARK.ALT')"
            :data-on-plate="dark.onPlate ? 'true' : 'false'"
            :class="[IMAGE, dark.onPlate ? PLATE : '']"
          />
          <span
            v-else
            class="i-lucide-image size-7 text-bk-soft"
            aria-hidden="true"
          />
        </div>
        <p class="m-0 text-base font-medium text-n-slate-12">
          {{ t('BOOKING.LOOK.LOGO_DARK.TITLE') }}
        </p>
        <div v-if="hasLogo" class="flex flex-wrap gap-2">
          <button
            type="button"
            data-upload-dark
            :disabled="busyDark || busyLight"
            :aria-label="`${t('BOOKING.LOOK.LOGO_DARK.TITLE')}: ${t(
              'BOOKING.LOOK.CHANGE'
            )}`"
            :class="BUTTON"
            @click="darkInput?.click()"
          >
            <span
              class="size-4"
              :class="
                busyDark
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-upload'
              "
              aria-hidden="true"
            />
            {{
              busyDark ? t('BOOKING.LOOK.UPLOADING') : t('BOOKING.LOOK.CHANGE')
            }}
          </button>
          <button
            v-if="canRemoveDark"
            type="button"
            data-remove-dark
            :disabled="busyDark || busyLight"
            :class="BUTTON"
            @click="emit('removeDark')"
          >
            <span class="i-lucide-undo-2 size-4" aria-hidden="true" />
            {{ t('BOOKING.LOOK.LOGO_DARK.REMOVE') }}
          </button>
        </div>
        <p
          data-logo-dark-origin
          :data-origin="originKey"
          role="status"
          class="m-0 text-base text-n-slate-11"
        >
          {{ t(`BOOKING.LOOK.LOGO_DARK.ORIGIN.${originKey}`) }}
        </p>
        <input
          ref="darkInput"
          data-file-dark
          type="file"
          :accept="IMAGE_TYPES.join(',')"
          class="hidden"
          @change="onFile('logo_dark', $event)"
        />
        <p
          v-if="errors.logoDark"
          role="alert"
          class="m-0 text-base text-n-ruby-11"
        >
          {{ errors.logoDark }}
        </p>
      </div>
    </div>
    <p class="m-0 text-sm text-n-slate-11">
      {{ t('BOOKING.LOOK.IMAGE_HINT') }} {{ t('BOOKING.LOOK.LOGO_HINT') }}
    </p>
  </div>
</template>
