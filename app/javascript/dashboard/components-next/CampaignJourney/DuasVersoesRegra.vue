<script setup>
// #3099 — "Como escolher a melhor" das duas versões: o plano em frases (quantos recebem o teste, quanto tempo esperar e
// para quantos vai a melhor) e, no "Alterar", as três escolhas: o que conta como melhor (respostas, compras ou eu
// escolho), a espera e a divisão. Entra fechado, como as linhas da revisão (MedirVendas): o padrão serve para quase
// todo mundo. Serve à campanha (com o público contado) e ao passo de mensagem da Automação livre (`naAutomacao`).
// Cada escolha é um grupo de rádio com setas (DuasVersoesPilulas). Ao abrir, o foco vai para a primeira escolha; no
// "Pronto", volta ao "Alterar".
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import DuasVersoesPilulas from './DuasVersoesPilulas.vue';
import { DIVISOES, ESPERAS, trocarCriterio } from './duasVersoes';
import { useFrasesDoPlano } from './useFrasesDoPlano';

const props = defineProps({
  // { criterio, divisao, espera }
  regra: { type: Object, required: true },
  // Quantas pessoas vão receber (campanha). Na automação não é usado.
  publico: { type: Number, default: 0 },
  // O plano contado pelo servidor (recipient_previews); sem ele, a conta é feita aqui com o `publico`.
  plano: { type: Object, default: null },
  naAutomacao: { type: Boolean, default: false },
  // Sem compras na conta (F1), "A que tiver mais compras" fica apagada, com o motivo.
  podeMedirCompras: { type: Boolean, default: true },
  comecaAberto: { type: Boolean, default: false },
});
const emit = defineEmits(['update']);

const NS = 'DUAS_VERSOES.REGRA';
const NS_REVISAO = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const { t } = useI18n();
const aberto = ref(props.comecaAberto);
const horas = n => t(`${NS}.HORAS`, { n }, n);
const frases = useFrasesDoPlano(
  computed(() => props.regra),
  computed(() => props.publico),
  computed(() => props.naAutomacao),
  false,
  computed(() => props.plano)
);

const ids = { criterio: useId(), espera: useId(), divisao: useId() };
const primeiraEscolha = ref(null);
const botaoAlterar = ref(null);
const abrir = async () => {
  aberto.value = true;
  await nextTick();
  primeiraEscolha.value?.focar();
};
const fechar = async () => {
  aberto.value = false;
  await nextTick();
  botaoAlterar.value?.$el?.focus();
};

const criterios = computed(() => [
  { valor: 'respostas', rotulo: t(`${NS}.RESPOSTAS`), serve: true },
  {
    valor: 'compras',
    rotulo: t(`${NS}.COMPRAS`),
    serve: props.podeMedirCompras,
  },
  { valor: 'eu_escolho', rotulo: t(`${NS}.EU_ESCOLHO`), serve: true },
]);
const esperas = computed(() =>
  ESPERAS.map(espera => ({ valor: espera, rotulo: horas(espera) }))
);
// "7 de cada 10 na versão 1": a parte da versão 1 em dezenas, sem porcentagem.
const divisoes = computed(() =>
  DIVISOES.map(divisao => ({
    valor: divisao,
    rotulo: t(divisao === 50 ? `${NS}.METADE` : `${NS}.MAIS_NA_1`),
    detalhe: t(
      divisao === 50 ? `${NS}.METADE_DETALHE` : `${NS}.MAIS_NA_1_DETALHE`,
      { n: divisao / 10 }
    ),
  }))
);
const ajudaDaEspera = computed(() =>
  t(
    props.regra.criterio === 'compras'
      ? `${NS}.ESPERA_AJUDA_COMPRAS`
      : `${NS}.ESPERA_AJUDA_RESPOSTAS`
  )
);

const mudar = patch => emit('update', { ...props.regra, ...patch });
const escolherCriterio = criterio =>
  emit('update', trocarCriterio(props.regra, criterio));
</script>

<template>
  <div class="flex flex-col gap-3" data-duas-versoes-regra>
    <div class="flex items-start justify-between gap-3">
      <div class="flex min-w-0 flex-col gap-1">
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.TITULO`) }}
        </p>
        <p
          v-for="(frase, indice) in frases"
          :key="indice"
          class="m-0 break-words"
          :class="
            indice === 0
              ? 'text-sm font-medium text-n-slate-12'
              : 'text-sm text-n-slate-11'
          "
          data-frase-do-plano
        >
          {{ frase }}
        </p>
      </div>
      <Button
        v-if="!aberto"
        ref="botaoAlterar"
        :label="t(`${NS_REVISAO}.CHANGE`)"
        :aria-label="
          t(`${NS_REVISAO}.CHANGE_ARIA`, { block: t(`${NS}.TITULO`) })
        "
        variant="ghost"
        size="sm"
        class="!min-h-11 shrink-0"
        data-alterar-regra
        @click="abrir"
      />
    </div>

    <div v-if="aberto" class="flex flex-col gap-4 rounded-xl bg-n-alpha-1 p-4">
      <div class="flex flex-col gap-2">
        <p
          :id="ids.criterio"
          class="m-0 mb-2 text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.CRITERIO`) }}
        </p>
        <DuasVersoesPilulas
          ref="primeiraEscolha"
          :opcoes="criterios"
          :rotulado-por="ids.criterio"
          :model-value="regra.criterio"
          marca="criterio"
          @update:model-value="escolherCriterio"
        />
        <p
          v-if="!podeMedirCompras"
          class="m-0 text-xs text-n-slate-11"
          data-sem-compras
        >
          {{ t(`${NS}.SEM_COMPRAS`) }}
        </p>
      </div>

      <div class="flex flex-col gap-2">
        <p
          :id="ids.espera"
          class="m-0 mb-2 text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.ESPERA`) }}
        </p>
        <DuasVersoesPilulas
          :opcoes="esperas"
          :rotulado-por="ids.espera"
          :model-value="regra.espera"
          marca="espera"
          @update:model-value="espera => mudar({ espera })"
        />
        <p class="m-0 text-xs text-n-slate-11">{{ ajudaDaEspera }}</p>
      </div>

      <div class="flex flex-col gap-2">
        <p
          :id="ids.divisao"
          class="m-0 mb-2 text-sm font-medium text-n-slate-12"
        >
          {{ t(`${NS}.DIVISAO`) }}
        </p>
        <DuasVersoesPilulas
          :opcoes="divisoes"
          :rotulado-por="ids.divisao"
          :model-value="regra.divisao"
          marca="divisao"
          @update:model-value="divisao => mudar({ divisao })"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t(`${NS}.DIVISAO_AJUDA`) }}
        </p>
      </div>
      <Button
        :label="t(`${NS}.PRONTO`)"
        variant="ghost"
        size="sm"
        class="!min-h-11 self-end"
        data-fechar-regra
        @click="fechar"
      />
    </div>
  </div>
</template>
