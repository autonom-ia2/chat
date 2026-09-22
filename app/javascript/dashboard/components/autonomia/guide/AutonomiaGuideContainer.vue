<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize, useEventListener } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import {
  useAutonomiaGuideStore,
  motivoUtilizavel,
} from 'dashboard/store/modules/autonomiaGuide';
import {
  isGuideRoute,
  guideRouteFeature,
} from 'dashboard/helper/guideRouteRegistry';
import { guideRouteParams } from 'dashboard/helper/guideNavigation';
import { useGuideHighlight } from 'dashboard/store/modules/guideHighlight';

import GuideHeader from './GuideHeader.vue';
import GuideComposer from './GuideComposer.vue';
import CopilotAgentMessage from 'dashboard/components-next/copilot/CopilotAgentMessage.vue';
import CopilotAssistantMessage from 'dashboard/components-next/copilot/CopilotAssistantMessage.vue';
import CopilotLoader from 'dashboard/components-next/copilot/CopilotLoader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// V1 — global "Guia da Plataforma" widget. Reuses the copilot presentational pieces but is NOT
// conversation-scoped: a single global thread that guides the user (onboarding/support) and, when
// the backend returns a `navigation` target, offers a button that takes the user to that screen
// (validated against the guide route allow-list + the router + the route guards). It ALSO executes
// the actions the backend proposes — but never on its own: só depois de a pessoa ler o que vai
// acontecer e clicar em confirmar.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const { uiSettings, updateUISettings } = useUISettings();
const currentAccount = useMapGetter('accounts/getAccount');
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// Tela que exige feature da conta não ganha botão quando a feature está desligada:
// o Guia nunca oferece uma tela que o backend nega. A relação tela→feature é
// gerada junto com o mapa (#534) — mantê-la à mão deixava de fora toda feature
// que alguém esquecesse de listar.
const { width: windowWidth } = useWindowSize();

const store = useAutonomiaGuideStore();
const { messages } = store;
const guideHighlight = useGuideHighlight();

const isSending = ref(false);
const chatContainer = ref(null);
const panelRef = ref(null);

// Estados em que a ação está parada e pode (re)começar. "cancelada" entra aqui
// de propósito: "Agora não" não destrói nada — nada foi executado —, e deixá-lo
// definitivo obrigava a pessoa a reescrever a pergunta inteira só para voltar
// atrás. O texto de cancelamento continua visível, então o cartão não finge que
// o clique não aconteceu.
const ESTADOS_PARADOS = ['aguardando', 'cancelada'];

const podeConfirmar = estado => ESTADOS_PARADOS.includes(estado);
const mostraBotoes = estado => podeConfirmar(estado) || estado === 'executando';

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const isEnabled = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const isPanelOpen = computed(
  () => uiSettings.value.is_autonomia_guide_panel_open === true
);

const showPanel = computed(() => isEnabled.value && isPanelOpen.value);

const hasMessages = computed(() => messages.length > 0);

const suggestions = computed(() => [
  t('AUTONOMIA_GUIDE.SUGGESTIONS.KANBAN'),
  t('AUTONOMIA_GUIDE.SUGGESTIONS.WHATSAPP'),
  t('AUTONOMIA_GUIDE.SUGGESTIONS.REPORTS'),
]);

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const closePanel = () => {
  updateUISettings({
    is_autonomia_guide_panel_open: false,
    is_contact_sidebar_open: false,
  });
};

const handleClickOutside = () => {
  if (isSmallScreen.value && isPanelOpen.value) closePanel();
};

// Resolve a backend `navigation` to a real router location, or null. Defense-in-depth: the route must
// be in the guide allow-list AND resolve cleanly (router.resolve THROWS on a missing required param,
// so a screen of ONE record without its id renders NO button instead of a dead one). The ids come
// from the model, which read the account (#590). The route guards still enforce the user's
// permission on push.
const navLocation = nav => {
  if (!nav?.route_name || !isGuideRoute(nav.route_name)) return null;
  const requiredFeature = guideRouteFeature(nav.route_name);
  if (
    requiredFeature &&
    !isFeatureEnabledonAccount.value(accountId.value, requiredFeature)
  ) {
    return null; // feature off → no button (backend would 404 the screen)
  }
  try {
    const target = accountScopedRoute(
      nav.route_name,
      guideRouteParams(nav.params)
    );
    const resolved = router.resolve(target);
    return resolved?.matched?.length ? target : null;
  } catch {
    return null; // unknown route or missing required param
  }
};

// Esta função não age sobre nada: só move a pessoa até a tela e (V2) destaca o
// elemento de lá. Quem executa ação é `confirmarAcao`, mais abaixo.
const navigateTo = nav => {
  const target = navLocation(nav);
  if (!target) return;
  router.push(target);
  if (nav.highlight) {
    // Close the chat panel so the highlighted element is fully visible (the right-docked panel would
    // otherwise cover right-aligned action buttons). Trigger AFTER the close transition so the element
    // is at its final position. The thread is preserved — reopening the Guia shows it again.
    const anchor = nav.highlight;
    closePanel();
    setTimeout(() => guideHighlight.show(anchor), 320);
  } else if (isSmallScreen.value) {
    closePanel();
  }
};

// O cartão da ação é o único lugar onde o desfecho aparece. Quando ele já não
// existe — a pessoa trocou de conta ou clicou em "Nova conversa" durante os
// segundos da execução —, a ação JÁ rodou no servidor e o resultado não pode
// simplesmente sumir: vira alerta.
const entregarDesfecho = ({ conta, id, estado, resultado, avisoSeSumiu }) => {
  const mesmaConta = accountId.value === conta;
  if (mesmaConta && store.marcarAcao(id, estado, resultado)) return;
  useAlert(avisoSeSumiu);
};

// A execução acontece aqui, e só aqui: depois de a pessoa ler a descrição e
// clicar em confirmar. O backend recusa de novo o que estiver fora do catálogo.
const confirmarAcao = async item => {
  // Porta de entrada única: `marcarAcao` muda o estado de forma síncrona, então
  // o segundo clique de um duplo-clique já encontra 'executando' e volta sem
  // disparar um segundo POST. Antes, dois cliques criavam dois registros.
  if (!podeConfirmar(item.acaoEstado)) return;
  // Mesma proteção de conta que o chat tem: a resposta pode levar segundos, e
  // o desfecho não pode cair na conversa de outra conta.
  const conta = accountId.value;
  store.marcarAcao(item.id, 'executando');
  try {
    const { data } = await AutonomiaGuideAPI.executarAcao({
      acao: item.acao.nome,
      dados: item.acao.dados,
    });
    entregarDesfecho({
      conta,
      id: item.id,
      estado: 'feita',
      resultado: data.mensagem,
      avisoSeSumiu: t('AUTONOMIA_GUIDE.ACTION.LOST'),
    });
  } catch (error) {
    const texto =
      motivoUtilizavel(error?.response?.data?.error) ||
      t('AUTONOMIA_GUIDE.ACTION.FAILED_GENERIC');
    entregarDesfecho({
      conta,
      id: item.id,
      estado: 'falhou',
      resultado: texto,
      // Aqui a ação não rodou, então o aviso é o próprio motivo da falha —
      // dizer "executou mas você saiu" seria mentira.
      avisoSeSumiu: texto,
    });
  }
};

// #572 — o Guia responde num job, e a tela busca a resposta. Antes ela vinha da
// própria requisição, que o servidor mata aos 15 segundos: pergunta que pedia
// duas leituras morria com erro 500.
//
// O tempo total de busca fica acima do teto de trabalho do Guia (180s no
// servidor), para a tela nunca desistir de uma resposta que ainda vai chegar.
const ESPERA_ENTRE_BUSCAS_MS = 1500;
const MAX_BUSCAS = 140;
const PENDENTE = 'pending';
const PRONTO = 'done';

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// Quem desmonta o painel não quer mais a resposta.
let desmontado = false;
onBeforeUnmount(() => {
  desmontado = true;
});

// Recursiva, e não um laço: cada busca espera a anterior, e a próxima só sai
// depois do intervalo — nunca duas no ar ao mesmo tempo.
//
// Para sozinha quando a resposta deixou de interessar: o painel saiu da tela,
// ou a pessoa trocou de conta. Sem isso a tela seguia consultando por até três
// minutos uma resposta que não ia mostrar a ninguém. -> null quando parou.
const buscarResposta = async (id, requestAccount, tentativa = 0) => {
  if (tentativa >= MAX_BUSCAS) return { status: 'failed' };
  await esperar(ESPERA_ENTRE_BUSCAS_MS);
  if (desmontado || accountId.value !== requestAccount) return null;
  const { data } = await AutonomiaGuideAPI.resposta(id);
  if (data.status !== PENDENTE) return data;
  return buscarResposta(id, requestAccount, tentativa + 1);
};

// A falha fica ESCRITA na conversa. Antes era um aviso que sumia sozinho em
// poucos segundos: quem olhava para a tela depois via a pergunta sem resposta
// nenhuma, e não tinha como saber que devia tentar de novo.
const avisarFalha = () =>
  store.addAssistantMessage({ content: t('AUTONOMIA_GUIDE.ERROR') });

const requestReply = async (requestAccount, message) => {
  try {
    const { data: pedido } = await AutonomiaGuideAPI.chat({
      message,
      history: store.toHistory(),
      routeContext: route.name,
    });
    const data = await buscarResposta(pedido.id, requestAccount);
    if (!data || accountId.value !== requestAccount) return;
    if (data.status !== PRONTO) {
      avisarFalha();
    } else if (data.available && data.text) {
      store.addAssistantMessage({
        content: data.text,
        navigation: data.navigation || null,
        acao: data.acao || null,
      });
    } else if (data.retido) {
      // O Guia está no ar e entendeu — só não está seguro o bastante para
      // afirmar. Dizer "indisponível" aqui faz a pessoa achar que o produto
      // caiu, e some com a oferta de suporte que é o próximo passo útil.
      store.addAssistantMessage({ content: t('AUTONOMIA_GUIDE.WITHHELD') });
    } else {
      useAlert(t('AUTONOMIA_GUIDE.UNAVAILABLE'));
    }
  } catch {
    if (accountId.value !== requestAccount) return;
    avisarFalha();
  } finally {
    isSending.value = false;
  }
};

// GuideComposer clears the field only when this returns true. Accept = the question is in the
// thread, so return right away and let the reply load behind the loader; false keeps the text.
const sendMessage = message => {
  if (!message?.trim()) return false;
  if (isSending.value) {
    // Antes a segunda pergunta não fazia nada e não avisava nada.
    useAlert(t('AUTONOMIA_GUIDE.SENDING'));
    return false;
  }
  // Pin the account this request belongs to: if the user switches accounts before the reply lands,
  // the late response must NOT be appended into the now-current account's thread (cross-account leak).
  const requestAccount = accountId.value;
  store.addUserMessage(message);
  isSending.value = true;
  requestReply(requestAccount, message);
  return true;
};

// Só o número de mensagens não basta: o desfecho da ação ("Pronto, feito.")
// entra num cartão que já existe, sem criar mensagem nenhuma, e ficava abaixo
// da dobra. A assinatura abaixo muda também quando o estado da ação muda.
const scrollSignal = computed(() =>
  messages
    .map(
      item => `${item.id}:${item.acaoEstado || ''}:${item.acaoResultado || ''}`
    )
    .join('|')
);

watch([scrollSignal, isSending], () => scrollToBottom());

// Esc fecha o painel de onde quer que o foco esteja (o painel é uma região
// lateral, não um modal, então o foco pode estar fora dele).
useEventListener(document, 'keydown', event => {
  if (event.key !== 'Escape' || !showPanel.value) return;
  closePanel();
});

// Ao abrir, o foco vai para a região — que tem nome — em vez de continuar no
// lançador, que some. Fechar devolve o foco ao lançador, e isso é feito lá,
// quando ele reaparece.
watch(showPanel, async aberto => {
  if (!aberto) return;
  await nextTick();
  panelRef.value?.focus();
});

// The guide thread is a global module-level singleton; clear it when switching accounts so the
// previous account's conversation never lingers on screen for a different account/operator.
watch(accountId, () => store.reset());
</script>

<template>
  <div
    v-if="showPanel"
    ref="panelRef"
    v-on-click-outside="handleClickOutside"
    role="complementary"
    tabindex="-1"
    :aria-label="$t('AUTONOMIA_GUIDE.A11Y.PANEL')"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none flex focus:outline-none"
  >
    <div class="flex flex-col h-full text-sm leading-6 tracking-tight w-full">
      <GuideHeader
        :title="$t('AUTONOMIA_GUIDE.TITLE')"
        :can-reset="hasMessages"
        @reset="store.reset()"
        @close="closePanel"
      />

      <div
        ref="chatContainer"
        role="log"
        aria-live="polite"
        :aria-busy="isSending ? 'true' : 'false'"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.LOG')"
        class="flex-1 flex px-4 py-4 overflow-y-auto items-start"
      >
        <div v-if="hasMessages" class="space-y-6 flex-1 flex flex-col w-full">
          <template v-for="(item, index) in messages" :key="item.id">
            <CopilotAgentMessage
              v-if="item.message_type === 'user'"
              :message="item.message"
            />
            <div v-else class="flex flex-col gap-2 w-full">
              <CopilotAssistantMessage
                :message="item.message"
                :is-last-message="index === messages.length - 1"
                :sender-name="$t('AUTONOMIA_GUIDE.TITLE')"
              />
              <!-- Ação proposta: a pessoa lê o que vai acontecer, com os valores,
                   e só então confirma. Nada executa antes disso. -->
              <div
                v-if="item.acao"
                class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2"
              >
                <p class="mb-0 text-sm break-words text-n-slate-12">
                  {{ item.acao.descricao.frase }}
                </p>
                <!-- O pedido literal, sempre visível: a frase acima pode
                     suavizar, isto não. É o que torna a confirmação informada —
                     por isso não fica no menor texto do cartão. -->
                <p class="mb-0 text-sm break-words text-n-slate-11">
                  {{ item.acao.descricao.detalhe }}
                </p>
                <p
                  v-if="item.acao.descricao.aviso"
                  class="mb-0 text-sm font-medium break-words text-n-ruby-11"
                >
                  {{ item.acao.descricao.aviso }}
                </p>
                <!-- Cada estado tem o seu próprio ramo, nomeado. A primeira
                     versão usava `v-else` para "cancelada", então o estado
                     "executando" caía nele: quem clicava em Confirmar lia
                     "Você cancelou esta ação" enquanto a ação rodava. -->
                <p
                  v-if="item.acaoEstado === 'executando'"
                  class="flex items-center gap-2 mb-0 text-sm text-n-slate-11"
                >
                  <span class="i-svg-spinner size-4 shrink-0" />
                  {{ $t('AUTONOMIA_GUIDE.ACTION.RUNNING') }}
                </p>
                <p
                  v-else-if="item.acaoEstado === 'cancelada'"
                  class="mb-0 text-sm text-n-slate-11"
                >
                  {{ $t('AUTONOMIA_GUIDE.ACTION.CANCELLED') }}
                </p>
                <p
                  v-else-if="item.acaoResultado"
                  class="mb-0 text-sm font-medium break-words"
                  :class="
                    item.acaoEstado === 'feita'
                      ? 'text-n-teal-11'
                      : 'text-n-ruby-11'
                  "
                >
                  {{ item.acaoResultado }}
                </p>
                <div
                  v-if="mostraBotoes(item.acaoEstado)"
                  class="flex flex-wrap gap-2"
                >
                  <Button
                    :label="$t('AUTONOMIA_GUIDE.ACTION.CONFIRM')"
                    :disabled="item.acaoEstado === 'executando'"
                    class="min-h-11"
                    blue
                    @click="confirmarAcao(item)"
                  />
                  <Button
                    v-if="item.acaoEstado !== 'cancelada'"
                    :label="$t('AUTONOMIA_GUIDE.ACTION.CANCEL')"
                    :disabled="item.acaoEstado === 'executando'"
                    class="min-h-11"
                    slate
                    faded
                    @click="store.marcarAcao(item.id, 'cancelada')"
                  />
                </div>
              </div>

              <!-- O rótulo vinha do título do fluxo, escrito para o manual e
                   longo demais para um painel estreito: ele estourava a largura
                   e levava a seta junto, deixando o botão com cara de texto
                   solto. Agora é frase curta e fixa, e o que sobrar é cortado. -->
              <Button
                v-if="navLocation(item.navigation)"
                :label="$t('AUTONOMIA_GUIDE.GO_TO_SCREEN')"
                icon="i-lucide-arrow-right"
                trailing-icon
                blue
                faded
                class="self-start max-w-full min-h-11 [&>span]:truncate"
                @click="navigateTo(item.navigation)"
              />
            </div>
          </template>
          <CopilotLoader
            v-if="isSending"
            :label="$t('AUTONOMIA_GUIDE.THINKING')"
          />
        </div>
        <div v-else class="flex-1 flex flex-col gap-3 px-1 py-2">
          <h3 class="text-base font-medium text-n-slate-12 leading-7">
            {{ $t('AUTONOMIA_GUIDE.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-6">
            {{ $t('AUTONOMIA_GUIDE.KICK_OFF') }}
          </p>
          <div class="flex flex-col gap-2 mt-2">
            <button
              v-for="(suggestion, i) in suggestions"
              :key="i"
              :disabled="isSending"
              class="text-left text-sm text-n-slate-12 bg-n-alpha-1 hover:bg-n-alpha-2 rounded-lg px-3 py-2 min-h-11 transition-colors disabled:cursor-not-allowed disabled:opacity-60"
              @click="sendMessage(suggestion)"
            >
              {{ suggestion }}
            </button>
          </div>
        </div>
      </div>

      <div class="mx-3 mt-px mb-2">
        <GuideComposer
          class="mb-1 w-full"
          :is-busy="isSending"
          @send="sendMessage"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>
