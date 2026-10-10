<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { usePermissoesDaJornada } from '../../composables/usePermissoesDaJornada';
import { MOTIVO } from '../../composables/useComecarAAtender';
import { TIPO_CANAL, tipoDoCanal, trocaNoCanal } from '../../utils/canais';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import OndeQuandoEscolha from '../OndeQuandoEscolha.vue';

// #1181 PR2 (protótipo T05) — a folha "Onde e quando {nome} atende": onde (caixas da L2, com a
// troca de quem já está numa caixa) e quando (config.response_window; padrão Sempre). Uma ação
// cheia só, embaixo: "Começar a atender" (ou "Trocar e começar a atender"). A falha aparece na
// própria folha dizendo o que continua igual. Quem chama faz a sequência (useComecarAAtender).
const props = defineProps({
  nome: { type: String, required: true },
  agenteId: { type: Number, required: true },
  canais: { type: Array, required: true },
  horarios: { type: Object, default: () => ({}) },
  semLeitura: { type: Boolean, default: false },
  ondeInicial: { type: Number, default: null },
  quandoInicial: { type: String, default: 'always' },
  comecando: { type: Boolean, default: false },
  // { motivo, troca? } do useComecarAAtender, ou null.
  erro: { type: Object, default: null },
});

const emit = defineEmits(['fechar', 'comecar']);

const { t } = useI18n();
const router = useRouter();
const { podeConectarCanal } = usePermissoesDaJornada();
const NS = 'AGENTS.JORNADA.CRIAR.COMECE';

const disponivel = inboxId => {
  const canal = props.canais.find(item => item.inbox_id === inboxId);
  return canal && tipoDoCanal(canal, props.agenteId) !== TIPO_CANAL.EXTERNO;
};

const onde = ref(disponivel(props.ondeInicial) ? props.ondeInicial : null);
const quando = ref(props.quandoInicial || 'always');
const escolha = ref(null);

const troca = computed(() =>
  trocaNoCanal(props.canais, onde.value, props.agenteId)
);
const todosOcupados = computed(
  () =>
    !props.canais.some(
      canal => tipoDoCanal(canal, props.agenteId) === TIPO_CANAL.LIVRE
    )
);
const linkConectarCanal = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);

const ERROS = {
  [MOTIVO.CANAL]: {
    titulo: 'AGENTS.JORNADA.ERRO.CANAL',
    garantia: 'AGENTS.JORNADA.ERRO.CANAL_GARANTIA',
    acao: 'AGENTS.JORNADA.ERRO.CANAL_ACAO',
    icone: 'i-lucide-list',
  },
  [MOTIVO.OFFLINE]: {
    titulo: 'AGENTS.JORNADA.ERRO.OFFLINE',
    garantia: 'AGENTS.JORNADA.ERRO.OFFLINE_GARANTIA',
    acao: 'AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO',
    tom: 'ambar',
  },
  [MOTIVO.TROCA_SEM_AGENTE]: {
    titulo: 'AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE',
    garantia: 'AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE_GARANTIA',
    acao: 'AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO',
  },
  [MOTIVO.COMECAR]: {
    titulo: 'AGENTS.JORNADA.ERRO.COMECAR_ATENDER',
    garantia: 'AGENTS.JORNADA.ERRO.COMECAR_ATENDER_GARANTIA',
    acao: 'AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO',
  },
};

const erroVisivel = computed(() => {
  if (!props.erro) return null;
  const molde = ERROS[props.erro.motivo] || ERROS[MOTIVO.COMECAR];
  const valores = { nome: props.nome, canal: props.erro.troca?.canal || '' };
  return {
    motivo: props.erro.motivo,
    titulo: t(molde.titulo, valores),
    garantia: t(molde.garantia, valores),
    acao: t(molde.acao),
    icone: molde.icone || 'i-lucide-refresh-cw',
    tom: molde.tom || 'rubi',
  };
});

const comecar = () => {
  if (!onde.value || props.comecando) return;
  emit('comecar', {
    inboxId: onde.value,
    quando: quando.value,
    troca: troca.value,
  });
};

// "Escolher outro" (o canal recusou): o foco vai para a lista de onde atende.
const aoAgirNoErro = () => {
  if (erroVisivel.value?.motivo === MOTIVO.CANAL) {
    escolha.value?.querySelector('[role="radio"][tabindex="0"]')?.focus();
    return;
  }
  comecar();
};
</script>

<template>
  <AgenteGaveta
    :titulo="t('AGENTS.JORNADA.ONDE_QUANDO.TITULO', { nome })"
    @fechar="emit('fechar')"
  >
    <div
      ref="escolha"
      class="flex flex-col gap-4"
      :aria-busy="comecando ? 'true' : undefined"
    >
      <OndeQuandoEscolha
        v-model:onde="onde"
        v-model:quando="quando"
        :canais="canais"
        :agente-id="agenteId"
        :nome="nome"
        :horarios="horarios"
        :sem-leitura="semLeitura"
      />
      <p v-if="todosOcupados" data-todos-ocupados class="m-0 text-sm">
        <a
          v-if="podeConectarCanal"
          :href="linkConectarCanal"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        >
          {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
          <span class="i-lucide-external-link size-4" aria-hidden="true" />
          <span class="sr-only">{{ t('AGENTS.JORNADA.COMUM.NOVA_ABA') }}</span>
        </a>
        <span v-else class="text-n-slate-11">
          {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
        </span>
      </p>
      <AgenteErro
        v-if="erroVisivel"
        data-erro-comecar
        :titulo="erroVisivel.titulo"
        :garantia="erroVisivel.garantia"
        :acao="erroVisivel.acao"
        :icone-acao="erroVisivel.icone"
        :tom="erroVisivel.tom"
        @acao="aoAgirNoErro"
      />
    </div>
    <template #rodape>
      <AgenteBotao
        data-comecar
        tamanho="xl"
        bloco
        :carregando="comecando"
        :rotulo-carregando="t('AGENTS.JORNADA.COMUM.COMECANDO')"
        :desabilitado="!onde"
        aria-describedby="comece-texto"
        @click="comecar"
      >
        {{ troca ? t(`${NS}.TROCAR`) : t(`${NS}.COMECAR`) }}
      </AgenteBotao>
      <p id="comece-texto" class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_TEXTO', { nome }) }}
      </p>
      <AgenteBotao
        data-voltar-teste
        variante="fantasma"
        bloco
        :desabilitado="comecando"
        @click="emit('fechar')"
      >
        {{ t(`${NS}.VOLTAR_TESTE`) }}
      </AgenteBotao>
    </template>
  </AgenteGaveta>
</template>
