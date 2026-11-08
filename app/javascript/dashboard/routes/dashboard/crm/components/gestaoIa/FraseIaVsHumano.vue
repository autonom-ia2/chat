<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useLocale } from 'shared/composables/useLocale';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2000 — o "IA vs humano" saiu de CRM › Números e virou esta frase na Gestão de IA, abaixo dos cartões de
// custo: no período escolhido, quantas vezes a IA mudou um cliente de etapa sozinha e, das sugestões dela,
// quantas a equipe aceitou e recusou.
// Soma os funis que a pessoa enxerga (`todos_os_funis`). Sem a leitura (erro ou sem funil), a frase some:
// o resto da página não depende dela.
const props = defineProps({
  since: { type: String, required: true },
  until: { type: String, required: true },
});

const { t } = useI18n();
const { resolvedLocale } = useLocale();
const NS = 'CRM_AI_USAGE.IA_VS_HUMANO';

const numeros = ref(null);
let pedido = 0;

const carregar = async () => {
  pedido += 1;
  const meu = pedido;
  try {
    const { data } = await CrmKanbanAPI.getReportAiVsHuman({
      since: props.since,
      until: props.until,
      todos_os_funis: true,
    });
    if (meu === pedido) numeros.value = data?.payload || null;
  } catch {
    if (meu === pedido) numeros.value = null;
  }
};

watch(() => [props.since, props.until], carregar, { immediate: true });

const formatar = n =>
  new Intl.NumberFormat(resolvedLocale.value).format(Number(n || 0));

// Três partes, cada uma só quando faz sentido: o que mudou sozinha (contado por mudança, não por cliente), e o
// que a equipe fez com as sugestões. Nada aconteceu: uma frase só.
const frase = computed(() => {
  if (!numeros.value) return '';
  const auto = Number(numeros.value.ai_auto_moves || 0);
  const aceitas = Number(numeros.value.ai_accepted || 0);
  const recusadas = Number(numeros.value.ai_dismissed || 0);
  if (!auto && !aceitas && !recusadas) return t(`${NS}.VAZIA`);
  const mudou = auto
    ? t(`${NS}.MUDOU`, { auto: formatar(auto) }, auto)
    : t(`${NS}.NAO_MUDOU`);
  if (!aceitas && !recusadas) return mudou;
  const sugeriu = t(`${NS}.SUGERIU`, {
    aceitas: formatar(aceitas),
    recusadas: formatar(recusadas),
  });
  return `${mudou} ${sugeriu}`;
});
</script>

<template>
  <section
    v-if="frase"
    data-ia-vs-humano
    class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <h2 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.TITULO`) }}
    </h2>
    <p data-ia-vs-humano-frase class="m-0 text-sm text-n-slate-11">
      {{ frase }}
    </p>
  </section>
  <!-- Sem a leitura, ou ainda sem resposta: a frase não aparece. -->
  <template v-else />
</template>
