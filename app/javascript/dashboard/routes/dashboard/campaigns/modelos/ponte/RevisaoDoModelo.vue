<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import api from '../api/modelosWhatsapp';
import { localeDoIntl } from '../helpers/datas';
import {
  formatInZone,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';
import PonteSinalDoModelo from './PonteSinalDoModelo.vue';
import { dinheiroDoProduto } from '../helpers/produtosNaCampanha';

// Revisão da campanha: qual modelo vai, o tipo da mensagem e quanto custa cada
// envio (e o total para quem recebe). Divulgação lembra que quem pediu para não
// receber fica de fora.
const props = defineProps({
  modelo: { type: Object, required: true },
  recebem: { type: Number, default: 0 },
  // #1334: o que o formato pediu (cupom, validade, cartões).
  formato: { type: Object, default: () => ({}) },
  pedido: { type: Object, default: null },
  timeZone: { type: String, default: 'UTC' },
});

const { locale } = useI18n();
const custo = ref(null);

watch(
  () => props.modelo.tipo,
  async tipo => {
    try {
      custo.value = await api.custoPorEnvio(tipo);
    } catch {
      custo.value = null;
    }
  },
  { immediate: true }
);

// Por envio com as casas da tabela da Meta (R$ 0,3217); o total em centavos.
const CASAS_DO_PRECO = 4;
const dinheiro = (valor, casas = 2) =>
  new Intl.NumberFormat(localeDoIntl(locale.value), {
    style: 'currency',
    currency: custo.value?.moeda || 'BRL',
    maximumFractionDigits: casas,
  }).format(valor);

const porEnvio = computed(() =>
  custo.value ? dinheiro(custo.value.valor, CASAS_DO_PRECO) : ''
);
const validade = computed(() => {
  const iso = scheduleToUtc(props.formato.validade, props.timeZone);
  return iso ? formatInZone(iso, props.timeZone, locale.value) : '';
});

// #1418: os produtos escolhidos, na ordem em que vão.
const produtos = computed(() =>
  props.pedido?.produtos ? props.formato.produtos || [] : []
);
// Separador visual entre nome e preço (não é texto para traduzir).
const PONTO = '·';
const rotuloDoProduto = produto =>
  [
    produto.nome,
    PONTO,
    dinheiroDoProduto(produto.preco, localeDoIntl(locale.value)),
  ].join(' ');

const total = computed(() =>
  custo.value ? dinheiro(custo.value.valor * props.recebem) : ''
);
</script>

<template>
  <section
    data-revisao-modelo
    class="flex flex-col gap-2 py-4 border-b border-n-weak"
  >
    <p class="m-0 text-xs font-semibold text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.TITULO') }}
    </p>
    <p class="m-0 text-sm font-semibold text-n-slate-12">
      {{ modelo.nome }}
      <span
        class="px-2 py-0.5 ms-1 text-xs font-medium rounded-full"
        :class="
          modelo.tipo === 'divulgacao'
            ? 'bg-n-amber-3 text-n-amber-11'
            : 'bg-n-teal-3 text-n-teal-11'
        "
      >
        {{ $t(`MODELOS_WHATSAPP.TIPOS.${modelo.tipo}.ROTULO`) }}
      </span>
    </p>
    <p v-if="custo" class="m-0 text-sm text-n-slate-12">
      {{
        recebem > 0
          ? $t('MODELOS_WHATSAPP.PONTE.REVISAO.CUSTO', {
              porEnvio,
              total,
              n: recebem,
            })
          : $t('MODELOS_WHATSAPP.PONTE.REVISAO.POR_ENVIO', { porEnvio })
      }}
    </p>
    <ul
      v-if="pedido"
      class="flex flex-col gap-1 p-0 m-0 text-sm list-none text-n-slate-12"
      data-revisao-formato
    >
      <li v-if="pedido.cupom">
        {{
          $t('MODELOS_WHATSAPP.PONTE.REVISAO.CUPOM', { cupom: formato.cupom })
        }}
      </li>
      <li v-if="pedido.validade && validade">
        {{
          $t('MODELOS_WHATSAPP.PONTE.REVISAO.VALIDADE', { quando: validade })
        }}
      </li>
      <li v-if="pedido.cartoes.length">
        {{
          $t('MODELOS_WHATSAPP.PONTE.REVISAO.CARTOES', {
            n: pedido.cartoes.length,
          })
        }}
      </li>
    </ul>
    <div
      v-if="produtos.length"
      data-revisao-produtos
      class="flex flex-col gap-2"
    >
      <p class="m-0 text-sm text-n-slate-12">
        {{
          $t(
            'MODELOS_WHATSAPP.PONTE.REVISAO.PRODUTOS',
            { n: produtos.length },
            produtos.length
          )
        }}
      </p>
      <ul class="flex flex-wrap gap-2 p-0 m-0 list-none">
        <li
          v-for="produto in produtos"
          :key="produto.id"
          class="flex items-center gap-2 py-1 ltr:pl-1 ltr:pr-3 rtl:pr-1 rtl:pl-3 rounded-full bg-n-alpha-2"
        >
          <img
            :src="produto.foto"
            alt=""
            class="object-cover rounded-full size-7 bg-n-slate-3"
          />
          <span class="text-xs text-n-slate-12">
            {{ rotuloDoProduto(produto) }}
          </span>
        </li>
      </ul>
      <p class="m-0 text-xs text-n-slate-11">
        {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.PRODUTOS_AJUDA') }}
      </p>
    </div>
    <p class="m-0 text-xs text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.CUSTO_AJUDA') }}
    </p>
    <p v-if="modelo.tipo === 'divulgacao'" class="m-0 text-xs text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.DIVULGACAO') }}
    </p>
    <PonteSinalDoModelo :modelo="modelo" />
  </section>
</template>
