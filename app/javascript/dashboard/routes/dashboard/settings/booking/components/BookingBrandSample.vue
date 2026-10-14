<script setup>
import { ref, toRef, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingThemeToggle from './BookingThemeToggle.vue';
import {
  PublicActionButton,
  PublicBrandHeader,
  PublicPageCard,
} from '../publicPage';
import { usePublicPagePreview } from '../composables/usePublicPagePreview';
import { DEFAULT_PAGE_THEME } from '../constants';

// "Assim fica na página" (#1289), no passo Sua marca: o cabeçalho e os botões
// da página pública de verdade, mudando na hora em que a pessoa troca a logo,
// o lado dela, a cor ou a frase. É aqui que ela vê se o texto do botão ficou
// legível sobre a cor que escolheu. Nenhum botão faz nada (`inert`).
//
// A página segue o tema do aparelho do cliente (#1295): "Claro / Escuro" troca
// o tema só desta amostra (`data-booking-theme`), seja qual for o do painel.
const props = defineProps({
  form: { type: Object, required: true },
  page: { type: Object, required: true },
});

const { t } = useI18n();
const root = useTemplateRef('root');
const theme = ref(DEFAULT_PAGE_THEME);

const { publicPage } = usePublicPagePreview({
  root,
  form: toRef(props, 'form'),
  page: toRef(props, 'page'),
});
</script>

<template>
  <figure data-brand-sample class="flex flex-col gap-3 m-0">
    <figcaption class="text-base font-semibold text-n-slate-12">
      {{ t('BOOKING.LOOK.SAMPLE_TITLE') }}
    </figcaption>
    <BookingThemeToggle v-model="theme" />
    <div
      ref="root"
      inert
      data-sample-page
      :data-booking-theme="theme"
      class="flex justify-center px-4 py-6 rounded-3xl bg-bk-page ring-1 ring-inset ring-n-weak"
    >
      <div class="w-full max-w-md">
        <PublicPageCard>
          <div class="flex flex-col gap-6">
            <PublicBrandHeader :page="publicPage" />
            <div class="flex flex-col gap-3">
              <PublicActionButton>
                {{ t('BOOKING.LOOK.SAMPLE_PRIMARY') }}
              </PublicActionButton>
              <PublicActionButton variant="secondary">
                {{ t('BOOKING.LOOK.SAMPLE_SECONDARY') }}
              </PublicActionButton>
            </div>
          </div>
        </PublicPageCard>
      </div>
    </div>
  </figure>
</template>
