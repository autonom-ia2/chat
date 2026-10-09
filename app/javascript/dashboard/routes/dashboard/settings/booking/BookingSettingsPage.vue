<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCanManage } from 'dashboard/composables/useCanManage';
import BookingPagesList from './components/BookingPagesList.vue';
import BookingWizard from './components/BookingWizard.vue';
import BookingPageView from './components/BookingPageView.vue';

// Configurações › Agendamento (#1187, F1-D): a lista de páginas, o assistente
// de seis passos e, para quem só vê, a página em modo leitura. Escrever pede
// `agendamento_manage` (o administrador tem).
const { t } = useI18n();
const canManage = useCanManage('agendamento_manage');

// { mode: 'list' } | { mode: 'wizard', pageId } | { mode: 'view', pageId }
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

    <BookingWizard
      v-if="screen.mode === 'wizard' && canManage"
      :page-id="screen.pageId"
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
      @view="view"
    />
  </div>
</template>
