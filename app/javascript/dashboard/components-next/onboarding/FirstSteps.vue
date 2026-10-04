<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { useOnboardingTrail } from 'dashboard/composables/useOnboardingTrail';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FirstStepsFocus from './FirstStepsFocus.vue';
import FirstStepsTrail from './FirstStepsTrail.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const {
  carregando,
  erro,
  resolvidos,
  total,
  percentual,
  passoAtual,
  essencialConcluido,
  numerados,
  porEtapa,
  minutosRestantes,
  carregar,
  pular,
} = useOnboardingTrail();

const accountId = computed(() => store.getters.getCurrentAccountId);
const nome = computed(() => store.getters.getCurrentUser?.name);

// "Preciso de ajuda" abre o Guia da Plataforma, que é quem sabe responder passo
// a passo. Só aparece quando o guia está de fato disponível na conta (mesma porta
// do lançador global): sem chave de IA o botão levaria a um painel vazio.
const { updateUISettings } = useUISettings();
const contaAtual = useMapGetter('accounts/getAccount');
const guiaDisponivel = computed(
  () => contaAtual.value(accountId.value)?.autonomia_guide_available === true
);

const abrirGuia = () => {
  updateUISettings({
    is_autonomia_guide_panel_open: true,
    is_autonomia_copilot_panel_open: false,
  });
};

onMounted(carregar);

// Em foco: o passo que a pessoa escolheu na lista ou, sem escolha, o primeiro
// que falta. Com o essencial pronto, a tela comemora até a pessoa pedir o resto.
const escolhidoId = ref(null);
const verResto = ref(false);

const emFoco = computed(() => {
  const escolhido = numerados.value.find(
    passo => passo.id === escolhidoId.value && passo.status === 'pendente'
  );
  if (escolhido) return escolhido;
  return numerados.value.find(passo => passo.id === passoAtual.value?.id);
});

const comemorando = computed(
  () => essencialConcluido.value && !verResto.value && !escolhidoId.value
);

const escolher = passo => {
  escolhidoId.value = passo.id;
};

const verOQueFalta = () => {
  verResto.value = true;
};

const irPara = passo => {
  router.push({
    name: passo.rota,
    params: { accountId: accountId.value, ...(passo.rota_params || {}) },
  });
};

const aoPular = async passo => {
  try {
    await pular(passo.id);
    escolhidoId.value = null;
  } catch {
    useAlert(t('ONBOARDING_TRAIL.SKIP_ERROR'));
  }
};

const etapas = computed(() =>
  porEtapa.value.map(etapa => {
    const feitos = etapa.passos.filter(
      passo => passo.status !== 'pendente'
    ).length;
    return {
      ...etapa,
      feitos,
      completa: feitos === etapa.passos.length,
      largura: `${(feitos / etapa.passos.length) * 100}%`,
    };
  })
);

// Anel de progresso: circunferência do círculo de raio 29.
const CIRCUNFERENCIA = 2 * Math.PI * 29;
const deslocamento = computed(
  () => CIRCUNFERENCIA * (1 - percentual.value / 100)
);
</script>

<template>
  <section class="h-full w-full overflow-y-auto">
    <div class="mx-auto flex max-w-4xl flex-col gap-6 px-4 py-8">
      <header class="flex flex-wrap items-center justify-between gap-6">
        <div class="min-w-0 flex-1">
          <p v-if="nome" class="mb-1 text-sm text-n-slate-11">
            {{ t('ONBOARDING_TRAIL.GREETING', { nome }) }}
          </p>
          <h1 class="mb-1.5 text-2xl font-semibold text-n-slate-12">
            {{
              essencialConcluido
                ? t('ONBOARDING_TRAIL.DONE_TITLE')
                : t('ONBOARDING_TRAIL.TITLE')
            }}
          </h1>
          <p class="mb-0 text-base text-n-slate-11">
            {{
              essencialConcluido
                ? t('ONBOARDING_TRAIL.DONE_SUBTITLE')
                : t('ONBOARDING_TRAIL.SUBTITLE')
            }}
          </p>
        </div>

        <div
          v-if="total"
          class="flex shrink-0 items-center gap-3"
          role="progressbar"
          :aria-valuenow="percentual"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-label="
            t('ONBOARDING_TRAIL.PROGRESS', { feitos: resolvidos, total })
          "
        >
          <svg
            viewBox="0 0 68 68"
            class="size-16 -rotate-90"
            aria-hidden="true"
          >
            <circle
              cx="34"
              cy="34"
              r="29"
              fill="none"
              stroke-width="6"
              class="stroke-n-alpha-2"
            />
            <circle
              cx="34"
              cy="34"
              r="29"
              fill="none"
              stroke-width="6"
              stroke-linecap="round"
              class="stroke-n-brand transition-[stroke-dashoffset] duration-500 motion-reduce:transition-none"
              :stroke-dasharray="CIRCUNFERENCIA"
              :stroke-dashoffset="deslocamento"
            />
          </svg>
          <div>
            <b class="block text-xl font-semibold tabular-nums text-n-slate-12">
              {{
                t('ONBOARDING_TRAIL.PROGRESS', { feitos: resolvidos, total })
              }}
            </b>
            <span class="text-sm text-n-slate-11">
              {{
                minutosRestantes
                  ? t('ONBOARDING_TRAIL.REMAINING', {
                      minutos: minutosRestantes,
                    })
                  : t('ONBOARDING_TRAIL.ALL_DONE')
              }}
            </span>
          </div>
        </div>
      </header>

      <div v-if="carregando" class="flex justify-center py-12">
        <Spinner />
      </div>

      <p v-else-if="erro" class="py-12 text-center text-sm text-n-slate-11">
        {{ t('ONBOARDING_TRAIL.LOAD_ERROR') }}
      </p>

      <template v-else>
        <ol class="m-0 grid list-none gap-3 p-0 sm:grid-cols-3">
          <li
            v-for="(etapa, indice) in etapas"
            :key="etapa.id"
            class="flex flex-col gap-2"
          >
            <span
              class="h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
              aria-hidden="true"
            >
              <span
                class="block h-full rounded-full transition-[width] duration-500 motion-reduce:transition-none"
                :class="etapa.completa ? 'bg-n-teal-9' : 'bg-n-brand'"
                :style="{ width: etapa.largura }"
              />
            </span>
            <span class="flex justify-between gap-2 text-sm text-n-slate-11">
              <span
                class="font-medium"
                :class="
                  emFoco?.etapa === etapa.id
                    ? 'text-n-blue-11'
                    : 'text-n-slate-12'
                "
              >
                {{ indice + 1 }}.
                {{ t(`ONBOARDING_TRAIL.ETAPAS.${etapa.id}`) }}
              </span>
              <span class="tabular-nums">
                {{
                  t('ONBOARDING_TRAIL.PROGRESS', {
                    feitos: etapa.feitos,
                    total: etapa.passos.length,
                  })
                }}
              </span>
            </span>
          </li>
        </ol>

        <div
          v-if="comemorando"
          class="flex flex-wrap items-center gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm"
        >
          <span
            class="grid size-16 shrink-0 place-items-center rounded-full bg-n-teal-9 text-white"
          >
            <span class="i-lucide-check size-8" />
          </span>
          <div class="min-w-0 flex-1">
            <h2 class="mb-1 text-xl font-semibold text-n-slate-12">
              {{ t('ONBOARDING_TRAIL.ESSENTIAL_READY') }}
            </h2>
            <p class="mb-0 text-base text-n-slate-11">
              {{ t('ONBOARDING_TRAIL.ESSENTIAL_READY_TEXT') }}
            </p>
          </div>
          <Button
            v-if="emFoco"
            lg
            color="slate"
            variant="outline"
            :label="t('ONBOARDING_TRAIL.SEE_REST')"
            @click="verOQueFalta"
          />
        </div>

        <FirstStepsFocus
          v-else-if="emFoco"
          :passo="emFoco"
          :total="total"
          :eh-proximo="emFoco.id === passoAtual?.id"
          :guia-disponivel="guiaDisponivel"
          :account-id="accountId"
          @fazer="irPara"
          @pular="aoPular"
          @ajuda="abrirGuia"
        />

        <FirstStepsTrail
          :etapas="etapas"
          :em-foco-id="comemorando ? null : emFoco?.id"
          @escolher="escolher"
        />
      </template>
    </div>
  </section>
</template>
