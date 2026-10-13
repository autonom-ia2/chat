<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { SINAIS, SINAIS_DE_ALERTA } from '../constants';
import { localeDoIntl, numero } from '../helpers/datas';

// Saúde do modelo (#1338): o que aconteceu com os envios dos últimos 30 dias
// (quantos receberam, leram e responderam, e quanto custou cada resposta) e o
// sinal do WhatsApp quando está bom ou ainda sem nota. Sinal ruim fica no topo
// da página (AlertaDeQualidade), no lugar da situação.
const props = defineProps({
  modelo: { type: Object, required: true },
});

const { t, locale } = useI18n();

// Sinal bom ou ainda sem nota, só em modelo pronto. Pausado e desativado já
// dizem o motivo na caixa de situação; sinal ruim vira o AlertaDeQualidade.
const sinal = computed(() => props.modelo.sinal || 'sem_nota');
const mostraSinal = computed(
  () =>
    props.modelo.situacao === 'pronto' &&
    !SINAIS_DE_ALERTA.includes(sinal.value)
);
const visual = computed(() => SINAIS[sinal.value]);

const saude = computed(() => props.modelo.saude || null);
const enviou = computed(() => Boolean(saude.value?.enviadas));

// Sem nenhuma entrega não há porcentagem: a tela mostra um traço, não "0%".
const SEM_VALOR = '—';
const porCento = parte =>
  saude.value.entregues
    ? Math.round((parte / saude.value.entregues) * 100)
    : null;
const emPorCento = valor => (valor == null ? SEM_VALOR : `${valor}%`);

const dinheiro = valor =>
  new Intl.NumberFormat(localeDoIntl(locale.value), {
    style: 'currency',
    currency: saude.value.custo.moeda,
  }).format(valor);

const respostas = computed(() => porCento(saude.value.responderam));
const comparacao = computed(() => {
  const media = saude.value.mediaDeRespostas;
  if (media == null || respostas.value == null) return '';
  if (respostas.value === media) return '';
  return respostas.value > media ? 'ACIMA' : 'ABAIXO';
});

const numeros = computed(() => {
  if (!enviou.value) return [];
  const { enviadas, entregues, lidas, responderam, custo } = saude.value;
  const n = valor => numero(valor, locale.value);
  return [
    {
      chave: 'receberam',
      valor: n(entregues),
      detalhe: t('MODELOS_WHATSAPP.SAUDE.DE_ENVIADAS', { n: n(enviadas) }),
    },
    {
      chave: 'leram',
      valor: emPorCento(porCento(lidas)),
      detalhe: t('MODELOS_WHATSAPP.SAUDE.PESSOAS', { n: n(lidas) }, lidas),
    },
    {
      chave: 'responderam',
      valor: emPorCento(respostas.value),
      detalhe: t(
        'MODELOS_WHATSAPP.SAUDE.PESSOAS',
        { n: n(responderam) },
        responderam
      ),
      comparacao: comparacao.value,
    },
    {
      chave: 'custo',
      valor:
        custo?.porResposta != null
          ? dinheiro(custo.porResposta)
          : t('MODELOS_WHATSAPP.SAUDE.SEM_RESPOSTA'),
      detalhe: custo
        ? t('MODELOS_WHATSAPP.SAUDE.TOTAL_GASTO', {
            valor: dinheiro(custo.total),
          })
        : '',
    },
  ];
});

const COR_DA_COMPARACAO = {
  ACIMA: 'text-n-teal-11',
  ABAIXO: 'text-n-amber-11',
};
</script>

<template>
  <section
    data-saude
    class="flex flex-col gap-5 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <header
      class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
    >
      <h2 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t('MODELOS_WHATSAPP.SAUDE.TITULO') }}
      </h2>
      <span class="text-sm text-n-slate-10">
        {{ $t('MODELOS_WHATSAPP.SAUDE.PERIODO') }}
      </span>
    </header>

    <div
      v-if="mostraSinal"
      :data-sinal="sinal"
      class="flex gap-3 px-4 py-3 rounded-xl ring-1 ring-inset"
      :class="visual.caixa"
    >
      <span
        class="size-5 mt-0.5 shrink-0"
        :class="[visual.icone, visual.cor]"
        aria-hidden="true"
      />
      <p class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-12">
        <strong class="block font-semibold">
          {{ $t(`MODELOS_WHATSAPP.SAUDE.SINAIS.${sinal}.TITULO`) }}
        </strong>
        {{ $t(`MODELOS_WHATSAPP.SAUDE.SINAIS.${sinal}.TEXTO`) }}
      </p>
    </div>

    <ul
      v-if="enviou"
      data-numeros
      class="grid grid-cols-2 gap-3 p-0 m-0 list-none lg:grid-cols-4"
    >
      <li
        v-for="item in numeros"
        :key="item.chave"
        :data-numero="item.chave"
        class="flex flex-col gap-1 p-4 rounded-xl bg-n-alpha-1"
      >
        <span class="text-sm text-n-slate-11">
          {{ $t(`MODELOS_WHATSAPP.SAUDE.NUMEROS.${item.chave}`) }}
        </span>
        <span class="text-2xl font-bold tracking-tight text-n-slate-12">
          {{ item.valor }}
        </span>
        <span v-if="item.detalhe" class="text-sm text-n-slate-11">
          {{ item.detalhe }}
        </span>
        <span
          v-if="item.comparacao"
          class="text-sm font-medium"
          :class="COR_DA_COMPARACAO[item.comparacao]"
        >
          {{
            $t(`MODELOS_WHATSAPP.SAUDE.MEDIA.${item.comparacao}`, {
              n: saude.mediaDeRespostas,
            })
          }}
        </span>
      </li>
    </ul>
    <p v-else data-sem-envios class="mb-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.SAUDE.SEM_ENVIOS') }}
    </p>

    <p v-if="enviou" class="mb-0 text-sm text-n-slate-10">
      {{ $t('MODELOS_WHATSAPP.SAUDE.NOTA') }}
    </p>
  </section>
</template>
