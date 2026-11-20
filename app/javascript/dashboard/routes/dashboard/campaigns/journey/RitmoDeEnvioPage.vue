<script setup>
// "Limite de mensagens" (#3063, item 2): quantas mensagens cada cliente recebe e em que horário, por conta. Vale para as
// campanhas e para o que as automações mandam; fora do limite ou do horário a mensagem espera e sai depois. Quem vê
// campanhas lê; quem cuida delas muda (campaign_manage).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useOnEnter } from 'dashboard/components-next/CampaignJourney/useOnEnter';
import RitmoDeEnvioAPI from 'dashboard/api/ritmoDeEnvio';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  DIAS,
  DIAS_DA_SEMANA,
  FINS,
  INICIOS,
  MENSAGENS,
  SEM_LIMITE,
  alternarDia,
  diasDoResumo,
  formularioDe,
  pedidoDe,
  problemaDo,
} from 'dashboard/components-next/CampaignJourney/ritmo/ritmoDeEnvio';

const NS = 'CAMPAIGN_JOURNEY.RITMO';

const { t, locale } = useI18n();
const podeMudar = useCanManage('campaign_manage');

const formulario = ref(formularioDe());
const salvo = ref(JSON.stringify(pedidoDe(formulario.value)));
const carregando = ref(true);
const erroAoCarregar = ref(false);
const salvando = ref(false);

const opcoesDeMensagens = computed(() => [
  { value: SEM_LIMITE, label: t(`${NS}.LIMITE.SEM_LIMITE`) },
  ...MENSAGENS.map(value => ({
    value,
    label: t(`${NS}.LIMITE.MENSAGENS`, { n: value }, value),
  })),
]);
const opcoesDeDias = computed(() =>
  DIAS.map(value => ({
    value,
    label: t(`${NS}.LIMITE.DIAS`, { n: value }, value),
  }))
);
const opcoesDeQuando = computed(() => [
  { value: false, label: t(`${NS}.HORARIO.QUALQUER_HORA`) },
  { value: true, label: t(`${NS}.HORARIO.SO_EM_CERTOS`) },
]);
const hora = value => t(`${NS}.HORARIO.HORA`, { hora: value });
const opcoesDeInicio = computed(() =>
  INICIOS.map(value => ({ value, label: hora(value) }))
);
const opcoesDeFim = computed(() =>
  FINS.map(value => ({ value, label: hora(value) }))
);

const comLimite = computed(() => formulario.value.mensagens !== SEM_LIMITE);
const problema = computed(() => problemaDo(formulario.value));
const mudou = computed(
  () => JSON.stringify(pedidoDe(formulario.value)) !== salvo.value
);
const podeSalvar = computed(
  () => podeMudar.value && mudou.value && !problema.value && !salvando.value
);

const diasEmTexto = dias => {
  const { tipo, dias: lista } = diasDoResumo(dias);
  if (tipo !== 'LISTA') return t(`${NS}.HORARIO.DIAS_RESUMO.${tipo}`);
  const nomes = lista.map(dia => t(`${NS}.HORARIO.DIAS_LONGOS.${dia}`));
  return new Intl.ListFormat(locale.value.replace('_', '-'), {
    type: 'conjunction',
  }).format(nomes);
};

const textoDoHorario = () => {
  if (!formulario.value.comHorario) return t(`${NS}.RESUMO.QUALQUER_HORA`);
  if (problema.value) return t(`${NS}.RESUMO.FALTA_HORARIO`);
  return t(`${NS}.RESUMO.HORARIO`, {
    dias: diasEmTexto(formulario.value.diasDaSemana),
    inicio: hora(formulario.value.inicio),
    fim: hora(formulario.value.fim),
  });
};

const resumo = computed(() => {
  const partes = [];
  partes.push(
    comLimite.value
      ? t(`${NS}.RESUMO.LIMITE`, {
          mensagens: t(
            `${NS}.LIMITE.MENSAGENS`,
            { n: formulario.value.mensagens },
            formulario.value.mensagens
          ),
          dias: t(
            `${NS}.LIMITE.DIAS`,
            { n: formulario.value.dias },
            formulario.value.dias
          ),
        })
      : t(`${NS}.RESUMO.SEM_LIMITE`)
  );
  partes.push(textoDoHorario());
  return partes.join(' ');
});

const aplicar = payload => {
  formulario.value = formularioDe(payload);
  salvo.value = JSON.stringify(pedidoDe(formulario.value));
};

const carregar = async () => {
  carregando.value = true;
  erroAoCarregar.value = false;
  try {
    const { data } = await RitmoDeEnvioAPI.buscar();
    aplicar(data.payload);
  } catch {
    erroAoCarregar.value = true;
  } finally {
    carregando.value = false;
  }
};

const salvar = async () => {
  if (!podeSalvar.value) return;
  salvando.value = true;
  try {
    const { data } = await RitmoDeEnvioAPI.salvar(pedidoDe(formulario.value));
    aplicar(data.payload);
    useAlert(t(`${NS}.SALVO`));
  } catch {
    useAlert(t(`${NS}.ERRO_AO_SALVAR`));
  } finally {
    salvando.value = false;
  }
};

const marcarDia = dia => {
  formulario.value.diasDaSemana = alternarDia(
    formulario.value.diasDaSemana,
    dia
  );
};

useOnEnter(carregar);
</script>

<template>
  <section
    class="flex h-full w-full min-w-0 flex-col overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-3xl p-4 sm:p-5 lg:p-8">
      <nav
        class="mb-5 flex items-center gap-2 text-xs text-n-slate-11"
        :aria-label="t(`${NS}.BREADCRUMB`)"
      >
        {{ t('CAMPAIGN_JOURNEY.SIDEBAR.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ t('CAMPAIGN_JOURNEY.SIDEBAR.RITMO') }}
        </span>
      </nav>

      <header class="mb-6">
        <h1
          class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
        >
          {{ t(`${NS}.TITLE`) }}
        </h1>
        <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
          {{ t(`${NS}.SUBTITLE`) }}
        </p>
      </header>

      <div v-if="carregando" class="flex justify-center py-16">
        <Spinner />
      </div>

      <div
        v-else-if="erroAoCarregar"
        class="flex flex-col items-start gap-3 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 px-5 py-4"
        role="alert"
      >
        <p class="mb-0 text-sm text-n-slate-12">{{ t(`${NS}.ERRO`) }}</p>
        <Button
          :label="t(`${NS}.TENTAR_DE_NOVO`)"
          class="!min-h-11"
          @click="carregar"
        />
      </div>

      <form v-else class="flex flex-col gap-5" @submit.prevent="salvar">
        <p
          v-if="!podeMudar"
          class="mb-0 flex items-start gap-2 rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-3 text-sm text-n-slate-12"
          data-ritmo-leitura
        >
          <span
            class="i-lucide-lock mt-0.5 size-4 shrink-0"
            aria-hidden="true"
          />
          {{ t(`${NS}.SO_LEITURA`) }}
        </p>
        <section
          v-if="podeMudar"
          class="rounded-3xl border border-n-weak bg-n-solid-1 px-5 py-5 shadow-sm sm:px-6"
          data-ritmo-limite
        >
          <h2 class="mb-1 text-base font-semibold text-n-slate-12">
            {{ t(`${NS}.LIMITE.TITLE`) }}
          </h2>
          <p class="mb-4 text-sm text-n-slate-11">
            {{ t(`${NS}.LIMITE.HELP`) }}
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <div class="w-full sm:w-64">
              <ChoiceSelect
                v-model="formulario.mensagens"
                :options="opcoesDeMensagens"
                :aria-label="t(`${NS}.LIMITE.MENSAGENS_LABEL`)"
              />
            </div>
            <template v-if="comLimite">
              <span class="text-sm text-n-slate-11">
                {{ t(`${NS}.LIMITE.A_CADA`) }}
              </span>
              <div class="w-full sm:w-48">
                <ChoiceSelect
                  v-model="formulario.dias"
                  :options="opcoesDeDias"
                  :aria-label="t(`${NS}.LIMITE.DIAS_LABEL`)"
                />
              </div>
            </template>
          </div>
        </section>

        <section
          v-if="podeMudar"
          class="rounded-3xl border border-n-weak bg-n-solid-1 px-5 py-5 shadow-sm sm:px-6"
          data-ritmo-horario
        >
          <h2 class="mb-1 text-base font-semibold text-n-slate-12">
            {{ t(`${NS}.HORARIO.TITLE`) }}
          </h2>
          <p class="mb-4 text-sm text-n-slate-11">
            {{ t(`${NS}.HORARIO.HELP`) }}
          </p>
          <div class="w-full sm:w-72">
            <ChoiceSelect
              v-model="formulario.comHorario"
              :options="opcoesDeQuando"
              :aria-label="t(`${NS}.HORARIO.QUANDO_LABEL`)"
            />
          </div>
          <template v-if="formulario.comHorario">
            <div
              class="mt-4 grid grid-cols-[auto_minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-2 sm:flex sm:flex-wrap sm:gap-3"
            >
              <span class="text-sm text-n-slate-11">
                {{ t(`${NS}.HORARIO.DAS`) }}
              </span>
              <div class="w-full sm:w-32">
                <ChoiceSelect
                  v-model="formulario.inicio"
                  :options="opcoesDeInicio"
                  :aria-label="t(`${NS}.HORARIO.INICIO_LABEL`)"
                />
              </div>
              <span class="text-sm text-n-slate-11">
                {{ t(`${NS}.HORARIO.AS`) }}
              </span>
              <div class="w-full sm:w-32">
                <ChoiceSelect
                  v-model="formulario.fim"
                  :options="opcoesDeFim"
                  :aria-label="t(`${NS}.HORARIO.FIM_LABEL`)"
                  :invalid="problema === 'FIM_ANTES'"
                />
              </div>
            </div>
            <p
              v-if="problema === 'FIM_ANTES'"
              class="mb-0 mt-2 text-sm text-n-ruby-11"
              role="alert"
              data-ritmo-problema
            >
              {{
                t(`${NS}.PROBLEMA.FIM_ANTES`, {
                  inicio: hora(formulario.inicio),
                  fim: hora(formulario.fim),
                })
              }}
            </p>
            <fieldset class="mt-4">
              <legend class="mb-2 text-sm text-n-slate-11">
                {{ t(`${NS}.HORARIO.DIAS_LABEL`) }}
              </legend>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="dia in DIAS_DA_SEMANA"
                  :key="dia"
                  type="button"
                  class="inline-flex min-h-11 min-w-11 items-center gap-1 rounded-xl border px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                  :class="
                    formulario.diasDaSemana.includes(dia)
                      ? 'border-n-brand bg-n-brand text-white'
                      : 'border-n-slate-7 bg-n-alpha-1 text-n-slate-12 hover:bg-n-alpha-2'
                  "
                  :aria-pressed="formulario.diasDaSemana.includes(dia)"
                  :data-dia="dia"
                  @click="marcarDia(dia)"
                >
                  <span
                    v-if="formulario.diasDaSemana.includes(dia)"
                    class="i-lucide-check size-3.5"
                    aria-hidden="true"
                  />
                  {{ t(`${NS}.HORARIO.DIAS_DA_SEMANA.${dia}`) }}
                </button>
              </div>
            </fieldset>
            <p class="mb-0 mt-4 text-xs text-n-slate-11">
              {{ t(`${NS}.HORARIO.FUSO`) }}
            </p>
            <p
              v-if="problema === 'SEM_DIA'"
              class="mb-0 mt-3 text-sm text-n-ruby-11"
              role="alert"
              data-ritmo-problema
            >
              {{ t(`${NS}.PROBLEMA.SEM_DIA`) }}
            </p>
          </template>
        </section>

        <section
          class="rounded-2xl border border-n-blue-6 bg-n-blue-2 px-5 py-4 text-sm text-n-slate-12"
          data-ritmo-resumo
        >
          <p class="mb-1 font-medium">{{ resumo }}</p>
          <p class="mb-0 text-n-slate-11">{{ t(`${NS}.ESPERA`) }}</p>
          <p class="mb-0 mt-1 text-n-slate-11">
            {{ t(`${NS}.FORA_DA_CONTA`) }}
          </p>
        </section>

        <div
          v-if="podeMudar"
          class="sticky bottom-0 -mx-4 flex items-center justify-end gap-3 border-t border-n-weak bg-n-slate-2 px-4 py-3 sm:static sm:mx-0 sm:border-0 sm:bg-transparent sm:p-0"
        >
          <p
            v-if="!mudou"
            class="mb-0 flex min-h-11 items-center gap-1 text-sm text-n-slate-11"
            data-ritmo-salvo
          >
            <span class="i-lucide-check size-4" aria-hidden="true" />
            {{ t(`${NS}.TUDO_SALVO`) }}
          </p>
          <Button
            v-else
            type="submit"
            :label="t(`${NS}.SALVAR`)"
            :is-loading="salvando"
            :disabled="!podeSalvar"
            class="!min-h-11 w-full !rounded-xl sm:w-auto"
            data-ritmo-salvar
          />
        </div>
      </form>
    </div>
  </section>
</template>
