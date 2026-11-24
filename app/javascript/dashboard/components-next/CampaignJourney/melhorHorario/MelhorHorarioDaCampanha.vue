<script setup>
// #3101 — em "Quando começa", na revisão da campanha: mandar a cada pessoa na hora em que ela costuma responder.
// Quem já respondeu antes recebe nessa hora, nas 24 horas depois do início; quem nunca respondeu recebe no início
// escolhido. Sempre dentro do horário permitido da conta (a tela "Limite de mensagens"): o melhor horário só escolhe a
// hora, o porteiro continua decidindo se pode.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import { JANELA_HORAS, coberturaDoPublico } from './melhorHorario';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  // Quantas pessoas do público têm uma hora de resposta conhecida. null = ainda contando.
  conhecidos: { type: Number, default: null },
  // Quantas pessoas a campanha alcança.
  total: { type: Number, default: 0 },
  // O horário permitido da conta já em palavras ("de segunda a sexta, das 8h às 20h"); vazio = a qualquer hora.
  horarioPermitido: { type: String, default: '' },
  // 'now' ou 'later', o "Quando começa" escolhido.
  quando: { type: String, default: 'now' },
});
const emit = defineEmits(['update:modelValue']);

const NS = 'REENVIO_HORARIO.MELHOR_HORARIO';
const { t, locale } = useI18n();
const inteiro = numero =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(numero);

const cobertura = computed(() =>
  coberturaDoPublico({ conhecidos: props.conhecidos, total: props.total })
);
const ninguem = computed(() => cobertura.value.estado === 'NINGUEM');
const contando = computed(() => cobertura.value.estado === 'CONTANDO');
const inicio = computed(() =>
  t(`${NS}.INICIO.${props.quando === 'later' ? 'LATER' : 'NOW'}`)
);
const horario = computed(() =>
  props.horarioPermitido
    ? t(`${NS}.HORARIO_DA_CONTA`, { horario: props.horarioPermitido })
    : t(`${NS}.QUALQUER_HORA`)
);
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    data-melhor-horario
  >
    <div class="flex items-start justify-between gap-3">
      <div class="flex min-w-0 flex-col gap-1">
        <p class="m-0 flex items-center gap-1.5 text-sm font-medium">
          <span
            class="i-lucide-clock-4 size-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span class="text-n-slate-12">{{ t(`${NS}.TITULO`) }}</span>
        </p>
        <p
          id="melhor-horario-ajuda"
          class="m-0 text-xs text-n-slate-11"
          data-melhor-horario-ajuda
        >
          {{
            ninguem
              ? t(`${NS}.NINGUEM`, { inicio })
              : t(`${NS}.AJUDA`, { horas: JANELA_HORAS })
          }}
        </p>
      </div>
      <ToggleSwitch
        :model-value="modelValue"
        :label="t(`${NS}.TITULO`)"
        :disabled="ninguem && !modelValue"
        described-by="melhor-horario-ajuda"
        @update:model-value="ligado => emit('update:modelValue', ligado)"
      />
    </div>

    <template v-if="modelValue">
      <div
        v-if="contando"
        class="flex flex-col gap-2"
        aria-busy="true"
        data-melhor-horario-contando
      >
        <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.CONTANDO`) }}</p>
        <div class="grid gap-2 sm:grid-cols-2">
          <div class="h-[76px] animate-pulse rounded-lg bg-n-alpha-2" />
          <div class="h-[76px] animate-pulse rounded-lg bg-n-alpha-2" />
        </div>
      </div>
      <dl
        v-else
        class="m-0 grid gap-2 sm:grid-cols-2"
        data-melhor-horario-cobertura
      >
        <div class="flex flex-col gap-0.5 rounded-lg bg-n-blue-2 px-3 py-2">
          <dt class="text-xs text-n-blue-11">{{ t(`${NS}.COM_HORA`) }}</dt>
          <dd class="m-0 text-lg font-semibold tabular-nums text-n-slate-12">
            {{
              t(
                `${NS}.PESSOAS`,
                { n: inteiro(cobertura.conhecidos) },
                cobertura.conhecidos
              )
            }}
          </dd>
          <dd class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.COM_HORA_AJUDA`) }}
          </dd>
        </div>
        <div
          v-if="cobertura.semHora > 0"
          class="flex flex-col gap-0.5 rounded-lg bg-n-alpha-1 px-3 py-2"
          data-melhor-horario-sem-hora
        >
          <dt class="text-xs text-n-slate-11">{{ t(`${NS}.SEM_HORA`) }}</dt>
          <dd class="m-0 text-lg font-semibold tabular-nums text-n-slate-12">
            {{
              t(
                `${NS}.PESSOAS`,
                { n: inteiro(cobertura.semHora) },
                cobertura.semHora
              )
            }}
          </dd>
          <dd class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.SEM_HORA_AJUDA`, { inicio }) }}
          </dd>
        </div>
      </dl>
      <p
        class="m-0 flex items-start gap-2 text-xs text-n-slate-11"
        data-melhor-horario-conta
      >
        <span
          class="i-lucide-shield-check mt-0.5 size-3.5 shrink-0"
          aria-hidden="true"
        />
        {{ horario }}
      </p>
    </template>
  </div>
</template>
