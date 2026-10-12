<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import api from '../api/modelosWhatsapp';
import { localeDoIntl } from '../helpers/datas';

// Revisão da campanha: qual modelo vai, o tipo da mensagem e quanto custa cada
// envio (e o total para quem recebe). Divulgação lembra que quem pediu para não
// receber fica de fora.
const props = defineProps({
  modelo: { type: Object, required: true },
  recebem: { type: Number, default: 0 },
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
    <p class="m-0 text-xs text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.CUSTO_AJUDA') }}
    </p>
    <p v-if="modelo.tipo === 'divulgacao'" class="m-0 text-xs text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.PONTE.REVISAO.DIVULGACAO') }}
    </p>
  </section>
</template>
