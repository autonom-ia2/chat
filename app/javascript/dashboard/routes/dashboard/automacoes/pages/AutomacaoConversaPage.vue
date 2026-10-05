<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import AutonomiaGuideContainer from 'dashboard/components/autonomia/guide/AutonomiaGuideContainer.vue';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import AutomacaoResumo from '../components/AutomacaoResumo.vue';
import AutomacaoEnsaio from '../components/AutomacaoEnsaio.vue';
import AutomacaoEtapas from '../components/AutomacaoEtapas.vue';
import { MODELOS, modeloExiste } from '../modelos';
import { useNomesDaConta } from '../composables/useNomesDaConta';
import {
  passoCriouAutomacao,
  passoMexeuEmAutomacao,
} from '../composables/useCriadasPeloGuia';

// #859/#982 — nova automação ou uma já existente, montada conversando com o
// Guia. À esquerda a conversa (a mesma do painel lateral, embutida); à direita a
// automação ao vivo — Quando → Só se → Faz, a prévia da mensagem, o que teria
// acontecido nas conversas recentes e o botão Ligar. No topo, as etapas Conte →
// Confira → Ligue.
//
// Que a automação nasce desligada nesta tela é instrução do Guia (porques.md,
// bloco `criar_automacao_conversando`), não regra no código.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const currentAccount = useMapGetter('accounts/getAccount');
const podeMudar = useCanManage('automation_manage');
const { nomes, carregarNomes } = useNomesDaConta();

const regraId = computed(() => {
  const id = Number(route.params.id);
  return Number.isInteger(id) && id > 0 ? id : null;
});

// Com id na rota, a tela já nasce carregando: sem piscar o resumo vazio antes.
const estado = ref(regraId.value ? 'carregando' : 'pronto');
const regra = ref(null);
const ligando = ref(false);

const guiaLigado = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const carregar = async () => {
  if (!regraId.value) {
    regra.value = null;
    estado.value = 'pronto';
    return;
  }
  // Recarregar depois de uma resposta do Guia não pisca: o resumo antigo fica
  // até o novo chegar.
  if (!regra.value || regra.value.id !== regraId.value) {
    estado.value = 'carregando';
  }
  try {
    const { data } = await AutomationAPI.show(regraId.value);
    regra.value = data?.payload || null;
    estado.value = regra.value ? 'pronto' : 'erro';
  } catch {
    regra.value = null;
    estado.value = 'erro';
  }
};

onMounted(() => {
  carregarNomes();
  carregar();
});
watch(regraId, carregar);

const descricao = computed(() =>
  regra.value
    ? descreverAutomacao(regra.value, { t, nomes: nomes.value })
    : null
);

const titulo = computed(() => {
  if (!regraId.value) return t('AUTOMACOES.CONVERSA.TITULO_NOVA');
  return regra.value?.name || t('AUTOMACOES.CONVERSA.TITULO_EDITAR');
});

const sugestoes = computed(() =>
  MODELOS.map(modelo => ({
    rotulo: t(`AUTOMACOES.MODELOS.${modelo.chave}.TITULO`),
    pergunta: t(`AUTOMACOES.MODELOS.${modelo.chave}.PEDIDO`),
  }))
);

// O que a pessoa pediu na lista vira a primeira pergunta ao Guia: o modelo
// escolhido (chave conhecida, na URL) ou o texto que ela escreveu (no estado da
// navegação, que só a própria tela preenche — um link de fora não manda pedido
// ao Guia em nome de ninguém).
const MAX_PEDIDO = 5000;
const pedidoEscrito = ref(
  typeof window.history.state?.pedidoAutomacao === 'string'
    ? window.history.state.pedidoAutomacao.slice(0, MAX_PEDIDO)
    : ''
);
// A pessoa tocou no microfone na lista: a conversa abre gravando. Vale uma vez.
const comecarPorVoz = ref(window.history.state?.pedidoPorVoz === true);
if (comecarPorVoz.value) {
  const { pedidoPorVoz, ...restoDoEstado } = window.history.state || {};
  window.history.replaceState(restoDoEstado, '');
}

// Os prints e arquivos que a pessoa juntou na lista (só File de verdade).
const anexosIniciais = ref(
  Array.isArray(window.history.state?.anexosAutomacao)
    ? window.history.state.anexosAutomacao.filter(item => item instanceof File)
    : []
);

const pedidoInicial = computed(() => {
  if (regraId.value) return '';
  const modelo = String(route.query.modelo || '');
  if (modeloExiste(modelo)) return t(`AUTOMACOES.MODELOS.${modelo}.PEDIDO`);
  return pedidoEscrito.value;
});

// O modelo vale uma pergunta só. Saiu, sai também da URL: a tela que nasce de
// novo (o Guia mudou a conta e o painel é remontado, ou a pessoa recarregou)
// não manda o mesmo pedido outra vez.
const gastarModelo = () => {
  if (pedidoEscrito.value || anexosIniciais.value.length) {
    pedidoEscrito.value = '';
    anexosIniciais.value = [];
    const { pedidoAutomacao, anexosAutomacao, ...restoDoEstado } =
      window.history.state || {};
    window.history.replaceState(restoDoEstado, '');
  }
  if (!route.query.modelo) return;
  const { modelo, ...resto } = route.query;
  router.replace({ name: route.name, params: route.params, query: resto });
};

// Depois de cada resposta: o Guia criou a automação → a tela passa a ser a dela;
// mexeu numa automação → o resumo é lido de novo.
const aoExecutar = execucao => {
  const passos = execucao?.passos || [];
  const criada = passos.find(passoCriouAutomacao);
  if (criada && !regraId.value) {
    router.replace({
      name: 'automacoes_editar',
      params: { accountId: accountId.value, id: criada.registro },
    });
    return;
  }
  if (passos.some(passoMexeuEmAutomacao)) carregar();
};

// Respostas de um toque depois da fala do Guia, enquanto a automação está
// montada e desligada. "Está ótima" não gasta pergunta: leva ao botão Ligar.
const ligarRef = ref(null);
const temMensagem = computed(() =>
  (regra.value?.actions || []).some(acao => acao.action_name === 'send_message')
);
const respostasRapidas = computed(() => {
  if (!regra.value || regra.value.active) return [];
  const otima = {
    chave: 'OTIMA',
    rotulo: t('AUTOMACOES.RESPOSTAS.OTIMA'),
  };
  if (!temMensagem.value) {
    return [
      otima,
      {
        chave: 'MUDAR',
        rotulo: t('AUTOMACOES.RESPOSTAS.MUDAR'),
        pergunta: t('AUTOMACOES.RESPOSTAS.MUDAR_PEDIDO'),
      },
    ];
  }
  return [
    otima,
    {
      chave: 'CURTA',
      rotulo: t('AUTOMACOES.RESPOSTAS.CURTA'),
      pergunta: t('AUTOMACOES.RESPOSTAS.CURTA_PEDIDO'),
    },
    {
      chave: 'ESCREVER',
      rotulo: t('AUTOMACOES.RESPOSTAS.ESCREVER'),
      pergunta: t('AUTOMACOES.RESPOSTAS.ESCREVER_PEDIDO'),
    },
  ];
});

const aoResponderRapido = chave => {
  if (chave !== 'OTIMA') return;
  const botao = ligarRef.value?.$el;
  botao?.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
  botao?.focus?.();
};

// Conte (sem automação) → Confira (montada, desligada) → Ligue (ligada).
const etapa = computed(() => {
  if (!regra.value) return 1;
  return regra.value.active ? 3 : 2;
});

const voltar = () =>
  router.push({
    name: 'automacoes_lista',
    params: { accountId: accountId.value },
  });

const modoManual = () =>
  router.push({
    name: 'automation_list',
    params: { accountId: accountId.value },
    query: regraId.value ? { editar: regraId.value } : {},
  });

const mudarLigada = async ligar => {
  if (!regra.value || ligando.value) return;
  ligando.value = true;
  try {
    await AutomationAPI.update(regra.value.id, { active: ligar });
    regra.value = { ...regra.value, active: ligar };
    useAlert(
      ligar ? t('AUTOMACOES.LISTA.LIGOU') : t('AUTOMACOES.LISTA.DESLIGOU')
    );
  } catch {
    useAlert(t('AUTOMACOES.LISTA.FALHA_TROCA'));
  } finally {
    ligando.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-7 px-5 py-6 mx-auto max-w-7xl md:px-8 md:py-8"
      >
        <header class="flex flex-col gap-4">
          <button
            type="button"
            data-voltar
            class="inline-flex items-center self-start gap-2 text-[0.9375rem] rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="voltar"
          >
            <span
              class="i-lucide-arrow-left size-5 rtl:rotate-180"
              aria-hidden="true"
            />
            {{ $t('AUTOMACOES.CONVERSA.VOLTAR') }}
          </button>
          <div class="flex flex-wrap items-center justify-between gap-5">
            <h1
              class="text-3xl font-bold tracking-tight break-words text-n-slate-12"
            >
              {{ titulo }}
            </h1>
            <AutomacaoEtapas
              :atual="etapa"
              :concluida="Boolean(regra && regra.active)"
            />
          </div>
        </header>

        <div
          class="grid gap-7 lg:grid-cols-[minmax(0,1fr)_minmax(0,27rem)] items-start"
        >
          <div class="flex flex-col min-w-0 gap-3">
            <div
              v-if="guiaLigado"
              data-conversa
              class="flex flex-col overflow-hidden border shadow-sm rounded-3xl border-n-weak bg-n-solid-1"
            >
              <div
                class="flex items-center gap-3 px-5 py-4 border-b border-n-weak"
              >
                <span
                  class="grid rounded-xl place-items-center size-10 bg-[#0D2344] text-n-blue-6"
                >
                  <span class="i-lucide-sparkles size-5" aria-hidden="true" />
                </span>
                <div class="min-w-0">
                  <p class="mb-0 text-base font-semibold text-n-slate-12">
                    {{ $t('AUTOMACOES.CONVERSA.GUIA_NOME') }}
                  </p>
                  <p class="mb-0 text-sm text-n-slate-11">
                    {{ $t('AUTOMACOES.CONVERSA.GUIA_SUBTITULO') }}
                  </p>
                </div>
              </div>
              <div class="h-[38rem] [&>*]:!rounded-none [&>*]:!border-0">
                <AutonomiaGuideContainer
                  embutido
                  sem-telas
                  :sugestoes="sugestoes"
                  :introducao="$t('AUTOMACOES.CONVERSA.INTRO_GUIA')"
                  :pedido-inicial="pedidoInicial"
                  :respostas-rapidas="respostasRapidas"
                  :comecar-por-voz="comecarPorVoz"
                  :anexos-iniciais="anexosIniciais"
                  @resposta-rapida="aoResponderRapido"
                  @execucao="aoExecutar"
                  @pedido-inicial-enviado="gastarModelo"
                />
              </div>
            </div>
            <div
              v-else
              data-guia-fora
              class="flex flex-col items-start gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
            >
              <p class="mb-0 text-base text-n-slate-12">
                {{ $t('AUTOMACOES.CONVERSA.GUIA_FORA') }}
              </p>
              <Button
                v-if="podeMudar"
                :label="$t('AUTOMACOES.CONVERSA.MONTAR_MANUAL')"
                icon="i-lucide-sliders-horizontal"
                slate
                faded
                class="min-h-11"
                @click="modoManual"
              />
            </div>
          </div>

          <aside class="flex flex-col min-w-0 gap-5">
            <div
              v-if="estado === 'carregando'"
              data-carregando
              aria-busy="true"
              class="flex flex-col gap-4"
            >
              <span class="sr-only">
                {{ $t('AUTOMACOES.CONVERSA.CARREGANDO') }}
              </span>
              <div class="h-72 rounded-3xl bg-n-alpha-2 animate-pulse" />
              <div class="h-40 rounded-3xl bg-n-alpha-2 animate-pulse" />
            </div>

            <div
              v-else-if="estado === 'erro'"
              data-erro
              role="alert"
              class="flex flex-col items-start gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
            >
              <p class="mb-0 text-base text-n-slate-12">
                {{ $t('AUTOMACOES.CONVERSA.ERRO') }}
              </p>
              <Button
                :label="$t('AUTOMACOES.CONVERSA.VOLTAR')"
                slate
                faded
                class="min-h-11"
                @click="voltar"
              />
            </div>

            <template v-else>
              <AutomacaoResumo :descricao="descricao" :regra="regra" />

              <template v-if="regra">
                <AutomacaoEnsaio
                  :key="regra.id"
                  :regra-id="regra.id"
                  :account-id="accountId"
                  :automatico="!regra.active"
                />

                <template v-if="podeMudar">
                  <div v-if="!regra.active" class="flex flex-col gap-2.5">
                    <Button
                      ref="ligarRef"
                      data-ligar
                      :label="$t('AUTOMACOES.CONVERSA.LIGAR')"
                      icon="i-lucide-power"
                      teal
                      size="lg"
                      justify="center"
                      class="w-full !min-h-14 !text-lg !font-bold !rounded-2xl shadow-lg"
                      :is-loading="ligando"
                      :disabled="ligando"
                      @click="mudarLigada(true)"
                    />
                    <p
                      data-situacao
                      class="mb-0 text-sm text-center text-n-slate-11"
                    >
                      {{ $t('AUTOMACOES.CONVERSA.DESLIGADA_AVISO') }}
                    </p>
                  </div>
                  <div
                    v-else
                    data-ligada
                    role="status"
                    class="flex items-center gap-4 p-5 rounded-2xl bg-n-teal-3"
                  >
                    <span
                      class="grid text-white rounded-full place-items-center size-10 shrink-0 bg-n-teal-10"
                    >
                      <span class="i-lucide-check size-5" aria-hidden="true" />
                    </span>
                    <div class="flex-1 min-w-0">
                      <p class="mb-0 text-base font-semibold text-n-teal-12">
                        {{ $t('AUTOMACOES.CONVERSA.LIGADA_TITULO') }}
                      </p>
                      <p
                        data-situacao
                        class="mb-0 text-[0.9375rem] text-n-teal-11"
                      >
                        {{ $t('AUTOMACOES.CONVERSA.LIGADA_AVISO') }}
                      </p>
                    </div>
                    <Button
                      data-desligar
                      :label="$t('AUTOMACOES.CONVERSA.DESLIGAR')"
                      teal
                      link
                      class="min-h-11 shrink-0 !font-semibold"
                      :is-loading="ligando"
                      :disabled="ligando"
                      @click="mudarLigada(false)"
                    />
                  </div>
                </template>
                <p
                  v-else
                  class="mb-0 p-4 text-[0.9375rem] rounded-2xl bg-n-alpha-1 text-n-slate-11"
                >
                  {{ $t('AUTOMACOES.CONVERSA.SO_LEITURA') }}
                </p>

                <Button
                  data-modo-manual
                  :label="$t('AUTOMACOES.CONVERSA.MODO_MANUAL')"
                  icon="i-lucide-sliders-horizontal"
                  link
                  slate
                  class="self-center min-h-11"
                  @click="modoManual"
                />
              </template>
              <Button
                v-else-if="podeMudar && guiaLigado"
                data-modo-manual
                :label="$t('AUTOMACOES.CONVERSA.MONTAR_MANUAL')"
                icon="i-lucide-sliders-horizontal"
                link
                slate
                class="self-center min-h-11"
                @click="modoManual"
              />
            </template>
          </aside>
        </div>
      </div>
    </main>
  </section>
</template>
