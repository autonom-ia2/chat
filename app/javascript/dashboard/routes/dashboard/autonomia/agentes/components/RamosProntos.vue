<script setup>
import { useI18n } from 'vue-i18n';
import RamoCartao from './RamoCartao.vue';

// #2881 — a fileira "Prontos para o seu ramo", dentro do herói navy, antes dos três modelos gerais. #3208: a mesma
// fileira na página "Criar agente" e na tela inicial de quem ainda não tem agente. Quais cartões aparecem é decisão do
// servidor (useRamosDeSeguro); quem usa só mostra a fileira quando há pelo menos um.
// `comecando`: a chave do cartão (ramo ou modelo) que a pessoa acabou de escolher, ou null.
defineProps({
  ramos: { type: Array, required: true },
  podeUsar: { type: Boolean, default: false },
  comecando: { type: String, default: null },
});

const emit = defineEmits(['usar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.RAMOS';
</script>

<template>
  <section
    data-ramos
    aria-labelledby="ramos-titulo"
    class="flex flex-col gap-4"
  >
    <div class="flex flex-col max-w-2xl gap-1">
      <h2 id="ramos-titulo" class="m-0 text-xl font-semibold text-white">
        {{ t(`${NS}.TITULO`) }}
      </h2>
      <p class="m-0 text-base leading-relaxed text-white/80">
        {{ t(`${NS}.TEXTO`) }}
      </p>
    </div>
    <ul
      :aria-label="t(`${NS}.TITULO`)"
      class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-2 lg:grid-cols-3"
    >
      <RamoCartao
        v-for="ramo in ramos"
        :key="ramo.chave"
        :ramo="ramo"
        :pode-usar="podeUsar"
        :comecando="comecando === ramo.chave"
        :bloqueado="!!comecando && comecando !== ramo.chave"
        @usar="chave => emit('usar', chave)"
      />
    </ul>
    <h2
      class="pt-6 m-0 text-xl font-semibold text-white border-t border-white/15"
    >
      {{ t(`${NS}.OUTROS_TITULO`) }}
    </h2>
  </section>
</template>
