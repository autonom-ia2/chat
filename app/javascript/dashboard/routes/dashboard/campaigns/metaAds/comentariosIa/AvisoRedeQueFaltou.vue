<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { MOTIVOS, podeTentarDeNovo } from './useCuidado';

// #2522: no anúncio nas duas redes, a leitura pode vir só da rede que leu (`network_status` do servidor: Painel, Resumo e
// os comentários do cartão em Agentes). Um aviso por rede que faltou, para nenhum comentário sumir em silêncio. O
// motivo só quando a tela conhece o código; o genérico ("não consegui ler o anúncio") diria o contrário do aviso.
// "Tentar de novo" só onde a tela relê (`podeTentar`) e no que passa sozinho.
const props = defineProps({
  networkStatus: { type: Object, default: null },
  podeTentar: { type: Boolean, default: false },
  carregando: { type: Boolean, default: false },
});

const emit = defineEmits(['tentar']);

const { t } = useI18n();
const KEY = 'META_ADS_COMMENTS_AI.SCREEN';

const faltaram = computed(() =>
  Object.entries(props.networkStatus || {})
    .filter(([, status]) => status !== 'ready')
    .map(([rede, status]) => ({
      rede,
      status,
      motivo: MOTIVOS.includes(status) ? t(`${KEY}.PROBLEM.${status}`) : '',
    }))
);
</script>

<template>
  <div
    v-for="falta in faltaram"
    :key="falta.rede"
    role="status"
    data-ia-rede-faltou
    :data-network="falta.rede"
    class="flex flex-col items-start gap-3 rounded-2xl bg-n-amber-2 p-5 ring-1 ring-inset ring-n-amber-6"
  >
    <p
      class="m-0 flex items-start gap-2 text-sm font-medium leading-6 text-n-amber-12"
    >
      <span
        class="i-lucide-triangle-alert mt-1 size-4 shrink-0"
        aria-hidden="true"
      />
      {{ t(`${KEY}.PARTIAL.${falta.rede}`) }}
      {{ falta.motivo }}
    </p>
    <Button
      v-if="podeTentar && podeTentarDeNovo(falta.status)"
      icon="i-lucide-refresh-cw"
      :label="t('META_ADS_COMMENTS_AI.SCREEN.RETRY')"
      :is-loading="carregando"
      class="!min-h-11 !rounded-xl"
      @click="emit('tentar')"
    />
  </div>
</template>
