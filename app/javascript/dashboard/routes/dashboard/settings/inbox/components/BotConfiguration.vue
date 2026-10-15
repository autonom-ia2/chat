<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import QuemAtendeAPI from 'dashboard/api/autonomia/quemAtende';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// Marcação por caixa (épico #1424): a caixa atendida por um agente da
// plataforma — principal (atende primeiro) ou da equipe (recebe quando alguém
// passa) — não aceita agente externo. A aba mostra quem atende e trava a
// escolha, com o motivo. Sem agente da plataforma, a escolha é a de sempre, só
// com agentes externos de verdade (os espelhos saem da lista desde a #1626).
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();
const canManage = useCanManage('inbox_manage');
const agentBots = useMapGetter('agentBots/getBots');
const uiFlags = useMapGetter('agentBots/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');

const inboxId = computed(() => Number(props.inbox?.id));
// { principal: { id, name } | null, equipe: [{ id, name }] }, ou null enquanto
// carrega ou quando a leitura falhou (`erroDeLeitura`).
const plataforma = ref(null);
// Sem saber quem atende, a escolha fica travada: nunca vira "caixa livre".
const erroDeLeitura = ref(false);
const selectedAgentBotId = ref('');

const activeAgentBot = computed(() =>
  store.getters['agentBots/getActiveAgentBot'](inboxId.value)
);
watch(
  activeAgentBot,
  bot => {
    selectedAgentBotId.value = bot?.id || '';
  },
  { immediate: true }
);

const opcoes = computed(() =>
  agentBots.value.map(bot => ({ value: bot.id, label: bot.name }))
);

const principal = computed(() => plataforma.value?.principal || null);
const equipe = computed(() => plataforma.value?.equipe || []);
const daPlataforma = computed(
  () => Boolean(principal.value) || equipe.value.length > 0
);

const motivo = computed(() => {
  if (principal.value && equipe.value.length) {
    return t('AGENTS.CAIXA_EXTERNO.TRAVADO_TUDO');
  }
  return principal.value
    ? t('AGENTS.CAIXA_EXTERNO.TRAVADO_PRINCIPAL')
    : t('AGENTS.CAIXA_EXTERNO.TRAVADO_EQUIPE');
});

const linhas = computed(() => [
  ...(principal.value
    ? [
        {
          ...principal.value,
          texto: t('AGENTS.CAIXA_EXTERNO.PRINCIPAL', {
            nome: principal.value.name,
          }),
        },
      ]
    : []),
  ...equipe.value.map(agente => ({
    ...agente,
    texto: t('AGENTS.CAIXA_EXTERNO.EQUIPE', { nome: agente.name }),
  })),
]);

const rotaDoAgente = agente => ({
  name: 'autonomia_agent_panel',
  params: { accountId: accountId.value, agentId: agente.id },
});

// #1648 — leitura própria da caixa, sem flag: a mesma regra da recusa do
// servidor (set_agent_bot). `papel`: 'porta' atende primeiro, 'area' recebe
// quando alguém passa.
const daCaixa = agentes => ({
  principal: agentes.find(agente => agente.papel === 'porta') || null,
  equipe: agentes.filter(agente => agente.papel === 'area'),
});

const carregarPlataforma = async () => {
  erroDeLeitura.value = false;
  try {
    const { data } = await QuemAtendeAPI.daCaixa(inboxId.value);
    plataforma.value = daCaixa(data.agentes);
  } catch {
    plataforma.value = null;
    erroDeLeitura.value = true;
  }
};

onMounted(() => {
  store.dispatch('agentBots/get');
  store.dispatch('agentBots/fetchAgentBotInbox', inboxId.value);
  carregarPlataforma();
});

// Falhou: relê quem atende. O servidor só recusa (422, #1648) quando a caixa
// tem agente da plataforma; aí a releitura mostra a caixa travada e o aviso é
// o motivo (TRAVADO_*), nunca "tente de novo" numa ação que não vai passar.
// O store devolve só a mensagem, sem o `code`: o estado relido é a fonte.
const avisarFalha = async textoGenerico => {
  await carregarPlataforma();
  useAlert(daPlataforma.value ? motivo.value : textoGenerico);
};

const salvar = async () => {
  try {
    await store.dispatch('agentBots/setAgentBotInbox', {
      inboxId: inboxId.value,
      botId: selectedAgentBotId.value || undefined,
    });
    useAlert(t('AGENTS.CAIXA_EXTERNO.SALVOU'));
  } catch {
    await avisarFalha(t('AGENTS.CAIXA_EXTERNO.FALHOU'));
  }
};

const desconectar = async () => {
  try {
    await store.dispatch('agentBots/disconnectBot', { inboxId: inboxId.value });
    useAlert(t('AGENTS.CAIXA_EXTERNO.DESCONECTOU'));
  } catch {
    await avisarFalha(t('AGENTS.CAIXA_EXTERNO.FALHOU_DESCONECTAR'));
  }
};
</script>

<template>
  <div class="mx-6 max-w-4xl">
    <SettingsFieldSection
      v-if="erroDeLeitura"
      data-erro-de-leitura
      :label="$t('AGENTS.CAIXA_EXTERNO.TITULO')"
      class="[&>div]:!items-start"
    >
      <div class="flex flex-col gap-3">
        <ChoiceSelect
          model-value=""
          disabled
          :options="[]"
          :aria-label="$t('AGENTS.CAIXA_EXTERNO.ESCOLHER')"
          :placeholder="$t('AGENTS.CAIXA_EXTERNO.ESCOLHER')"
        />
        <p
          role="alert"
          class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-11"
        >
          <span
            class="i-lucide-triangle-alert mt-0.5 size-4 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ $t('AGENTS.CAIXA_EXTERNO.ERRO_LEITURA') }}
        </p>
        <NextButton
          type="button"
          data-tentar-de-novo
          class="!min-h-11 self-start"
          :label="$t('AGENTS.CAIXA_EXTERNO.TENTAR_DE_NOVO')"
          icon="i-lucide-refresh-cw"
          slate
          faded
          @click="carregarPlataforma"
        />
      </div>
    </SettingsFieldSection>
    <LoadingState
      v-else-if="
        !plataforma || uiFlags.isFetching || uiFlags.isFetchingAgentBot
      "
    />
    <SettingsFieldSection
      v-else-if="daPlataforma"
      data-caixa-da-plataforma
      :label="$t('AGENTS.CAIXA_EXTERNO.TITULO')"
      class="[&>div]:!items-start"
    >
      <div class="flex flex-col gap-4">
        <section
          class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
        >
          <p class="mb-0 text-[0.9375rem] font-semibold text-n-slate-12">
            {{ $t('AGENTS.CAIXA_EXTERNO.PLATAFORMA') }}
          </p>
          <ul class="m-0 flex list-none flex-col gap-2 p-0">
            <li
              v-for="agente in linhas"
              :key="agente.id"
              data-agente-da-caixa
              class="flex flex-wrap items-center gap-3"
            >
              <span
                class="grid size-9 shrink-0 place-items-center rounded-full bg-n-iris-3 text-n-iris-11"
                aria-hidden="true"
              >
                <span class="i-lucide-bot size-5" />
              </span>
              <div
                class="flex min-w-0 flex-1 flex-col md:flex-row md:items-center md:gap-3"
              >
                <span
                  class="min-w-0 text-[0.9375rem] text-n-slate-12 md:flex-1"
                >
                  {{ agente.texto }}
                </span>
                <router-link
                  :to="rotaDoAgente(agente)"
                  data-abrir-agente
                  class="-ms-2 inline-flex min-h-11 items-center gap-1.5 self-start rounded-lg px-2 text-[0.9375rem] font-medium text-n-blue-11 hover:bg-n-alpha-2 md:ms-0 md:self-auto"
                >
                  {{ $t('AGENTS.CAIXA_EXTERNO.ABRIR') }}
                  <span
                    class="i-lucide-arrow-right size-4 rtl:rotate-180"
                    aria-hidden="true"
                  />
                </router-link>
              </div>
            </li>
          </ul>
        </section>
        <div class="flex flex-col gap-2">
          <ChoiceSelect
            model-value=""
            disabled
            :options="[]"
            :aria-label="$t('AGENTS.CAIXA_EXTERNO.ESCOLHER')"
            :placeholder="$t('AGENTS.CAIXA_EXTERNO.NENHUM')"
          />
          <p
            data-motivo
            class="mb-0 flex items-start gap-2 text-[0.9375rem] text-n-slate-11"
          >
            <span
              class="i-lucide-lock mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ motivo }}
          </p>
        </div>
      </div>
    </SettingsFieldSection>
    <form v-else data-caixa-livre @submit.prevent="salvar">
      <SettingsFieldSection
        :label="$t('AGENTS.CAIXA_EXTERNO.TITULO')"
        :help-text="$t('AGENTS.CAIXA_EXTERNO.EXPLICA')"
        class="[&>div]:!items-start"
      >
        <ChoiceSelect
          v-model="selectedAgentBotId"
          :options="opcoes"
          :aria-label="$t('AGENTS.CAIXA_EXTERNO.ESCOLHER')"
          :placeholder="$t('AGENTS.CAIXA_EXTERNO.ESCOLHER')"
          :disabled="!canManage"
        />
        <template #extra>
          <div class="mt-3 grid grid-cols-1 lg:grid-cols-8">
            <div class="invisible col-span-1 lg:col-span-2" />
            <div
              v-if="canManage"
              class="col-span-1 mx-1 flex flex-wrap gap-2 lg:col-span-6"
            >
              <NextButton
                type="submit"
                class="!min-h-11"
                :label="$t('AGENTS.CAIXA_EXTERNO.SALVAR')"
                :is-loading="uiFlags.isSettingAgentBot"
              />
              <NextButton
                type="button"
                data-desconectar
                class="!min-h-11"
                :label="$t('AGENTS.CAIXA_EXTERNO.DESCONECTAR')"
                :disabled="!activeAgentBot"
                :is-loading="uiFlags.isDisconnecting"
                faded
                ruby
                @click="desconectar"
              />
            </div>
          </div>
        </template>
      </SettingsFieldSection>
    </form>
  </div>
</template>
