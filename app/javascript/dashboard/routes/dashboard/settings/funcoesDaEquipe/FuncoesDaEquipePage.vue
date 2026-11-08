<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import Button from 'dashboard/components-next/button/Button.vue';
import CartaoDaFuncao from './components/CartaoDaFuncao.vue';
import ErroAoAbrir from './components/ErroAoAbrir.vue';
import FaixaSemFuncao from './components/FaixaSemFuncao.vue';
import FuncoesFixas from './components/FuncoesFixas.vue';
import PaywallDasFuncoes from './components/PaywallDasFuncoes.vue';
import VazioDasFuncoes from './components/VazioDasFuncoes.vue';
import ApagarFuncao from './pessoas/ApagarFuncao.vue';
import GavetaDaFuncao from './pessoas/GavetaDaFuncao.vue';
import { devolverFoco } from './guiada/focoQueFica';
import { ALTERAR_NOVA, CRIAR_NOVA, DUPLICAR_NOVA } from './listaPelaFlag';
import { useApagarFuncao } from './pessoas/useApagarFuncao';

// Funções da equipe, a lista nova (#2308, épico #1784, especificação 5.A). Atrás da flag funcoes_guiadas
// (listaPelaFlag.js). Criar, alterar e duplicar abrem a conversa guiada (PR 3); quem usa, quem está sem função e
// apagar ficam aqui (PR 4, especificação 5.D e 5.E).
const store = useStore();
const router = useRouter();
const { canManagePeople, roleLockReason } = usePeopleAccess();

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
// As pessoas ainda vêm (esqueleto) ou falharam (a tela diz isso): nos dois casos, nunca "nenhuma pessoa com função".
const pessoasCarregando = ref(true);
const pessoasFalharam = ref(false);
const apagarRef = ref(null);
const raiz = ref(null);
// Quando o gatilho some (o cartão apagado, "Escolher pessoas" que virou a pilha de rostos), o foco vem para cá.
const TITULO = '[data-titulo-da-lista]';
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

// Devolve se as pessoas vieram.
const carregarPessoas = async () => {
  pessoasCarregando.value = true;
  pessoasFalharam.value = (await store.dispatch('agents/get')) === false;
  pessoasCarregando.value = false;
  return !pessoasFalharam.value;
};

onMounted(() => {
  carregar();
  carregarPessoas();
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
const fecharGaveta = () => {
  gaveta.value = null;
  devolverFoco(raiz.value, [TITULO]);
};

// "Pôr uma pessoa nela" (especificação 7.8): precisa de Pessoas e de alcançar a função.
const podeEscolherPessoas = funcao =>
  canManagePeople.value && !roleLockReason(funcao);

const { pedirParaApagar, apagar } = useApagarFuncao({
  apagarRef,
  pessoasDa,
  carregar,
  carregarPessoas,
});
const estadoDasPessoas = computed(() => {
  if (pessoasCarregando.value) return 'carregando';
  return pessoasFalharam.value ? 'erro' : 'pronto';
});
</script>

<template>
  <section
    ref="raiz"
    class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1"
  >
    <div class="flex-1 overflow-y-auto">
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
                data-titulo-da-lista
                tabindex="-1"
                class="m-0 text-3xl font-bold tracking-tight outline-none sm:text-4xl text-n-slate-12"
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
                <span
                  v-if="pessoasCarregando"
                  data-pessoas-carregando
                  aria-hidden="true"
                  class="inline-block w-32 h-4 align-middle rounded bg-n-alpha-2 animate-pulse"
                />
                <template v-else-if="pessoasFalharam">
                  <span data-pessoas-erro role="alert">
                    {{ $t('FUNCOES_EQUIPE.CONTAGEM.PESSOAS_ERRO') }}
                  </span>
                  <button
                    type="button"
                    data-tentar-pessoas
                    class="px-1 font-semibold underline rounded min-h-11 underline-offset-4 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                    @click="carregarPessoas"
                  >
                    {{ $t('FUNCOES_EQUIPE.ERRO.TENTAR') }}
                  </button>
                </template>
                <template v-else>
                  {{
                    $t(
                      'FUNCOES_EQUIPE.CONTAGEM.PESSOAS',
                      { n: comFuncao },
                      comFuncao
                    )
                  }}
                </template>
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

          <ErroAoAbrir v-if="estado === 'erro'" @tentar="carregar" />

          <template v-else>
            <FaixaSemFuncao
              v-if="
                canManagePeople &&
                semFuncao &&
                !pessoasFalharam &&
                !pessoasCarregando
              "
              :quantidade="semFuncao"
              @ver-quem-sao="abrirGaveta(null)"
            />

            <ul class="flex flex-col gap-3.5 p-0 m-0 list-none">
              <CartaoDaFuncao
                v-for="(funcao, indice) in funcoes"
                :key="funcao.id"
                :funcao="funcao"
                :pessoas="pessoasDa(funcao)"
                :sem-pessoas="pessoasFalharam"
                :carregando-pessoas="pessoasCarregando"
                :tom="TONS[indice % TONS.length]"
                :trava="roleLockReason(funcao) || ''"
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
              :sem-pessoas="pessoasFalharam || pessoasCarregando"
            />
          </template>
        </template>
      </div>
    </div>

    <div
      v-if="estado === 'lista'"
      class="fixed inset-x-0 bottom-0 z-10 py-4 pe-4 ps-20 border-t sm:hidden border-n-weak bg-n-solid-1 shadow-[0_-8px_16px_-8px_rgb(0_0_0/0.12)]"
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

    <ApagarFuncao
      ref="apagarRef"
      :pessoas-da="pessoasDa"
      :estado-das-pessoas="estadoDasPessoas"
      :apagar="apagar"
      :foco-de-reserva="TITULO"
      @tentar-pessoas="carregarPessoas"
    />
    <GavetaDaFuncao
      v-if="gaveta"
      :funcao="gaveta.funcao"
      @fechar="fecharGaveta"
    />
  </section>
</template>
