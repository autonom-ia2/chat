<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { variacaoDaProposta } from '../../carteira/situacaoDoSeguro';

// #2897 — "Renovação" na gaveta do seguro: em que funil e etapa o card está,
// quem cuida e, quando há proposta, quanto mudou em relação ao ano passado. Sem
// proposta, numa conta que cota sozinha, o botão discreto "Cotar agora".
const props = defineProps({
  renovacao: { type: Object, required: true },
  // O link "Abrir a renovação" só aparece quando não é o botão principal.
  mostraAbrir: { type: Boolean, default: false },
  podeCotar: { type: Boolean, default: false },
  pedindoCotacao: { type: Boolean, default: false },
});
const emit = defineEmits(['abrir', 'cotar']);

const { t } = useI18n();
const tr = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.GAVETA.RENOVACAO.${chave}`, valores);
const idDoTitulo = useId();

const variacao = computed(() => {
  const mudou = variacaoDaProposta(props.renovacao.proposta);
  return mudou ? tr(mudou.id, { count: mudou.count }) : '';
});
const cotando = computed(() => props.renovacao.cotando);
const ofereceCotar = computed(
  () => props.podeCotar && !props.renovacao.proposta && !cotando.value
);
</script>

<template>
  <section
    data-carteira="renovacao"
    :aria-labelledby="idDoTitulo"
    class="flex flex-col gap-3"
  >
    <h3 :id="idDoTitulo" class="m-0 text-base font-semibold text-n-slate-12">
      {{ tr('TITULO') }}
    </h3>
    <p class="m-0 text-base break-words text-n-slate-12">
      {{
        tr('FUNIL', {
          funil: renovacao.funil,
          etapa: renovacao.etapa,
          cuida: renovacao.cuida,
        })
      }}
    </p>
    <p v-if="variacao" class="m-0 text-base text-n-slate-12">{{ variacao }}</p>
    <p
      v-if="cotando"
      data-carteira="cotando"
      role="status"
      class="m-0 text-base text-n-slate-11"
    >
      {{ tr('COTANDO') }}
    </p>
    <div v-if="ofereceCotar" class="flex flex-col items-start gap-2">
      <Button
        slate
        faded
        size="lg"
        data-carteira="cotar-agora"
        :is-loading="pedindoCotacao"
        :label="tr('COTAR_AGORA')"
        @click="emit('cotar')"
      />
      <p class="m-0 text-sm text-n-slate-11">{{ tr('USA_CONSULTA') }}</p>
    </div>
    <div v-if="mostraAbrir">
      <Button
        link
        size="lg"
        data-carteira="abrir-renovacao"
        :label="tr('ABRIR')"
        @click="emit('abrir')"
      />
    </div>
  </section>
</template>
