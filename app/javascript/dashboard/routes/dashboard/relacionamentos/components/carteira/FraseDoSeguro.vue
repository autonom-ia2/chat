<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { diasDesde } from '../../fonte/selosDoSeguro';
import { quandoDoSeguro } from '../../carteira/quandoDoSeguro';
import { SITUACOES, situacaoDoSeguro } from '../../carteira/situacaoDoSeguro';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SelosDoSeguro from './SelosDoSeguro.vue';

// #2897 — o topo da gaveta do seguro: o selo e UMA frase que diz como o seguro
// está agora. O próximo passo (o botão) fica no rodapé da gaveta.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();
const textos = useTextosDoSeguro();
const tf = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.FRASE.${chave}`, valores);

// Quando vence: a mesma regra da lista e da ficha (`quandoDoSeguro`).
const quandoVence = (seguro, agora) => {
  const { id, count, data } = quandoDoSeguro(seguro, agora);
  return tf(id, { count, data: data ? textos.dataInteira(data) : '' });
};
const AMANHA = 1;
const quandoVenceu = dias => {
  if (dias === 0) return tf('VENCEU_HOJE');
  return dias === AMANHA
    ? tf('VENCEU_ONTEM')
    : tf('VENCEU_HA', { count: dias });
};

const frases = computed(() => {
  const { seguro, agora } = props;
  const porSituacao = {
    [SITUACOES.EM_RENOVACAO]: () => [
      quandoVence(seguro, agora),
      textos.renovacao(seguro.renovacao),
    ],
    [SITUACOES.ATIVO]: () => [
      tf('VALE_ATE', { data: textos.dataInteira(seguro.termina) }),
      seguro.temPdf ? '' : tf('SEM_PDF'),
    ],
    [SITUACOES.PARCELA]: () => [
      tf('PARCELA', { data: textos.diaMes(seguro.parcelaAbertaEm, agora) }),
    ],
    [SITUACOES.RENOVADO]: () => [
      tf('RENOVOU_EM', { data: textos.diaMes(seguro.renovadoEm, agora) }),
    ],
    [SITUACOES.VENCIDO]: () => [
      quandoVenceu(diasDesde(seguro.termina, agora)),
      seguro.motivo
        ? tf('MOTIVO', {
            motivo: t(
              `RELACIONAMENTOS_CARTEIRA.MOTIVOS.${seguro.motivo.toUpperCase()}`
            ),
          })
        : '',
    ],
    [SITUACOES.CANCELADO]: () => [
      tf('CANCELADO_EM', { data: textos.diaMes(seguro.canceladoEm, agora) }),
    ],
  };
  return porSituacao[situacaoDoSeguro(seguro, agora).id]().filter(Boolean);
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <SelosDoSeguro :seguro="seguro" :agora="agora" />
    </div>
    <p
      data-carteira="frase-do-seguro"
      class="m-0 text-xl font-semibold leading-snug text-balance text-n-slate-12"
    >
      {{ frases.join(' ') }}
    </p>
  </div>
</template>
