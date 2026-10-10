<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCanManage } from 'dashboard/composables/useCanManage';
import BookingPagesList from './components/BookingPagesList.vue';
import BookingWizard from './components/BookingWizard.vue';
import BookingPageView from './components/BookingPageView.vue';
import BookingSettingsTabs from './components/BookingSettingsTabs.vue';
import { STEP } from './constants';

// Configurações › Agendamento (#1187, F1-D): a lista de páginas, o assistente
// de sete passos e, para quem só vê, a página em modo leitura. Escrever pede
// `agendamento_manage` (o administrador tem).
const { t } = useI18n();
const canManage = useCanManage('agendamento_manage');

// { mode: 'list' } | { mode: 'wizard', pageId, step } | { mode: 'view', pageId }
const screen = ref({ mode: 'list' });

const showList = () => {
  screen.value = { mode: 'list' };
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
      @close="showList"
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
