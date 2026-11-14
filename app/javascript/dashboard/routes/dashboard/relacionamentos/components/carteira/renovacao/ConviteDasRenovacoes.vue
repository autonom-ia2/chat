<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';

// #2898 — o convite da aba Seguros para a conta que ainda não escolheu em que
// funil as renovações aparecem: uma frase e um botão, que leva a "Ajustar
// renovações". Enquanto ninguém escolhe, nenhuma renovação aparece em funil
// nenhum. A conta que já escolheu não vê nada aqui. Se a leitura dos ajustes
// falhar, o convite só não aparece: a lista de seguros não depende dele, e a
// tela "Ajustar renovações" mostra o erro e o "tentar de novo" dela. A falha
// fica registrada, sem dado de ninguém.
// O convite volta quando o funil escolhido foi arquivado ou apagado
// (carteira/funilDasRenovacoes.js): as renovações pararam de aparecer, e a
// frase diz por quê.
const props = defineProps({
  // A fonte das renovações (fonte/renovacoesFonte.js).
  fonte: { type: Object, required: true },
});
const emit = defineEmits(['escolher']);

const { t } = useI18n();
const doConvite = chave =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.CONVITE.${chave}`);
const falta = ref(false);
// '' = a conta ainda não escolheu; ARQUIVADO ou APAGADO = o funil parou.
const parou = ref('');
const ONDE_FALHOU = { tela: 'relacionamentos_convite_das_renovacoes' };

onMounted(async () => {
  try {
    const { ajustes, semPermissao, funilParou } = await props.fonte.ajustes();
    parou.value = funilParou || '';
    falta.value = (!ajustes.funilId || Boolean(parou.value)) && !semPermissao;
  } catch (falha) {
    // De propósito: sem os ajustes a aba Seguros segue inteira, só sem o
    // convite.
    reportarSemDados(falha, ONDE_FALHOU);
    falta.value = false;
  }
});
</script>

<template>
  <!-- `contents`: sem o convite, a peça não ocupa lugar na coluna da lista. -->
  <div class="contents">
    <section
      v-if="falta"
      data-carteira="convite-das-renovacoes"
      :data-estado="parou || undefined"
      class="flex flex-wrap items-center justify-between min-w-0 p-5 border gap-x-6 gap-y-4 rounded-2xl border-n-blue-4 bg-n-blue-2"
    >
      <div class="flex flex-col flex-1 min-w-0 gap-1 basis-64">
        <p class="m-0 text-lg font-semibold text-n-slate-12">
          {{ parou ? doConvite(`PAROU.${parou}`) : doConvite('FRASE') }}
        </p>
        <p class="m-0 text-base text-n-slate-11">
          {{ doConvite(parou ? 'APOIO_PAROU' : 'APOIO') }}
        </p>
      </div>
      <Button
        size="lg"
        class="basis-full sm:basis-auto whitespace-nowrap"
        data-carteira="escolher-funil-das-renovacoes"
        :label="doConvite(parou ? 'BOTAO_PAROU' : 'BOTAO')"
        @click="emit('escolher')"
      />
    </section>
  </div>
</template>
