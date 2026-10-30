<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CardMolduraLado from './previas/CardMolduraLado.vue';
import FunilQuadro from '../funil/FunilQuadro.vue';
import CardFicha from './previas/CardFicha.vue';
import PreviaNegocio from './previas/PreviaNegocio.vue';
import PreviaRetorno from './previas/PreviaRetorno.vue';

// #1423 — a coluna da direita. Nas telas que mudam algo, a prévia do que vai
// mudar ("Prévia"), tirada do mesmo estado do formulário. Nas outras, só
// "Onde está no funil": nada do que a esquerda já mostra se repete aqui. "Onde
// está no funil" é o mesmo quadro das telas de funil (FunilQuadro, #1414):
// colunas sempre, rolagem para o lado com setas e "mais N etapas", e a coluna
// do cliente acesa, com o cartão dele dentro, rolada até o meio.
const props = defineProps({
  tela: { type: String, required: true },
  card: { type: Object, default: null },
  etapas: { type: Array, default: () => [] },
  funil: { type: String, default: '' },
  nome: { type: String, default: '' },
  // O nome no cartão dentro do quadro: o mesmo título do topo do card.
  exemplo: { type: String, default: '' },
  formato: { type: Object, required: true },
  negocio: { type: Object, default: null },
  retorno: { type: Object, default: null },
  // Quem cuida escolhido na tela "Quem cuida" (prévia da troca).
  dono: { type: String, default: '' },
  reuniao: { type: Object, default: null },
  // Tocar numa coluna do quadro move o cliente (com confirmação na gaveta).
  podeMover: { type: Boolean, default: false },
  // Criação: o funil (funilId), as etapas e a etapa (etapaId) escolhidos no
  // passo 2; o nome do funil vem de `funis`.
  criacao: { type: Object, default: null },
  funis: { type: Array, default: () => [] },
  // #1498 — Atender não mostra valor (só a Cobrança) nem a nota de atenção.
  atender: { type: Boolean, default: false },
  cobranca: { type: Boolean, default: false },
});

defineEmits(['mover']);

const { t } = useI18n();
const L = 'CRM_CARD.LADO';
const corDaEtapa = computed(
  () =>
    props.etapas.find(etapa => etapa.id === props.card?.stage_id)?.color ||
    props.card?.stage?.color
);
const URGENCIA = {
  low: 'LOW',
  medium: 'MEDIUM',
  high: 'HIGH',
  urgent: 'URGENT',
};
const quadro = computed(() => {
  const dados = props.negocio || {
    title: props.card?.title,
    valueAmount: (props.card?.value_cents || 0) / 100,
    currency: props.card?.currency,
    priority: props.card?.priority,
    score: props.card?.score,
  };
  return {
    cor: corDaEtapa.value,
    cliente: props.nome,
    titulo: dados.title,
    valor:
      Number(dados.valueAmount) && (!props.atender || props.cobranca)
        ? props.formato.dinheiro(
            Math.round(Number(dados.valueAmount) * 100),
            dados.currency
          )
        : '',
    urgencia: t(`CRM_KANBAN.PRIORITY.${URGENCIA[dados.priority] || 'MEDIUM'}`),
    urgente: ['high', 'urgent'].includes(dados.priority),
    atencao: props.atender ? 0 : Number(dados.score) || 0,
    quemCuida: props.dono || props.card?.owner?.name || '',
  };
});
// Reunião marcada: quem participa e quem marcou. A esquerda já mostra quando,
// o assunto e o telefone; aqui vem o que ela não mostra.
const MARCOU_PELO_CLIENTE = ['public_link', 'invite'];
const quemMarcou = reuniao => {
  if (MARCOU_PELO_CLIENTE.includes(reuniao.source))
    return t(`${L}.MARCOU_CLIENTE`);
  if (reuniao.source === 'ai') return t(`${L}.MARCOU_ASSISTENTE`);
  // Sem quem marcou só quando a pessoa foi excluída da plataforma (#2135).
  return reuniao.scheduled_by?.name || t(`${L}.PESSOA_REMOVIDA`);
};
const fichaReuniao = computed(() => {
  const reuniao = props.reuniao;
  if (!reuniao) return [];
  const convidados = (reuniao.guests || []).filter(
    convidado => convidado.guest_type !== 'contact_guest'
  ).length;
  return [
    { rotulo: t(`${L}.CLIENTE`), valor: reuniao.client?.name || props.nome },
    {
      rotulo: t(`${L}.QUEM_CUIDA`),
      valor: props.card?.owner?.name || t('CRM_KANBAN.CARD.NO_OWNER'),
    },
    { rotulo: t(`${L}.QUEM_MARCOU`), valor: quemMarcou(reuniao) },
    ...(convidados
      ? [
          {
            rotulo: t(`${L}.CONVIDADOS`),
            valor: t(`${L}.N_CONVIDADOS`, { n: convidados }, convidados),
          },
        ]
      : []),
  ];
});
const em = (...telas) => telas.includes(props.tela);

// O quadro do funil recebe as etapas no formato do FunilQuadro.
const paraQuadro = lista =>
  lista.map(etapa => ({
    chave: etapa.id,
    nome: etapa.name,
    cor: etapa.color,
    total: Number.isFinite(etapa.total_cards_count)
      ? etapa.total_cards_count
      : null,
  }));
const quadroDoCard = computed(() => paraQuadro(props.etapas));
const colunaDoCard = computed(() =>
  props.etapas.findIndex(etapa => etapa.id === props.card?.stage_id)
);
const etapasDaCriacao = computed(() =>
  props.criacao?.etapas?.length ? props.criacao.etapas : props.etapas
);
const quadroDaCriacao = computed(() => paraQuadro(etapasDaCriacao.value));
const funilDaCriacao = computed(
  () =>
    props.funis.find(item => String(item.id) === String(props.criacao?.funilId))
      ?.name || ''
);
const colunaDaCriacao = computed(() => {
  const alvo = String(props.criacao?.etapaId || etapasDaCriacao.value[0]?.id);
  return etapasDaCriacao.value.findIndex(etapa => String(etapa.id) === alvo);
});
</script>

<template>
  <div class="flex flex-col gap-4 lg:sticky lg:top-7">
    <CardMolduraLado
      v-if="em('negocio')"
      selo="previa"
      :titulo="t(`${L}.QUADRO_TITULO`)"
      :texto="t(`${L}.QUADRO_TEXTO`)"
    >
      <PreviaNegocio v-bind="quadro" />
    </CardMolduraLado>
    <CardMolduraLado
      v-else-if="em('dono')"
      :selo="dono && dono !== card?.owner?.name ? 'previa' : 'agora'"
      :titulo="t(`${L}.QUADRO_TITULO`)"
      :texto="t(`${L}.DONO_TEXTO`)"
    >
      <PreviaNegocio v-bind="quadro" />
    </CardMolduraLado>
    <CardMolduraLado
      v-else-if="em('retorno-novo') && retorno"
      selo="previa"
      :titulo="t(`${L}.RETORNO_TITULO`)"
      :texto="t(`${L}.RETORNO_TEXTO`)"
    >
      <PreviaRetorno v-bind="retorno" :cliente="nome" />
    </CardMolduraLado>
    <CardMolduraLado
      v-else-if="em('agenda') && reuniao"
      :titulo="t(`${L}.PARTICIPA_TITULO`)"
      :texto="t(`${L}.PARTICIPA_TEXTO`)"
    >
      <CardFicha :linhas="fichaReuniao" />
    </CardMolduraLado>
    <CardMolduraLado
      v-else-if="em('criar-1', 'criar-2')"
      selo="previa"
      :titulo="t(`${L}.CRIAR_TITULO`)"
      :texto="t(`${L}.CRIAR_TEXTO`)"
    >
      <FunilQuadro
        :nome="funilDaCriacao || funil"
        :etapas="quadroDaCriacao"
        :chegando="colunaDaCriacao"
        :exemplo="exemplo"
      />
    </CardMolduraLado>
    <CardMolduraLado
      v-else
      :titulo="t(`${L}.FUNIL_TITULO`)"
      :texto="
        em('etapa')
          ? t(`${L}.ETAPA_TEXTO`)
          : podeMover && em('resumo')
            ? t(`${L}.TOQUE_PARA_MOVER`)
            : ''
      "
    >
      <FunilQuadro
        v-if="etapas.length"
        :nome="funil"
        :etapas="quadroDoCard"
        :acesa="colunaDoCard"
        :chegando="colunaDoCard"
        :exemplo="exemplo"
        :clicavel="podeMover"
        :rotulo-escolher="etapa => t(`${L}.MOVER_PARA`, { etapa })"
        @escolher="indice => $emit('mover', etapas[indice])"
      />
    </CardMolduraLado>
  </div>
</template>
