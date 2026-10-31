<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { I18nT } from 'vue-i18n';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
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
const podeMontar = usePermissionGranted('automation_manage');
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
