<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmFollowUpSeriesAPI from 'dashboard/api/crmFollowUpSeries';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { diaDaParede, diaLongo, frase, horaDe, paredeDe } from './recorrencia';
import { repetirDaApi } from './paraApi';

// #1460 — a "visão de recorrência" de um lembrete que repete: como repete, as
// próximas datas, quem recebe e o que já passou. Concluir uma vez não apaga a
// série. Pausar não apaga datas: elas ficam marcadas "Pausado" e ninguém é
// avisado até retomar. Encerrar para de repetir e guarda o histórico. Mudar
// pergunta "só a próxima" ou "esta e todas as próximas".
const props = defineProps({
  serieId: { type: [Number, String], required: true },
  formato: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: true },
});
const emit = defineEmits(['mudar', 'mudou', 'carregou']);

const { t, locale } = useI18n();
const S = 'CRM_LEMBRETE.SERIE';
const idioma = computed(() => locale.value.replace('_', '-'));

const serie = ref(null);
const carregando = ref(false);
const salvando = ref(false);
const erro = ref(false);
const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    serie.value = await CrmFollowUpSeriesAPI.buscar(props.serieId);
    emit('carregou', serie.value);
  } catch {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};
onMounted(carregar);
watch(() => props.serieId, carregar);

const parede = iso => paredeDe(iso, serie.value.timezone);
const inicio = computed(() =>
  serie.value ? parede(serie.value.starts_at) : ''
);
const fraseDaSerie = computed(() =>
  serie.value
    ? frase({
        t,
        idioma: idioma.value,
        juntar: props.formato.juntar,
        inicio: inicio.value,
        repetir: repetirDaApi(serie.value),
      })
    : ''
);
const proximas = computed(() =>
  (serie.value?.next_occurrences || []).map(iso => {
    const texto = parede(iso);
    return {
      chave: iso,
      dia: diaLongo(diaDaParede(texto), idioma.value),
      hora: horaDe(texto),
    };
  })
);
const situacao = computed(() => serie.value?.status || 'active');
const pausada = computed(() => situacao.value === 'paused');
const encerrada = computed(() => situacao.value === 'ended');
const SITUACAO = {
  active: { chave: 'ATIVA', tom: 'bg-n-teal-3 text-n-teal-11' },
  paused: { chave: 'PAUSADA', tom: 'bg-n-amber-3 text-n-amber-11' },
  ended: { chave: 'ENCERRADA', tom: 'bg-n-slate-4 text-n-slate-11' },
};
const pausadaEm = computed(() =>
  serie.value?.paused_at
    ? diaLongo(diaDaParede(parede(serie.value.paused_at)), idioma.value)
    : ''
);
const fuso = computed(() => rotuloDoFuso(serie.value?.timezone));

const ligadoA = computed(() => {
  if (serie.value?.card)
    return t(`${S}.LIGADO_CARD`, { nome: serie.value.card.title });
  if (serie.value?.company)
    return t(`${S}.LIGADO_EMPRESA`, { nome: serie.value.company.name });
  if (serie.value?.contact)
    return t(`${S}.LIGADO_CONTATO`, { nome: serie.value.contact.name });
  return t(`${S}.LIGADO_NADA`);
});
const quemTexto = computed(() => {
  const nomes = props.formato.juntar(serie.value?.recipient_names || []);
  return serie.value?.recipient_mode === 'card_owner'
    ? t(`${S}.QUEM_DONO`, { nomes })
    : nomes;
});
const HISTORICO = {
  done: 'FEITA',
  overdue: 'AVISADA',
  canceled: 'NAO_AVISADA',
};
const passadas = computed(() =>
  (serie.value?.history || []).map(item => ({
    chave: item.id,
    dia: diaLongo(diaDaParede(parede(item.occurrence_at)), idioma.value),
    situacao: t(`${S}.HISTORICO.${HISTORICO[item.status] || 'AVISADA'}`),
  }))
);

// Cada ação chama a API, recarrega a série e avisa quem abriu (card,
// calendário) para recarregar também.
const agir = async (acao, aviso) => {
  salvando.value = true;
  try {
    await acao();
    useAlert(aviso);
    await carregar();
    emit('mudou');
  } catch {
    useAlert(t(`${S}.ERRO`));
  } finally {
    salvando.value = false;
  }
};
const dialogoEncerrar = ref(null);
const dialogoMudar = ref(null);
const feitoEste = () => {
  const dia = proximas.value[0]?.dia || '';
  agir(
    () => CrmKanbanAPI.completeFollowUp(serie.value.pending_follow_up_id),
    t(`${S}.FEITO_OK`, { dia })
  );
};
const pausar = () =>
  agir(() => CrmFollowUpSeriesAPI.pausar(serie.value.id), t(`${S}.PAUSADA_OK`));
const retomar = () =>
  agir(
    () => CrmFollowUpSeriesAPI.retomar(serie.value.id),
    t(`${S}.RETOMADA_OK`)
  );
const encerrar = () => {
  dialogoEncerrar.value?.close();
  agir(
    () => CrmFollowUpSeriesAPI.encerrar(serie.value.id),
    t(`${S}.ENCERRADA_OK`)
  );
};
const mudar = qual => {
  dialogoMudar.value?.close();
  emit('mudar', { qual, serie: serie.value });
};

defineExpose({
  abrirMudar: () => dialogoMudar.value?.open(),
  encerrada,
});
</script>

<template>
  <p
    v-if="carregando && !serie"
    role="status"
    class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
  >
    <span class="i-lucide-loader-2 size-4 animate-spin" aria-hidden="true" />
    {{ t('CRM_CARD.CARREGANDO') }}
  </p>
  <div
    v-else-if="erro"
    role="alert"
    class="flex flex-col items-start gap-3 rounded-2xl border border-n-ruby-7 bg-n-ruby-2 p-4 text-n-ruby-11"
  >
    {{ t(`${S}.ERRO_CARREGAR`) }}
    <Button
      :label="t(`${S}.TENTAR_DE_NOVO`)"
      slate
      outline
      class="!min-h-11"
      @click="carregar"
    />
  </div>
  <section v-else-if="serie" class="flex flex-col gap-5" data-lembrete-serie>
    <Dialog
      ref="dialogoEncerrar"
      type="alert"
      :title="t(`${S}.ENCERRAR_TITULO`)"
      :description="t(`${S}.ENCERRAR_TEXTO`)"
      :confirm-button-label="t(`${S}.ENCERRAR_CONFIRMA`)"
      :cancel-button-label="t(`${S}.CONTINUAR`)"
      @confirm="encerrar"
    />
    <Dialog
      ref="dialogoMudar"
      :title="t(`${S}.MUDAR_TITULO`)"
      :description="t(`${S}.MUDAR_TEXTO`)"
      :show-confirm-button="false"
      :cancel-button-label="t('CRM_CARD.CANCELAR')"
    >
      <div class="flex flex-col gap-2" data-serie-mudar>
        <button
          type="button"
          data-mudar="esta"
          class="flex min-h-11 items-start gap-3 rounded-2xl bg-n-solid-1 p-4 text-start ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="mudar('esta')"
        >
          <span
            class="i-lucide-calendar-check mt-0.5 size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span class="flex flex-col gap-1">
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${S}.SO_ESTA`, { dia: proximas[0]?.dia || '' }) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t(`${S}.SO_ESTA_TEXTO`) }}
            </span>
          </span>
        </button>
        <button
          type="button"
          data-mudar="proximas"
          class="flex min-h-11 items-start gap-3 rounded-2xl bg-n-solid-1 p-4 text-start ring-1 ring-inset ring-n-weak transition hover:ring-n-slate-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="mudar('proximas')"
        >
          <span
            class="i-lucide-repeat mt-0.5 size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span class="flex flex-col gap-1">
            <span class="text-[0.9375rem] font-semibold text-n-slate-12">
              {{ t(`${S}.ESTA_E_PROXIMAS`) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ t(`${S}.ESTA_E_PROXIMAS_TEXTO`) }}
            </span>
          </span>
        </button>
      </div>
    </Dialog>

    <article
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    >
      <div class="flex items-start gap-4">
        <span
          class="grid size-12 shrink-0 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-repeat size-6" />
        </span>
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <span
            class="w-fit rounded-lg px-2 py-0.5 text-sm font-medium"
            :class="SITUACAO[situacao].tom"
            data-serie-situacao
          >
            {{ t(`${S}.SITUACAO.${SITUACAO[situacao].chave}`) }}
          </span>
          <p class="mb-0 text-lg font-semibold text-n-slate-12">
            {{ fraseDaSerie }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ ligadoA }} ·
            {{ t(`${S}.FUSO`, { fuso }) }}
          </p>
          <p v-if="serie.description" class="mb-0 text-sm text-n-slate-12">
            {{ serie.description }}
          </p>
        </div>
      </div>
      <div
        v-if="pausada"
        role="status"
        class="flex flex-wrap items-center gap-3 rounded-xl border border-n-amber-7 bg-n-amber-2 p-3 text-[0.9375rem] text-n-amber-11"
      >
        <span class="i-lucide-pause size-4 shrink-0" aria-hidden="true" />
        <span class="min-w-0 flex-1">
          {{ t(`${S}.PAUSADA_DESDE`, { dia: pausadaEm }) }}
        </span>
      </div>
      <div
        v-if="!encerrada && podeGerenciar"
        class="flex flex-wrap gap-2 sm:ps-16"
      >
        <Button
          v-if="!pausada"
          data-serie-feito
          :disabled="salvando || !serie.pending_follow_up_id"
          :label="t(`${S}.FEITO_ESTE`)"
          icon="i-lucide-check"
          slate
          outline
          class="!min-h-11 !outline-n-weak"
          @click="feitoEste"
        />
        <Button
          v-if="pausada"
          data-serie-retomar
          :is-loading="salvando"
          :label="t(`${S}.RETOMAR`)"
          icon="i-lucide-play"
          class="!min-h-11"
          @click="retomar"
        />
        <Button
          v-else
          data-serie-pausar
          :disabled="salvando"
          :label="t(`${S}.PAUSAR`)"
          icon="i-lucide-pause"
          slate
          ghost
          class="!min-h-11"
          @click="pausar"
        />
        <Button
          data-serie-encerrar
          :disabled="salvando"
          :label="t(`${S}.ENCERRAR`)"
          icon="i-lucide-circle-stop"
          ruby
          ghost
          class="!min-h-11"
          @click="dialogoEncerrar?.open()"
        />
      </div>
    </article>

    <section v-if="!encerrada" class="flex flex-col gap-3">
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${S}.PROXIMAS`) }}
      </h3>
      <ol
        class="m-0 flex list-none flex-col divide-y divide-n-weak rounded-2xl border border-n-weak bg-n-solid-1 p-0"
        data-serie-proximas
      >
        <li
          v-for="(item, indice) in proximas"
          :key="item.chave"
          class="flex min-h-11 items-center justify-between gap-3 px-4 py-3"
          :class="pausada ? 'opacity-60' : ''"
        >
          <span class="flex items-center gap-3">
            <span
              class="i-lucide-bell size-4 shrink-0"
              :class="indice ? 'text-n-slate-10' : 'text-n-blue-11'"
              aria-hidden="true"
            />
            <span
              class="text-[0.9375rem] first-letter:uppercase"
              :class="
                indice ? 'text-n-slate-12' : 'font-semibold text-n-slate-12'
              "
            >
              {{ t(`${S}.DIA_HORA`, { dia: item.dia, hora: item.hora }) }}
            </span>
          </span>
          <span
            v-if="!indice && !pausada"
            class="shrink-0 whitespace-nowrap rounded-lg bg-n-blue-3 px-2 py-0.5 text-xs font-medium text-n-blue-11"
          >
            {{ t(`${S}.A_PROXIMA`) }}
          </span>
          <span
            v-else-if="pausada"
            class="shrink-0 whitespace-nowrap rounded-lg bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            {{ t(`${S}.NAO_AVISA`) }}
          </span>
        </li>
      </ol>
    </section>

    <section class="flex flex-col gap-3">
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t(`${S}.QUEM_RECEBE`) }}
      </h3>
      <p
        class="mb-0 flex items-start gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-[0.9375rem] text-n-slate-12"
        data-serie-quem
      >
        <span
          class="i-lucide-users mt-0.5 size-5 shrink-0 text-n-blue-11"
          aria-hidden="true"
        />
        {{ quemTexto }}
      </p>
    </section>

    <details
      v-if="passadas.length"
      class="group rounded-2xl border border-n-weak bg-n-solid-1"
    >
      <summary
        class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
      >
        {{ t(`${S}.PASSADAS`, { n: passadas.length }) }}
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
          aria-hidden="true"
        />
      </summary>
      <ul
        class="m-0 flex list-none flex-col divide-y divide-n-weak border-t border-n-weak p-0"
      >
        <li
          v-for="item in passadas"
          :key="item.chave"
          class="flex items-center justify-between gap-3 px-4 py-3 text-sm"
        >
          <span class="text-n-slate-12 first-letter:uppercase">{{
            item.dia
          }}</span>
          <span class="text-n-slate-11">
            {{ item.situacao }}
          </span>
        </li>
      </ul>
    </details>
  </section>
</template>
