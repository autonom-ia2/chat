<script setup>
import { computed } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import PassagemCartao from './PassagemCartao.vue';
import PassagemAvisoOnline from './PassagemAvisoOnline.vue';
import {
  ETAPA_DESLIGADA,
  MAX_PROPRIAS_UMA_A_UMA,
  etapasPorModo,
  juntarNomes,
  minutosDe,
  nomeDe,
  podeFicarSemResposta,
  textoDoJeito,
} from './passagem';

// #1385 — a regra do funil inteira em frases, cada parte com um controle só: "Alterar" ou, no cartão de cima, o
// liga/desliga. O liga/desliga e o "Corrigir agora" gravam na hora (quem grava é a página). Desligada, sobra o cartão
// de cima, e o de etapas só quando alguma etapa chama a equipe do seu jeito.
const props = defineProps({
  regra: { type: Object, required: true },
  etapas: { type: Array, required: true },
  pessoas: { type: Array, default: () => [] },
  incompletas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
  salvando: { type: Boolean, default: false },
  iaLigada: { type: Boolean, default: true },
});

const emit = defineEmits(['abrir', 'ligar', 'corrigir']);

const { t, locale } = useI18n();
const R = 'CRM_KANBAN.PASSAGEM.RESUMO';

const ligada = computed({
  get: () => props.regra.enabled,
  set: valor => emit('ligar', valor),
});
const semResposta = computed(() => podeFicarSemResposta(props.regra));
// Sem a assistente do funil ligada, ninguém atende: a frase de desligada não pode dizer que ela atende sozinha.
const chaveDoEstado = computed(() => {
  if (ligada.value) return `${R}.LIGADA`;
  return props.iaLigada ? `${R}.DESLIGADA` : `${R}.DESLIGADA_SEM_IA`;
});
// A regra antiga não olha quem está online (HandoffMemberSelector#preferred_pool): as frases não prometem isso.
const olhaOnline = computed(() => props.regra.prefer_online);
const naHora = computed(() => props.regra.handoff_mode === 'r2_direct');
const quando = computed(() => props.regra.trigger.trim());
const pessoa = computed(() => nomeDe(props.pessoas, props.regra.pool_id));
const outra = computed(() =>
  nomeDe(props.pessoas, props.regra.escalation_user_id)
);
const grupos = computed(() => etapasPorModo(props.etapas, props.regra));
const nomes = lista =>
  juntarNomes(
    lista.map(etapa => etapa.nome),
    locale.value
  );
const minutos = computed(() =>
  t(`${R}.MINUTOS`, { n: minutosDe(props.regra) })
);

// A linha de baixo do "Como entregar": o que acontece quando ninguém está online, do jeito que o back-end faz.
const linhaDoComo = computed(() => {
  if (!naHora.value) {
    return props.regra.escalation_action === 'escalate'
      ? t(`${R}.COMO_CONVITE_PASSA`, {
          minutos: minutos.value,
          nome: outra.value || t(`${R}.ALGUEM`),
        })
      : t(`${R}.COMO_CONVITE_AVISA`, { minutos: minutos.value });
  }
  if (props.regra.pool_type === 'user' && pessoa.value) {
    return t(`${R}.COMO_NA_HORA_FORA_PESSOA`, { nome: pessoa.value });
  }
  return t(`${R}.COMO_NA_HORA_FORA`);
});

// O que foge do resto, em fatos: "Em Proposta enviada, a equipe recebe um convite. Em Fechado, a equipe não é chamada."
// Com muitas etapas do seu jeito, uma frase só com os nomes; o jeito de cada uma fica na tela de etapas.
const frasesDasProprias = proprias => {
  if (proprias.length > MAX_PROPRIAS_UMA_A_UMA) {
    return [t(`${R}.ETAPAS_PROPRIAS`, { nomes: nomes(proprias) })];
  }
  return proprias.map(etapa =>
    t(`${R}.ETAPAS_EM`, {
      nome: etapa.nome,
      jeito: textoDoJeito(t, etapa.regra, props.pessoas, 'FRASE'),
    })
  );
};
const linhaDasEtapas = computed(() => {
  const proprias = frasesDasProprias(grupos.value.proprias);
  const desligadas = props.etapas.filter(
    etapa => etapa.modo === ETAPA_DESLIGADA
  );
  const sem = desligadas.length
    ? [t(`${R}.ETAPAS_SEM_EM`, { nomes: nomes(desligadas) })]
    : [];
  return [...proprias, ...sem].join(' ');
});
const mostraEtapas = computed(
  () => ligada.value || grupos.value.proprias.length > 0
);
const faltaNoFunil = computed(
  () => props.mostrarErros && props.incompletas.includes('funil')
);
const faltaNaEtapa = computed(
  () => props.mostrarErros && props.incompletas.some(id => id !== 'funil')
);
</script>

<template>
  <PassagemCartao
    v-model:ligado="ligada"
    parte="ligada"
    icone="i-lucide-user-round-check"
    tom="bg-n-teal-3 text-n-teal-11"
    :titulo="t(`${R}.LIGADA_TITULO`)"
    :apagado="!ligada"
    :ocupado="salvando"
    interruptor
  >
    <I18nT :keypath="chaveDoEstado" tag="span" scope="global">
      <template #estado>
        <strong class="font-semibold">{{
          t(ligada ? `${R}.LIGADA_SIM` : `${R}.LIGADA_NAO`)
        }}</strong>
      </template>
    </I18nT>
    <template v-if="!ligada && grupos.proprias.length" #extra>
      <p class="mb-0 mt-1 text-[0.9375rem] text-n-slate-11">
        {{
          t(
            `${R}.SO_NAS_PROPRIAS`,
            { nomes: nomes(grupos.proprias) },
            grupos.proprias.length
          )
        }}
      </p>
    </template>
  </PassagemCartao>

  <template v-if="ligada">
    <PassagemCartao
      parte="quando"
      icone="i-lucide-message-circle-question"
      :titulo="t(`${R}.QUANDO_TITULO`)"
      @alterar="$emit('abrir', 'quando')"
    >
      <template v-if="quando">{{ t(`${R}.QUANDO_FRASE`) }}</template>
      <I18nT v-else :keypath="`${R}.QUANDO_PADRAO`" tag="span" scope="global">
        <template #pedido>
          <strong class="font-semibold">{{
            t(`${R}.QUANDO_PADRAO_PEDIDO`)
          }}</strong>
        </template>
      </I18nT>
      <!-- A frase é de quem configura: aparece inteira, numa citação própria, sem o código cortar ou reescrever. -->
      <template v-if="quando" #extra>
        <p
          class="mb-0 mt-1 max-w-prose rounded-xl bg-n-alpha-1 px-3 py-2 text-[0.9375rem] leading-relaxed text-n-slate-12"
        >
          {{ t(`${R}.CITACAO`, { frase: quando }) }}
        </p>
      </template>
    </PassagemCartao>

    <PassagemCartao
      parte="quem"
      icone="i-lucide-users"
      tom="bg-n-iris-3 text-n-iris-11"
      :titulo="t(`${R}.QUEM_TITULO`)"
      :erro="faltaNoFunil"
      @alterar="$emit('abrir', 'quem')"
    >
      <I18nT
        v-if="regra.pool_type === 'user'"
        :keypath="pessoa ? `${R}.QUEM_PESSOA` : `${R}.QUEM_NINGUEM`"
        tag="span"
        scope="global"
      >
        <template #nome>
          <strong class="font-semibold">{{ pessoa }}</strong>
        </template>
      </I18nT>
      <I18nT
        v-else
        :keypath="
          regra.mode === 'direct'
            ? `${R}.QUEM_EQUIPE_NOME`
            : olhaOnline
              ? `${R}.QUEM_EQUIPE`
              : `${R}.QUEM_EQUIPE_ANTIGA`
        "
        tag="span"
        scope="global"
      >
        <template #equipe>
          <strong class="font-semibold">{{
            t(`${R}.QUEM_EQUIPE_NEGRITO`)
          }}</strong>
        </template>
      </I18nT>
      <template v-if="faltaNoFunil" #extra>
        <p
          role="alert"
          class="mb-0 mt-1 text-[0.9375rem] font-medium text-n-ruby-11"
        >
          {{ t('CRM_KANBAN.PASSAGEM.FALTA_PESSOA') }}
        </p>
      </template>
    </PassagemCartao>

    <PassagemCartao
      parte="como"
      icone="i-lucide-send"
      tom="bg-n-teal-3 text-n-teal-11"
      :titulo="t(`${R}.COMO_TITULO`)"
      :aviso="semResposta"
      @alterar="$emit('abrir', 'como')"
    >
      <I18nT
        :keypath="
          naHora
            ? olhaOnline
              ? `${R}.COMO_NA_HORA`
              : `${R}.COMO_NA_HORA_ANTIGA`
            : `${R}.COMO_CONVITE`
        "
        tag="span"
        scope="global"
      >
        <template #jeito>
          <strong class="font-semibold">{{
            t(
              naHora ? `${R}.COMO_NA_HORA_NEGRITO` : `${R}.COMO_CONVITE_NEGRITO`
            )
          }}</strong>
        </template>
      </I18nT>
      <template #extra>
        <PassagemAvisoOnline
          v-if="semResposta"
          :ocupado="salvando"
          @corrigir="$emit('corrigir')"
        />
        <p v-else class="mb-0 mt-1 text-[0.9375rem] text-n-slate-11">
          {{ linhaDoComo }}
        </p>
      </template>
    </PassagemCartao>
  </template>

  <PassagemCartao
    v-if="mostraEtapas"
    parte="etapas"
    icone="i-lucide-columns-3"
    tom="bg-n-amber-3 text-n-amber-11"
    :titulo="t(`${R}.ETAPAS_TITULO`)"
    :erro="faltaNaEtapa"
    @alterar="$emit('abrir', 'etapas')"
  >
    <I18nT :keypath="`${R}.ETAPAS_VALE`" tag="span" scope="global">
      <template #conta>
        <strong class="font-semibold">
          {{
            t(`${R}.ETAPAS_CONTA`, {
              n: grupos.ligadas.length,
              total: etapas.length,
            })
          }}
        </strong>
      </template>
    </I18nT>
    <template v-if="linhaDasEtapas || faltaNaEtapa" #extra>
      <p
        v-if="linhaDasEtapas"
        class="mb-0 mt-1 text-[0.9375rem] text-n-slate-11"
      >
        {{ linhaDasEtapas }}
      </p>
      <p
        v-if="faltaNaEtapa"
        role="alert"
        class="mb-0 mt-1 text-[0.9375rem] font-medium text-n-ruby-11"
      >
        {{ t('CRM_KANBAN.PASSAGEM.FALTA_PESSOA_ETAPA') }}
      </p>
    </template>
  </PassagemCartao>
</template>
