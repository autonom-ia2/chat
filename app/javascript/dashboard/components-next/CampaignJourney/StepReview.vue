<script setup>
import {
  DOT,
  MINUS,
} from 'dashboard/components-next/CampaignJourney/textMarks';
// Passo 3 — Revisar e agendar (#993, PRD §6.4, D3, D8, B8). Blocks with "Alterar" (built by
// the page for each channel), the CRM line, when (now, or date and time in the account time
// zone), the exact "vão receber" from POST campaign_journey/recipient_previews with the
// reasons of who is left out (each person once), "Enviar teste para mim" for e-mail and a
// final confirmation with the number. No batches: everyone at the chosen time.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { formatInZone, isFutureSchedule, scheduleToUtc } from './scheduleTime';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { toLocaleTag, formatNumber } from './localeTag';
import MedirVendas from './MedirVendas.vue';
import MelhorHorarioDaCampanha from './melhorHorario/MelhorHorarioDaCampanha.vue';
import ReenvioDaCampanha from './reenvio/ReenvioDaCampanha.vue';
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import {
  MENSAGEM,
  faltaNoReenvio,
  mensagemDoCanal,
  reenvioDoCanal,
} from './reenvio/reenvio';
import { JANELA_HORAS } from './melhorHorario/melhorHorario';

const props = defineProps({
  draft: { type: Object, required: true },
  // [{ key, step, title, main, detail }]
  blocks: { type: Array, required: true },
  channelLabel: { type: String, required: true },
  onChannelLabel: { type: String, required: true },
  crmTag: { type: String, required: true },
  // Audience count on the channel while the server preview is not there.
  reach: { type: Number, default: 0 },
  // { total, receive, reasons: { opted_out: 2, ... } } from recipient_previews, or null.
  preview: { type: Object, default: null },
  // E-mail readiness checks [{ key, ok }] (send_readiness of the e-mail engine).
  checks: { type: Array, default: () => [] },
  showTestSend: { type: Boolean, default: false },
  isTestSending: { type: Boolean, default: false },
  timeZone: { type: String, required: true },
  isSubmitting: { type: Boolean, default: false },
  errorMessage: { type: String, default: '' },
  // Fork (Modelos do WhatsApp): motivo para "Enviar agora" ficar desativado (modelo ainda
  // em análise). Vazio, as duas opções valem.
  nowBlockedReason: { type: String, default: '' },
  // #1898: quem monta sem a chave de disparar deixa a campanha pronta, sem enviar.
  soDeixaPronta: { type: Boolean, default: false },
  // #1898: quem dispara abriu uma campanha que outra pessoa deixou pronta.
  montadaPor: { type: String, default: '' },
  // #3101: "Mandar de novo" para quem não respondeu. { canal, modelos, colunas, gruposDeCampos, maximoDoTexto }
  // (ReenvioDaCampanha); null = a
  // linha não aparece (o canal não tem reenvio, ou a página ainda não o oferece).
  reenvio: { type: Object, default: null },
  // #3101: "No melhor horário de cada cliente" em "Quando começa". { conhecidos, horarioPermitido }
  // (MelhorHorarioDaCampanha); null = a opção não aparece.
  melhorHorario: { type: Object, default: null },
});

const emit = defineEmits(['update', 'go', 'back', 'submit', 'testSend']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const confirmRef = ref(null);

const REASON_ORDER = [
  'channel_disabled',
  'opted_out',
  'blocked',
  'unsubscribed',
  'bounced',
  'suppressed',
  'missing_variables',
];

const isLater = computed(() => props.draft.when === 'later');
const total = computed(() => props.preview?.total ?? props.reach);
// #3098: o público que alcança, antes do grupo de controle. O sorteio tira a porcentagem escolhida (para baixo, como o
// servidor faz em CampaignJourney::GrupoDeControle); "Vão receber" e a confirmação já mostram sem eles.
const publico = computed(() => props.preview?.receive ?? props.reach);
const semReceber = computed(() =>
  Math.floor((publico.value * (props.draft.grupoDeControle || 0)) / 100)
);
const receivers = computed(() => publico.value - semReceber.value);
const medir = ({ janela, controle }) =>
  emit(
    'update',
    janela === undefined
      ? { grupoDeControle: controle }
      : { janelaDeCompra: janela }
  );
const reasons = computed(() =>
  REASON_ORDER.map(key => ({
    key,
    count: Number(props.preview?.reasons?.[key]) || 0,
  })).filter(reason => reason.count > 0)
);
const isScheduleValid = computed(
  () =>
    !isLater.value || isFutureSchedule(props.draft.scheduledAt, props.timeZone)
);
// The past-date error only after the person typed a date (#1387): empty is not wrong yet.
const showPastError = computed(
  () => Boolean(props.draft.scheduledAt) && !isScheduleValid.value
);
const scheduleMessage = computed(() => {
  if (showPastError.value) return t(`${NS}.PAST`);
  return props.draft.scheduledAt ? '' : t(`${NS}.PICK_DATE`);
});
// O fuso da conta como Configurações o mostra (regra do Rodrigo, #1456).
const zoneLabel = computed(() => rotuloDoFuso(props.timeZone));
const whenText = computed(() => {
  if (!isLater.value || !isScheduleValid.value) return '';
  return formatInZone(
    scheduleToUtc(props.draft.scheduledAt, props.timeZone),
    props.timeZone,
    toLocaleTag(locale.value)
  );
});
const actionLabel = computed(() => {
  if (props.soDeixaPronta) return t(`${NS}.PRONTA.DEIXAR`);
  return isLater.value ? t(`${NS}.SCHEDULE`) : t(`${NS}.SEND_NOW`);
});
const confirmTitle = computed(() =>
  t(
    isLater.value ? `${NS}.CONFIRM_LATER` : `${NS}.CONFIRM_NOW`,
    { count: n(receivers.value) },
    receivers.value
  )
);
const NS_MELHOR = 'REENVIO_HORARIO.MELHOR_HORARIO';
const comMelhorHorario = computed(
  () => Boolean(props.melhorHorario) && Boolean(props.draft.melhorHorario)
);
const NS_REENVIO = 'REENVIO_HORARIO.REENVIO';
// #3101: o reenvio como vale no canal ("não leu" vira "não respondeu" onde a leitura não é avisada); null sem ele.
const reenvioLigado = computed(() =>
  props.reenvio && props.draft.reenvio
    ? reenvioDoCanal(props.draft.reenvio, props.reenvio.canal)
    : null
);
const textoDoInicio = () => {
  if (comMelhorHorario.value)
    return isLater.value
      ? t(`${NS_MELHOR}.CONFIRM_LATER_TEXT`, {
          when: whenText.value,
          horas: JANELA_HORAS,
        })
      : t(`${NS_MELHOR}.CONFIRM_NOW_TEXT`, { horas: JANELA_HORAS });
  return isLater.value
    ? t(`${NS}.CONFIRM_LATER_TEXT`, { when: whenText.value })
    : t(`${NS}.CONFIRM_NOW_TEXT`);
};
// A última chance de ver que, dias depois, sai uma segunda leva sozinha: de quando contam os dias, para quantos no
// máximo (quem recebe a primeira) e, no WhatsApp Oficial, que cada uma é um modelo pago.
const textoDoReenvio = () => {
  const { dias, quem } = reenvioLigado.value;
  return t(
    `${NS_REENVIO}.CONFIRM`,
    {
      dias,
      quem: t(`${NS_REENVIO}.QUEM_RESUMO.${quem.toUpperCase()}`),
      total: n(receivers.value),
    },
    dias
  );
};
// Uma ideia por linha na confirmação.
const linhasDaConfirmacao = computed(() => {
  if (!reenvioLigado.value) return [textoDoInicio()];
  const pago =
    props.reenvio.canal === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
      ? [t(`${NS_REENVIO}.CONFIRM_PAGO`)]
      : [];
  return [textoDoInicio(), textoDoReenvio(), ...pago];
});
// #3101: com o reenvio ligado, a segunda mensagem precisa estar escrita antes de a campanha sair.
const modeloDoReenvio = computed(() =>
  (props.reenvio?.modelos || []).find(
    modelo => modelo.value === props.draft.reenvio?.modeloId
  )
);
// O modelo escolhido que sumiu da caixa (apagado ou desligado depois de escolhido) volta a faltar: sem ele, a segunda
// mensagem não teria o que mandar.
const modeloSumiu = computed(
  () =>
    mensagemDoCanal(props.reenvio?.canal) === MENSAGEM.MODELO &&
    Boolean(props.draft.reenvio?.modeloId) &&
    !modeloDoReenvio.value
);
const faltaReenvio = computed(() => {
  if (!props.reenvio) return null;
  if (modeloSumiu.value) return 'SEM_MODELO';
  return faltaNoReenvio(
    props.draft.reenvio,
    props.reenvio.canal,
    modeloDoReenvio.value
  );
});
const isBlocked = computed(
  () => props.checks.some(check => !check.ok) || Boolean(faltaReenvio.value)
);

const openConfirmation = () => {
  if (!isScheduleValid.value || isBlocked.value) return;
  // Deixar pronta não envia nada: sem a confirmação de quantas pessoas vão receber.
  if (props.soDeixaPronta) {
    emit('submit');
    return;
  }
  confirmRef.value?.open();
};

const submit = () => {
  confirmRef.value?.close();
  emit('submit');
};
</script>

<template>
  <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start">
    <section
      class="flex min-w-0 flex-col rounded-2xl border border-n-weak bg-n-solid-1 px-4 shadow-sm sm:px-5"
      data-test="review"
    >
      <div
        v-for="block in blocks"
        :key="block.key"
        class="flex items-start justify-between gap-3 border-b border-n-weak py-4"
        :data-review-block="block.key"
      >
        <div class="min-w-0">
          <p class="m-0 text-xs font-semibold uppercase text-n-slate-11">
            {{ block.title }}
          </p>
          <p class="m-0 break-words text-sm font-semibold text-n-slate-12">
            {{ block.main }}
          </p>
          <p class="m-0 break-words text-xs text-n-slate-11">
            {{ block.detail }}
          </p>
        </div>
        <Button
          :label="t(`${NS}.CHANGE`)"
          :aria-label="t(`${NS}.CHANGE_ARIA`, { block: block.title })"
          variant="ghost"
          size="sm"
          class="!min-h-11 shrink-0"
          @click="emit('go', block.step)"
        />
      </div>
      <slot name="modelo" />
      <p
        class="m-0 flex flex-wrap items-center gap-2 border-b border-n-weak py-4 text-sm text-n-slate-12"
        data-test="review-crm"
      >
        <span
          class="rounded-full bg-n-blue-3 px-2 py-0.5 text-xs font-semibold text-n-blue-11"
        >
          {{ t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.CRM_BADGE') }}
        </span>
        {{ t(`${NS}.CRM`, { tag: crmTag }) }}
      </p>
      <!-- The padding lives on a wrapper: a legend sits on the fieldset's top edge and
           ignores its padding, so "Quando começa" stuck to the line above (#1387). -->
      <div class="py-4">
        <!-- min-w-0: sem ele o fieldset cresce até a palavra mais longa e estoura a tela no celular. -->
        <fieldset class="m-0 flex min-w-0 flex-col gap-3 border-0 p-0">
          <legend class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
            {{ t(`${NS}.WHEN`) }}
          </legend>
          <div class="flex flex-wrap gap-2" role="radiogroup">
            <button
              v-for="option in ['now', 'later']"
              :key="option"
              type="button"
              role="radio"
              :aria-checked="draft.when === option"
              :data-when="option"
              :disabled="option === 'now' && Boolean(nowBlockedReason)"
              class="min-h-11 rounded-xl border border-solid px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50"
              :class="
                draft.when === option
                  ? 'border-n-blue-8 bg-n-blue-2 text-n-blue-11'
                  : 'border-n-slate-6 text-n-slate-12 hover:bg-n-alpha-1'
              "
              @click="emit('update', { when: option })"
            >
              {{ option === 'now' ? t(`${NS}.NOW`) : t(`${NS}.LATER`) }}
            </button>
          </div>
          <p
            v-if="nowBlockedReason"
            class="m-0 text-xs text-n-slate-11"
            data-test="now-blocked"
          >
            {{ nowBlockedReason }}
          </p>
          <Input
            v-if="isLater"
            :model-value="draft.scheduledAt"
            type="datetime-local"
            :label="t(`${NS}.DATE_LABEL`, { zone: zoneLabel })"
            :message="scheduleMessage"
            :message-type="showPastError ? 'error' : 'info'"
            custom-input-class="!h-11"
            data-test="schedule-at"
            @update:model-value="scheduledAt => emit('update', { scheduledAt })"
          />
          <MelhorHorarioDaCampanha
            v-if="melhorHorario"
            :model-value="Boolean(draft.melhorHorario)"
            :conhecidos="melhorHorario.conhecidos"
            :total="receivers"
            :horario-permitido="melhorHorario.horarioPermitido"
            :quando="draft.when"
            @update:model-value="
              ligado => emit('update', { melhorHorario: ligado })
            "
          />
        </fieldset>
      </div>
      <ReenvioDaCampanha
        v-if="reenvio"
        :model-value="reenvioDoCanal(draft.reenvio || null, reenvio.canal)"
        :canal="reenvio.canal"
        :modelos="reenvio.modelos"
        :colunas="reenvio.colunas"
        :grupos-de-campos="reenvio.gruposDeCampos"
        :maximo-do-texto="reenvio.maximoDoTexto"
        @update:model-value="valor => emit('update', { reenvio: valor })"
      />
      <MedirVendas
        :janela="draft.janelaDeCompra || 7"
        :controle="draft.grupoDeControle || 0"
        :publico="publico"
        @update="medir"
      />
    </section>

    <aside
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm lg:sticky lg:top-4"
      data-test="review-aside"
    >
      <div class="rounded-xl bg-[#0D2344] p-4 text-white">
        <p class="m-0 text-xs font-semibold uppercase opacity-80">
          {{ t(`${NS}.RECEIVE`) }}
        </p>
        <p
          class="m-0 text-4xl font-semibold tabular-nums"
          data-test="receivers"
        >
          {{ n(receivers) }}
        </p>
        <p class="m-0 text-sm opacity-80" data-test="receive-when">
          {{ channelLabel }}
          <template v-if="!isLater || whenText">
            {{ DOT }}
            <!-- #3099: com duas versões, quantos recebem quando ("270 agora, 1.080 depois de 4 horas"), da Nova campanha. -->
            <slot name="vao-receber" :quando="isLater ? whenText : ''">
              {{ isLater ? whenText : t(`${NS}.NOW`) }}
            </slot>
          </template>
        </p>
        <p
          v-if="comMelhorHorario"
          class="m-0 mt-1 flex items-center gap-1 text-xs opacity-80"
          data-test="review-melhor-horario"
        >
          <span class="i-lucide-clock-4 size-3.5" aria-hidden="true" />
          {{ t(`${NS_MELHOR}.NO_RESUMO`, { horas: JANELA_HORAS }) }}
        </p>
        <p
          v-if="draft.reenvio && reenvio"
          class="m-0 mt-1 flex items-center gap-1 text-xs opacity-80"
          data-test="review-reenvio"
        >
          <span class="i-lucide-repeat size-3.5" aria-hidden="true" />
          {{
            t(
              `${NS_REENVIO}.NO_RESUMO`,
              { dias: draft.reenvio.dias },
              draft.reenvio.dias
            )
          }}
        </p>
      </div>
      <dl class="m-0 flex flex-col gap-1 text-sm" data-test="review-counts">
        <div class="flex justify-between gap-3">
          <dt class="text-n-slate-11">{{ onChannelLabel }}</dt>
          <dd class="m-0 font-semibold tabular-nums">{{ n(total) }}</dd>
        </div>
        <div
          v-for="reason in reasons"
          :key="reason.key"
          class="flex justify-between gap-3"
          :data-reason="reason.key"
        >
          <dt class="text-n-slate-11">
            {{ t(`${NS}.REASONS.${reason.key.toUpperCase()}`) }}
          </dt>
          <dd class="m-0 tabular-nums">{{ MINUS }}{{ n(reason.count) }}</dd>
        </div>
        <div
          v-if="semReceber"
          class="flex justify-between gap-3"
          data-test="review-controle"
        >
          <dt class="text-n-slate-11">
            {{ t('CAMPANHA_VENDAS.MEDIR.FICAM_PARA_COMPARAR') }}
          </dt>
          <dd class="m-0 font-semibold tabular-nums">
            {{ MINUS }}{{ n(semReceber) }}
          </dd>
        </div>
      </dl>
      <ul
        v-if="checks.length"
        class="m-0 flex list-none flex-col gap-1 p-0 text-xs"
        data-test="review-checks"
      >
        <li
          v-for="check in checks"
          :key="check.key"
          class="flex items-center gap-2"
          :class="check.ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          <span
            :class="check.ok ? 'i-lucide-check' : 'i-lucide-x'"
            class="size-3.5 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${NS}.CHECKS.${check.key.toUpperCase()}`) }}
        </li>
      </ul>
      <Button
        v-if="showTestSend"
        :label="t(`${NS}.TEST_SEND`)"
        :is-loading="isTestSending"
        variant="outline"
        color="slate"
        class="!min-h-11 w-full justify-center !rounded-xl"
        data-test="test-send"
        @click="emit('testSend')"
      />
      <p
        v-if="faltaReenvio"
        class="m-0 text-sm text-n-ruby-11"
        data-test="review-falta-reenvio"
      >
        {{ t(`${NS_REENVIO}.FALTA.${faltaReenvio}`) }}
      </p>
      <p v-if="errorMessage" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <p
        v-if="soDeixaPronta || montadaPor"
        class="m-0 flex items-start gap-2 rounded-xl bg-n-alpha-1 p-3 text-sm text-n-slate-12"
        data-test="aviso-pronta"
      >
        <span
          class="i-lucide-send size-4 mt-0.5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{
          soDeixaPronta
            ? t(`${NS}.PRONTA.QUEM_MONTA`)
            : t(`${NS}.PRONTA.QUEM_DISPARA`, { nome: montadaPor })
        }}
      </p>
      <Button
        :label="actionLabel"
        :disabled="!isScheduleValid || !receivers || isBlocked || isSubmitting"
        :is-loading="isSubmitting"
        class="!min-h-11 w-full justify-center !rounded-xl"
        data-test="open-confirmation"
        @click="openConfirmation"
      />
      <p v-if="!soDeixaPronta" class="m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.EDIT_NOTE`) }}
      </p>
      <Button
        :label="t('CAMPAIGN_JOURNEY.NEW_CAMPAIGN.BACK')"
        variant="outline"
        color="slate"
        class="!min-h-11 w-full justify-center !rounded-xl"
        @click="emit('back')"
      />
    </aside>

    <Dialog
      ref="confirmRef"
      :title="confirmTitle"
      :confirm-button-label="actionLabel"
      :cancel-button-label="t(`${NS}.CONFIRM_BACK`)"
      @confirm="submit"
    >
      <template #description>
        <div class="flex flex-col gap-2" data-test="confirm-text">
          <p
            v-for="linha in linhasDaConfirmacao"
            :key="linha"
            class="mb-0 text-sm text-n-slate-11"
          >
            {{ linha }}
          </p>
        </div>
      </template>
    </Dialog>
  </div>
</template>
