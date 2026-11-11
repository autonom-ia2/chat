<script setup>
import { computed, ref } from 'vue';
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
const raiz = ref(null);
const ROTULOS_DO_CONTADOR = {
  NOVAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.NOVAS',
  COMPLETADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.COMPLETADAS',
  PRECISAM: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.PRECISAM',
  DEIXADAS: 'RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.DEIXADAS',
};

// "Achei 200 pessoas." — o título curto; os números vêm nos contadores.
const frase = computed(() =>
  t(
    'RELACIONAMENTOS_TRAZER.CONFERIR.FRASE.TOTAL',
    { count: props.resumo.total },
    props.resumo.total
  )
);

// Contador com zero não aparece. "Precisam de você" leva ao bloco dos problemas.
const contadores = computed(() =>
  partesDaFrase(props.resumo).map(({ chave, count }) => {
    const rotulo = t(ROTULOS_DO_CONTADOR[chave], count);
    return {
      chave,
      count,
      rotulo,
      leitura: `${count} ${rotulo}`,
      levaAosProblemas: chave === 'PRECISAM',
    };
  })
);

const irParaPrecisam = () => {
  const secao = raiz.value?.querySelector(
    '[data-relacionamentos="precisam-de-voce"]'
  );
  if (!secao) return;
  const reduz = window.matchMedia?.(
    '(prefers-reduced-motion: reduce)'
  )?.matches;
  secao.scrollIntoView({ behavior: reduz ? 'auto' : 'smooth', block: 'start' });
  secao
    .querySelector('[data-relacionamentos="precisam-titulo"]')
    ?.focus({ preventScroll: true });
};
</script>

<template>
  <section
    ref="raiz"
    data-relacionamentos="conferir"
    class="flex flex-col gap-10"
  >
    <div class="flex flex-col gap-6">
      <h1
        data-titulo-da-tela
        tabindex="-1"
        class="m-0 text-3xl font-bold leading-tight tracking-tight outline-none md:text-4xl text-n-slate-12"
      >
        {{ frase }}
      </h1>
      <ul
        v-if="contadores.length"
        data-relacionamentos="contadores"
        :aria-label="t('RELACIONAMENTOS_TRAZER.CONFERIR.CONTADOR.LISTA')"
        class="flex flex-wrap p-0 m-0 list-none gap-x-10 gap-y-4"
      >
        <li
          v-for="contador in contadores"
          :key="contador.chave"
          :data-contador="contador.chave"
        >
          <component
            :is="contador.levaAosProblemas ? 'button' : 'div'"
            :type="contador.levaAosProblemas ? 'button' : undefined"
            class="flex flex-col items-start gap-1 text-start"
            :class="
              contador.levaAosProblemas
                ? 'min-h-11 rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand'
                : ''
            "
            @click="contador.levaAosProblemas ? irParaPrecisam() : undefined"
          >
            <span class="sr-only">{{ contador.leitura }}</span>
            <span
              class="text-4xl font-bold leading-none tabular-nums text-n-slate-12"
              aria-hidden="true"
            >
              {{ contador.count }}
            </span>
            <span
              class="text-sm text-n-slate-11"
              :class="
                contador.levaAosProblemas
                  ? 'underline underline-offset-4 decoration-n-weak'
                  : ''
              "
              aria-hidden="true"
            >
              {{ contador.rotulo }}
            </span>
          </component>
        </li>
      </ul>
    </div>

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
