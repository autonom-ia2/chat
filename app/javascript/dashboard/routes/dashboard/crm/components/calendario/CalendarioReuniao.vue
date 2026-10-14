<script setup>
// Calendário Ouro — "Reunião com cliente" pelo agendamento novo (#1187), direto
// do calendário, na gaveta da casa (topo escuro, formulário, um botão azul).
// O formulário é o mesmo do card → Agenda → Marcar, sem reescrever:
//   'pagina'  — CrmBookingAgendaForm (página de agendamento, o dia escolhido);
//   'externa' — CrmProviderMeetingForm (agenda do Google ou da Microsoft).
// Quem decide o jeito é useJeitoDeMarcar (quem abre esta gaveta passa).
import { computed, ref, useId, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CardHeroi from '../card/CardHeroi.vue';
import CardRodape from '../card/CardRodape.vue';
import { useFocoPreso } from '../card/useFocoPreso';
import CrmBookingAgendaForm from '../calendar/CrmBookingAgendaForm.vue';
import CrmProviderMeetingForm from '../calendar/CrmProviderMeetingForm.vue';
import { dataDaChave } from './tempoNaConta';

const props = defineProps({
  show: { type: Boolean, default: false },
  cardId: { type: [Number, String], default: null },
  // O dia escolhido no calendário (AAAA-MM-DD, no fuso da conta).
  dia: { type: String, default: '' },
  jeito: { type: String, default: 'carregando' },
  paginas: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
  accountId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'marcou']);

const { t } = useI18n();
const store = useStore();
const N = 'CRM_CALENDARIO.REUNIAO';
const gavetaId = `reuniao-gaveta-${useId()}`;

const card = ref(null);
const carregando = ref(false);
const salvando = ref(false);
const agenda = ref(null);
const externa = ref(null);
const raiz = ref(null);

const pelaPagina = computed(() => props.jeito === 'pagina');
const pronto = computed(() => Boolean(card.value) && !carregando.value);

watch(
  () => [props.show, props.cardId],
  async ([aberta, id]) => {
    if (!aberta || !id) return;
    card.value = null;
    carregando.value = true;
    try {
      card.value = await store.dispatch('crmKanban/fetchCard', id);
    } catch {
      useAlert(t('CRM_KANBAN.ALERTS.CARD_LOAD_ERROR'));
      emit('close');
    } finally {
      carregando.value = false;
    }
  },
  { immediate: true }
);

const fechar = () => {
  if (!salvando.value) emit('close');
};
const marcou = reuniao => {
  emit('marcou', reuniao);
  emit('close');
};
const marcar = () =>
  pelaPagina.value ? agenda.value?.submit() : externa.value?.submit();

const cliente = computed(
  () => card.value?.contact?.name || card.value?.title || ''
);
const heroi = computed(() => ({
  rotulo: t(`${N}.ROTULO`),
  icone: 'i-lucide-calendar-check',
  titulo: cliente.value
    ? t(`${N}.TITULO`, { nome: cliente.value })
    : t(`${N}.TITULO_SEM_NOME`),
  texto: pelaPagina.value ? t(`${N}.TEXTO_PAGINA`) : t(`${N}.TEXTO_EXTERNA`),
}));
const mostrandoLink = computed(
  () => pelaPagina.value && Boolean(agenda.value?.isShowingLink)
);
const rodape = computed(() => ({
  secundaria: { rotulo: t(`${N}.CANCELAR`), acao: fechar },
  principal: mostrandoLink.value
    ? null
    : {
        rotulo: t(`${N}.MARCAR`),
        icone: 'i-lucide-check',
        carregando: salvando.value,
        desabilitado: !pronto.value,
        acao: marcar,
      },
}));

const { prender } = useFocoPreso({ raiz, mostrar: computed(() => props.show) });
const dataDoDia = computed(() =>
  props.dia ? dataDaChave(props.dia) : new Date()
);
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      ref="raiz"
      data-reuniao-gaveta
      role="dialog"
      aria-modal="true"
      :aria-labelledby="`${gavetaId}-titulo`"
      tabindex="-1"
      class="fixed inset-y-0 z-50 flex h-full w-[48rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl outline-none ltr:right-0 rtl:left-0"
      @keydown="prender"
      @keydown.esc="fechar"
    >
      <CardHeroi
        v-bind="heroi"
        :titulo-id="`${gavetaId}-titulo`"
        :texto-id="`${gavetaId}-texto`"
        @fechar="fechar"
      />
      <div class="min-h-0 flex-1 overflow-y-auto px-5 py-6 sm:px-8">
        <div
          v-if="!pronto"
          class="flex flex-col gap-3"
          aria-busy="true"
          data-reuniao-carregando
        >
          <span
            v-for="n in 3"
            :key="n"
            class="h-16 animate-pulse rounded-2xl bg-n-alpha-2"
          />
        </div>
        <div
          v-else
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
        >
          <CrmBookingAgendaForm
            v-if="pelaPagina"
            ref="agenda"
            :pages="paginas"
            :card="card"
            :card-id="card.id"
            :initial-day="dia"
            @saving="salvando = $event"
            @booked="marcou"
          />
          <CrmProviderMeetingForm
            v-else
            ref="externa"
            active
            :account-id="accountId"
            :card-id="card.id"
            :date="dataDoDia"
            :available-inboxes="caixas"
            :card-contact-email="card.contact?.email || ''"
            :card-contact-name="card.contact?.name || ''"
            @saving="salvando = $event"
            @create="marcou"
          />
        </div>
      </div>
      <CardRodape :rodape="rodape" :ocupado="salvando" />
    </div>
  </transition>
</template>
