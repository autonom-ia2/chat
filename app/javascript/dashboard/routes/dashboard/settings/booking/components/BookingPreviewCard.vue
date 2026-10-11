<script setup>
import { ref, toRef, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingThemeToggle from './BookingThemeToggle.vue';
import { PublicPageCard, PublicStepDate } from '../publicPage';
import { usePublicPagePreview } from '../composables/usePublicPagePreview';
import { DEFAULT_PAGE_THEME } from '../constants';

// "Assim o cliente vai ver" (#1289): a primeira tela da página pública de
// verdade — o mesmo cartão, o mesmo cabeçalho e a mesma tela de escolher o dia
// (public_booking_v2), com o que acabou de ser preenchido. Não é um desenho
// parecido: se a página mudar, a prévia muda junto. O "Mais cedo" é um exemplo
// e nenhum botão aqui faz nada (`inert`).
//
// A página segue o tema do aparelho do cliente (#1295): "Claro / Escuro" troca
// o tema só desta prévia (`data-booking-theme`), seja qual for o do painel.
const props = defineProps({
  form: { type: Object, required: true },
  // A página como a API devolve (PageSerializer#full): logo, foto, pessoas.
  page: { type: Object, required: true },
});

const { t } = useI18n();
const root = useTemplateRef('root');
const theme = ref(DEFAULT_PAGE_THEME);

usePublicPagePreview({
  root,
  form: toRef(props, 'form'),
  page: toRef(props, 'page'),
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <BookingThemeToggle v-model="theme" />
    <figure
      ref="root"
      data-preview
      :data-booking-theme="theme"
      class="flex justify-center m-0 px-4 py-6 overflow-hidden rounded-3xl bg-bk-page ring-1 ring-inset ring-n-weak"
    >
      <figcaption class="sr-only">{{ t('BOOKING.PREVIEW.TITLE') }}</figcaption>
      <div inert class="w-full max-w-md">
        <PublicPageCard>
          <PublicStepDate />
        </PublicPageCard>
      </div>
    </figure>
  </div>
</template>
