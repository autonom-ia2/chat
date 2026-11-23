<script setup>
// #3099 — "Como escolher a melhor" das duas versões: o plano em frases (quantos recebem o teste, quanto tempo esperar e
// para quantos vai a melhor) e, no "Alterar", as três escolhas: o que conta como melhor (respostas, compras ou eu
// escolho), a espera e a divisão. Entra fechado, como as linhas da revisão (MedirVendas): o padrão serve para quase
// todo mundo. Serve à campanha (com o público contado) e ao passo de mensagem da Automação livre (`naAutomacao`).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
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

const criterios = computed(() => [
  { valor: 'respostas', rotulo: t(`${NS}.RESPOSTAS`), serve: true },
  {
    valor: 'compras',
    rotulo: t(`${NS}.COMPRAS`),
    serve: props.podeMedirCompras,
  },
  { valor: 'eu_escolho', rotulo: t(`${NS}.EU_ESCOLHO`), serve: true },
]);
const divisoes = computed(() =>
  DIVISOES.map(divisao => ({
    divisao,
    rotulo: t(divisao === 50 ? `${NS}.METADE` : `${NS}.MAIS_NA_1`),
    detalhe: t(
      divisao === 50 ? `${NS}.METADE_DETALHE` : `${NS}.MAIS_NA_1_DETALHE`
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

// Contorno por anel (ring): a regra base de `button` em _base.scss zera a borda e venceria o `border`.
const classeDaPilula = escolhida =>
  escolhida
    ? 'ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
    : 'ring-n-slate-7 bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1';
const PILULA =
  'min-h-11 rounded-xl ring-1 ring-inset px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:text-n-slate-10';
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
        :label="t(`${NS_REVISAO}.CHANGE`)"
        :aria-label="
          t(`${NS_REVISAO}.CHANGE_ARIA`, { block: t(`${NS}.TITULO`) })
        "
        variant="ghost"
        size="sm"
        class="!min-h-11 shrink-0"
        data-alterar-regra
        @click="aberto = true"
      />
    </div>

    <div v-if="aberto" class="flex flex-col gap-4 rounded-xl bg-n-alpha-1 p-4">
      <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
        <legend class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.CRITERIO`) }}
        </legend>
        <div class="flex flex-wrap gap-2" role="radiogroup">
          <button
            v-for="opcao in criterios"
            :key="opcao.valor"
            type="button"
            role="radio"
            :aria-checked="regra.criterio === opcao.valor"
            :disabled="!opcao.serve"
            :data-criterio="opcao.valor"
            :class="[PILULA, classeDaPilula(regra.criterio === opcao.valor)]"
            @click="escolherCriterio(opcao.valor)"
          >
            {{ opcao.rotulo }}
          </button>
        </div>
        <p
          v-if="!podeMedirCompras"
          class="m-0 text-xs text-n-slate-11"
          data-sem-compras
        >
          {{ t(`${NS}.SEM_COMPRAS`) }}
        </p>
      </fieldset>

      <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
        <legend class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.ESPERA`) }}
        </legend>
        <div class="flex flex-wrap gap-2" role="radiogroup">
          <button
            v-for="espera in ESPERAS"
            :key="espera"
            type="button"
            role="radio"
            :aria-checked="regra.espera === espera"
            :data-espera="espera"
            class="tabular-nums"
            :class="[PILULA, classeDaPilula(regra.espera === espera)]"
            @click="mudar({ espera })"
          >
            {{ horas(espera) }}
          </button>
        </div>
        <p class="m-0 text-xs text-n-slate-11">{{ ajudaDaEspera }}</p>
      </fieldset>

      <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
        <legend class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t(`${NS}.DIVISAO`) }}
        </legend>
        <div class="flex flex-wrap gap-2" role="radiogroup">
          <button
            v-for="opcao in divisoes"
            :key="opcao.divisao"
            type="button"
            role="radio"
            :aria-checked="regra.divisao === opcao.divisao"
            :data-divisao="opcao.divisao"
            class="flex flex-col items-start justify-center py-1"
            :class="[PILULA, classeDaPilula(regra.divisao === opcao.divisao)]"
            @click="mudar({ divisao: opcao.divisao })"
          >
            <span>{{ opcao.rotulo }}</span>
            <span class="text-xs font-normal tabular-nums text-n-slate-11">
              {{ opcao.detalhe }}
            </span>
          </button>
        </div>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t(`${NS}.DIVISAO_AJUDA`) }}
        </p>
      </fieldset>
      <Button
        :label="t(`${NS}.PRONTO`)"
        variant="ghost"
        size="sm"
        class="!min-h-11 self-end"
        data-fechar-regra
        @click="aberto = false"
      />
    </div>
  </div>
</template>
