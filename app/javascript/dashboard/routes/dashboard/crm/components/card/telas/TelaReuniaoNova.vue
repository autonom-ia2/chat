<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmBookingAgendaForm from '../../calendar/CrmBookingAgendaForm.vue';
import CrmProviderMeetingForm from '../../calendar/CrmProviderMeetingForm.vue';

// #1423 — marcar reunião dentro da gaveta, no padrão das outras telas (herói,
// cartão-frase, conteúdo, um botão azul no rodapé). Dois caminhos, os mesmos da
// janela do calendário:
//   'pagina'  — pela página de agendamento (#1265): dia, horário livre,
//               duração, lugar e aviso ao cliente;
//   'externa' — pela agenda do Google ou da Microsoft: convite por e-mail,
//               chamada de vídeo e lembrete.
// Com os dois ligados, a pessoa escolhe em cima (como as abas da janela). A
// gaveta chama `marcar()` pelo botão do rodapé e ouve `marcou`.
const props = defineProps({
  card: { type: Object, required: true },
  paginas: { type: Array, default: () => [] },
  caixas: { type: Array, default: () => [] },
  temCaixa: { type: Boolean, default: false },
  accountId: { type: [String, Number], required: true },
});
const emit = defineEmits(['marcou']);

const { t } = useI18n();
const R = 'CRM_CARD.REUNIAO_NOVA';
const PAGINA = 'pagina';
const EXTERNA = 'externa';

const temPagina = computed(() => props.paginas.length > 0);
const jeito = ref(temPagina.value ? PAGINA : EXTERNA);
watch(temPagina, valor => {
  if (!valor) jeito.value = EXTERNA;
});
const escolhe = computed(() => temPagina.value && props.temCaixa);
const pelaPagina = computed(() => temPagina.value && jeito.value === PAGINA);

const agenda = ref(null);
const externa = ref(null);
const salvando = ref(false);

defineExpose({
  marcar: () =>
    pelaPagina.value ? agenda.value?.submit() : externa.value?.submit(),
  salvando,
  externa: computed(() => !pelaPagina.value),
  // Depois de pedir o link pela página, a ação é enviar ou copiar (o próprio
  // formulário).
  mostrandoLink: computed(
    () => pelaPagina.value && Boolean(agenda.value?.isShowingLink)
  ),
});
</script>

<template>
  <section class="flex flex-col gap-4" data-tela="reuniao-nova">
    <div
      v-if="escolhe"
      role="group"
      :aria-label="t(`${R}.COMO`)"
      class="grid grid-cols-2 gap-1 rounded-2xl bg-n-alpha-2 p-1"
      data-reuniao-jeito
    >
      <button
        v-for="opcao in [PAGINA, EXTERNA]"
        :key="opcao"
        type="button"
        :aria-pressed="jeito === opcao"
        :data-reuniao-jeito-opcao="opcao"
        :disabled="salvando"
        class="min-h-11 rounded-xl px-3 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        :class="
          jeito === opcao
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="jeito = opcao"
      >
        {{ t(opcao === PAGINA ? `${R}.PELA_PAGINA` : `${R}.PELA_AGENDA`) }}
      </button>
    </div>

    <p
      v-if="!pelaPagina"
      data-reuniao-frase
      class="mb-0 flex items-start gap-3 rounded-2xl bg-n-blue-2 p-4 text-sm text-n-slate-12"
    >
      <span
        class="i-lucide-mail-check mt-0.5 size-5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ t(`${R}.FRASE_EXTERNA`) }}
    </p>

    <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm">
      <!-- Os dois ficam montados ao trocar o jeito: nada do que foi digitado se
      perde. -->
      <CrmBookingAgendaForm
        v-if="temPagina"
        v-show="pelaPagina"
        ref="agenda"
        :pages="paginas"
        :card="card"
        :card-id="card.id"
        @saving="salvando = $event"
        @booked="emit('marcou', $event)"
      />
      <CrmProviderMeetingForm
        v-if="temCaixa || !temPagina"
        v-show="!pelaPagina"
        ref="externa"
        active
        :account-id="accountId"
        :card-id="card.id"
        :available-inboxes="caixas"
        :card-contact-email="card.contact?.email || ''"
        :card-contact-name="card.contact?.name || ''"
        @saving="salvando = $event"
        @create="emit('marcou', $event)"
      />
    </div>
  </section>
</template>
