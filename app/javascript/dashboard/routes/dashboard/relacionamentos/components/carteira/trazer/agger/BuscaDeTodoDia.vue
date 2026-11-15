<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  chaveDaRecusaDoAgger,
  codigoDaRecusa,
} from '../../../../carteira/recusas';

// #2900 (E7.3) — o interruptor "Buscar novos seguros todo dia". Ligado, a busca
// roda sozinha uma vez por dia e o que ela traz entra na carteira (aparece nas
// buscas, com Desfazer). Ele liga sozinho na primeira busca trazida e só
// aparece depois dela (`jaTrouxe`); a pessoa desliga e liga quando quiser. Se
// o pedido falha, o interruptor volta ao que era e a frase diz que não deu.
//
// Quando o Agger recusou o login guardado (`pedeLogin`), a busca de todo dia
// não roda: no lugar do "Ligado", a frase diz isso e o que fazer — entrar de
// novo (quem pode escrever o login) ou pedir a quem administra a conta.
const props = defineProps({
  fonte: { type: Object, required: true },
  pedeLogin: { type: Boolean, default: false },
  podeLigar: { type: Boolean, default: false },
});
const emit = defineEmits(['entrar']);

const { t } = useI18n();
const BASE = 'RELACIONAMENTOS_CARTEIRA.AGGER.TODO_DIA';
const ligado = ref(false);
const jaTrouxe = ref(false);
const carregou = ref(false);
const ocupado = ref(false);
const erro = ref('');
const fazerComOLogin = computed(() =>
  props.podeLigar
    ? `${BASE}.PEDE_LOGIN_FAZER`
    : 'RELACIONAMENTOS_CARTEIRA.AGGER.PECA_AO_ADMIN'
);

const falhou = falha => {
  erro.value = chaveDaRecusaDoAgger(
    codigoDaRecusa(falha),
    'RELACIONAMENTOS_CARTEIRA.AGGER.NAO_DEU'
  );
};

const carregar = async () => {
  erro.value = '';
  try {
    const diaria = await props.fonte.buscaDiaria();
    ligado.value = diaria.ligado;
    jaTrouxe.value = diaria.jaTrouxe;
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
  <section
    v-if="(carregou && jaTrouxe) || erro"
    data-carteira="busca-de-todo-dia"
    class="flex flex-col gap-2"
  >
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
    <div
      v-if="carregou && ligado && pedeLogin"
      id="carteira-agger-todo-dia-apoio"
      role="alert"
      data-carteira="todo-dia-pede-login"
      class="flex flex-col gap-2 p-4 border rounded-2xl border-n-amber-6 bg-n-amber-2"
    >
      <span class="text-base font-medium text-n-slate-12">
        {{ t(`${BASE}.PEDE_LOGIN`) }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ t(fazerComOLogin) }}
      </span>
      <button
        v-if="podeLigar"
        type="button"
        data-carteira="todo-dia-entrar"
        class="self-start px-4 text-sm font-medium border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('entrar')"
      >
        {{ t('RELACIONAMENTOS_CARTEIRA.AGGER.ENTRAR') }}
      </button>
    </div>
    <p
      v-else-if="carregou"
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
