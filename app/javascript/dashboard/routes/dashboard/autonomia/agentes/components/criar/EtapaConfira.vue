<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import CelularConversa from '../CelularConversa.vue';
import CompositorAA from '../CompositorAA.vue';
import RespostasRapidas from '../RespostasRapidas.vue';

// #1181 PR2 (protótipo T04) — o celular vira teste de verdade: perguntas prontas do modelo ou
// escritas, resposta em partes, "usou: <arquivo>" e a faixa de quando passaria para a equipe.
// "Respondeu errado?" leva o pedido para a conversa. #1504 — "Começar a atender no {canal}" aparece
// assim que a conversa fecha: o teste é opcional ("Se quiser, teste antes"). Sem canal, vira
// "Conectar seu WhatsApp ou outro canal" (ou o pedido a um administrador). "Fazer ajustes avançados"
// pede à página para abrir o agente parado e sem canal; terminar depois é o "Voltar" do topo.
const props = defineProps({
  nome: { type: String, required: true },
  empresa: { type: String, default: '' },
  perguntas: { type: Array, default: () => [] },
  mensagens: { type: Array, default: () => [] },
  digitando: { type: Boolean, default: false },
  problema: { type: String, default: null },
  atualizado: { type: Boolean, default: false },
  respondidas: { type: Number, default: 0 },
  // A conversa ao lado ainda está gerando: "Respondeu errado?" espera.
  conversaPensando: { type: Boolean, default: false },
  // Rótulo do botão de começar ("Começar a atender no WhatsApp"), ou '' quando não há canal.
  rotuloComecar: { type: String, default: '' },
  podeConectarCanal: { type: Boolean, default: false },
  linkConectarCanal: { type: String, default: '' },
  celular: { type: Boolean, default: false },
  // Copiloto da equipe (#1494): o teste é de alguém da equipe e o agente não responde clientes.
  interno: { type: Boolean, default: false },
  // "Fazer ajustes avançados" foi pedido e a página ainda está deixando o agente parado.
  abrindoAjustes: { type: Boolean, default: false },
  // As caixas ainda estão sendo lidas: Começar espera (sem teste, a pessoa chega aqui antes delas).
  carregandoCanais: { type: Boolean, default: false },
});

const emit = defineEmits([
  'perguntar',
  'tentarDeNovo',
  'limpar',
  'respondeuErrado',
  'comecar',
  'ajustes',
]);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR.CONFIRA';

const pergunta = ref('');
const pediuCorrecao = ref(false);

watch(
  () => props.respondidas,
  () => {
    pediuCorrecao.value = false;
  }
);

// A última parte da resposta traz `passaria` quando o agente passaria a conversa para a equipe:
// a faixa entra logo depois dela. O copiloto já fala com a equipe: sem faixa, e quem pergunta é
// alguém da equipe, não um cliente.
const celularMensagens = computed(() =>
  props.mensagens.flatMap(mensagem => {
    if (props.interno) {
      return [
        mensagem.de === 'cliente' ? { ...mensagem, de: 'equipe' } : mensagem,
      ];
    }
    return mensagem.passaria
      ? [
          mensagem,
          { de: 'aviso', texto: t(`${NS}.PASSARIA`, { nome: props.nome }) },
        ]
      : [mensagem];
  })
);

const textosDasPerguntas = computed(() =>
  props.perguntas.map(chave => t(`${NS}.PERGUNTAS.${chave}`))
);

const ultima = computed(() => props.mensagens[props.mensagens.length - 1]);
const podeDizerErrado = computed(
  () =>
    !props.digitando &&
    !props.problema &&
    !props.conversaPensando &&
    !pediuCorrecao.value &&
    ultima.value?.de === 'agente'
);

const estadoDoCabecalho = computed(() => {
  const nome = { nome: props.nome };
  if (props.digitando) return t(`${NS}.ESCREVENDO`, nome);
  return props.interno
    ? t(`${NS}.AJUDA_DA_EQUIPE`, nome)
    : t(`${NS}.ATENDIDO_POR`, nome);
});

const erro = computed(() => {
  const nome = { nome: props.nome };
  const tentar = t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO');
  const MAPA = {
    falha: {
      titulo: t(`${NS}.FALHA`, nome),
      garantia: props.interno
        ? t(`${NS}.FALHA_GARANTIA_COPILOTO`)
        : t(`${NS}.FALHA_GARANTIA`),
      acao: tentar,
    },
    demora: { titulo: t(`${NS}.DEMORA`), tom: 'ambar', acao: tentar },
    offline: {
      titulo: t('AGENTS.JORNADA.ERRO.OFFLINE'),
      garantia: t('AGENTS.JORNADA.ERRO.OFFLINE_GARANTIA'),
      tom: 'ambar',
      acao: tentar,
    },
    incompleto: {
      titulo: props.celular
        ? t(`${NS}.INCOMPLETO_CELULAR`, nome)
        : t(`${NS}.INCOMPLETO`, nome),
      tom: 'ambar',
    },
  };
  return props.problema ? MAPA[props.problema] : null;
});

const perguntar = texto => emit('perguntar', { texto, anexos: [] });
const enviar = ({ texto, anexos }) => {
  emit('perguntar', { texto, anexos });
  pergunta.value = '';
};

const pedirAjustes = () => {
  if (!props.abrindoAjustes) emit('ajustes');
};

const respondeuErrado = () => {
  pediuCorrecao.value = true;
  emit('respondeuErrado');
};
</script>

<template>
  <section
    data-confira
    aria-labelledby="confira-titulo"
    class="flex flex-col min-w-0 gap-4"
    :class="celular ? 'pb-[26rem]' : ''"
  >
    <div class="relative flex flex-col gap-1">
      <!-- No celular o título da tela já diz isso: aqui fica só para o leitor de tela. -->
      <h2
        id="confira-titulo"
        class="m-0 text-lg font-semibold text-n-slate-12"
        :class="celular ? 'sr-only' : ''"
      >
        {{ interno ? t(`${NS}.TITULO_COPILOTO`) : t(`${NS}.TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.TEXTO`) }}</p>
      <!-- No celular a dica fica aqui em cima: a barra fixa embaixo já leva perguntas, campo e Começar. -->
      <p
        v-if="celular && !respondidas"
        data-teste-opcional
        class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-lightbulb size-4 mt-0.5 shrink-0"
          aria-hidden="true"
        />
        {{ t(`${NS}.TESTE_OPCIONAL`, { nome }) }}
      </p>
    </div>

    <CelularConversa
      :mensagens="celularMensagens"
      :digitando="digitando"
      :nome="interno ? nome : empresa || nome"
      :estado="estadoDoCabecalho"
    >
      <template v-if="mensagens.length || atualizado" #acao>
        <button
          type="button"
          data-limpar
          :disabled="digitando"
          class="px-2 text-xs font-semibold text-white underline rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:opacity-50 disabled:cursor-not-allowed"
          @click="emit('limpar')"
        >
          {{ t(`${NS}.LIMPAR`) }}
        </button>
      </template>
      <template #depois>
        <p
          v-if="atualizado"
          data-atualizado
          role="status"
          class="flex items-center self-center gap-1.5 px-3 py-1 m-0 text-xs rounded-full bg-n-teal-3 text-n-slate-12"
        >
          <span class="i-lucide-refresh-cw size-3.5" aria-hidden="true" />
          {{ t(`${NS}.ATUALIZADO`) }}
        </p>
        <p
          v-if="!mensagens.length && !digitando"
          data-vazio
          class="self-center px-4 m-0 text-sm text-center text-n-slate-11"
        >
          {{ celular ? t(`${NS}.VAZIO_CELULAR`) : t(`${NS}.VAZIO`) }}
        </p>
        <AgenteErro
          v-if="erro"
          data-erro-teste
          :titulo="erro.titulo"
          :garantia="erro.garantia || ''"
          :acao="erro.acao || ''"
          :tom="erro.tom || 'rubi'"
          @acao="emit('tentarDeNovo')"
        />
        <button
          v-if="podeDizerErrado"
          type="button"
          data-respondeu-errado
          class="self-start px-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          @click="respondeuErrado"
        >
          {{ t(`${NS}.RESPONDEU_ERRADO`) }}
        </button>
      </template>
      <template v-if="!celular" #rodape>
        <div
          class="flex flex-col gap-2 p-3 border-t border-n-weak bg-n-solid-1"
        >
          <RespostasRapidas
            data-perguntas
            :rotulo="t(`${NS}.PERGUNTAS_ROTULO`)"
            :opcoes="textosDasPerguntas"
            :desabilitado="digitando"
            @escolher="perguntar"
          />
          <CompositorAA
            v-model="pergunta"
            anexar
            so-imagens
            :placeholder="t(`${NS}.ESCREVA`)"
            :enviando="digitando"
            @enviar="enviar"
          />
        </div>
      </template>
    </CelularConversa>

    <div
      class="flex flex-col gap-3"
      :class="
        celular
          ? 'fixed inset-x-0 bottom-0 z-20 p-4 border-t bg-n-solid-1 border-n-weak'
          : ''
      "
    >
      <template v-if="celular">
        <RespostasRapidas
          data-perguntas
          :rotulo="t(`${NS}.PERGUNTAS_ROTULO`)"
          :opcoes="textosDasPerguntas"
          :desabilitado="digitando"
          @escolher="perguntar"
        />
        <CompositorAA
          v-model="pergunta"
          anexar
          so-imagens
          :placeholder="t(`${NS}.ESCREVA`)"
          :enviando="digitando"
          @enviar="enviar"
        />
      </template>
      <p
        v-if="!celular && !respondidas"
        data-teste-opcional
        class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-lightbulb size-4 mt-0.5 shrink-0"
          aria-hidden="true"
        />
        {{ t(`${NS}.TESTE_OPCIONAL`, { nome }) }}
      </p>
      <div v-if="rotuloComecar" data-comecar class="flex flex-col gap-1">
        <AgenteBotao
          tamanho="xl"
          bloco
          aria-describedby="confira-comecar-texto"
          :carregando="carregandoCanais"
          @click="emit('comecar')"
        >
          {{ rotuloComecar }}
        </AgenteBotao>
        <p id="confira-comecar-texto" class="m-0 text-sm text-n-slate-11">
          {{
            interno
              ? t(`${NS}.COMECAR_TEXTO_COPILOTO`, { nome })
              : t(`${NS}.COMECAR_TEXTO`, { nome })
          }}
        </p>
      </div>
      <div v-else-if="!interno" data-sem-canal class="flex flex-col gap-2">
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.ERRO.SEM_CANAL_GARANTIA', { nome }) }}
        </p>
        <a
          v-if="podeConectarCanal"
          data-conectar
          :href="linkConectarCanal"
          target="_blank"
          rel="noopener noreferrer"
          class="relative inline-flex items-center justify-center w-full gap-2 px-6 text-base font-semibold text-white rounded-xl min-h-14 bg-n-blue-11 dark:text-n-slate-1 hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11"
        >
          {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
          <span class="i-lucide-external-link size-5" aria-hidden="true" />
          <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
        </a>
        <p v-else class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
        </p>
      </div>
    </div>
    <!-- Fora da barra fixa: no celular fica embaixo do teste, e a barra continua curta. -->
    <div data-ajustes class="flex flex-col items-start gap-0.5">
      <button
        type="button"
        data-ajustes-botao
        aria-describedby="confira-ajustes-texto"
        :aria-busy="abrindoAjustes ? 'true' : undefined"
        :aria-disabled="abrindoAjustes ? 'true' : undefined"
        class="inline-flex items-center gap-1.5 px-1 text-sm font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 aria-disabled:cursor-wait aria-disabled:opacity-60"
        @click="pedirAjustes"
      >
        <span
          class="i-lucide-sliders-horizontal size-4 shrink-0"
          aria-hidden="true"
        />
        {{ t(`${NS}.AJUSTES`) }}
      </button>
      <p id="confira-ajustes-texto" class="px-1 m-0 text-xs text-n-slate-11">
        {{ t(`${NS}.AJUSTES_TEXTO`, { nome }) }}
      </p>
    </div>
  </section>
</template>
