<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PassagemOpcao from './PassagemOpcao.vue';
import PassagemPassos from './PassagemPassos.vue';
import PassagemQuando from './PassagemQuando.vue';
import PassagemQuem from './PassagemQuem.vue';
import PassagemComo from './PassagemComo.vue';
import { ETAPA_DESLIGADA, ETAPA_IGUAL, ETAPA_PROPRIA } from './passagem';

// #1385 — uma etapa: como nas outras, do meu jeito, ou sem chamar ninguém. "Do meu jeito" vem em passos guiados
// (Quando → Quem recebe → Como entregar); o passo 0 é a escolha. As outras duas salvam direto no passo 0.
defineProps({
  funilLigado: { type: Boolean, required: true },
  equipe: { type: Array, default: () => [] },
  todas: { type: Array, default: () => [] },
  mostrarErros: { type: Boolean, default: false },
});

const etapa = defineModel({ type: Object, required: true });
const passo = defineModel('passo', { type: Number, default: 0 });

const { t } = useI18n();
const E = 'CRM_KANBAN.PASSAGEM.ETAPA';

const modo = computed({
  get: () => etapa.value.modo,
  set: valor => {
    etapa.value = { ...etapa.value, modo: valor };
  },
});
const regra = computed({
  get: () => etapa.value.regra,
  set: valor => {
    etapa.value = { ...etapa.value, regra: valor };
  },
});
const nomesDosPassos = computed(() => [
  t(`${E}.PASSO_QUANDO`),
  t(`${E}.PASSO_QUEM`),
  t(`${E}.PASSO_COMO`),
]);
const prefixo = computed(() => `etapa-${etapa.value.id}`);
</script>

<template>
  <div class="flex flex-col gap-6">
    <section
      v-if="passo === 0"
      class="flex flex-col gap-4"
      :aria-labelledby="`${prefixo}-modo`"
    >
      <h2
        :id="`${prefixo}-modo`"
        class="mb-0 text-lg font-semibold text-n-slate-12"
      >
        {{ t(`${E}.TITULO`) }}
      </h2>
      <div
        role="radiogroup"
        :aria-labelledby="`${prefixo}-modo`"
        class="flex flex-col gap-3"
      >
        <PassagemOpcao
          v-model="modo"
          :name="`${prefixo}-modo`"
          :value="ETAPA_IGUAL"
          :titulo="t(`${E}.IGUAL`)"
          :descricao="
            t(funilLigado ? `${E}.IGUAL_DESC` : `${E}.IGUAL_DESC_DESLIGADO`)
          "
        />
        <PassagemOpcao
          v-model="modo"
          :name="`${prefixo}-modo`"
          :value="ETAPA_PROPRIA"
          :titulo="t(`${E}.PROPRIA`)"
          :descricao="t(`${E}.PROPRIA_DESC`)"
        />
        <PassagemOpcao
          v-model="modo"
          :name="`${prefixo}-modo`"
          :value="ETAPA_DESLIGADA"
          :titulo="t(`${E}.DESLIGADA`)"
          :descricao="t(`${E}.DESLIGADA_DESC`)"
        />
      </div>
    </section>

    <template v-else>
      <PassagemPassos
        :atual="passo"
        :nomes="nomesDosPassos"
        :rotulo="t(`${E}.PASSOS_ROTULO`)"
        @ir="passo = $event"
      />
      <PassagemQuando v-if="passo === 1" v-model="regra" :nome="prefixo" />
      <PassagemQuem
        v-else-if="passo === 2"
        v-model="regra"
        :nome="prefixo"
        :equipe="equipe"
        :todas="todas"
        :mostrar-erros="mostrarErros"
      />
      <PassagemComo
        v-else
        v-model="regra"
        :nome="prefixo"
        :equipe="equipe"
        :todas="todas"
        :mostrar-erros="mostrarErros"
      />
    </template>
  </div>
</template>
