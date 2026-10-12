<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { quandoSai } from '../funil';

// #1384 — o que acontece nas duas situações, com a Ana de exemplo: quando
// ela some (a mensagem de retorno, ou o lembrete da equipe, e o calendário
// das tentativas) e quando ela pede para falar depois.
const props = defineProps({
  retorno: { type: Object, required: true },
  mensagemNoDia: { type: Boolean, default: false },
});

const { t } = useI18n();
const avisaEquipe = computed(() => props.retorno.mode === 'ai_reminder');

const calendario = computed(() =>
  quandoSai({
    intervalos: props.retorno.intervalsHours,
    dias: props.retorno.allowedDays,
    inicio: props.retorno.quietHours.start,
    fim: props.retorno.quietHours.end,
  }).map((quando, indice) => ({
    numero: indice + 1,
    texto: quando
      ? t(
          quando.semanaQueVem
            ? 'CRM_FUNIL.PREVIA.QUANDO_PROXIMA'
            : 'CRM_FUNIL.PREVIA.QUANDO',
          {
            dia: t(
              `CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.DAYS_FULL.${quando.dia}`
            ),
            hora: quando.hora,
          }
        )
      : '…',
  }))
);
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ $t('CRM_FUNIL.RETORNO.SUMIU_TITULO') }}
      </h4>
      <p
        v-if="!retorno.enabled"
        class="mb-0 rounded-xl border border-dashed border-n-slate-6 p-3 text-[0.9375rem] text-n-slate-11"
      >
        {{ $t('CRM_FUNIL.PREVIA.RETORNO_DESLIGADO') }}
      </p>
      <template v-else>
        <div
          v-if="!avisaEquipe"
          class="flex flex-col gap-2 rounded-xl bg-n-teal-2 p-3"
        >
          <p
            class="mb-0 max-w-[85%] self-end rounded-xl rounded-ee-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
          >
            {{ $t('CRM_FUNIL.PREVIA.MSG_NOSSA') }}
          </p>
          <p
            class="mb-0 max-w-[85%] self-start rounded-xl rounded-es-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
          >
            {{ $t('CRM_FUNIL.PREVIA.MSG_CLIENTE') }}
          </p>
          <span
            class="self-center rounded-lg bg-n-solid-1 px-2 py-0.5 text-sm text-n-slate-11"
          >
            {{ calendario[0]?.texto }}
          </span>
          <p
            class="mb-0 max-w-[85%] self-end rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
          >
            {{ $t('CRM_FUNIL.PREVIA.MSG_RETORNO') }}
          </p>
        </div>
        <div
          v-else
          class="flex items-start gap-3 rounded-xl bg-n-iris-2 p-3 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-bell-ring mt-0.5 size-5 shrink-0 text-n-iris-11"
            aria-hidden="true"
          />
          <span class="flex flex-col gap-1">
            <strong class="font-semibold">
              {{ $t('CRM_FUNIL.PREVIA.LEMBRETE_TITULO') }}
            </strong>
            {{ $t('CRM_FUNIL.PREVIA.LEMBRETE_TEXTO') }}
          </span>
        </div>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ $t('CRM_FUNIL.PREVIA.SEMANA_INICIO') }}
        </p>
        <ol class="m-0 flex list-none flex-col gap-2 p-0">
          <li
            v-for="item in calendario"
            :key="item.numero"
            class="flex items-center gap-3 text-[0.9375rem] text-n-slate-12"
          >
            <span
              class="grid size-7 shrink-0 place-items-center rounded-full bg-n-blue-3 text-xs font-bold text-n-blue-11"
            >
              {{ $t('CRM_FUNIL.RETORNO.ORDEM', { n: item.numero }) }}
            </span>
            {{ item.texto }}
          </li>
        </ol>
      </template>
    </section>

    <section
      class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
    >
      <h4 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ $t('CRM_FUNIL.RETORNO.DEPOIS_TITULO') }}
      </h4>
      <div class="flex flex-col gap-2 rounded-xl bg-n-iris-2 p-3">
        <p
          class="mb-0 max-w-[85%] self-start rounded-xl rounded-es-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
        >
          {{ $t('CRM_FUNIL.RETORNO.DEPOIS_PEDIDO') }}
        </p>
        <span
          class="self-center rounded-lg bg-n-solid-1 px-2 py-0.5 text-sm text-n-slate-11"
        >
          {{ $t('CRM_FUNIL.PREVIA.SEXTA') }}
        </span>
        <p
          v-if="mensagemNoDia"
          class="mb-0 max-w-[85%] self-end rounded-xl rounded-ee-sm bg-n-blue-9 px-3 py-2 text-sm text-white"
        >
          {{ $t('CRM_FUNIL.PREVIA.MSG_COMBINADO') }}
        </p>
        <p
          class="mb-0 flex items-start gap-2 rounded-xl bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
        >
          <span
            class="i-lucide-bell mt-0.5 size-4 shrink-0 text-n-iris-11"
            aria-hidden="true"
          />
          {{
            $t(
              mensagemNoDia
                ? 'CRM_FUNIL.PREVIA.COMBINADO_E_LEMBRETE'
                : 'CRM_FUNIL.PREVIA.COMBINADO_SO_LEMBRETE'
            )
          }}
        </p>
      </div>
    </section>
  </div>
</template>
