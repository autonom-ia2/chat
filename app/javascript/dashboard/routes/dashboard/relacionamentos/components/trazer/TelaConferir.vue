<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import { partesDaFrase } from '../../trazer/contagem';
import FichaDeExemplo from './FichaDeExemplo.vue';
import OQueVouGuardar from './OQueVouGuardar.vue';
import PrecisamDeVoce from './PrecisamDeVoce.vue';

// #2894 — "Conferir": a frase do que achei, três fichas de exemplo, o que
// precisa da pessoa, o que vai ser guardado e o botão único de trazer.
const props = defineProps({
  leitura: { type: Object, required: true },
  resumo: { type: Object, required: true },
  total: { type: Number, required: true },
  ocupado: { type: Boolean, default: false },
  comErro: { type: Boolean, default: false },
});
const emit = defineEmits([
  'guardar',
  'deixarDeFora',
  'reabrir',
  'trocar',
  'trazer',
  'voltar',
  'tentar',
]);

const { t } = useI18n();
const CHAVES_DA_FRASE = {
  NOVAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.NOVAS',
  COMPLETADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.COMPLETADAS',
  PRECISAM: 'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.PRECISAM',
  DEIXADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.DEIXADAS',
};

// "Achei 200 pessoas. 180 são novas, 15 já estavam aqui…, 5 precisam de você."
const frase = computed(() => {
  const achei = t(
    'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.TOTAL',
    { count: props.resumo.total },
    props.resumo.total
  );
  const partes = partesDaFrase(props.resumo).map(({ chave, count }) =>
    t(CHAVES_DA_FRASE[chave], { count }, count)
  );
  return partes.length ? `${achei} ${partes.join(', ')}.` : achei;
});
</script>

<template>
  <section data-relacionamentos="conferir" class="flex flex-col gap-10">
    <h1
      data-titulo-da-tela
      tabindex="-1"
      aria-live="polite"
      class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ frase }}
    </h1>

    <section class="flex flex-col gap-4">
      <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.EXEMPLOS') }}
      </h2>
      <div class="grid gap-3 md:grid-cols-3">
        <FichaDeExemplo
          v-for="pessoa in leitura.exemplos"
          :key="pessoa.nome"
          :pessoa="pessoa"
        />
      </div>
    </section>

    <PrecisamDeVoce
      v-if="leitura.problemas.length"
      :problemas="leitura.problemas"
      :ocupado="ocupado"
      @guardar="(linha, valor) => emit('guardar', linha, valor)"
      @deixar-de-fora="linha => emit('deixarDeFora', linha)"
      @reabrir="linha => emit('reabrir', linha)"
    />

    <OQueVouGuardar
      :colunas="leitura.colunas"
      :ocupado="ocupado"
      @trocar="(coluna, destino) => emit('trocar', coluna, destino)"
    />

    <div class="flex flex-col gap-4">
      <p class="flex items-center gap-2 m-0 text-base text-n-slate-11">
        <span class="i-lucide-undo-2 size-5" aria-hidden="true" />
        {{ t('RELACIONAMENTOS_TRAZER.CONFERIR.SOSSEGO') }}
      </p>
      <div v-if="comErro" data-relacionamentos="erro">
        <ErroComTentarDeNovo
          :mensagem="t('RELACIONAMENTOS_TRAZER.ERROS.TRAZER')"
          @tentar="emit('tentar')"
        />
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          data-relacionamentos="trazer-confirmar"
          size="lg"
          class="!min-h-12 !rounded-xl"
          :label="
            t('RELACIONAMENTOS_TRAZER.CONFERIR.TRAZER', { count: total }, total)
          "
          :disabled="total === 0 || ocupado"
          @click="emit('trazer')"
        />
        <Button
          slate
          faded
          class="min-h-11"
          :label="t('RELACIONAMENTOS.COMUM.VOLTAR')"
          @click="emit('voltar')"
        />
      </div>
    </div>
  </section>
</template>
