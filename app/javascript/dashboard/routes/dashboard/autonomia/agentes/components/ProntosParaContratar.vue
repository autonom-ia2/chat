<script setup>
import { useI18n } from 'vue-i18n';
import ContratadoCartao from './ContratadoCartao.vue';

// #3211 — "Vendem sozinhos": os agentes prontos que a corretora contrata, dentro do herói navy da página "Criar
// agente", antes dos ramos (mockup aprovado, estado 01). Quais modelos aparecem é decisão do servidor
// (useContratados); quem usa só monta a seção com pelo menos um modelo que a tela conhece. `abrir` leva a chave do
// modelo, e a página navega para autonomia_contratado_modelo.
defineProps({
  modelos: { type: Array, required: true },
  podeUsar: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);

const { t } = useI18n();
</script>

<template>
  <section
    data-contratados
    aria-labelledby="contratados-titulo"
    class="flex flex-col gap-4"
  >
    <div class="flex flex-col max-w-2xl gap-1">
      <h2 id="contratados-titulo" class="m-0 text-xl font-semibold text-white">
        {{ t('AGENTS.CONTRATADOS.AREA.TITULO') }}
      </h2>
      <p class="m-0 text-base leading-relaxed text-white/80">
        {{ t('AGENTS.CONTRATADOS.AREA.TEXTO') }}
      </p>
    </div>
    <ul
      :aria-label="t('AGENTS.CONTRATADOS.AREA.TITULO')"
      class="flex flex-col gap-4 p-0 m-0 list-none"
    >
      <ContratadoCartao
        v-for="modelo in modelos"
        :key="modelo"
        :modelo="modelo"
        :pode-usar="podeUsar"
        @abrir="chave => emit('abrir', chave)"
      />
    </ul>
  </section>
</template>
