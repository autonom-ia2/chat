<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import api from '../api/modelosWhatsapp';
import { localeDoIntl, numero } from '../helpers/datas';

// Franquia do mês: quantas respostas ao cliente (mensagem livre, sem modelo)
// cada número já mandou, contra as grátis do WhatsApp. Passou da franquia, cada
// resposta tem o preço de "serviço". Sem dados (sem permissão ou sem tabela),
// não aparece.
const { t, locale } = useI18n();
const franquia = ref(null);
const custo = ref(null);

onMounted(async () => {
  try {
    [franquia.value, custo.value] = await Promise.all([
      api.obterFranquia(),
      api.custoPorEnvio('resposta'),
    ]);
  } catch {
    franquia.value = null;
  }
});

const dinheiro = computed(() =>
  custo.value
    ? new Intl.NumberFormat(localeDoIntl(locale.value), {
        style: 'currency',
        currency: custo.value.moeda,
        maximumFractionDigits: 4,
      }).format(custo.value.valor)
    : ''
);

const linhas = computed(() =>
  (franquia.value?.numeros || []).map(item => {
    const passou = item.usadas > franquia.value.limite;
    return {
      ...item,
      passou,
      texto: passou
        ? t('MODELOS_WHATSAPP.FRANQUIA.PASSOU', {
            limite: numero(franquia.value.limite, locale.value),
          })
        : t('MODELOS_WHATSAPP.FRANQUIA.USADAS', {
            n: numero(item.usadas, locale.value),
            limite: numero(franquia.value.limite, locale.value),
          }),
    };
  })
);
</script>

<template>
  <section
    v-if="linhas.length"
    data-franquia
    class="flex flex-col gap-2 px-5 py-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
  >
    <h2 class="m-0 text-base font-semibold text-n-slate-12">
      {{ $t('MODELOS_WHATSAPP.FRANQUIA.TITULO') }}
    </h2>
    <p class="mb-0 text-sm text-n-slate-11">
      {{
        dinheiro
          ? $t('MODELOS_WHATSAPP.FRANQUIA.EXPLICA', {
              limite: numero(franquia.limite, locale),
              valor: dinheiro,
            })
          : $t('MODELOS_WHATSAPP.FRANQUIA.EXPLICA_SEM_VALOR', {
              limite: numero(franquia.limite, locale),
            })
      }}
    </p>
    <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        :data-franquia-numero="linha.id"
        class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 text-[0.9375rem]"
      >
        <span class="font-medium break-words text-n-slate-12">
          {{ linha.nome }}
        </span>
        <span
          class="text-end"
          :class="
            linha.passou ? 'text-n-amber-11 font-medium' : 'text-n-slate-11'
          "
        >
          {{ linha.texto }}
        </span>
      </li>
    </ul>
  </section>
</template>
