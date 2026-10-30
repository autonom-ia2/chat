<script setup>
import { computed, provide, ref, useId, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmOpportunityForm from '../CrmOpportunityForm.vue';
import CardHeroi from './CardHeroi.vue';
import CardFaixa from './CardFaixa.vue';
import CardProximoPasso from './CardProximoPasso.vue';
import OrigemAnuncioMeta from './origem/OrigemAnuncioMeta.vue';
import CardResumo from './CardResumo.vue';
import CardLado from './CardLado.vue';
import CardRodape from './CardRodape.vue';
import DialogoGanhou from './DialogoGanhou.vue';
import DialogoPerdeu from './DialogoPerdeu.vue';
import TelaEtapa from './telas/TelaEtapa.vue';
import TelaNegocio from './telas/TelaNegocio.vue';
import TelaQuemCuida from './telas/TelaQuemCuida.vue';
import TelaCliente from './telas/TelaCliente.vue';
import TelaConversas from './telas/TelaConversas.vue';
import TelaRetornos from './telas/TelaRetornos.vue';
import TelaRetornoNovo from './telas/TelaRetornoNovo.vue';
import TelaAgenda from './telas/TelaAgenda.vue';
import TelaReuniaoNova from './telas/TelaReuniaoNova.vue';
import TelaLinkAgenda from './telas/TelaLinkAgenda.vue';
import { useCardAgendar } from './useCardAgendar';
import { useCardAbertura } from './useCardAbertura';
import { useCardDono } from './useCardDono';
import { useCardMover } from './useCardMover';
import TelaOrigem from './telas/TelaOrigem.vue';
import TelaHistorico from './telas/TelaHistorico.vue';
import LembreteSerie from '../lembrete/LembreteSerie.vue';
import MensagemMarcadaGaveta from '../mensagemMarcada/MensagemMarcadaGaveta.vue';
import { usaGavetaNova } from '../mensagemMarcada/useMensagemMarcada';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { passosDoCard } from './proximoPasso';
import { payloadDoNegocio, useCardNegocio } from './useCardNegocio';
import { useCardRetorno } from './useCardRetorno';
import { useCardHistorico } from './useCardHistorico';
import { useAvisoDeReuniao } from '../../composables/useAvisoDeReuniao';
import { useCardDesfecho } from './useCardDesfecho';
import { useCardTipo } from './useCardTipo';
import { useCardConversao } from './useCardConversao';
import { useCardCliente } from './useCardCliente';
import { useCardNomes } from './useCardNomes';
import { useCardGuarda } from './useCardGuarda';
import { useSugestaoEtapa } from './useSugestaoEtapa';
import { useProximaReuniao } from './useProximaReuniao';
import { useResumoConversa } from './useResumoConversa';
import { useCardMoldura } from './useCardMoldura';
import { useFormato } from './useFormato';
import { useFocoPreso } from './useFocoPreso';
import ArquivarCardDialogo from '../arquivados/ArquivarCardDialogo.vue';
import CardArquivado from '../arquivados/CardArquivado.vue';

// #1423 — o card do funil ("Resumo primeiro"), no lugar da gaveta antiga
// com abas. A página fala com ele por props, eventos e guardNavigation (o
// mesmo contrato de antes). O card abre em "como está este cliente
// agora": um Próximo passo, cartões-frase com "Alterar"/"Ver" e, à direita,
// onde ele está no funil. Cada parte abre numa tela própria.
const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' },
  card: { type: Object, default: null },
  initialTab: { type: String, default: null },
  initialContact: { type: Object, default: null },
  stages: { type: Array, default: () => [] },
  pipelines: { type: Array, default: () => [] },
  pipelineId: { type: [String, Number], default: '' },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  followUps: { type: Array, default: () => [] },
  canManageCards: { type: Boolean, default: false },
  canMoveCards: { type: Boolean, default: false },
  canDeleteCards: { type: Boolean, default: false },
  isMovingCard: { type: Boolean, default: false },
  canManageAi: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  isLoadingDetails: { type: Boolean, default: false },
  isArchiving: { type: Boolean, default: false },
  isFetchingFollowUps: { type: Boolean, default: false },
  isSavingFollowUp: { type: Boolean, default: false },
  meetingsEnabled: { type: Boolean, default: false },
  // #2095 (flag crm_arquivados): a janela nova de arquivar e o card arquivado com Restaurar.
  arquivadosLigado: { type: Boolean, default: false },
  erroArquivar: { type: String, default: '' },
  restaurando: { type: Boolean, default: false },
  erroRestaurar: { type: String, default: '' },
});

const emit = defineEmits([
  'close',
  'save',
  'move',
  'archive',
  'closeDeal',
  'createFollowUp',
  'completeFollowUp',
  'cancelFollowUp',
  'refreshCard',
  'restaurar',
]);

const { t, te, locale } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { canManageRelationshipRecords, canViewRelationshipRecords } =
  useRelationshipPermissions();
const formato = useFormato({ t, locale });
const gavetaId = `crm-card-gaveta-${useId()}`;

// ——— Card e permissões ———
const editando = computed(() => props.mode === 'edit');
const card = computed(() => props.card || {});
const cardId = computed(() => props.card?.id || null);
const iaLigada = computed(
  () =>
    store.getters['globalConfig/get']?.crmAiEnabled === true ||
    window.globalConfig?.CRM_AI_ENABLED === 'true'
);
// PM-08: os botões do assistente pedem também o funil do card (can_edit).
const podeIa = computed(
  () => props.canManageAi && (!editando.value || card.value.can_edit === true)
);
// #2150 — a sugestão de etapa da IA é de quem tem crm_manage_ai: sem a chave, a
// gaveta nem pede ao servidor (que recusaria) e não mostra a leitura da IA.
const leSugestao = computed(() => iaLigada.value && props.canManageAi);
const podeGerenciar = computed(() => props.canManageCards);
const podeMover = computed(() => props.canMoveCards);
const podeArquivar = computed(() => props.canDeleteCards);
const funil = computed(() => {
  const id = Number(card.value.pipeline_id || props.pipelineId);
  return props.pipelines.find(item => item.id === id);
});
// #1498 — Negócio (Vender) ou Assunto (Atender), e Cobrança.
const jeito = useCardTipo({ t, funil });
const etapaDoCard = computed(
  () =>
    props.stages.find(etapa => etapa.id === card.value.stage_id)?.name ||
    card.value.stage?.name ||
    ''
);
// A etapa não entra na migalha: ela é o rótulo do topo.
const migalha = computed(() => [funil.value?.name].filter(Boolean));

// ——— Desfecho (ST-01 a ST-07) ———
const {
  status,
  venda,
  rotulosProprios,
  rotuloGanhar,
  rotuloPerder,
  perdaPadrao,
  desfecho,
} = useCardDesfecho({ t, card, funil });
const { nome, titulo, subtitulo } = useCardNomes({ t, card, venda });

// ——— Partes do card ———
const negocio = useCardNegocio();
const atividades = computed(() => card.value.activities || []);
const { porDia } = useCardHistorico({
  t,
  te,
  locale,
  activities: atividades,
  // #1498 — Atender tem frases próprias ("Atendimento reaberto").
  textos: () =>
    jeito.atender.value
      ? ['CRM_CARD.HISTORICO.EVENTO_ATENDER', 'CRM_CARD.HISTORICO.EVENTO']
      : ['CRM_CARD.HISTORICO.EVENTO'],
});
const sugestao = useSugestaoEtapa({
  t,
  cardId,
  inicial: computed(() =>
    props.canManageAi ? props.card?.ai_suggestion || null : null
  ),
  ligada: computed(() => leSugestao.value && editando.value && props.show),
  aoMudar: () => emit('refreshCard'),
});
const reuniao = useProximaReuniao({
  accountId: computed(() => route.params.accountId),
  cardId,
  ligada: computed(() => props.meetingsEnabled && editando.value && props.show),
});
const conversas = computed(() => {
  if (card.value.linked_conversations?.length)
    return card.value.linked_conversations;
  return card.value.conversation ? [card.value.conversation] : [];
});

// Conversão para o Facebook e o Instagram (MT-01): só a linha deste card.
const conversao = useCardConversao({
  mostrar: computed(() => props.show),
  cardId,
});

// #2195 — quem chegou pelo formulário do anúncio da Meta e ainda não tem conversa: a origem e as respostas ficam
// abertas no card, e o próximo passo é chamar no WhatsApp.
const formularioMeta = computed(() => {
  const formulario = card.value.metadata?.meta_lead_form;
  return formulario?.fields?.length && !card.value.conversation?.display_id
    ? formulario
    : null;
});

const passos = computed(() =>
  passosDoCard({
    reuniao: reuniao.reuniao.value,
    retornos: props.followUps,
    esperaDesde: card.value.conversation?.waiting_since || null,
    sugestao: leSugestao.value ? sugestao.sugestao.value : null,
    formulario: formularioMeta.value,
    status: status.value,
  })
);

// ——— Telas ———
const tela = ref('resumo');
const pilha = ref([]);
const telaCliente = ref(null);
const criacao = ref(null);
const resumoConversa = useResumoConversa({
  card,
  detalhe: computed(() => !props.isLoadingDetails),
  ligada: iaLigada,
  aberta: computed(() => tela.value === 'conversas'),
});

const irPara = destino => {
  pilha.value = [...pilha.value, tela.value];
  tela.value = destino;
};
const voltarSemGuarda = () => {
  tela.value = pilha.value.at(-1) || 'resumo';
  pilha.value = pilha.value.slice(0, -1);
};

const useAccountFlags = useAccount();
const retorno = useCardRetorno({
  t,
  store,
  card,
  emit,
  podeGerenciar,
  formato,
  agentes: computed(() => props.agents),
  locale,
  lembretesV2: computed(() =>
    useAccountFlags.isCloudFeatureEnabled(FEATURE_FLAGS.CRM_LEMBRETES_V2)
  ),
  // Mudança de um lembrete que repete salva direto na API (#1460): volta à
  // repetição, que recarrega.
  aoSalvarEdicao: () => {
    voltarSemGuarda();
    emit('refreshCard');
  },
});
provide('cardRetorno', retorno);
// #1590: com a flag, "Mandar mensagem" de um card da caixa oficial abre a
// gaveta da Mensagem marcada (já com o cliente); fora disso, o retorno de sempre.
const mensagemNova = computed(
  () =>
    useAccountFlags.isCloudFeatureEnabled(FEATURE_FLAGS.CRM_MENSAGEM_MARCADA) &&
    usaGavetaNova(card.value, props.inboxes)
);
const mensagemAberta = ref(false);
// Marcou pela tela do retorno: volta para a Agenda, onde a mensagem aparece.
const mensagemMarcou = () => {
  emit('refreshCard');
  if (tela.value === 'retorno-novo') voltarSemGuarda();
};
// #1460: a visão da repetição de um lembrete, dentro do card.
const serieAberta = ref(null);
const serieTitulo = ref('');
const telaSerie = ref(null);
const abrirSerie = serieId => {
  serieAberta.value = serieId;
  irPara('retorno-serie');
};
// "Só a próxima" abre o lembrete sem repetição; "esta e as próximas", com ela.
const mudarSerie = escolha => {
  retorno.editarSerie(escolha);
  irPara('retorno-novo');
};

// ——— Quem cuida (DN-02/OB-07): troca o dono na própria gaveta ———
const dono = useCardDono({
  card,
  agentes: computed(() => props.agents),
  tela,
  podeGerenciar,
  emit,
  voltarSemGuarda,
});
const { escolhido: donoEscolhido, sujo: donoSujo, nome: donoNome } = dono;
// As telas de reunião e de link avisam quando estão enviando (ocupado).
const telaReuniao = ref(null);
const telaLink = ref(null);
// ——— Rascunhos e "Sair sem salvar?" (DS-01) ———
// Enquanto algo está indo para o servidor, a tela não fecha nem volta: a
// resposta precisa da tela aberta para avisar e recarregar.
const ocupado = () =>
  props.isSaving ||
  criacao.value?.sending ||
  telaCliente.value?.ocupado ||
  telaReuniao.value?.salvando ||
  telaLink.value?.ocupado;
const descarte = useCardGuarda({
  formato,
  tela,
  editando,
  rascunhos: () =>
    [
      negocio.sujo.value &&
        editando.value &&
        t(
          jeito.atender.value
            ? 'CRM_CARD.SAIR.ASSUNTO'
            : 'CRM_CARD.SAIR.NEGOCIO'
        ),
      retorno.sujo.value && t('CRM_CARD.SAIR.RETORNO'),
      donoSujo.value && t('CRM_CARD.SAIR.DONO'),
      telaCliente.value?.sujo && t('CRM_CARD.SAIR.CLIENTE'),
      !editando.value && criacao.value?.dirty && t('CRM_CARD.SAIR.CRIAR'),
    ].filter(Boolean),
  sujoNaTela: () => ({
    negocio: negocio.sujo.value,
    'retorno-novo': retorno.sujo.value,
    dono: donoSujo.value,
    contato: Boolean(telaCliente.value?.sujo),
    empresa: Boolean(telaCliente.value?.sujo),
  }),
  ocupado,
  descartarTudo: () => {
    negocio.desfazer();
    retorno.reiniciar();
    telaCliente.value?.desfazer();
    dono.desfazer();
  },
});
const { guardar } = descarte;
const dialogoDescartar = descarte.dialogo;
const descartarAberto = descarte.aberto;

const fechar = () => guardar(() => emit('close'), { leaving: true });
const voltar = () =>
  guardar(() => {
    if (tela.value === 'negocio') negocio.desfazer();
    if (tela.value === 'retorno-novo') retorno.reiniciar();
    if (['contato', 'empresa'].includes(tela.value))
      telaCliente.value?.desfazer();
    voltarSemGuarda();
  });
const abrir = destino => irPara(destino);
const abrirConversa = (numero = card.value.conversation?.display_id) => {
  if (!numero) return;
  guardar(
    () =>
      router.push({
        name: 'inbox_conversation',
        params: { accountId: route.params.accountId, conversation_id: numero },
      }),
    { leaving: true }
  );
};
const voltarAoContato = () =>
  guardar(() =>
    router.push({
      name: 'contacts_edit',
      params: {
        accountId: route.params.accountId,
        contactId: props.initialContact.id,
      },
    })
  );

// ——— Ações ———
const dialogoGanhou = ref(null);
const dialogoPerdeu = ref(null);
const dialogoArquivar = ref(null);
const { isCloudFeatureEnabled } = useAccount();
const empresasLigadas = computed(() => isCloudFeatureEnabled('companies'));
const cliente = useCardCliente({
  t,
  store,
  card,
  podeRegistros: canManageRelationshipRecords,
  aoMudar: () => emit('refreshCard'),
});
const dialogoCliente = cliente.dialogo;
const ganhou = () =>
  guardar(() => {
    if (!podeGerenciar.value) return;
    if (!venda.value) emit('closeDeal', { result: 'won' });
    else dialogoGanhou.value?.abrir(props.card);
  });
const perdeu = () =>
  guardar(() => podeGerenciar.value && dialogoPerdeu.value?.abrir(props.card));
const reabrir = () =>
  guardar(() => podeGerenciar.value && emit('closeDeal', { result: 'reopen' }));
const fecharNegocio = dados => podeGerenciar.value && emit('closeDeal', dados);
// A reunião marcada continua de pé ao arquivar (#2091): o diálogo avisa.
// Arquivar espera o aviso chegar (carregando, com teto em useAvisoDeReuniao).
const {
  aviso: avisoDeReuniao,
  carregando: carregandoAviso,
  consultar: consultarReuniao,
} = useAvisoDeReuniao();
const arquivar = () =>
  guardar(() => {
    if (!podeArquivar.value) return;
    consultarReuniao(cardId.value ? [cardId.value] : []);
    dialogoArquivar.value?.open();
  });
const confirmarArquivar = () => {
  if (carregandoAviso.value) return;
  dialogoArquivar.value?.close();
  if (podeArquivar.value) emit('archive');
};
// #2095: com a flag, a janela nova fica aberta até a página responder (erro aparece nela; o sucesso fecha o card).
const arquivado = computed(
  () => props.arquivadosLigado && status.value === 'archived'
);
const dialogoArquivarNovo = ref(null);
const arquivarNovo = () =>
  guardar(() => {
    if (!podeArquivar.value) return;
    consultarReuniao(cardId.value ? [cardId.value] : []);
    dialogoArquivarNovo.value?.open();
  });
// O que o Archiver cancela: lembretes por vencer, menos o da reunião marcada.
const retornosQueParam = computed(
  () =>
    props.followUps.filter(
      item =>
        ['pending', 'overdue'].includes(item.status) &&
        item.follow_up_type !== 'meeting'
    ).length
);
const confirmarArquivarNovo = () =>
  podeArquivar.value && emit('archive', { retornos: retornosQueParam.value });
const vendaQueContinua = computed(() =>
  status.value === 'won' && venda.value && !card.value.value_hidden
    ? formato.dinheiro(card.value.value_cents, card.value.currency)
    : ''
);
watch(
  () => props.show,
  aberta => {
    if (!aberta) dialogoArquivarNovo.value?.close();
  }
);
const {
  dialogo: dialogoMover,
  pedida: etapaPedida,
  mover,
  pedir: pedirMover,
  confirmar: confirmarMover,
} = useCardMover({
  podeMover,
  movendo: computed(() => props.isMovingCard),
  emit,
});
const feito = item => podeGerenciar.value && emit('completeFollowUp', item);
const cancelarRetorno = item =>
  podeGerenciar.value && emit('cancelFollowUp', item);
// Novo lembrete, mensagem no dia ou esconder a conversa: a escolha feita na
// Agenda já chega marcada.
const novoRetorno = (modo = 'reminder_only') => {
  if (!podeGerenciar.value) return;
  // #1590: a mensagem no dia abre a gaveta da Mensagem marcada.
  if (modo === 'auto_send_message' && mensagemNova.value) {
    mensagemAberta.value = true;
    return;
  }
  retorno.reiniciar(modo);
  irPara('retorno-novo');
};
const criarRetorno = () => retorno.criar();
const adiarRetorno = retorno.adiar;

// ——— Reunião e link da agenda: telas da própria gaveta ———
const {
  linkAgenda,
  jeitoDeMarcar,
  marcarReuniao,
  confirmarReuniao,
  reuniaoMarcada,
  abrirLink,
  linkCaiu,
  criarPagina,
} = useCardAgendar({
  t,
  store,
  router,
  props,
  cardId,
  editando,
  podeGerenciar,
  tela,
  irPara,
  voltarSemGuarda,
  guardar,
  reuniao,
  telaReuniao,
  aoMudar: () => emit('refreshCard'),
});

// A página chama o 3º argumento quando salvou: a tela volta ao resumo.
const salvarNegocio = () => {
  if (!podeGerenciar.value || !negocio.valido.value) return;
  const payload = payloadDoNegocio(negocio.form, {
    cobranca: jeito.cobranca.value,
    valorOculto: Boolean(card.value.value_hidden),
  });
  emit('save', payload, undefined, () => {
    negocio.carregar({ ...props.card, ...payload });
    if (tela.value === 'negocio') voltarSemGuarda();
  });
};

const salvarDono = dono.salvar;

// ——— Molde de cada tela ———
const { heroi, rodape } = useCardMoldura({
  t,
  tela,
  pilha,
  titulo,
  subtitulo,
  migalha,
  nome,
  jeito,
  etapa: etapaDoCard,
  contatoInicial: computed(() => props.initialContact),
  permissoes: {
    gerenciar: podeGerenciar,
    verContatos: canViewRelationshipRecords,
  },
  estado: {
    salvando: computed(() => props.isSaving),
    negocioValido: negocio.valido,
    salvandoRetorno: computed(
      () => props.isSavingFollowUp || retorno.salvandoEdicao.value
    ),
    retornoPronto: retorno.pronto,
    modoRetorno: computed(() => retorno.form.automationMode),
    salvandoReuniao: computed(() => Boolean(telaReuniao.value?.salvando)),
    reuniaoMostrandoLink: computed(() =>
      Boolean(telaReuniao.value?.mostrandoLink)
    ),
    reuniaoExterna: computed(() => Boolean(telaReuniao.value?.externa)),
    link: computed(() => telaLink.value?.principal || null),
    donoSujo,
    retornoFalta: retorno.faltaFrase,
    serieTitulo,
    edicaoRetorno: computed(() => retorno.edicao.value?.qual || ''),
    cliente: computed(() => telaCliente.value),
    criacao: computed(() => criacao.value),
  },
  acoes: {
    fechar,
    voltar,
    salvarNegocio,
    salvarDono,
    confirmarReuniao,
    novoRetorno,
    criarRetorno,
    abrirMudarSerie: () => telaSerie.value?.abrirMudar(),
    desfazerCliente: () => telaCliente.value?.desfazer(),
    passo1: () => {
      tela.value = 'criar-1';
    },
    passo2: () => {
      tela.value = 'criar-2';
    },
  },
});
const voltarDoHeroi = () => {
  if (tela.value === 'criar-1') voltarAoContato();
  else if (tela.value === 'criar-2') tela.value = 'criar-1';
  else voltar();
};

// ——— Abrir, re-hidratar e foco (DS-02, TK-02) ———
const conteudo = ref(null);
const raiz = ref(null);
const { prender } = useFocoPreso({ raiz, mostrar: computed(() => props.show) });

useCardAbertura({
  props,
  abaInicial: () => props.initialTab,
  editando,
  negocio,
  retorno,
  reuniao,
  tela,
  pilha,
  irPara,
  conteudo,
  raiz,
  fechar,
  voltarDoHeroi,
  descartando: descartarAberto,
});

defineExpose({
  resetFollowUpForm: () => {
    retorno.reiniciar();
    if (tela.value === 'retorno-novo') voltarSemGuarda();
  },
  guardNavigation: guardar,
  refreshMessagingWindow: retorno.atualizarJanela,
});
</script>

<template>
  <Dialog
    ref="dialogoDescartar"
    type="alert"
    :title="t('CRM_CARD.SAIR.TITULO')"
    :description="t('CRM_CARD.SAIR.TEXTO', { coisas: descarte.perdas.value })"
    :confirm-button-label="t('CRM_CARD.SAIR.CONFIRMA')"
    :cancel-button-label="t('CRM_CARD.SAIR.CONTINUAR')"
    @confirm="descarte.confirmar"
    @close="descarte.aberto.value = false"
  />
  <ArquivarCardDialogo
    v-if="arquivadosLigado"
    ref="dialogoArquivarNovo"
    :nome="nome"
    :retornos="retornosQueParam"
    :aviso-de-reuniao="avisoDeReuniao"
    :venda-que-continua="vendaQueContinua"
    :ocupado="isArchiving"
    :erro="erroArquivar"
    @confirmar="confirmarArquivarNovo"
  />
  <Dialog
    v-else
    ref="dialogoArquivar"
    type="alert"
    :title="t('CRM_CARD.ARQUIVAR.TITULO', { nome: titulo })"
    :description="t('CRM_CARD.ARQUIVAR.TEXTO')"
    :confirm-button-label="t('CRM_CARD.ARQUIVAR.BOTAO')"
    :is-loading="isArchiving || carregandoAviso"
    @confirm="confirmarArquivar"
  >
    <p
      v-if="avisoDeReuniao"
      data-aviso-reuniao
      class="mb-0 text-sm text-n-amber-11"
    >
      {{ avisoDeReuniao }}
    </p>
  </Dialog>
  <Dialog
    ref="dialogoCliente"
    :type="cliente.virar.value ? 'edit' : 'alert'"
    :title="t(`${cliente.chave.value}.TITLE`)"
    :description="t(`${cliente.chave.value}.DESCRIPTION`)"
    :confirm-button-label="t(`${cliente.chave.value}.CONFIRM`)"
    :is-loading="cliente.salvando.value"
    @confirm="cliente.confirmar"
  />
  <Dialog
    ref="dialogoMover"
    :title="t('CRM_CARD.MOVER.TITULO', { etapa: etapaPedida?.name || '' })"
    :description="t('CRM_CARD.MOVER.TEXTO', { nome })"
    :confirm-button-label="t('CRM_CARD.MOVER.CONFIRMA')"
    @confirm="confirmarMover"
  />
  <DialogoGanhou
    ref="dialogoGanhou"
    :rotulo="rotuloGanhar"
    :padrao="venda && !rotulosProprios.success"
    :achado-na-conversa="card.ai_value?.source === 'ai'"
    @confirmar="fecharNegocio"
  />
  <DialogoPerdeu
    ref="dialogoPerdeu"
    :rotulo="rotuloPerder"
    :venda="venda"
    :padrao="perdaPadrao"
    @confirmar="fecharNegocio"
  />
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <div
      v-if="show"
      ref="raiz"
      data-crm-card-drawer
      data-card-gaveta
      :data-tela="tela"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="`${gavetaId}-titulo`"
      :aria-describedby="`${gavetaId}-texto`"
      tabindex="-1"
      class="fixed inset-y-0 z-50 flex h-full w-[80rem] max-w-full flex-col overflow-hidden bg-n-solid-1 shadow-2xl outline-none ltr:right-0 rtl:left-0"
      @keydown="prender"
    >
      <CardHeroi
        v-bind="heroi"
        :contato="tela === 'resumo' ? card.contact : null"
        :titulo-id="`${gavetaId}-titulo`"
        :texto-id="`${gavetaId}-texto`"
        @voltar="voltarDoHeroi"
        @fechar="fechar"
      />
      <CardFaixa
        v-if="editando && tela === 'resumo'"
        :status="desfecho.status"
        :status-tom="desfecho.tom"
        :aberto="desfecho.aberto"
        :ganhar="rotuloGanhar"
        :perder="rotuloPerder"
        :venda="venda"
        :pode-gerenciar="podeGerenciar"
        :carregando="isLoadingDetails"
        @ganhou="ganhou"
        @perdeu="perdeu"
      />

      <div ref="conteudo" class="min-h-0 flex-1 overflow-y-auto">
        <div
          class="grid min-h-full grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,1fr)_32rem]"
        >
          <main class="flex min-w-0 flex-col gap-3 px-5 py-3 sm:px-8">
            <template v-if="!editando">
              <CrmOpportunityForm
                :key="`${route.params.accountId}:${initialContact?.id || 'new'}`"
                ref="criacao"
                :passo="tela === 'criar-2' ? 2 : 1"
                :initial-contact="initialContact"
                :pipelines="pipelines"
                :pipeline-id="pipelineId"
                :stages="stages"
                :agents="agents"
                :inboxes="inboxes"
                :can-manage="canManageCards"
                :can-create-contact="canManageRelationshipRecords"
                :can-pick-contact="canViewRelationshipRecords"
                @passo="tela = 'criar-1'"
                @save="(payload, failed) => emit('save', payload, failed)"
              />
            </template>

            <template v-else-if="tela === 'resumo'">
              <CardArquivado
                v-if="arquivado"
                :card="card"
                :funil="funil"
                :formato="formato"
                :pode-arquivar="podeArquivar"
                :ocupado="restaurando"
                :erro="erroRestaurar"
                @restaurar="emit('restaurar')"
              />
              <CardProximoPasso
                v-else
                :passos="passos"
                :nome="nome"
                :formato="formato"
                :pode-gerenciar="podeGerenciar"
                :pode-ia="podeIa"
                :tem-conversa="Boolean(card.conversation?.display_id)"
                :ocupado="isSavingFollowUp || sugestao.respondendo.value"
                :status="desfecho.status"
                :venda="venda"
                :contato-id="card.contact_id ? String(card.contact_id) : null"
                @responder="abrirConversa()"
                @feito="feito"
                @retorno="novoRetorno"
                @abrir="abrir"
                @aceitar="sugestao.aceitar"
                @dispensar="sugestao.dispensar"
                @reabrir="reabrir"
              />
              <OrigemAnuncioMeta
                v-if="formularioMeta"
                :formulario="formularioMeta"
              />
              <CardResumo
                :card="card"
                :etapas="stages"
                :reuniao="reuniao.reuniao.value"
                :retornos="followUps"
                :passos="passos"
                :sugestao="sugestao.sugestao.value"
                :ia="iaLigada"
                :resumo="{
                  texto: resumoConversa.texto.value,
                  quando: resumoConversa.quando.value,
                }"
                :conversas="conversas"
                :conversao="conversao"
                :formato="formato"
                :nome="nome"
                :pode-gerenciar="podeGerenciar"
                :pode-arquivar="podeArquivar && !arquivado"
                :pode-registros="canManageRelationshipRecords"
                :pode-ver-contatos="canViewRelationshipRecords"
                :arquivando="isArchiving"
                :empresas="empresasLigadas"
                :jeito="jeito"
                @abrir="abrir"
                @arquivar="arquivadosLigado ? arquivarNovo() : arquivar()"
                @conversa="abrirConversa()"
                @cliente="cliente.pedir"
              />
            </template>

            <TelaEtapa
              v-else-if="tela === 'etapa'"
              :etapas="stages"
              :atual="card.stage_id"
              :pode-mover="podeMover"
              :movendo="isMovingCard"
              :leitura="leSugestao"
              :pode-ia="podeIa"
              :sugestao="sugestao.sugestao.value"
              :carregando="sugestao.carregando.value"
              :lendo="sugestao.lendo.value"
              :respondendo="sugestao.respondendo.value"
              :aviso="sugestao.aviso.value"
              @mover="mover"
              @ler="sugestao.lerDeNovo"
              @aceitar="sugestao.aceitar"
              @dispensar="sugestao.dispensar"
            />
            <TelaNegocio
              v-else-if="tela === 'negocio'"
              v-model:titulo="negocio.form.title"
              v-model:descricao="negocio.form.description"
              v-model:valor="negocio.form.valueAmount"
              v-model:moeda="negocio.form.currency"
              v-model:urgencia="negocio.form.priority"
              v-model:atencao="negocio.form.score"
              v-model:fechar-ate="negocio.form.expectedCloseAt"
              v-model:promessa="negocio.form.paymentPromiseAt"
              :card="card"
              :jeito="jeito"
              :pode-gerenciar="podeGerenciar"
            />
            <TelaQuemCuida
              v-else-if="tela === 'dono'"
              v-model:dono="donoEscolhido"
              :card="card"
              :conversas="conversas"
              :agentes="agents"
              :pode-gerenciar="podeGerenciar"
            />
            <TelaCliente
              v-else-if="tela === 'contato' || tela === 'empresa'"
              ref="telaCliente"
              :parte="tela === 'contato' ? 'pessoa' : 'empresa'"
              :card="card"
              :pode-gerenciar="podeGerenciar"
              :pode-registros="canManageRelationshipRecords"
              :pode-ver-contatos="canViewRelationshipRecords"
              @guard="guardar"
              @mudou="emit('refreshCard')"
            />
            <TelaConversas
              v-else-if="tela === 'conversas'"
              :conversas="conversas"
              :formato="formato"
              :carregando="isLoadingDetails"
              :resumo="{
                texto: resumoConversa.texto.value,
                quando: resumoConversa.quando.value,
                carregando: resumoConversa.carregando.value,
                erro: resumoConversa.erro.value,
                temConversa: resumoConversa.temConversa.value,
              }"
              :ia="iaLigada"
              :pode-ia="podeIa"
              @abrir="abrirConversa"
              @atualizar="resumoConversa.gerar"
            />
            <TelaRetornoNovo
              v-else-if="tela === 'retorno-novo'"
              :funil="funil?.name || ''"
              :mensagem-nova="mensagemNova"
              @mensagem-nova="mensagemAberta = true"
            />
            <LembreteSerie
              v-else-if="tela === 'retorno-serie' && serieAberta"
              ref="telaSerie"
              :serie-id="serieAberta"
              :pode-gerenciar="podeGerenciar"
              :formato="formato"
              @carregou="serie => (serieTitulo = serie.title)"
              @mudou="emit('refreshCard')"
              @mudar="mudarSerie"
            />
            <TelaReuniaoNova
              v-else-if="tela === 'reuniao-nova'"
              ref="telaReuniao"
              :card="card"
              :paginas="jeitoDeMarcar.paginas.value"
              :caixas="inboxes"
              :tem-caixa="jeitoDeMarcar.temCaixa.value"
              :account-id="route.params.accountId"
              @marcou="reuniaoMarcada"
            />
            <TelaLinkAgenda
              v-else-if="tela === 'link-agenda'"
              ref="telaLink"
              :card="card"
              :nome="nome"
              @enviou="voltarSemGuarda"
              @sem-link="linkCaiu"
              @criar-pagina="criarPagina"
            />
            <TelaAgenda
              v-else-if="tela === 'agenda'"
              :card="card"
              :reuniao="reuniao.reuniao.value"
              :account-id="route.params.accountId"
              :formato="formato"
              :pode-gerenciar="podeGerenciar"
              :reunioes="meetingsEnabled"
              :link-agenda="linkAgenda"
              :tem-conversa="retorno.temConversa.value"
              :jeito="jeitoDeMarcar.jeito.value"
              :pode-criar-pagina="jeitoDeMarcar.podeCriarPagina.value"
              @novo="novoRetorno"
              @reuniao="marcarReuniao"
              @link="abrirLink"
              @criar-pagina="criarPagina"
              @mudou="reuniao.recarregar"
              @sem-link="linkCaiu"
            >
              <template #retornos>
                <TelaRetornos
                  :card="card"
                  :retornos="followUps"
                  :formato="formato"
                  :carregando="isFetchingFollowUps"
                  :salvando="isSavingFollowUp"
                  :pode-gerenciar="podeGerenciar"
                  :pode-ia="podeIa"
                  :pode-registros="canManageRelationshipRecords"
                  @feito="feito"
                  @cancelar="cancelarRetorno"
                  @adiar="adiarRetorno"
                  @mudou="emit('refreshCard')"
                  @serie="abrirSerie"
                />
              </template>
            </TelaAgenda>
            <TelaOrigem
              v-else-if="tela === 'origem'"
              :card="card"
              :conversao="conversao"
              @conversa="abrirConversa()"
            />
            <TelaHistorico
              v-else-if="tela === 'historico'"
              :dias="porDia"
              :carregando="isLoadingDetails"
              :venda="venda"
            />
          </main>

          <aside
            data-card-lado
            class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-5"
          >
            <CardLado
              :tela="tela"
              :card="card"
              :etapas="stages"
              :funil="funil?.name || ''"
              :nome="nome"
              :exemplo="editando ? titulo : t('CRM_CARD.LADO.CLIENTE_NOVO')"
              :formato="formato"
              :negocio="tela === 'negocio' ? negocio.form : null"
              :atender="jeito.atender.value"
              :cobranca="jeito.cobranca.value"
              :retorno="tela === 'retorno-novo' ? retorno.previa.value : null"
              :dono="donoNome"
              :reuniao="reuniao.reuniao.value"
              :criacao="editando ? null : criacao?.escolha || null"
              :funis="pipelines"
              :pode-mover="
                editando &&
                podeMover &&
                !isMovingCard &&
                ['resumo', 'etapa'].includes(tela)
              "
              @mover="pedirMover"
            />
          </aside>
        </div>
      </div>

      <CardRodape
        v-if="rodape"
        :rodape="rodape"
        :ocupado="Boolean(ocupado())"
      />
      <MensagemMarcadaGaveta
        v-if="mensagemNova"
        :show="mensagemAberta"
        :card="card"
        :caixas="inboxes"
        @salvou="mensagemMarcou"
        @close="mensagemAberta = false"
      />
    </div>
  </transition>
</template>
