<script setup>
import { computed, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useBookingInvite } from 'dashboard/components-next/Booking/useBookingInvite';
import {
  stateLabelKey,
  stateToneClass,
} from 'dashboard/components-next/Booking/bookingInvite';
import CrmMeetingDayActions from '../../calendar/CrmMeetingDayActions.vue';
import { resolveMeetingLocation } from '../../../helpers/meetingLocation';
import { confirmationMeta } from '../../../helpers/meetingNotices';

// #1423 — a agenda do cliente. Em cima, o que já está marcado: a próxima
// reunião (RS-01) e os retornos (slot, TelaRetornos). Embaixo, "Marcar algo
// novo" com as escolhas sempre à vista, uma por cartão:
//   Lembrete — só para a equipe, aparece no calendário, o cliente não recebe
//   nada (reminder_only); Mensagem no dia (auto_send_message); Reunião;
//   Link para o cliente escolher. Sem página de agendamento, a tela avisa
//   antes de abrir qualquer janela e oferece criar a página ou só um lembrete.
const props = defineProps({
  card: { type: Object, required: true },
  reuniao: { type: Object, default: null },
  accountId: { type: [String, Number], required: true },
  formato: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
  reunioes: { type: Boolean, default: false },
  linkAgenda: { type: Boolean, default: false },
  temConversa: { type: Boolean, default: false },
  // 'pagina' | 'externa' | 'falta' | 'carregando' (useJeitoDeMarcar).
  jeito: { type: String, default: 'carregando' },
  podeCriarPagina: { type: Boolean, default: false },
});
const emit = defineEmits([
  'novo',
  'reuniao',
  'criarPagina',
  'mudou',
  'semLink',
  'link',
]);

const { t } = useI18n();
const A = 'CRM_CARD.AGENDA';
const local = computed(() =>
  props.reuniao ? resolveMeetingLocation(props.reuniao) : null
);
const resposta = computed(() =>
  props.reuniao?.booking
    ? confirmationMeta(props.reuniao.confirmation_status)
    : null
);
// O selo do último link (enviado, aberto, marcado…) e o servidor desligando o
// link depois de aberto: o cartão some e a gaveta guarda isso enquanto o card
// estiver aberto.
const ultimoLink = useBookingInvite({
  conversation: computed(() => null),
  card: toRef(props, 'card'),
  withStatus: computed(() => props.linkAgenda && props.jeito === 'pagina'),
});
const seloLink = ultimoLink.badgeState;
const linkFora = ultimoLink.isDisabledOnServer;
watch(linkFora, fora => fora && emit('semLink'));
const comReuniao = computed(
  () => props.reunioes && ['pagina', 'externa'].includes(props.jeito)
);
const comLink = computed(
  () => props.linkAgenda && props.jeito === 'pagina' && !linkFora.value
);
const faltaPagina = computed(() => props.reunioes && props.jeito === 'falta');
</script>

<template>
  <section class="flex flex-col gap-5" data-tela="agenda">
    <article
      v-if="reuniao"
      data-agenda-reuniao
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <div class="flex items-start gap-4">
        <span
          class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
        >
          <span class="i-lucide-calendar-clock size-6" />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <h3 class="mb-0 text-sm font-medium text-n-slate-11">
            {{ t(`${A}.MARCADA`) }}
          </h3>
          <p class="mb-0 text-lg font-semibold text-n-slate-12">
            {{ formato.quando(reuniao.starts_at) }}
          </p>
          <p v-if="reuniao.title" class="mb-0 text-sm text-n-slate-12">
            {{ reuniao.title }}
          </p>
          <span
            v-if="resposta"
            class="inline-flex w-fit items-center gap-1 rounded-lg px-2 py-0.5 text-sm font-medium"
            :class="resposta.className"
          >
            <span class="size-3.5" :class="resposta.icon" aria-hidden="true" />
            {{ t(`CRM_KANBAN.CALENDAR.MEETING_DETAIL.CLIENT.${resposta.key}`) }}
          </span>
          <p
            v-if="local?.isInternal"
            class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
          >
            <span class="size-4" :class="local.icon" aria-hidden="true" />
            {{ [t(local.labelKey), t(`${A}.SO_EQUIPE`)].join(' · ') }}
          </p>
        </div>
      </div>
      <div class="sm:max-w-sm sm:ps-16" data-agenda-dia>
        <CrmMeetingDayActions
          :meeting="reuniao"
          :account-id="accountId"
          @changed="$emit('mudou')"
        />
      </div>
    </article>

    <slot name="retornos" />

    <section v-if="podeGerenciar" class="flex flex-col gap-3" data-agenda-novo>
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${A}.NOVO`) }}
      </h3>
      <div class="grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          data-agenda-opcao="lembrete"
          class="flex min-h-11 flex-col items-start gap-1 rounded-2xl bg-n-solid-1 p-4 text-start shadow-sm ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="$emit('novo', 'reminder_only')"
        >
          <span class="flex items-center gap-2">
            <span
              class="grid size-9 place-items-center rounded-xl bg-n-amber-3 text-n-amber-11"
              aria-hidden="true"
            >
              <span class="i-lucide-bell-ring size-5" />
            </span>
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${A}.LEMBRETE`) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t(`${A}.LEMBRETE_TEXTO`) }}
          </span>
          <span class="text-sm italic text-n-slate-11">
            {{ t(`${A}.LEMBRETE_EXEMPLO`) }}
          </span>
        </button>
        <button
          type="button"
          data-agenda-opcao="mensagem"
          :disabled="!temConversa"
          class="flex min-h-11 flex-col items-start gap-1 rounded-2xl bg-n-solid-1 p-4 text-start shadow-sm ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed disabled:opacity-60"
          @click="$emit('novo', 'auto_send_message')"
        >
          <span class="flex items-center gap-2">
            <span
              class="grid size-9 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span class="i-lucide-send size-5" />
            </span>
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${A}.MENSAGEM`) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              temConversa
                ? t(`${A}.MENSAGEM_TEXTO`)
                : t('CRM_CARD.RETORNO.PRECISA_CONVERSA')
            }}
          </span>
        </button>
        <button
          v-if="comReuniao"
          type="button"
          data-agenda-eu
          class="flex min-h-11 flex-col items-start gap-1 rounded-2xl bg-n-solid-1 p-4 text-start shadow-sm ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="$emit('reuniao')"
        >
          <span class="flex items-center gap-2">
            <span
              class="grid size-9 place-items-center rounded-xl bg-n-teal-3 text-n-teal-11"
              aria-hidden="true"
            >
              <span class="i-lucide-calendar-plus size-5" />
            </span>
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(reuniao ? `${A}.OUTRA_REUNIAO` : `${A}.REUNIAO`) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{
              t(
                jeito === 'externa'
                  ? `${A}.REUNIAO_EXTERNA`
                  : `${A}.REUNIAO_TEXTO`
              )
            }}
          </span>
        </button>
        <button
          v-if="comLink"
          type="button"
          data-agenda-opcao="link"
          class="flex min-h-11 flex-col items-start gap-1 rounded-2xl bg-n-solid-1 p-4 text-start shadow-sm ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="$emit('link')"
        >
          <span class="flex flex-wrap items-center gap-2">
            <span
              class="grid size-9 place-items-center rounded-xl bg-n-iris-3 text-n-iris-11"
              aria-hidden="true"
            >
              <span class="i-lucide-link size-5" />
            </span>
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${A}.CLIENTE_ESCOLHE`) }}
            </span>
            <span
              v-if="seloLink"
              data-agenda-link-selo
              class="rounded-full px-2 py-0.5 text-xs font-medium"
              :class="stateToneClass(seloLink)"
            >
              {{ t(stateLabelKey(seloLink)) }}
            </span>
          </span>
          <span class="text-sm text-n-slate-11">
            {{ t(`${A}.CLIENTE_ESCOLHE_TEXTO`) }}
          </span>
        </button>
        <p
          v-if="reunioes && jeito === 'carregando'"
          role="status"
          class="mb-0 flex items-center gap-2 p-4 text-sm text-n-slate-11"
        >
          <span
            class="i-lucide-loader-2 size-4 animate-spin"
            aria-hidden="true"
          />
          {{ t('CRM_CARD.CARREGANDO') }}
        </p>
      </div>

      <article
        v-if="faltaPagina"
        data-agenda-falta-pagina
        class="flex flex-col gap-3 rounded-2xl border border-dashed border-n-amber-7 bg-n-amber-2 p-5"
      >
        <span class="flex items-start gap-3">
          <span
            class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-amber-3 text-n-amber-11"
            aria-hidden="true"
          >
            <span class="i-lucide-calendar-x size-5" />
          </span>
          <span class="flex min-w-0 flex-col gap-1">
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${A}.FALTA_TITULO`) }}
            </span>
            <span class="text-sm text-n-slate-12">
              {{
                t(
                  podeCriarPagina
                    ? `${A}.FALTA_TEXTO`
                    : `${A}.FALTA_TEXTO_SEM_ACESSO`
                )
              }}
            </span>
          </span>
        </span>
        <span class="flex flex-wrap gap-2 sm:ps-12">
          <Button
            v-if="podeCriarPagina"
            data-agenda-criar-pagina
            :label="t(`${A}.CRIAR_PAGINA`)"
            icon="i-lucide-calendar-plus"
            slate
            faded
            class="!min-h-11"
            @click="$emit('criarPagina')"
          />
          <Button
            data-agenda-so-lembrete
            :label="t(`${A}.SO_LEMBRETE`)"
            icon="i-lucide-bell-ring"
            slate
            ghost
            class="!min-h-11"
            @click="$emit('novo', 'reminder_only')"
          />
        </span>
      </article>
    </section>
  </section>
</template>
