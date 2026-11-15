<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { chaveDaRecusa, codigoDaRecusa } from '../../../../carteira/recusas';

// #2900 (E7.3) — o interruptor "Buscar novos seguros todo dia". Ligado, a busca
// roda sozinha uma vez por dia e o que ela traz entra na carteira (aparece nas
// buscas, com Desfazer). Ele liga sozinho na primeira busca trazida; a pessoa
// desliga e liga quando quiser. Se o pedido falha, o interruptor volta ao que
// era e a frase diz que não deu.
const props = defineProps({
  fonte: { type: Object, required: true },
});

const { t } = useI18n();
const BASE = 'RELACIONAMENTOS_CARTEIRA.AGGER.TODO_DIA';
const ligado = ref(false);
const carregou = ref(false);
const ocupado = ref(false);
const erro = ref('');

const falhou = falha => {
  erro.value = chaveDaRecusa(
    codigoDaRecusa(falha),
    'RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU'
  );
};

const carregar = async () => {
  erro.value = '';
  try {
    ligado.value = await props.fonte.buscaDiaria();
    carregou.value = true;
  } catch (falha) {
    falhou(falha);
  }
};

const trocar = async () => {
  if (ocupado.value) return;
  ocupado.value = true;
  erro.value = '';
  const antes = ligado.value;
  ligado.value = !antes;
  try {
    ligado.value = await props.fonte.mudarBuscaDiaria(!antes);
  } catch (falha) {
    ligado.value = antes;
    falhou(falha);
  } finally {
    ocupado.value = false;
  }
};

onMounted(carregar);
defineExpose({ carregar });
</script>

<template>
  <section data-carteira="busca-de-todo-dia" class="flex flex-col gap-2">
    <button
      v-if="carregou"
      type="button"
      role="switch"
      data-carteira="interruptor-todo-dia"
      :aria-checked="ligado"
      :aria-busy="ocupado"
      aria-describedby="carteira-agger-todo-dia-apoio"
      class="flex items-center justify-between w-full gap-4 p-4 text-start border rounded-2xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="trocar"
    >
      <span class="text-base font-medium">{{ t(`${BASE}.ROTULO`) }}</span>
      <span
        aria-hidden="true"
        class="relative inline-flex items-center flex-shrink-0 h-7 transition-colors rounded-full w-12"
        :class="ligado ? 'bg-n-brand' : 'bg-n-slate-6'"
      >
        <span
          class="absolute bg-white rounded-full shadow size-5 transition-transform"
          :class="ligado ? 'translate-x-6' : 'translate-x-1'"
        />
      </span>
    </button>
    <p
      v-if="carregou"
      id="carteira-agger-todo-dia-apoio"
      class="m-0 text-sm text-n-slate-11"
    >
      {{ t(ligado ? `${BASE}.LIGADO` : `${BASE}.DESLIGADO`) }}
    </p>
    <template v-if="erro">
      <p role="alert" class="m-0 text-base text-n-ruby-11">{{ t(erro) }}</p>
      <button
        v-if="!carregou"
        type="button"
        data-carteira="tentar-todo-dia"
        class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="carregar"
      >
        {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.TENTAR_DE_NOVO') }}
      </button>
    </template>
  </section>
</template>
