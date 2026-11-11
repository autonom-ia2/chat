<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import CartoesDeEscolha from '../../trazer/CartoesDeEscolha.vue';
import { COMECO } from '../../../carteira/useTrazerSeguros';
import { COMO } from '../../../carteira/passosDeTrazerSeguros';

// #2897 — "Como você quer trazer seus clientes e seguros?": três cartões
// (planilha, PDFs das apólices, Agger) e UM botão. O botão fica sempre ligado:
// sem cartão escolhido, o clique diz o que falta e leva o foco aos cartões.
const props = defineProps({
  estado: { type: String, default: COMECO.PRONTO },
  aggerLigado: { type: Boolean, default: false },
});
const emit = defineEmits(['continuar', 'tentar']);

const { t } = useI18n();
const tc = chave => t(`RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.${chave}`);
const id = useId();
const raiz = ref(null);
const escolha = ref('');
const falta = ref(false);

const cartao = (como, rotulo, descricao) => ({
  id: como,
  rotulo: tc(rotulo),
  descricao: tc(descricao),
  atributos: { 'data-carteira': `cartao-${como}` },
});
const opcoes = computed(() => [
  cartao(COMO.PLANILHA, 'PLANILHA', 'PLANILHA_APOIO'),
  cartao(COMO.PDFS, 'PDFS', 'PDFS_APOIO'),
  cartao(
    COMO.AGGER,
    'AGGER',
    props.aggerLigado ? 'AGGER_LIGADO' : 'AGGER_APOIO'
  ),
]);

const continuar = () => {
  if (escolha.value) {
    emit('continuar', escolha.value);
    return;
  }
  falta.value = true;
  raiz.value?.querySelector('[role="radio"]')?.focus();
};

watch(escolha, () => {
  falta.value = false;
});
</script>

<template>
  <section ref="raiz" data-carteira="como-trazer" class="flex flex-col gap-8">
    <h1
      :id="`${id}-titulo`"
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ tc('TITULO') }}
    </h1>

    <div v-if="estado === COMECO.ERRO" data-carteira="erro">
      <ErroComTentarDeNovo :mensagem="tc('ERRO')" @tentar="emit('tentar')" />
    </div>
    <div
      v-else-if="estado === COMECO.CARREGANDO"
      data-carteira="carregando"
      role="status"
      aria-busy="true"
      :aria-label="t('RELACIONAMENTOS.COMUM.CARREGANDO')"
      class="grid gap-3 sm:grid-cols-3"
    >
      <div
        v-for="cartaoVazio in 3"
        :key="cartaoVazio"
        aria-hidden="true"
        class="h-28 rounded-2xl bg-n-slate-3 dark:bg-n-slate-5 animate-pulse"
      />
    </div>
    <template v-else>
      <CartoesDeEscolha
        v-model="escolha"
        :opcoes="opcoes"
        :rotulo-id="`${id}-titulo`"
        :invalido="falta"
        :descrito-por="falta ? `${id}-falta` : undefined"
      />
      <p
        v-if="falta"
        :id="`${id}-falta`"
        data-carteira="falta-escolher"
        role="alert"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ tc('FALTA_ESCOLHER') }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          data-carteira="continuar-como"
          size="lg"
          :label="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
          @click="continuar"
        />
      </div>
    </template>
  </section>
</template>
