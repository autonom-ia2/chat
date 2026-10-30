<script setup>
import { computed, onMounted, ref } from 'vue';
import CrmNumerosOrigensAPI from 'dashboard/api/crmNumerosOrigens';
import { useNumerosFormato } from '../useNumerosFormato';

// Números › Origens (#2001, F6) — na visão "Equipe" de Números, a porta para "De onde vieram os clientes": um cartão
// que já diz de onde veio a maior parte dos clientes novos do mês, no funil principal. Aparece só quando o mês da
// Equipe é o mês de hoje (o atalho abre a tela no mês de hoje; lá dá para trocar de mês e de funil) e só quando
// chegou alguém. Quem decide se aparece (flag `crm_numeros_origens`) é a tela da Equipe.
const props = defineProps({
  mesChave: { type: String, required: true },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t } = useNumerosFormato();
const dados = ref(null);

onMounted(async () => {
  try {
    const { data } = await CrmNumerosOrigensAPI.show();
    dados.value = data;
  } catch {
    dados.value = null;
  }
});

const origens = computed(() => dados.value?.origens || []);
const total = computed(() =>
  origens.value.reduce((acc, o) => acc + o.clientes, 0)
);
const primeira = computed(() => origens.value.find(o => o.tipo !== 'outras'));
const mostrar = computed(
  () =>
    dados.value &&
    !dados.value.vazio &&
    dados.value.mes.chave === props.mesChave &&
    total.value > 0 &&
    primeira.value
);
const texto = computed(() =>
  primeira.value
    ? t(`${O}.ATALHO.TEXTO`, {
        origem: t(`${O}.NOMES.${primeira.value.tipo.toUpperCase()}`),
        n: primeira.value.clientes,
        total: total.value,
      })
    : ''
);
</script>

<template>
  <!-- Sempre presente e sem caixa própria (contents): o cartão só aparece quando há o que dizer. -->
  <div class="contents">
    <RouterLink
      v-if="mostrar"
      :to="{ name: 'crm_numeros_origens' }"
      data-origens-atalho
      :data-total="total"
      class="group flex min-h-12 items-center justify-between gap-3 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 hover:ring-n-slate-6 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand motion-reduce:transition-none"
    >
      <span class="flex min-w-0 flex-col gap-0.5">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t(`${O}.TITULO`) }}
        </span>
        <span class="text-sm text-n-slate-11" data-origens-atalho-total>
          {{ texto }}
        </span>
      </span>
      <span
        class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
        aria-hidden="true"
      />
    </RouterLink>
  </div>
</template>
