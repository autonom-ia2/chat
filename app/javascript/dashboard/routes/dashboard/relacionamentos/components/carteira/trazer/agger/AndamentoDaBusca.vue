<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { larguraDaBarra } from '../../../../trazer/larguraDaBarra';

// #2900 (E7.5) — a busca no Agger andando: "Buscando seus seguros… Pode sair
// desta página: a busca continua." O Agger pede os seguros mês a mês; quando o
// servidor diz quantos meses já pediu (`fatias`), uma barra simples mostra
// "Buscando mês 5 de 37". A busca de um mês só não tem barra. Nenhum aviso de
// seguradora aparece aqui: os da busca anterior não valem para a que anda.
const props = defineProps({
  // { pedidas, total } | null
  fatias: { type: Object, default: null },
});

const { t } = useI18n();

const total = computed(() => Number(props.fatias?.total) || 0);
const mes = computed(() =>
  Math.min(total.value, Math.max(1, Number(props.fatias?.pedidas) || 0))
);
const comBarra = computed(() => total.value > 1);
const fraseDoMes = computed(() =>
  t('RELACIONAMENTOS_CARTEIRA.AGGER.MES', {
    mes: mes.value,
    total: total.value,
  })
);
const largura = computed(() =>
  larguraDaBarra((mes.value / Math.max(1, total.value)) * 100)
);
</script>

<template>
  <div
    role="status"
    aria-busy="true"
    data-carteira="buscando-no-agger"
    class="flex flex-col gap-4 p-8 border rounded-3xl border-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-lg text-center text-n-slate-12 text-balance">
      {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.BUSCANDO') }}
    </p>
    <template v-if="comBarra">
      <p
        data-carteira="mes-da-busca"
        class="m-0 text-base text-center tabular-nums text-n-slate-11"
      >
        {{ fraseDoMes }}
      </p>
      <div
        role="progressbar"
        :aria-label="t('RELACIONAMENTOS_CARTEIRA.AGGER.BARRA')"
        aria-valuemin="0"
        :aria-valuemax="total"
        :aria-valuenow="mes"
        :aria-valuetext="fraseDoMes"
        class="h-3 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          class="h-full rounded-full bg-n-blue-11 dark:bg-n-blue-9"
          :class="largura"
        />
      </div>
    </template>
  </div>
</template>
