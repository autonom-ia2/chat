<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { I18nT } from 'vue-i18n';
import { usePodeMontarAutomacao } from 'dashboard/composables/usePodeMontarAutomacao';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { automacoesDaEtapa } from 'dashboard/routes/dashboard/automacoes/livre/gatilhosDemo';
import FunilResumoCartao from './FunilResumoCartao.vue';

// #1384 — as ações automáticas de uma etapa já salva, numa frase com
// "Alterar" (que abre a tela das ações). Só lê quantas há e quantas estão
// ligadas; criar e mudar continua no painel de ações.
const props = defineProps({
  etapaId: { type: [Number, String], required: true },
});

defineEmits(['alterar']);

const store = useStore();
// #2414 F1.3: sem a chave das regras automáticas, as ações da etapa só se veem.
const podeMontar = usePodeMontarAutomacao();
const acoes = ref(null);

watch(
  () => props.etapaId,
  async id => {
    acoes.value = null;
    try {
      acoes.value = await store.dispatch('crmKanban/fetchStageAutomations', id);
    } catch {
      acoes.value = [];
    }
  },
  { immediate: true }
);

const ligadas = computed(
  () => (acoes.value || []).filter(acao => acao.enabled !== false).length
);

// #2499: com os gatilhos novos, a frase conta também as automações novas que
// começam nesta etapa ("2 automações, 1 ligada").
// PROTÓTIPO: as novas vêm do adaptador falso (gatilhosDemo).
const { isCloudFeatureEnabled } = useAccount();
const comGatilhos = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_GATILHOS)
);
const novas = computed(() =>
  comGatilhos.value ? automacoesDaEtapa({ id: props.etapaId }).novas : []
);
const total = computed(() => (acoes.value || []).length + novas.value.length);
const ligadasNoTotal = computed(
  () => ligadas.value + novas.value.filter(automacao => automacao.ligada).length
);
</script>

<template>
  <FunilResumoCartao
    parte="stage-actions"
    icone="i-lucide-zap"
    tom="bg-n-iris-3 text-n-iris-11"
    :titulo="$t('CRM_FUNIL.ETAPA.ACOES')"
    :so-ver="!podeMontar"
    @alterar="$emit('alterar')"
  >
    <template v-if="acoes === null">{{ $t('CRM_FUNIL.CARREGANDO') }}</template>
    <strong v-else-if="comGatilhos && total" class="font-semibold">
      {{
        $t('AUTOMACAO_LIVRE.GATILHOS_F6.ETAPA.RESUMO', {
          automacoes: $t(
            'AUTOMACAO_LIVRE.GATILHOS_F6.ETAPA.RESUMO_AUTOMACOES',
            { n: total },
            total
          ),
          ligadas: $t(
            'AUTOMACAO_LIVRE.GATILHOS_F6.ETAPA.RESUMO_LIGADAS',
            { n: ligadasNoTotal },
            ligadasNoTotal
          ),
        })
      }}
    </strong>
    <I18nT
      v-else-if="ligadas"
      keypath="CRM_FUNIL.ETAPA.ACOES_FRASE"
      tag="span"
      scope="global"
      :plural="ligadas"
    >
      <template #acoes>
        <strong class="font-semibold">
          {{ $t('CRM_FUNIL.ETAPA.ACOES_N', { n: ligadas }, ligadas) }}
        </strong>
      </template>
    </I18nT>
    <template v-else>{{ $t('CRM_FUNIL.ETAPA.ACOES_NENHUMA') }}</template>
  </FunilResumoCartao>
</template>
