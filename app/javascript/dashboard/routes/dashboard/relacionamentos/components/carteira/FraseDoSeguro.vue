<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { diasDesde } from '../../fonte/selosDoSeguro';
import { quandoDoSeguro } from '../../carteira/quandoDoSeguro';
import { SITUACOES, situacaoDoSeguro } from '../../carteira/situacaoDoSeguro';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import SelosDoSeguro from './SelosDoSeguro.vue';

// #2897 — o topo da gaveta do seguro: o selo e UMA frase que diz como o seguro
// está agora. O próximo passo (o botão) fica no rodapé da gaveta. No seguro em
// renovação, a frase é a mesma do título da gaveta da renovação (por isso
// `daConta`: o que a conta cota sozinha). Logo abaixo, quando algo que ia sair
// sozinho não saiu, uma linha diz o que foi e o caminho (`naoSaiu`).
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
  // { cotaSozinha, tiposQueCota }
  daConta: { type: Object, default: () => ({}) },
  naoSaiu: { type: String, default: '' },
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
  const { seguro, agora, daConta } = props;
  const porSituacao = {
    [SITUACOES.EM_RENOVACAO]: () => [
      quandoVence(seguro, agora),
      textos.renovacao(seguro, daConta),
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
    <p
      v-if="naoSaiu"
      role="status"
      data-carteira="nao-saiu"
      class="flex items-start gap-2 m-0 text-base font-medium text-n-slate-12"
    >
      <span
        class="mt-0.5 i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      <span class="min-w-0 break-words">{{ naoSaiu }}</span>
    </p>
  </div>
</template>
