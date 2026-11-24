<script setup>
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert, useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { COPILOT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { useAutonomiaCopilotStore } from 'dashboard/store/modules/autonomiaCopilot';
import {
  MAX_ANEXOS_POR_CONVERSA,
  motivoUtilizavel,
} from 'dashboard/store/modules/autonomiaGuide';
import { useLarguraDoGuia } from 'dashboard/components/autonomia/guide/useLarguraDoGuia';
import { menuEGuia } from 'dashboard/components-next/sidebar/menuEGuia';

import Button from 'dashboard/components-next/button/Button.vue';
import CopilotHeader from './CopilotHeader.vue';
import GuideComposer from 'dashboard/components/autonomia/guide/GuideComposer.vue';
import GuideUserMessage from 'dashboard/components/autonomia/guide/GuideUserMessage.vue';
import GuideResposta from 'dashboard/components/autonomia/guide/GuideResposta.vue';

// V2.3 — "Copiloto Autonom.ia": a equipe conversa, dentro de uma conversa com cliente, com os
// agentes internos/both da conta. Gated pelas flags do kanban + copiloto, com chaves próprias de
// uiSetting. Independe do Captain.
// #3191 — mesmo desenho e mesma largura do Guia (#3184): balão azul de quem pergunta, resposta em
// cartão sem bico com a foto do agente, "Novo assunto" escrito e caixa de pergunta do Guia. Abrir
// recolhe o menu sem gravar preferência (menuEGuia.js). Guia e copiloto não ficam abertos juntos:
// seriam três colunas ao lado da conversa.
// #3198 — a equipe manda foto, documento e áudio ao copiloto, como no Guia: o arquivo sobe pelo
// endpoint do Guia e vai com cada pergunta do assunto; o áudio vira texto antes da pergunta.
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const globalConfig = useMapGetter('globalConfig/get');
const currentChat = useMapGetter('getSelectedChat');
const currentAccountId = useMapGetter('getCurrentAccountId');
const { width: windowWidth } = useWindowSize();

const store = useAutonomiaCopilotStore();
const { messages } = store;

const agents = ref([]);
const selectedAgentId = ref(null);
const isSending = ref(false);
// A mensagem de voz está virando texto; a resposta ainda não foi pedida.
const transcrevendo = ref(false);
// Há gravação no campo: nenhuma outra mensagem sai até ela ser enviada ou apagada.
const gravandoVoz = ref(false);
const chatContainer = ref(null);
let requestSequence = 0;
let agentsRequestSequence = 0;

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const isEnabled = computed(
  () =>
    globalConfig.value?.crmKanbanEnabled === true &&
    globalConfig.value?.crmCopilotEnabled === true
);

const isPanelOpen = computed(
  () => uiSettings.value.is_autonomia_copilot_panel_open === true
);

const isGuideOpen = computed(
  () => uiSettings.value.is_autonomia_guide_panel_open === true
);

const conversationDisplayId = computed(() => currentChat.value?.id);

// Só DENTRO de uma conversa: o copiloto agora é acessado pelo switch da conversa (SidepanelSwitch),
// não mais por um botão flutuante global.
const showPanel = computed(
  () => isEnabled.value && isPanelOpen.value && !!conversationDisplayId.value
);

const hasAgents = computed(() => agents.value.length > 0);
// Os anexos que esperam o próximo envio, e quantos ainda cabem no assunto (o que falhou não conta).
const pendentes = computed(() => store.arquivosPendentes());
const vagas = computed(
  () =>
    MAX_ANEXOS_POR_CONVERSA -
    store.arquivos.filter(arquivo => arquivo.estado !== 'erro').length
);
const hasMessages = computed(() => messages.length > 0);

const activeAgent = computed(() => {
  const preferred = agents.value.find(a => a.id === selectedAgentId.value);
  return preferred || agents.value[0] || null;
});

const panelTitle = computed(
  () => activeAgent.value?.name || t('AUTONOMIA_COPILOT.TITLE')
);

const fotoDoAgente = computed(() => activeAgent.value?.avatar_url || '');

// Os três pedidos de sempre da equipe, num toque (o mesmo trio do teste do copiloto).
const sugestoes = computed(() => [
  t('AUTONOMIA_COPILOT.SUGGESTIONS.SUMMARY'),
  t('AUTONOMIA_COPILOT.SUGGESTIONS.NEXT_STEP'),
  t('AUTONOMIA_COPILOT.SUGGESTIONS.DRAFT'),
]);

// #3191 — mesma largura do Guia; o copiloto avisa o menu, que recolhe sem gravar.
// Avisa quando a pessoa ABRE o copiloto (a chave liga), não a cada volta a uma conversa: o
// painel some e reaparece com a conversa, e recolher de novo o menu que ela reabriu seria brigar
// com o clique dela. Ao carregar a página, vale o painel na tela.
const { estilo: estiloDoPainel } = useLarguraDoGuia({
  embutido: false,
  larguraDaTela: windowWidth,
});
menuEGuia.copilotoAberto.value = showPanel.value;
watch(isPanelOpen, aberto => {
  menuEGuia.copilotoAberto.value = aberto && showPanel.value;
});

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const closePanel = () => {
  // Fechar o copiloto volta ao painel de contato da conversa (não deixa o lado direito vazio).
  updateUISettings({
    is_autonomia_copilot_panel_open: false,
    is_contact_sidebar_open: true,
  });
};

const handleClickOutside = () => {
  if (isSmallScreen.value && isPanelOpen.value) closePanel();
};

// Larga o pedido em curso (a resposta ou a transcrição que chegar depois é descartada) e o assunto.
const largarPedido = () => {
  requestSequence += 1;
  isSending.value = false;
  transcrevendo.value = false;
  store.reset();
};

const resetConversation = largarPedido;

// O Guia abriu: o copiloto fecha. Só a chave dele: reabrir o contato ao lado do Guia daria as
// três colunas que se quer evitar (quem abre o Guia já cuida do contato).
watch(isGuideOpen, aberto => {
  if (aberto && isPanelOpen.value) {
    updateUISettings({ is_autonomia_copilot_panel_open: false });
  }
});

// "Usar esta resposta": só na última fala, e só quando o agente a escreveu como resposta ao
// cliente. Entra pela caixa rica para o markdown virar parágrafos.
const podeUsar = (item, index) =>
  Boolean(item.message?.content && item.message?.reply_suggestion) &&
  index === messages.length - 1;

const usarResposta = item => {
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, item.message.content);
  useTrack(COPILOT_EVENTS.USE_CAPTAIN_RESPONSE);
  useAlert(t('AUTONOMIA_COPILOT.INSERTED'));
};

// Default agent = the inbox's linked agent when it is internal/both, else the first agent.
// The remembered preference wins when still valid.
const resolveDefaultAgent = () => {
  const preferred = uiSettings.value.preferred_autonomia_copilot_agent_id;
  if (preferred && agents.value.some(a => a.id === preferred)) {
    selectedAgentId.value = preferred;
    return;
  }
  selectedAgentId.value = agents.value[0]?.id ?? null;
};

const setAgent = async agent => {
  largarPedido();
  selectedAgentId.value = agent.id;
  await updateUISettings({ preferred_autonomia_copilot_agent_id: agent.id });
};

const fetchAgents = async () => {
  agentsRequestSequence += 1;
  const requestId = agentsRequestSequence;
  const requestAccountId = currentAccountId.value;
  const requestConversationId = conversationDisplayId.value;

  if (!requestConversationId) {
    agents.value = [];
    selectedAgentId.value = null;
    return;
  }
  try {
    const { data } = await AutonomiaCopilotAPI.listAgents(
      requestConversationId
    );
    if (
      requestId !== agentsRequestSequence ||
      currentAccountId.value !== requestAccountId ||
      conversationDisplayId.value !== requestConversationId
    )
      return;
    agents.value = data.agents || [];
    resolveDefaultAgent();
  } catch {
    if (
      requestId === agentsRequestSequence &&
      currentAccountId.value === requestAccountId &&
      conversationDisplayId.value === requestConversationId
    ) {
      agents.value = [];
      selectedAgentId.value = null;
    }
  }
};

// `arquivos`: os do assunto na hora do envio (a voz guarda os seus antes de transcrever).
const requestReply = async (
  requestConversation,
  message,
  requestId,
  arquivos = store.arquivosProntos()
) => {
  try {
    const { data } = await AutonomiaCopilotAPI.chat(requestConversation, {
      agentId: activeAgent.value.id,
      message,
      history: store.toHistory(),
      arquivos,
    });
    if (
      requestId !== requestSequence ||
      conversationDisplayId.value !== requestConversation
    )
      return;
    if (data.available && data.text) {
      store.addAssistantMessage({
        content: data.text,
        replySuggestion: data.reply_suggestion,
      });
    } else {
      store.addAssistantMessage({ content: '' });
      useAlert(t('AUTONOMIA_COPILOT.UNAVAILABLE'));
    }
  } catch {
    if (
      requestId !== requestSequence ||
      conversationDisplayId.value !== requestConversation
    )
      return;
    store.addAssistantMessage({ content: '' });
    useAlert(t('AUTONOMIA_COPILOT.ERROR'));
  } finally {
    if (requestId === requestSequence) isSending.value = false;
  }
};

const podeEnviar = () =>
  !isSending.value &&
  Boolean(activeAgent.value) &&
  Boolean(conversationDisplayId.value);

// Pin the conversation this request belongs to. If the agent navigates to another conversation
// before the response lands, the late reply must NOT be appended into the now-current
// conversation's thread (cross-conversation leak).
const abrirPedido = () => {
  requestSequence += 1;
  isSending.value = true;
  return { conversa: conversationDisplayId.value, pedido: requestSequence };
};

// GuideComposer clears the field only when this returns true. Accept = the question is in the
// thread, so return right away and let the reply load behind the loader; false keeps the text.
// A message with only files goes with the default sentence; a file still uploading holds it.
const sendMessage = message => {
  const temTexto = Boolean(message?.trim());
  const prontos = pendentes.value.filter(item => item.estado === 'pronto');
  if (!temTexto && !prontos.length) return false;
  if (pendentes.value.some(item => item.estado === 'subindo')) {
    useAlert(t('AUTONOMIA_GUIDE.FILE.WAIT'));
    return false;
  }
  // Com gravação no campo, o texto espera: senão o áudio se perderia sem a pessoa pedir. A voz
  // não passa por aqui (ela sai com a gravação ainda ligada).
  if (gravandoVoz.value) {
    useAlert(t('AUTONOMIA_GUIDE.VOICE.FINISH_FIRST'));
    return false;
  }
  if (!podeEnviar()) return false;
  const conteudo = temTexto
    ? message
    : t('AUTONOMIA_GUIDE.FILE.DEFAULT_MESSAGE');
  const { conversa, pedido } = abrirPedido();
  store.addUserMessage(conteudo, { texto: temTexto ? message : '' });
  requestReply(conversa, conteudo, pedido);
  return true;
};

const avisarLimiteDeAnexos = () =>
  useAlert(t('AUTONOMIA_COPILOT.FILE_LIMIT', { max: MAX_ANEXOS_POR_CONVERSA }));

// Sobe pelo endpoint do Guia (mesmos tipos e limites); o motivo da recusa vira aviso.
const anexarArquivo = async file => {
  if (vagas.value <= 0) {
    avisarLimiteDeAnexos();
    return;
  }
  const conversa = conversationDisplayId.value;
  const ehFoto = (file.type || '').startsWith('image/');
  const id = store.addArquivo(file.name, {
    tipo: ehFoto ? 'imagem' : 'documento',
    previa: ehFoto ? URL.createObjectURL(file) : null,
  });
  try {
    const { data } = await AutonomiaGuideAPI.enviarArquivo(file);
    if (conversationDisplayId.value !== conversa) return;
    store.marcarArquivo(id, 'pronto', data.signed_id);
  } catch (error) {
    if (conversationDisplayId.value !== conversa) return;
    store.marcarArquivo(id, 'erro');
    useAlert(
      motivoUtilizavel(error?.response?.data?.error) ||
        t('AUTONOMIA_GUIDE.FILE.FAILED')
    );
  }
};

// A mensagem de voz vira texto aqui, e só com o texto o agente é chamado. Falhou: o balão
// mostra o erro e o "Tentar de novo"; nada é pedido.
const transcreverMensagem = async (registro, conversa, pedido, arquivos) => {
  const ainda = () =>
    pedido === requestSequence && conversationDisplayId.value === conversa;
  transcrevendo.value = true;
  let texto = '';
  let erro = '';
  try {
    const { data } = await AutonomiaGuideAPI.transcrever(registro.voz.audio);
    texto = (data?.texto || '').trim();
  } catch (error) {
    erro = motivoUtilizavel(error?.response?.data?.error);
  }
  if (!ainda()) return;
  transcrevendo.value = false;
  if (!texto) {
    store.marcarVoz(registro.id, 'erro', {
      erro: erro || t('AUTONOMIA_GUIDE.VOICE.FAILED'),
    });
    isSending.value = false;
    return;
  }
  if (!store.marcarVoz(registro.id, 'pronta', { texto })) return;
  requestReply(conversa, texto, pedido, arquivos);
};

const enviarVoz = ({ audio, duracao }) => {
  if (!podeEnviar()) return false;
  const { conversa, pedido } = abrirPedido();
  const registro = store.addUserMessage('', {
    voz: { audio, url: URL.createObjectURL(audio), duracao },
  });
  transcreverMensagem(registro, conversa, pedido, store.arquivosProntos());
  return true;
};

const tentarVozDeNovo = item => {
  if (item.voz?.estado !== 'erro' || !podeEnviar()) return;
  const { conversa, pedido } = abrirPedido();
  store.marcarVoz(item.id, 'transcrevendo');
  transcreverMensagem(item, conversa, pedido, store.arquivosProntos());
};

watch(showPanel, opened => {
  if (opened) fetchAgents();
});

// Reset on ANY conversation change (even with the panel closed) so a thread from
// conversation A never lingers — or rides as `history` — when you later open the
// copilot on conversation B. Same-conversation close/reopen keeps its thread.
watch(conversationDisplayId, () => {
  largarPedido();
  agentsRequestSequence += 1;
  agents.value = [];
  selectedAgentId.value = null;
  if (showPanel.value) fetchAgents();
});

watch(currentAccountId, () => {
  largarPedido();
  agentsRequestSequence += 1;
  agents.value = [];
  selectedAgentId.value = null;
  if (showPanel.value) fetchAgents();
});

watch(
  () => messages.length,
  () => scrollToBottom()
);

onMounted(() => {
  if (showPanel.value) fetchAgents();
});

onBeforeUnmount(() => {
  requestSequence += 1;
  agentsRequestSequence += 1;
  menuEGuia.copilotoAberto.value = false;
});
</script>

<template>
  <div
    v-if="showPanel"
    v-on-click-outside="handleClickOutside"
    role="complementary"
    :aria-label="$t('AUTONOMIA_COPILOT.PANEL')"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full transition-transform duration-300 ease-in-out md:static md:shrink-0 ltr:border-l rtl:border-r border-n-weak shadow-lg md:shadow-none flex"
    :style="estiloDoPainel"
  >
    <div class="flex flex-col h-full text-sm leading-6 tracking-tight w-full">
      <CopilotHeader
        :agente="activeAgent"
        :agentes="agents"
        :can-reset="hasMessages"
        @reset="resetConversation"
        @close="closePanel"
        @trocar="setAgent"
      />

      <div
        ref="chatContainer"
        role="log"
        :aria-label="$t('AUTONOMIA_COPILOT.LOG', { nome: panelTitle })"
        class="flex-1 flex px-4 py-5 overflow-y-auto items-start"
      >
        <div v-if="hasMessages" class="space-y-5 flex-1 flex flex-col w-full">
          <template v-for="(item, index) in messages" :key="item.id">
            <GuideUserMessage
              v-if="item.message_type === 'user'"
              :item="item"
              destaque
              @tentar-de-novo="tentarVozDeNovo(item)"
            />
            <GuideResposta
              v-else
              :message="item.message"
              :sender-name="panelTitle"
              :foto="fotoDoAgente"
            >
              <Button
                v-if="podeUsar(item, index)"
                data-usar-resposta
                :label="$t('AUTONOMIA_COPILOT.USE')"
                icon="i-lucide-corner-down-left"
                blue
                faded
                class="self-start min-h-11"
                @click="usarResposta(item)"
              />
            </GuideResposta>
          </template>
          <div
            v-if="isSending && !transcrevendo"
            class="flex items-start gap-2 w-full"
          >
            <img
              v-if="fotoDoAgente"
              :src="fotoDoAgente"
              alt=""
              class="size-7 mt-1 shrink-0 rounded-lg object-cover"
            />
            <span
              v-else
              class="grid place-content-center size-7 mt-1 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <p
              class="flex flex-1 items-center gap-3 mb-0 min-w-0 rounded-xl border border-dashed border-n-strong bg-n-solid-1 px-4 py-3 text-[0.9375rem] text-n-slate-11"
            >
              <span
                class="i-lucide-loader-circle animate-spin size-4 shrink-0"
                aria-hidden="true"
              />
              {{ $t('AUTONOMIA_COPILOT.THINKING') }}
            </p>
          </div>
        </div>
        <div v-else class="flex-1 flex flex-col gap-3 w-full">
          <!-- A primeira fala é do agente: o que ele faz, num cartão dele. -->
          <div class="flex items-start gap-2 w-full" data-boas-vindas>
            <img
              v-if="fotoDoAgente"
              :src="fotoDoAgente"
              alt=""
              class="size-7 mt-1 shrink-0 rounded-lg object-cover"
            />
            <span
              v-else
              class="grid place-content-center size-7 mt-1 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-11"
              aria-hidden="true"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <div
              class="flex flex-col flex-1 gap-1 min-w-0 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3"
            >
              <h3 class="mb-0 text-base font-semibold text-n-slate-12">
                {{ panelTitle }}
              </h3>
              <p class="mb-0 text-base leading-relaxed text-n-slate-12">
                {{
                  hasAgents
                    ? $t('AUTONOMIA_COPILOT.KICK_OFF')
                    : $t('AUTONOMIA_COPILOT.NO_AGENTS')
                }}
              </p>
            </div>
          </div>
          <div v-if="hasAgents" class="flex flex-col gap-2 ms-9">
            <button
              v-for="sugestao in sugestoes"
              :key="sugestao"
              type="button"
              data-sugestao
              :disabled="isSending"
              class="text-start text-[0.9375rem] font-medium text-n-blue-11 bg-n-solid-1 ring-1 ring-inset ring-n-blue-6 hover:bg-n-blue-2 rounded-xl px-4 py-2 min-h-11 transition-colors disabled:cursor-not-allowed disabled:opacity-60"
              @click="sendMessage(sugestao)"
            >
              {{ sugestao }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-if="hasAgents"
        class="px-3 pt-2 pb-3 border-t border-n-weak bg-n-solid-1"
      >
        <!-- Uma conversa, um composer: trocar de conversa descarta a gravação que esperava a vez. -->
        <GuideComposer
          :key="conversationDisplayId"
          class="w-full"
          :is-busy="isSending"
          :arquivos="pendentes"
          :on-enviar-voz="enviarVoz"
          :vagas="vagas"
          :texto-de-espera="$t('AUTONOMIA_COPILOT.VOICE_WAITING')"
          :placeholder="
            $t('AUTONOMIA_COPILOT.PLACEHOLDER', { nome: panelTitle })
          "
          @send="sendMessage"
          @sem-microfone="useAlert($t('AUTONOMIA_GUIDE.VOICE.NO_MIC'))"
          @gravacao-falhou="useAlert($t('AUTONOMIA_GUIDE.VOICE.RECORD_FAILED'))"
          @anexar="anexarArquivo"
          @gravando="gravandoVoz = $event"
          @limite-de-anexos="avisarLimiteDeAnexos"
          @remover="store.removeArquivo"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>
