<script setup>
// #2202 — o item da lista "Quem está esperando" (atrás da chave lista_quem_espera).
// 2 ou 3 linhas, uma pergunta por linha:
//   1. quem é e quando foi a última mensagem ("17:21", "Ontem", "seg", "12/10");
//   2. quem disse e o quê ("Você:", "Ana:", "Gabriela [IA]:", "Equipe:") + a bolinha;
//   3. só quando importa: a prioridade alta/urgente, um sinal que nunca é cortado
//      e, à direita, a etapa (que desce inteira quando não cabe).
// Mesmas props e eventos do ConversationCard antigo; raiz div.conversation(.active)
// para o Alt+J/K continuar achando o item.
import { computed, inject, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { nomeOuTelefone } from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';
import { iconeDaCaixa } from './iconeDaCaixa';
import { dataEHoraDaMensagem } from 'dashboard/components-next/conversa-canal/dataDaConversa';
import { textoDaMensagem } from 'dashboard/components-next/conversa-canal/ecoDoCelular';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import CustomerBadge from 'dashboard/components-next/customer-badge/CustomerBadge.vue';
import MessagePreview from 'dashboard/components/widgets/conversation/MessagePreview.vue';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { useCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import SeloIA from './SeloIA.vue';
import { horaDaLista } from './horaDaLista';
import { REMETENTE, prefixoDoRemetente } from './prefixoDoRemetente';
import { FAIXA_DA_VEZ, sinalDaConversa } from './sinalDaConversa';
import { FAIXA } from './duracaoDaEspera';
import { useRelogioDaLista } from './useRelogioDaLista';
import { useFunisDaConta } from './useFunisDaConta';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  selectable: { type: Boolean, default: true },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const { t } = useI18n();
const store = useStore();
const agora = useRelogioDaLista();
const eu = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');
const contaPorId = useMapGetter('accounts/getAccount');
const caixas = useMapGetter('inboxes/getInboxes');

const fuso = computed(() => fusoDaConta(contaPorId.value?.(contaId.value)));
// #2211: no resultado da busca, a conversa resolvida diz "Resolvida" na linha 3, e o card não tem a
// caixa de seleção (a seleção em lote é da lista, que fica escondida durante a busca).
const naBusca = inject('cardNaBusca', false);
const agentePorId = id => store.getters['agents/getAgentById'](id);
const nomeDoAgente = id => {
  const agente = agentePorId(id);
  return agente?.available_name || agente?.name || '';
};

// O avatar tem 36 px no celular e 40 no resto, pela classe responsiva (sem medir a janela em
// cada card): o Avatar recebe o tamanho em número, então são dois, e só um aparece.
const AVATARES = [
  { tamanho: 36, classe: 'md:hidden', marcador: 'size-9' },
  { tamanho: 40, classe: 'hidden md:inline-flex', marcador: 'size-10' },
];
const hovered = ref(false);
watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);

// Quem é: o nome; sem nome, o telefone legível ("+55 11 94444-3333"); sem telefone, o e-mail;
// sem e-mail, o identificador. Sem nome gravado, o avatar fica com o ícone de pessoa (e-mail e
// identificador não viram iniciais); nome que é só telefone o próprio Avatar resolve (#2255).
const pessoas = computed(() =>
  [props.currentContact, props.chat.meta?.sender].filter(Boolean)
);
const primeiroCampo = campo =>
  pessoas.value.map(pessoa => pessoa[campo]).find(Boolean) || '';
const nomeGravado = computed(() => primeiroCampo('name'));
const nome = computed(
  () =>
    nomeOuTelefone(nomeGravado.value, primeiroCampo('phone_number')) ||
    primeiroCampo('email') ||
    primeiroCampo('identifier')
);
const nomeNoAvatar = computed(() => (nomeGravado.value ? nome.value : ''));
const ultima = computed(() => getLastMessage(props.chat));
const prefixo = computed(() =>
  prefixoDoRemetente(ultima.value, {
    euId: eu.value?.id,
    agentePorId,
  })
);
const nomeDoUltimoRobo = computed(() =>
  prefixo.value.tipo === REMETENTE.ROBO ? prefixo.value.nome : ''
);

const hora = computed(() =>
  horaDaLista({
    quando: props.chat.timestamp,
    agora: agora.value,
    fuso: fuso.value,
    t,
  })
);
const dicaDaHora = computed(() =>
  t('LISTA_DE_CONVERSAS.HORA.DICA', {
    ultima: dataEHoraDaMensagem(props.chat.timestamp, fuso.value),
    comeco: dataEHoraDaMensagem(props.chat.created_at, fuso.value),
  })
);
const horaIso = computed(() =>
  new Date((props.chat.timestamp || 0) * 1000).toISOString()
);

// O responsável vem do ConversationItem (meta.assignee), como no card antigo.
const conversaComResponsavel = computed(() => ({
  ...props.chat,
  meta: {
    ...props.chat.meta,
    assignee: props.assignee?.id ? props.assignee : null,
  },
}));
const linha3 = computed(() =>
  sinalDaConversa(conversaComResponsavel.value, {
    t,
    agora: agora.value,
    fuso: fuso.value,
    euId: eu.value?.id,
    ultima: prefixo.value,
    nomeDoUltimoRobo: nomeDoUltimoRobo.value,
    nomeDoAgente,
    mostrarResponsavel: props.showAssignee,
    marcarResolvida: naBusca,
  })
);

// Cor do sinal: âmbar para "Sua vez" e para a espera de 15 min a 2 h; vermelho de
// 2 h a 7 dias; o resto em cinza. A cor sempre vem com uma palavra.
// Contraste medido no protótipo (#2202): no tema claro o n-amber-11 dá 4,57:1 no
// fundo da lista, mas 4,30 no item aberto, 4,24 com o mouse em cima e 4,38 no
// selecionado (abaixo do AA 4,5). Nesses três estados o texto vai para n-amber-12.
const AMBAR = {
  texto: 'text-n-amber-11 group-hover:text-n-amber-12',
  textoForte: 'text-n-amber-12',
  ponto: 'bg-n-amber-9',
};
const COR_DA_FAIXA = {
  [FAIXA_DA_VEZ]: AMBAR,
  [FAIXA.ATENCAO]: AMBAR,
  [FAIXA.URGENTE]: { texto: 'text-n-ruby-11', ponto: 'bg-n-ruby-9' },
};
const cor = computed(() => {
  const faixa = linha3.value.sinal?.faixa;
  const escolhida = COR_DA_FAIXA[faixa] || {
    texto: 'text-n-slate-11',
    ponto: '',
  };
  const destacado = props.isActiveChat || props.selected;
  return {
    ...escolhida,
    texto:
      destacado && escolhida.textoForte
        ? escolhida.textoForte
        : escolhida.texto,
  };
});

// Etapa do CRM: texto, não link. Conta sem funil com várias caixas: o nome da caixa.
const { canViewCrm } = useCrmPermissions();
const crmLigado = computed(
  () => canViewCrm.value && window.globalConfig?.CRM_KANBAN_ENABLED === 'true'
);
const etapa = useCrmConversationStage(
  computed(() => (crmLigado.value ? props.chat?.id : null))
);
const funis = useFunisDaConta(contaId, crmLigado);
const outrosAssuntos = computed(() =>
  Math.max((etapa.value?.subjects_count || 0) - 1, 0)
);
const textoDaEtapa = computed(() => {
  if (etapa.value?.stage_name) return etapa.value.stage_name;
  const semFunil = !crmLigado.value || funis.value.semFunil;
  return semFunil && props.showInboxName ? props.inbox?.name || '' : '';
});
const dicaDaEtapa = computed(() => {
  if (!etapa.value?.stage_name) return textoDaEtapa.value;
  return t('LISTA_DE_CONVERSAS.ETAPA.DICA', {
    funil: etapa.value.pipeline_name || '',
    etapa: etapa.value.stage_name,
  });
});

const temLinha3 = computed(
  () =>
    Boolean(linha3.value.prioridade || linha3.value.sinal) ||
    Boolean(textoDaEtapa.value)
);

// Ícone do canal só quando a conta tem mais de um tipo de canal.
const variosCanais = computed(
  () => new Set((caixas.value || []).map(caixa => caixa.channel_type)).size > 1
);
const iconeDoCanal = computed(() =>
  variosCanais.value && props.inbox?.channel_type
    ? iconeDaCaixa(props.inbox)
    : ''
);

const naoLidas = computed(() => props.chat.unread_count || 0);
const textoDasNaoLidas = computed(() =>
  naoLidas.value > 9 ? '9+' : String(naoLidas.value)
);

const prefixoNaTela = computed(() => {
  const { tipo, nome: quem } = prefixo.value;
  if (tipo === REMETENTE.VOCE) return t('LISTA_DE_CONVERSAS.PREFIXO.VOCE');
  if (tipo === REMETENTE.NOTA) return t('LISTA_DE_CONVERSAS.PREFIXO.NOTA');
  if (tipo === REMETENTE.EQUIPE) return t('LISTA_DE_CONVERSAS.PREFIXO.EQUIPE');
  if (tipo === REMETENTE.PESSOA || tipo === REMETENTE.ROBO) return quem;
  return '';
});

const textoDaUltima = computed(() =>
  textoDaMensagem(ultima.value?.content, ultima.value?.content_attributes)
);
const quemEscreveu = computed(() => {
  const { tipo, nome: quem } = prefixo.value;
  if (tipo === REMETENTE.ROBO) {
    return t('LISTA_DE_CONVERSAS.ARIA.ROBO_ESCREVEU', { nome: quem });
  }
  if (tipo === REMETENTE.CLIENTE) {
    return t('LISTA_DE_CONVERSAS.ARIA.ESCREVEU', { nome: nome.value });
  }
  if (prefixoNaTela.value) {
    return t('LISTA_DE_CONVERSAS.ARIA.ESCREVEU', { nome: prefixoNaTela.value });
  }
  return '';
});
const rotulo = computed(() =>
  [
    `${nome.value}.`,
    t('LISTA_DE_CONVERSAS.ARIA.ULTIMA', { quando: hora.value }),
    quemEscreveu.value
      ? `${quemEscreveu.value} ${textoDaUltima.value || ''}`.trim()
      : '',
    naoLidas.value
      ? t(
          'LISTA_DE_CONVERSAS.ARIA.NAO_LIDAS',
          { n: naoLidas.value },
          naoLidas.value
        )
      : '',
    linha3.value.prioridade ? `${linha3.value.prioridade}.` : '',
    linha3.value.sinal ? `${linha3.value.sinal.aria}.` : '',
    textoDaEtapa.value ? `${dicaDaEtapa.value}.` : '',
  ]
    .filter(Boolean)
    .join(' ')
);

const selecionada = computed({
  get: () => props.selected,
  set: valor => {
    if (valor) emit('selectConversation', props.chat.id, props.inbox.id);
    else emit('deSelectConversation', props.chat.id, props.inbox.id);
  },
});
</script>

<template>
  <div
    class="relative flex items-start gap-3 px-4 py-3 border-b cursor-pointer group conversation border-n-weak hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3"
    :class="{
      'active animate-card-select bg-n-background': isActiveChat,
      'selected bg-n-slate-2': selected,
    }"
    data-card-da-conversa
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      class="relative flex-shrink-0"
      @mouseenter="hovered = true"
      @mouseleave="hovered = false"
    >
      <Avatar
        v-for="avatar in AVATARES"
        :key="avatar.tamanho"
        :class="avatar.classe"
        :name="nomeNoAvatar"
        :src="currentContact.thumbnail"
        :size="avatar.tamanho"
        :status="currentContact.availability_status"
        hide-offline-status
        rounded-full
        :data-avatar="avatar.tamanho"
      >
        <template #overlay>
          <label
            v-if="selectable && !naBusca && (hovered || selected)"
            class="absolute inset-0 z-10 flex items-center justify-center rounded-full cursor-pointer backdrop-blur-[2px]"
            :class="avatar.marcador"
            @click.stop
          >
            <Checkbox v-model="selecionada" />
          </label>
        </template>
      </Avatar>
    </div>
    <button
      type="button"
      class="flex flex-col flex-1 min-w-0 gap-0.5 p-0 m-0 text-start bg-transparent border-0 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand rounded"
      :aria-label="rotulo"
      data-card-texto
    >
      <span class="flex items-center min-w-0 gap-2" data-linha="1">
        <span class="text-sm font-medium truncate text-n-slate-12" data-nome>
          {{ nome }}
        </span>
        <CustomerBadge :contact="currentContact" />
        <span
          class="flex items-center flex-shrink-0 gap-1 ms-auto text-xs tabular-nums text-n-slate-11"
        >
          <Icon
            v-if="iconeDoCanal"
            :icon="iconeDoCanal"
            class="size-3.5 text-n-slate-11"
          />
          <time :datetime="horaIso" :title="dicaDaHora" data-hora>
            {{ hora }}
          </time>
        </span>
      </span>
      <span class="flex items-center min-w-0 gap-2" data-linha="2">
        <span
          class="flex items-center flex-1 min-w-0 gap-1 text-sm text-n-slate-11"
        >
          <span
            v-if="prefixo.tipo === 'nota'"
            class="flex-shrink-0 i-lucide-lock size-3.5 text-n-slate-11"
          />
          <span
            v-if="prefixoNaTela"
            class="flex items-center flex-shrink-0 font-medium text-n-slate-12 max-w-[50%]"
            data-prefixo
          >
            <span class="truncate">{{ prefixoNaTela }}</span>
            <SeloIA v-if="prefixo.tipo === 'robo'" class="ms-1" />
            <!-- Os dois-pontos encostam no selo (o respiro que se via era o recuo interno do selo). -->
            <span :class="prefixo.tipo === 'robo' && '-ms-0.5'">{{
              $t('LISTA_DE_CONVERSAS.PREFIXO.SEPARADOR')
            }}</span>
          </span>
          <MessagePreview
            v-if="ultima"
            :message="ultima"
            :show-message-type="false"
            tag="span"
            class="flex-1 min-w-0 leading-5"
          />
          <span v-else class="truncate">
            {{ $t('CHAT_LIST.NO_MESSAGES') }}
          </span>
        </span>
        <span
          v-if="naoLidas > 0"
          class="flex items-center justify-center flex-shrink-0 h-5 px-1.5 text-xs font-semibold text-white rounded-full min-w-5 bg-n-brand tabular-nums"
          data-nao-lidas
        >
          {{ textoDasNaoLidas }}
        </span>
      </span>
      <span
        v-if="temLinha3"
        class="flex flex-wrap items-center min-w-0 text-xs gap-x-2 gap-y-0.5 leading-5"
        data-linha="3"
      >
        <span class="flex items-center flex-shrink-0 gap-1.5 whitespace-nowrap">
          <span
            v-if="linha3.prioridade"
            class="flex items-center gap-1 font-medium text-n-slate-12"
            data-prioridade
          >
            <span class="i-lucide-flag size-3.5" />
            {{ linha3.prioridade }}
          </span>
          <span
            v-if="linha3.prioridade && linha3.sinal"
            class="text-n-slate-11"
          >
            {{ $t('LISTA_DE_CONVERSAS.SINAL.SEPARADOR') }}
          </span>
          <span
            v-if="linha3.sinal"
            class="flex items-center gap-1.5"
            :class="cor.texto"
            :data-sinal="linha3.sinal.familia"
            :data-faixa="linha3.sinal.faixa"
          >
            <span
              v-if="cor.ponto"
              class="flex-shrink-0 rounded-full size-2"
              :class="cor.ponto"
            />
            <span
              v-else-if="linha3.sinal.icone"
              class="flex-shrink-0 size-3.5"
              :class="linha3.sinal.icone"
            />
            <span>{{ linha3.sinal.texto }}</span>
            <SeloIA v-if="linha3.sinal.selo" />
          </span>
        </span>
        <span
          v-if="textoDaEtapa"
          class="flex items-center gap-1 whitespace-nowrap ms-auto text-n-slate-11"
          :title="dicaDaEtapa"
          data-etapa
        >
          {{ textoDaEtapa }}
          <span
            v-if="outrosAssuntos"
            class="px-1 rounded-full text-[10px] font-semibold leading-4 bg-n-alpha-2"
          >
            {{ $t('LISTA_DE_CONVERSAS.ETAPA.MAIS', { n: outrosAssuntos }) }}
          </span>
        </span>
      </span>
    </button>
  </div>
</template>
