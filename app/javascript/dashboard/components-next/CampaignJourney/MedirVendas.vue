<script setup>
// #3098 — no passo de revisão da campanha, depois de "Quando começa": por quantos dias contar quem recebeu e comprou
// (mesmo sem responder) e deixar uma parte do público sorteada sem receber, para comparar (toda campanha da jornada vai
// para um público salvo, então o grupo sempre cabe; o sorteio é CampaignJourney::GrupoDeControle).
// Entra fechado, como as outras linhas da revisão (o resumo e "Alterar"): o padrão (7 dias, sem grupo de controle)
// serve para quase todo mundo, e quem não mexe mede igual.
//
// O grupo de controle fala em pessoas, não em porcentagem: "45 de 450 pessoas não vão receber". A porcentagem que
// deixaria menos de MINIMO_NO_CONTROLE pessoas de fora fica indisponível; se nenhuma serve, o público é pequeno demais.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/toggle-switch/ToggleSwitch.vue';
import { MINIMO_NO_CONTROLE } from 'dashboard/components-next/CampaignResult/comparacaoComControle';

const props = defineProps({
  janela: { type: Number, default: 7 },
  // 0 = sem grupo de controle; senão, a porcentagem do público que fica sem receber.
  controle: { type: Number, default: 0 },
  // Quantas pessoas a campanha alcança (o "Vão receber" da revisão, antes de tirar o grupo de controle).
  publico: { type: Number, default: 0 },
});
const emit = defineEmits(['update']);

const NS = 'CAMPANHA_VENDAS.MEDIR';
// O "Alterar" é o mesmo das outras linhas da revisão (StepReview), com o nome da linha para o leitor de tela.
const NS_REVISAO = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW';
const JANELAS = [7, 15, 30];
const PORCENTAGENS = [5, 10, 20];
// Menor público em que a maior porcentagem ainda deixa MINIMO_NO_CONTROLE pessoas de fora (150).
const PUBLICO_MINIMO = (MINIMO_NO_CONTROLE * 100) / Math.max(...PORCENTAGENS);

const { t, locale } = useI18n();
const aberto = ref(false);
const inteiro = numero =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(numero);

const deFora = pct => Math.floor((props.publico * pct) / 100);
const opcoes = computed(() =>
  PORCENTAGENS.map(pct => ({
    pct,
    pessoas: deFora(pct),
    serve: deFora(pct) >= MINIMO_NO_CONTROLE,
  }))
);
const algumaServe = computed(() => opcoes.value.some(opcao => opcao.serve));
const primeiraQueServe = computed(
  () =>
    opcoes.value.find(opcao => opcao.serve && opcao.pct >= 10) ??
    opcoes.value.find(opcao => opcao.serve)
);
const comControle = computed(() => props.controle > 0);
const semReceber = computed(() => deFora(props.controle));

const alternarControle = ligado =>
  emit('update', { controle: ligado ? primeiraQueServe.value.pct : 0 });

const resumo = computed(() => t(`${NS}.RESUMO`, { dias: props.janela }));
const detalhe = computed(() =>
  comControle.value
    ? t(`${NS}.RESUMO_COM_CONTROLE`, { sem: inteiro(semReceber.value) })
    : t(`${NS}.RESUMO_SEM_CONTROLE`)
);
const ajuda = computed(() => {
  if (!algumaServe.value)
    return t(`${NS}.PUBLICO_PEQUENO`, {
      minimo: inteiro(PUBLICO_MINIMO),
      total: inteiro(props.publico),
    });
  if (!comControle.value) return t(`${NS}.CONTROLE_AJUDA_DESLIGADO`);
  return t(`${NS}.CONTROLE_AJUDA`, {
    sem: inteiro(semReceber.value),
    total: inteiro(props.publico),
  });
});
const algumaApagada = computed(() => opcoes.value.some(opcao => !opcao.serve));

const classeDaPilula = escolhida =>
  escolhida
    ? 'border-n-blue-8 bg-n-blue-2 text-n-blue-11'
    : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-1';
</script>

<template>
  <div class="py-4 border-t border-n-weak" data-medir-vendas>
    <div
      v-if="!aberto"
      class="flex items-start justify-between gap-3"
      data-resumo
    >
      <div class="flex flex-col min-w-0 gap-1">
        <p class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.TITULO`) }}
        </p>
        <p class="m-0 text-sm font-semibold break-words text-n-slate-12">
          {{ resumo }}
        </p>
        <p class="m-0 text-xs break-words text-n-slate-11">{{ detalhe }}</p>
      </div>
      <Button
        :label="t(`${NS_REVISAO}.CHANGE`)"
        :aria-label="
          t(`${NS_REVISAO}.CHANGE_ARIA`, { block: t(`${NS}.TITULO`) })
        "
        variant="ghost"
        size="sm"
        class="!min-h-11 shrink-0"
        data-alterar
        @click="aberto = true"
      />
    </div>

    <fieldset v-else class="flex flex-col gap-3 p-0 m-0 border-0">
      <legend class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
        {{ t(`${NS}.TITULO`) }}
      </legend>
      <p id="janela-das-vendas" class="m-0 text-sm text-n-slate-12">
        {{ t(`${NS}.JANELA`) }}
      </p>
      <div
        class="flex flex-wrap gap-2"
        role="radiogroup"
        aria-labelledby="janela-das-vendas"
      >
        <button
          v-for="dias in JANELAS"
          :key="dias"
          type="button"
          role="radio"
          :aria-checked="janela === dias"
          :data-janela="dias"
          class="px-4 text-sm font-medium border min-h-11 rounded-xl tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="classeDaPilula(janela === dias)"
          @click="emit('update', { janela: dias })"
        >
          {{ t(`${NS}.DIAS`, { n: dias }, dias) }}
        </button>
      </div>
      <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.JANELA_AJUDA`) }}</p>

      <div
        class="flex flex-col gap-3 p-4 mt-1 rounded-xl bg-n-alpha-1"
        data-controle
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex flex-col min-w-0 gap-1">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{ t(`${NS}.CONTROLE`) }}
            </p>
            <p
              id="ajuda-do-controle"
              class="m-0 text-xs text-n-slate-11"
              data-ajuda-controle
            >
              {{ ajuda }}
            </p>
          </div>
          <ToggleSwitch
            :model-value="comControle"
            :label="t(`${NS}.CONTROLE`)"
            :disabled="!algumaServe"
            @update:model-value="alternarControle"
          />
        </div>
        <div v-if="comControle" class="flex flex-col gap-2">
          <p id="quantos-sem-receber" class="m-0 text-xs text-n-slate-11">
            {{ t(`${NS}.CONTROLE_QUANTO`) }}
          </p>
          <div
            class="flex flex-wrap gap-2"
            role="radiogroup"
            aria-labelledby="quantos-sem-receber"
          >
            <button
              v-for="opcao in opcoes"
              :key="opcao.pct"
              type="button"
              role="radio"
              :aria-checked="controle === opcao.pct"
              :disabled="!opcao.serve"
              :data-controle-pct="opcao.pct"
              class="flex flex-col items-center justify-center px-4 py-1 text-sm font-medium border min-h-11 rounded-xl tabular-nums focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:text-n-slate-10"
              :class="classeDaPilula(controle === opcao.pct)"
              @click="emit('update', { controle: opcao.pct })"
            >
              <span>{{ t(`${NS}.PORCENTO`, { n: opcao.pct }) }}</span>
              <span class="text-xs font-normal text-n-slate-11">
                {{
                  t(
                    `${NS}.PESSOAS_DO_GRUPO`,
                    { n: inteiro(opcao.pessoas) },
                    opcao.pessoas
                  )
                }}
              </span>
            </button>
          </div>
          <p
            v-if="algumaApagada"
            class="m-0 text-xs text-n-slate-11"
            data-pouco-para-comparar
          >
            {{ t(`${NS}.POUCO_PARA_COMPARAR`, { minimo: MINIMO_NO_CONTROLE }) }}
          </p>
        </div>
      </div>
    </fieldset>
  </div>
</template>
