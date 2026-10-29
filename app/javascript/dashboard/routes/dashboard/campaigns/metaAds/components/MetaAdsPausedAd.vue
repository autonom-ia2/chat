<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { longDate, money } from '../dinheiroDoAnuncio';
import { lerOrcamento } from '../criacaoNaMeta';
import MetaAdsAdStatus from './MetaAdsAdStatus.vue';

// Anúncios da Meta (#2198): um anúncio da lista "Pausados, esperando você ativar". A linha mostra o valor de quando o
// anúncio foi criado, marcado assim ("Valor ao criar"). O "Ativar anúncio" lê o orçamento de agora só no toque (cada
// leitura são 4 chamadas à Meta; ler a lista inteira ao abrir o painel bateria no limite de uso da conta) e a
// confirmação usa só ele. Enquanto lê, o botão mostra que está carregando; se falhar, a confirmação não abre e o
// "Tentar de novo" lê outra vez.
// Em análise da Meta (`in_review`, #2354): a situação (MetaAdsAdStatus) diz que a Meta está conferindo e não oferece
// ativar. A doc da Meta não diz se dá para ligar durante a análise.
const props = defineProps({
  // { ad_id, name, created_at, budget, in_review }: `budget` é o de quando o anúncio foi criado.
  ad: { type: Object, required: true },
});

const emit = defineEmits(['changed']);

const { locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PAUSED_LIST';
const gestao = computed(() => ({
  status: 'PAUSED',
  effective_status: 'PAUSED',
  can_change: true,
  in_review: Boolean(props.ad.in_review),
}));

const readBudget = () => lerOrcamento(props.ad.ad_id);

const perDay = computed(() =>
  money(props.ad.budget.amount, props.ad.budget.currency, locale.value)
);
</script>

<template>
  <li
    :data-panel-paused-ad="ad.ad_id"
    class="flex flex-col gap-3 rounded-xl bg-n-alpha-1 p-4 sm:flex-row sm:items-center sm:justify-between"
  >
    <div class="flex min-w-0 flex-col gap-0.5">
      <span class="break-words text-sm font-semibold text-n-slate-12">
        {{ ad.name }}
      </span>
      <span class="text-xs text-n-slate-11">
        {{
          $t(`${KEY}.LINE`, {
            date: longDate(ad.created_at, locale),
            value: perDay,
          })
        }}
      </span>
    </div>
    <MetaAdsAdStatus
      :ad-id="ad.ad_id"
      :ad-name="ad.name"
      :gestao="gestao"
      :read-budget="readBudget"
      can-manage
      tone="light"
      @changed="(status, result) => emit('changed', status, result)"
    />
  </li>
</template>
