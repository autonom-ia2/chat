<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaFuncao from './components/CartaoDaFuncao.vue';
import FaixaSemFuncao from './components/FaixaSemFuncao.vue';
import FuncoesFixas from './components/FuncoesFixas.vue';
import PaywallDasFuncoes from './components/PaywallDasFuncoes.vue';
import VazioDasFuncoes from './components/VazioDasFuncoes.vue';
import ApagarFuncao from './pessoas/ApagarFuncao.vue';
import GavetaDaFuncao from './pessoas/GavetaDaFuncao.vue';
import { ALTERAR_NOVA, CRIAR_NOVA, DUPLICAR_NOVA } from './listaPelaFlag';

// Funções da equipe, a lista nova (#2308, épico #1784, especificação 5.A). Atrás da flag funcoes_guiadas
// (listaPelaFlag.js). Criar, alterar e duplicar abrem a conversa guiada (PR 3); quem usa, quem está sem função e
// apagar ficam aqui (PR 4, especificação 5.D e 5.E).
const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { canManagePeople, roleLockReason, reachesRole } = usePeopleAccess();

const funcoes = useMapGetter('customRole/getCustomRoles');
const uiFlags = useMapGetter('customRole/getUIFlags');
const agentes = useMapGetter('agents/getAgents');
const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const accountId = useMapGetter('getCurrentAccountId');

const TONS = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-iris-3 text-n-iris-11',
  'bg-n-amber-3 text-n-amber-11',
];

const carregou = ref(false);
const apagarRef = ref(null);
// A gaveta aberta: { funcao } de uma função, { funcao: null } para quem está sem função.
const gaveta = ref(null);

const atrasDoPlano = computed(
  () => !isFeatureEnabledOnAccount.value(accountId.value, 'custom_roles')
);

// Erro de rede nunca aparece como lista vazia.
const estado = computed(() => {
  if (atrasDoPlano.value) return 'paywall';
  if (!carregou.value || uiFlags.value.fetchingList) return 'carregando';
  if (uiFlags.value.fetchingListFailed) return 'erro';
  return funcoes.value.length ? 'lista' : 'vazio';
});

const agentesComuns = computed(() =>
  agentes.value.filter(agente => agente.role === 'agent')
);
const semFuncao = computed(
  () => agentesComuns.value.filter(agente => !agente.custom_role_id).length
);
const comFuncao = computed(() => agentesComuns.value.length - semFuncao.value);
const administradores = computed(
  () => agentes.value.filter(agente => agente.role === 'administrator').length
);
const pessoasDa = funcao =>
  agentes.value.filter(agente => agente.custom_role_id === funcao.id);

const carregar = async () => {
  await store.dispatch('customRole/getCustomRole');
  carregou.value = true;
};

onMounted(() => {
  carregar();
  store.dispatch('agents/get');
});

// Do vazio, a pronta escolhida já vem na rota e a conversa começa em Ajustes.
const criar = pronta =>
  router.push(
    pronta ? { name: CRIAR_NOVA, query: { pronta } } : { name: CRIAR_NOVA }
  );
const alterar = funcao =>
  router.push({ name: ALTERAR_NOVA, params: { roleId: funcao.id } });
const duplicar = funcao =>
  router.push({ name: DUPLICAR_NOVA, params: { roleId: funcao.id } });
const abrirGaveta = funcao => {
  gaveta.value = { funcao };
};

// "Pôr uma pessoa nela" (especificação 7.8): precisa de Pessoas e de alcançar a função.
const podeEscolherPessoas = funcao =>
  canManagePeople.value && !roleLockReason(funcao);

const pedirParaApagar = (funcao, mensagem) =>
  apagarRef.value?.abrir(funcao, pessoasDa(funcao).length, mensagem);

// O servidor recusou: a lista de agentes estava velha (achou gente), a função de destino sumiu ou saiu do alcance,
// ou alguém mudou a função no meio. A tela recarrega o que mudou e pergunta de novo.
const RECUSAS = {
  destination_required: async (funcao, mensagem) => {
    await store.dispatch('agents/get');
    if (pessoasDa(funcao).length) pedirParaApagar(funcao);
    else useAlert(mensagem);
  },
  destination_invalid: async funcao => {
    await store.dispatch('customRole/getCustomRole');
    pedirParaApagar(funcao, t('FUNCOES_EQUIPE.APAGAR.INDISPONIVEL'));
  },
  changed_meanwhile: async () => {
    useAlert(t('FUNCOES_EQUIPE.APAGAR.MUDOU'));
    await Promise.all([carregar(), store.dispatch('agents/get')]);
  },
};

const apagar = async ({ funcao, destino }) => {
  try {
    await store.dispatch('customRole/deleteCustomRole', {
      id: funcao.id,
      destinationRoleId: destino,
    });
    if (destino) store.dispatch('agents/get');
    useAlert(t('FUNCOES_EQUIPE.APAGAR.APAGADA', { nome: funcao.name }));
  } catch (error) {
    const mensagem = error?.message || t('FUNCOES_EQUIPE.APAGAR.ERRO');
    const recusa = RECUSAS[error?.code];
    if (recusa) await recusa(funcao, mensagem);
    else useAlert(mensagem);
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-8 px-4 pt-8 mx-auto pb-28 max-w-6xl sm:px-8 sm:py-10"
      >
        <PaywallDasFuncoes v-if="estado === 'paywall'" />

        <div
          v-else-if="estado === 'carregando'"
          data-carregando
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t('FUNCOES_EQUIPE.CARREGANDO') }}</span>
          <div class="w-64 h-10 rounded-xl bg-n-alpha-2 animate-pulse" />
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-28 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <VazioDasFuncoes v-else-if="estado === 'vazio'" @criar="criar" />

        <template v-else>
          <header class="flex flex-wrap items-end justify-between gap-5">
            <div class="min-w-0">
              <h1
                class="m-0 text-3xl font-bold tracking-tight sm:text-4xl text-n-slate-12"
              >
                {{ $t('FUNCOES_EQUIPE.TITULO') }}
              </h1>
              <p class="mt-2 mb-0 text-base sm:text-lg text-n-slate-11">
                {{ $t('FUNCOES_EQUIPE.SUBTITULO') }}
              </p>
              <p
                v-if="estado === 'lista'"
                data-contagem
                class="mt-3 mb-0 text-sm sm:text-[0.9375rem] text-n-slate-11"
              >
                {{
                  $t(
                    'FUNCOES_EQUIPE.CONTAGEM.FUNCOES',
                    { n: funcoes.length },
                    funcoes.length
                  )
                }}
                {{ $t('FUNCOES_EQUIPE.CONTAGEM.SEPARADOR') }}
                {{
                  $t(
                    'FUNCOES_EQUIPE.CONTAGEM.PESSOAS',
                    { n: comFuncao },
                    comFuncao
                  )
                }}
              </p>
            </div>
            <Button
              v-if="estado === 'lista'"
              data-criar
              :label="$t('FUNCOES_EQUIPE.CRIAR')"
              icon="i-lucide-plus"
              size="lg"
              class="hidden sm:inline-flex !min-h-12 !rounded-xl"
              @click="criar()"
            />
          </header>

          <div
            v-if="estado === 'erro'"
            data-erro
            role="alert"
            class="flex flex-col items-center gap-4 px-6 text-center border py-14 rounded-2xl border-n-weak bg-n-solid-1"
          >
            <span
              class="grid place-items-center size-12 rounded-xl bg-n-ruby-3 text-n-ruby-11"
            >
              <span class="i-lucide-wifi-off size-6" aria-hidden="true" />
            </span>
            <p class="m-0 text-xl font-semibold leading-snug text-n-slate-12">
              {{ $t('FUNCOES_EQUIPE.ERRO.TITULO') }}
            </p>
            <p class="m-0 text-[0.9375rem] text-n-slate-11">
              {{ $t('FUNCOES_EQUIPE.ERRO.TEXTO') }}
            </p>
            <Button
              data-tentar-de-novo
              :label="$t('FUNCOES_EQUIPE.ERRO.TENTAR')"
              icon="i-lucide-refresh-cw"
              slate
              faded
              class="min-h-11"
              @click="carregar"
            />
          </div>

          <template v-else>
            <FaixaSemFuncao
              v-if="canManagePeople && semFuncao"
              :quantidade="semFuncao"
              @ver-quem-sao="abrirGaveta(null)"
            />

            <ul class="flex flex-col gap-3.5 p-0 m-0 list-none">
              <CartaoDaFuncao
                v-for="(funcao, indice) in funcoes"
                :key="funcao.id"
                :funcao="funcao"
                :pessoas="pessoasDa(funcao)"
                :tom="TONS[indice % TONS.length]"
                :travada="!!roleLockReason(funcao)"
                :pode-duplicar="reachesRole(funcao)"
                :pode-escolher-pessoas="podeEscolherPessoas(funcao)"
                @alterar="alterar(funcao)"
                @duplicar="duplicar(funcao)"
                @apagar="pedirParaApagar(funcao)"
                @escolher-pessoas="abrirGaveta(funcao)"
                @ver-pessoas="abrirGaveta(funcao)"
              />
            </ul>

            <FuncoesFixas
              :administradores="administradores"
              :sem-funcao="semFuncao"
            />
          </template>
        </template>
      </div>
    </main>

    <div
      v-if="estado === 'lista'"
      class="fixed inset-x-0 bottom-0 z-10 px-4 py-4 border-t sm:hidden border-n-weak bg-n-solid-1 shadow-[0_-8px_16px_-8px_rgb(0_0_0/0.12)]"
    >
      <span
        aria-hidden="true"
        class="absolute inset-x-0 pointer-events-none -top-14 h-14 bg-gradient-to-t from-n-surface-1 to-transparent"
      />
      <Button
        data-criar-celular
        :label="$t('FUNCOES_EQUIPE.CRIAR')"
        icon="i-lucide-plus"
        size="lg"
        class="w-full !h-[3.25rem] !rounded-xl"
        @click="criar()"
      />
    </div>

    <ApagarFuncao ref="apagarRef" @apagar="apagar" />
    <GavetaDaFuncao
      v-if="gaveta"
      :funcao="gaveta.funcao"
      @fechar="gaveta = null"
    />
  </section>
</template>
