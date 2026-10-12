<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useCanManage } from 'dashboard/composables/useCanManage';
import BookingPagesList from './components/BookingPagesList.vue';
import BookingWizard from './components/BookingWizard.vue';
import BookingPageView from './components/BookingPageView.vue';
import BookingSettingsTabs from './components/BookingSettingsTabs.vue';
import BookingBackToCalendar from './components/BookingBackToCalendar.vue';
import { STEP } from './constants';
import { internalReturnPath } from './bookingReturnPath';

// CRM › Agendamento (#1187, F1-D): a lista de páginas, o assistente
// de sete passos e, para quem só vê, a página em modo leitura. Escrever pede
// `agendamento_manage` (o administrador tem).
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const canManage = useCanManage('agendamento_manage');

// { mode: 'list' } | { mode: 'wizard', pageId, step } | { mode: 'view', pageId }
const screen = ref({ mode: 'list' });

// Link direto (#1371): `?nova=1` abre o assistente de página nova, só para
// quem pode gerenciar (sem permissão, a lista de sempre). Vale ao abrir a tela
// e também numa mudança só de query, com a tela já montada.
watch(
  () => route.query,
  query => {
    if (query?.nova === '1' && canManage.value) {
      screen.value = { mode: 'wizard', pageId: null };
    }
  },
  { immediate: true }
);

const showList = () => {
  screen.value = { mode: 'list' };
};
// Ao sair do assistente: para o `?voltar=` se for caminho interno do painel
// desta conta (bookingReturnPath.js); senão a lista, sem `nova`/`voltar` no
// endereço (um F5 não reabre o assistente). Vale também para o "Concluir" com
// a página já no ar, de propósito: quem veio do agente volta para ele.
const closeWizard = () => {
  const returnTo = internalReturnPath(
    route.query?.voltar,
    route.params?.accountId
  );
  if (returnTo) {
    router.push(returnTo);
    return;
  }
  showList();
  const { nova, voltar, ...rest } = route.query || {};
  if (nova !== undefined || voltar !== undefined)
    router.replace({ query: rest });
};
const create = () => {
  screen.value = { mode: 'wizard', pageId: null };
};
const edit = page => {
  screen.value = { mode: 'wizard', pageId: page.id };
};
// "Publicar" do cartão abre a prévia: a pessoa confere antes de pôr no ar.
const publish = page => {
  screen.value = { mode: 'wizard', pageId: page.id, step: STEP.PREVIA };
};
const view = page => {
  screen.value = { mode: 'view', pageId: page.id };
};
</script>

<template>
  <div class="flex flex-col w-full max-w-3xl gap-8 mx-auto">
    <BookingBackToCalendar v-if="screen.mode === 'list'" />

    <header class="flex flex-col gap-2">
      <h1 class="m-0 text-3xl font-semibold text-n-slate-12">
        {{ t('BOOKING.PAGE.TITLE') }}
      </h1>
      <p class="m-0 text-lg text-n-slate-11">
        {{ t('BOOKING.PAGE.SUBTITLE') }}
      </p>
    </header>

    <BookingSettingsTabs v-if="screen.mode === 'list'" />

    <BookingWizard
      v-if="screen.mode === 'wizard' && canManage"
      :page-id="screen.pageId"
      :initial-step="screen.step"
      @close="closeWizard"
    />
    <BookingPageView
      v-else-if="screen.mode === 'view'"
      :page-id="screen.pageId"
      @close="showList"
    />
    <BookingPagesList
      v-else
      :can-manage="canManage"
      @create="create"
      @edit="edit"
      @publish="publish"
      @view="view"
    />
  </div>
</template>
