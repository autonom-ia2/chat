<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { useOnboardingTrail } from 'dashboard/composables/useOnboardingTrail';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const {
  passos,
  carregando,
  erro,
  resolvidos,
  total,
  percentual,
  passoAtual,
  essencialConcluido,
  carregar,
  pular,
} = useOnboardingTrail();

const accountId = computed(() => store.getters.getCurrentAccountId);

// "Estou travado" abre o Guia da Plataforma, que é quem sabe responder passo a
// passo. Só aparece quando o guia está de fato disponível na conta (mesma porta
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

const emFoco = passo =>
  passo.status === 'pendente' && passo.id === passoAtual.value?.id;

const irPara = passo => {
  router.push({
    name: passo.rota,
    params: { accountId: accountId.value, ...(passo.rota_params || {}) },
  });
};

const aoPular = async passo => {
  try {
    await pular(passo.id);
  } catch {
    useAlert(t('ONBOARDING_TRAIL.SKIP_ERROR'));
  }
};
</script>

<template>
  <section class="w-full max-w-3xl mx-auto px-4 py-8 flex flex-col gap-6">
    <header class="flex flex-col gap-3">
      <h1 class="mb-0 text-2xl font-medium text-n-slate-12">
        {{
          essencialConcluido
            ? t('ONBOARDING_TRAIL.DONE_TITLE')
            : t('ONBOARDING_TRAIL.TITLE')
        }}
      </h1>
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          essencialConcluido
            ? t('ONBOARDING_TRAIL.DONE_SUBTITLE')
            : t('ONBOARDING_TRAIL.SUBTITLE')
        }}
      </p>

      <div v-if="total" class="flex items-center gap-3">
        <div
          class="h-2 flex-1 rounded-full bg-n-alpha-2 overflow-hidden"
          role="progressbar"
          :aria-valuenow="percentual"
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <div
            class="h-full rounded-full bg-n-teal-9 transition-[width] duration-300"
            :style="{ width: `${percentual}%` }"
          />
        </div>
        <span class="text-sm tabular-nums text-n-slate-11">
          {{ t('ONBOARDING_TRAIL.PROGRESS', { feitos: resolvidos, total }) }}
        </span>
      </div>
    </header>

    <div v-if="carregando" class="flex justify-center py-12">
      <Spinner />
    </div>

    <p v-else-if="erro" class="py-12 text-center text-sm text-n-slate-11">
      {{ t('ONBOARDING_TRAIL.LOAD_ERROR') }}
    </p>

    <ol v-else class="flex flex-col gap-3 m-0 p-0 list-none">
      <li
        v-for="passo in passos"
        :key="passo.id"
        class="rounded-xl border bg-n-solid-1 px-5 py-4 flex flex-col gap-2"
        :class="
          emFoco(passo)
            ? 'border-n-brand outline outline-1 outline-n-brand'
            : 'border-n-weak'
        "
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-3 min-w-0">
            <span
              class="mt-0.5 size-5 shrink-0"
              :class="{
                'i-lucide-circle-check-big text-n-teal-11':
                  passo.status === 'feito',
                'i-lucide-circle-slash text-n-slate-10':
                  passo.status === 'pulado',
                'i-lucide-circle text-n-slate-9': passo.status === 'pendente',
              }"
            />
            <div class="min-w-0">
              <p class="mb-1 font-medium text-n-slate-12">
                {{ passo.titulo }}
              </p>
              <p class="mb-0 text-sm text-n-slate-11">{{ passo.por_que }}</p>
            </div>
          </div>

          <span
            v-if="passo.status !== 'pendente'"
            class="shrink-0 text-xs font-medium"
            :class="
              passo.status === 'feito' ? 'text-n-teal-11' : 'text-n-slate-10'
            "
          >
            {{
              passo.status === 'feito'
                ? t('ONBOARDING_TRAIL.STATUS.DONE')
                : t('ONBOARDING_TRAIL.STATUS.SKIPPED')
            }}
          </span>
        </div>

        <ul
          v-if="emFoco(passo) && passo.pre_requisitos?.length"
          class="mb-0 ltr:ml-8 rtl:mr-8 list-disc text-sm text-n-slate-11"
        >
          <li v-for="item in passo.pre_requisitos" :key="item">{{ item }}</li>
        </ul>

        <div
          v-if="passo.status === 'pendente'"
          class="flex flex-wrap gap-2 ltr:ml-8 rtl:mr-8"
        >
          <Button
            sm
            :color="emFoco(passo) ? 'blue' : 'slate'"
            :variant="emFoco(passo) ? 'solid' : 'outline'"
            :label="t('ONBOARDING_TRAIL.DO_IT')"
            @click="irPara(passo)"
          />
          <Button
            v-if="emFoco(passo) && guiaDisponivel"
            sm
            color="slate"
            variant="ghost"
            icon="i-lucide-life-buoy"
            :label="t('ONBOARDING_TRAIL.STUCK')"
            @click="abrirGuia"
          />
          <Button
            v-if="passo.pulavel"
            sm
            color="slate"
            variant="ghost"
            :label="t('ONBOARDING_TRAIL.SKIP')"
            @click="aoPular(passo)"
          />
        </div>
      </li>
    </ol>
  </section>
</template>
