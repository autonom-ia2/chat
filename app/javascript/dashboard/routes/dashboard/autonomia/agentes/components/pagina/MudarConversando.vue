<script setup>
import { computed, onBeforeUnmount, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AutonomiaBuilderImagesAPI from 'dashboard/api/autonomia/builderImages';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import CompositorAA from '../CompositorAA.vue';
import RespostasRapidas from '../RespostasRapidas.vue';
import TesteDoAgente from './TesteDoAgente.vue';
import DialogoAcao from './DialogoAcao.vue';
import { useTesteDoAgente } from '../../composables/useTesteDoAgente';
import { fecharFrase } from '../../utils/pagina';

// #1181 PR3 (protótipo T11) — "Mudar {nome}": a mesma conversa do Construtor, sem etapas, com o
// celular de teste ao lado. Usa a store autonomiaBuildThreads como está: ela guarda uma conversa só,
// então abrir aqui zera a anterior (stopPolling + RESET) e a conversa só nasce na primeira mensagem
// (como o Ajustar do painel antigo). Ideias para começar só no primeiro turno, preenchendo o campo
// (DECISOES.md item 3). Quando o Construtor termina, o agente é relido: se o nome mudou, aparece
// "O nome agora é …" com "Voltar para {antigo}"; se o jeito mudou, avisa; o teste recomeça.
// Ao sair, para o poll e zera a conversa (DECISOES.md item 11).
const props = defineProps({
  agente: { type: Object, required: true },
  origem: {
    type: String,
    default: 'geral',
    validator: v => ['geral', 'jeito', 'teste'].includes(v),
  },
  testeInicial: { type: Object, default: null },
});

const emit = defineEmits(['sair', 'voltarNome']);

const { t } = useI18n();
const store = useStore();
const NS = 'AGENTS.JORNADA.PAGINA.MUDAR_VISTA';

const mensagens = useMapGetter('autonomiaBuildThreads/getMessages');
const status = useMapGetter('autonomiaBuildThreads/getStatus');
const erroDaConversa = useMapGetter('autonomiaBuildThreads/getError');
const flags = useMapGetter('autonomiaBuildThreads/getUIFlags');
const thread = useMapGetter('autonomiaBuildThreads/getThread');
const agenteGerado = useMapGetter('autonomiaBuildThreads/getAgent');

const teste = useTesteDoAgente(toRef(props, 'agente'));
const rascunho = ref('');
const feito = ref(null);
const ultimoEnvio = ref(null);
const celularAberto = ref(false);
const dialogoSair = ref(null);
const antes = ref({ name: props.agente.name, tone: props.agente.tone });
// Saiu da tela com o start/send ainda em voo: quando ele voltar, a store refaria a conversa e o
// poll. `saiu` faz a limpeza de novo nessa hora.
let saiu = false;
const limparConversa = () => {
  store.dispatch('autonomiaBuildThreads/stopPolling');
  store.commit('autonomiaBuildThreads/RESET');
};

const nome = computed(() => props.agente.name || '');

const rascunhoErrado = ({ pergunta, resposta }) =>
  t(`${NS}.RASCUNHO_ERRADO`, {
    pergunta: fecharFrase(pergunta),
    nome: nome.value,
    resposta: fecharFrase(resposta),
  });

const CHIPS = {
  geral: { chave: 'CHIPS_GERAL', letras: ['A', 'B', 'C', 'D'] },
  jeito: { chave: 'CHIPS_JEITO', letras: ['A', 'B', 'C', 'D'] },
};
const ideias = computed(() => {
  const grupo = CHIPS[props.origem];
  if (!grupo) return [];
  return grupo.letras.map(letra =>
    t(`${NS}.${grupo.chave}.${letra}`, { nome: nome.value })
  );
});

const visiveis = computed(() =>
  (mensagens.value || []).filter(
    mensagem => mensagem.role === 'user' || mensagem.role === 'assistant'
  )
);
const comecou = computed(() =>
  visiveis.value.some(mensagem => mensagem.role === 'user')
);
const pensando = computed(
  () =>
    Boolean(flags.value?.sending || flags.value?.creating) ||
    status.value === 'processing'
);
const falhou = computed(() => Boolean(erroDaConversa.value) && !pensando.value);
const noMeio = computed(
  () => pensando.value || (comecou.value && !feito.value)
);

const subirImagens = async imagens => {
  const respostas = await Promise.all(
    imagens.map(imagem => AutonomiaBuilderImagesAPI.upload(imagem))
  );
  return respostas.map(({ data }) => data.signed_id);
};

const guardarArquivos = arquivos =>
  Promise.all(
    arquivos.map(arquivo =>
      store
        .dispatch('autonomiaSources/create', {
          agentId: props.agente.id,
          descriptor: { file: arquivo, kind: 'knowledge' },
        })
        .catch(() => useAlert(t(`${NS}.ANEXO_ERRO`, { arquivo: arquivo.name })))
    )
  );

const mandar = async ({ conteudo, imagens }) => {
  const imageSignedIds = await subirImagens(imagens);
  const threadId = thread.value?.id;
  if (!threadId) {
    await store.dispatch('autonomiaBuildThreads/start', {
      agentId: props.agente.id,
      type: props.agente.agent_type,
      message: conteudo,
      image_signed_ids: imageSignedIds,
    });
    return;
  }
  await store.dispatch('autonomiaBuildThreads/send', {
    threadId,
    content: conteudo,
    extra: { image_signed_ids: imageSignedIds },
  });
};

const tentarMandar = async envio => {
  try {
    await mandar(envio);
  } catch (error) {
    // 409: o Construtor ainda está trabalhando no turno anterior; a store volta a acompanhar.
    if (error?.response?.status === 409 || saiu) return;
    if (!erroDaConversa.value) {
      store.commit('autonomiaBuildThreads/SET_ERROR', 'send');
    }
  } finally {
    if (saiu) limparConversa();
  }
};

const enviar = async ({ texto, anexos }) => {
  if (pensando.value) return;
  const imagens = anexos.filter(arquivo =>
    (arquivo.type || '').startsWith('image/')
  );
  const arquivos = anexos.filter(arquivo => !imagens.includes(arquivo));
  const conteudo = texto || anexos.map(arquivo => arquivo.name).join(', ');
  rascunho.value = '';
  feito.value = null;
  await guardarArquivos(arquivos);
  ultimoEnvio.value = { conteudo, imagens };
  await tentarMandar(ultimoEnvio.value);
};

const tentarDeNovo = async () => {
  if (erroDaConversa.value !== 'send' && thread.value?.id) {
    try {
      await store.dispatch('autonomiaBuildThreads/retry', {
        threadId: thread.value.id,
      });
    } catch {
      store.commit('autonomiaBuildThreads/SET_ERROR', 'failed');
    }
    return;
  }
  if (!ultimoEnvio.value) return;
  store.commit('autonomiaBuildThreads/SET_ERROR', null);
  await tentarMandar(ultimoEnvio.value);
};

// Quando o Construtor termina, a store relê o agente: compara com o de antes da conversa.
watch(agenteGerado, novo => {
  if (!novo || novo.id !== props.agente.id) return;
  const nomeNovo = novo.name !== antes.value.name ? novo.name : null;
  feito.value = {
    nomeNovo,
    nomeAntigo: nomeNovo ? antes.value.name : null,
    jeito: novo.tone !== antes.value.tone,
  };
  antes.value = { name: novo.name, tone: novo.tone };
  teste.marcarAtualizado();
});

const usarIdeia = ideia => {
  rascunho.value = ideia;
};

const respondeuErrado = ultima => {
  rascunho.value = rascunhoErrado(ultima);
  celularAberto.value = false;
};

const pedirSaida = () => {
  if (noMeio.value) {
    dialogoSair.value?.abrir();
    return;
  }
  emit('sair');
};

onMounted(() => {
  limparConversa();
  if (props.origem === 'teste' && props.testeInicial) {
    teste.mostrar(props.testeInicial);
    rascunho.value = rascunhoErrado(props.testeInicial);
  }
});

onBeforeUnmount(() => {
  saiu = true;
  teste.parar();
  limparConversa();
});
</script>

<template>
  <div class="flex flex-col w-full gap-6">
    <div class="flex flex-col gap-2">
      <button
        data-voltar
        type="button"
        class="inline-flex items-center gap-2 text-sm font-semibold min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="pedirSaida"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${NS}.VOLTAR`, { nome }) }}
      </button>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <h1 id="mudar-titulo" class="m-0 text-3xl font-bold text-n-slate-12">
          {{ t(`${NS}.TITULO`, { nome }) }}
        </h1>
        <AgenteBotao
          data-pronto
          tamanho="lg"
          :variante="feito ? 'primario' : 'contorno'"
          :icone="feito ? 'i-lucide-check' : ''"
          @click="pedirSaida"
        >
          {{ t(`${NS}.PRONTO`) }}
        </AgenteBotao>
      </div>
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <section
        aria-labelledby="mudar-titulo"
        class="flex flex-col gap-4 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
      >
        <div
          data-conversa
          :aria-label="t(`${NS}.CONVERSA`)"
          aria-live="polite"
          class="flex flex-col gap-3"
        >
          <div class="flex items-start gap-2">
            <span
              aria-hidden="true"
              class="grid rounded-full place-items-center size-8 shrink-0 bg-n-blue-3 text-n-blue-11"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <div class="flex flex-col gap-3">
              <p
                data-abertura
                class="px-4 py-3 m-0 text-sm rounded-2xl rounded-es-md bg-n-slate-2 text-n-slate-12"
              >
                <span class="sr-only">{{ t(`${NS}.ASSISTENTE`) }}</span>
                {{ t(`${NS}.ABERTURA`, { nome }) }}
              </p>
              <RespostasRapidas
                v-if="!comecou && ideias.length"
                data-ideias
                :opcoes="ideias"
                :rotulo="t('AGENTS.JORNADA.COMUM.IDEIAS')"
                @escolher="usarIdeia"
              />
            </div>
          </div>
          <div
            v-for="(mensagem, indice) in visiveis"
            :key="indice"
            :data-mensagem="mensagem.role"
            class="flex"
            :class="
              mensagem.role === 'user' ? 'justify-end' : 'items-start gap-2'
            "
          >
            <span
              v-if="mensagem.role === 'assistant'"
              aria-hidden="true"
              class="grid rounded-full place-items-center size-8 shrink-0 bg-n-blue-3 text-n-blue-11"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <p
              class="px-4 py-3 m-0 text-sm whitespace-pre-line rounded-2xl max-w-[85%]"
              :class="
                mensagem.role === 'user'
                  ? 'bg-n-blue-3 text-n-slate-12 rounded-ee-md'
                  : 'bg-n-slate-2 text-n-slate-12 rounded-es-md'
              "
            >
              <span class="sr-only">{{
                mensagem.role === 'user'
                  ? t(`${NS}.VOCE`)
                  : t(`${NS}.ASSISTENTE`)
              }}</span>
              {{ mensagem.content }}
            </p>
          </div>
          <p
            v-if="pensando"
            data-pensando
            class="flex items-center gap-2 px-4 py-3 m-0 text-sm w-fit rounded-2xl bg-n-slate-2 text-n-slate-11"
          >
            <span
              aria-hidden="true"
              class="border-2 rounded-full size-3.5 border-n-slate-7 border-t-n-blue-11 motion-safe:animate-spin"
            />
            {{ t(`${NS}.PENSANDO`) }}
          </p>
          <AgenteErro
            v-if="falhou"
            data-erro
            :titulo="t(`${NS}.ERRO`)"
            :garantia="t(`${NS}.ERRO_GARANTIA`, { nome })"
            :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
            @acao="tentarDeNovo"
          />
          <div
            v-if="feito"
            data-feito
            class="flex items-start gap-3 p-4 rounded-2xl bg-n-teal-2 ring-1 ring-inset ring-n-teal-6"
          >
            <span
              class="i-lucide-circle-check size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            <div class="flex flex-col gap-2 text-sm text-n-slate-12">
              <p class="m-0 font-semibold">{{ t(`${NS}.FEITO`, { nome }) }}</p>
              <p v-if="feito.nomeNovo" data-nome-novo class="m-0">
                {{ t(`${NS}.NOME_NOVO`, { nome: feito.nomeNovo }) }}
                <button
                  data-voltar-nome
                  type="button"
                  class="font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
                  @click="emit('voltarNome', feito.nomeAntigo)"
                >
                  {{ t(`${NS}.VOLTAR_NOME`, { nome: feito.nomeAntigo }) }}
                </button>
              </p>
              <p v-if="feito.jeito" data-jeito-novo class="m-0">
                {{ t(`${NS}.JEITO_NOVO`) }}
              </p>
            </div>
          </div>
        </div>

        <p
          v-if="!feito"
          class="flex items-center gap-2 m-0 text-sm text-n-slate-11"
        >
          <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
          {{ t(`${NS}.AO_VIVO`, { nome }) }}
        </p>
        <AgenteBotao
          class="lg:hidden"
          variante="contorno"
          icone="i-lucide-flask-conical"
          bloco
          @click="celularAberto = true"
        >
          {{ t(`${NS}.TESTAR_NOME`, { nome }) }}
        </AgenteBotao>
        <CompositorAA
          v-model="rascunho"
          anexar
          :enviando="pensando"
          @enviar="enviar"
        />
      </section>

      <aside
        aria-labelledby="mudar-celular"
        class="flex-col hidden gap-2 lg:flex"
      >
        <h2
          id="mudar-celular"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t(`${NS}.TESTE_TITULO`) }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.PAGINA.TESTE.NINGUEM') }}
        </p>
        <TesteDoAgente
          :teste="teste"
          :nome="nome"
          :tipo="agente.agent_type"
          pode-mudar
          @errado="respondeuErrado"
        />
      </aside>
    </div>

    <AgenteGaveta
      v-if="celularAberto"
      :titulo="t(`${NS}.TESTAR_NOME`, { nome })"
      @fechar="celularAberto = false"
    >
      <TesteDoAgente
        :teste="teste"
        :nome="nome"
        :tipo="agente.agent_type"
        pode-mudar
        @errado="respondeuErrado"
      />
    </AgenteGaveta>

    <DialogoAcao
      ref="dialogoSair"
      :titulo="t(`${NS}.SAIR_TITULO`)"
      :texto="t(`${NS}.SAIR_TEXTO`, { nome })"
      :cancelar="t(`${NS}.CONTINUAR_AQUI`)"
      :confirmar="t(`${NS}.SAIR`)"
      @confirmado="emit('sair')"
    />
  </div>
</template>
