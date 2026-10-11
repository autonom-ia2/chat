<script setup>
import { toRef, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { PublicPageCard, PublicStepDate } from '../publicPage';
import { usePublicPagePreview } from '../composables/usePublicPagePreview';

// "Assim o cliente vai ver" (#1289): a primeira tela da página pública de
// verdade — o mesmo cartão, o mesmo cabeçalho e a mesma tela de escolher o dia
// (public_booking_v2), com o que acabou de ser preenchido. Não é um desenho
// parecido: se a página mudar, a prévia muda junto. O "Mais cedo" é um exemplo
// e nenhum botão aqui faz nada (`inert`).
const props = defineProps({
  form: { type: Object, required: true },
  // A página como a API devolve (PageSerializer#full): logo, foto, pessoas.
  page: { type: Object, required: true },
});

const { t } = useI18n();
const root = useTemplateRef('root');

usePublicPagePreview({
  root,
  form: toRef(props, 'form'),
  page: toRef(props, 'page'),
});
</script>

<template>
  <figure
    ref="root"
    data-preview
    class="flex justify-center m-0 px-4 py-6 overflow-hidden rounded-3xl bg-slate-100 ring-1 ring-inset ring-n-weak"
  >
    <figcaption class="sr-only">{{ t('BOOKING.PREVIEW.TITLE') }}</figcaption>
    <div inert class="w-full max-w-md">
      <PublicPageCard>
        <PublicStepDate />
      </PublicPageCard>
    </div>
  </figure>
</template>
