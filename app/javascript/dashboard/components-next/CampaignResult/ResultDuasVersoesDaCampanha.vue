<script setup>
// #3099 — o resultado das duas versões no Resultado da campanha (MessageResultView e EmailResultView), ligado ao
// servidor: mostra o bloco `duas_versoes` do resultado (ResultDuasVersoes) e, no "Sim, mandar", pede a versão do resto
// (POST …/results/:channel/:id/vencedora). Escolher é disparo: só com a chave campaign_send (#1898). Mandou: avisa a
// página, que recarrega o resultado.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CampaignResultsAPI from 'dashboard/api/campaignResults';
import ResultDuasVersoes from './ResultDuasVersoes.vue';

const props = defineProps({
  channel: { type: String, required: true },
  campaignId: { type: [String, Number], required: true },
  // O bloco `duas_versoes` do resultado (CampaignJourney::DuasVersoes::Resultado).
  teste: { type: Object, required: true },
});
const emit = defineEmits(['escolhida', 'recarregar']);

const NS = 'DUAS_VERSOES.RESULTADO';
const { t } = useI18n();
const podeEscolher = useCanManage('campaign_send');
const enviando = ref(null);

const escolher = async versao => {
  if (enviando.value) return;
  enviando.value = versao;
  try {
    await CampaignResultsAPI.escolherVersao(
      props.channel,
      props.campaignId,
      versao
    );
    emit('escolhida', versao);
  } catch (error) {
    // 422: outra pessoa (ou o sistema, na hora marcada) já escolheu. O resultado recarrega e mostra qual foi.
    const jaEscolhida = error?.response?.status === 422;
    useAlert(t(jaEscolhida ? `${NS}.JA_ESCOLHIDA` : `${NS}.ERRO_ESCOLHER`));
    if (jaEscolhida) emit('recarregar');
  } finally {
    enviando.value = null;
  }
};
</script>

<template>
  <ResultDuasVersoes
    :teste="teste"
    :pode-escolher="podeEscolher"
    :enviando="enviando"
    @escolher="escolher"
    @recarregar="emit('recarregar')"
  />
</template>
