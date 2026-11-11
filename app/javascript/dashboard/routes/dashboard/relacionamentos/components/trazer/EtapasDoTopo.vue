<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ETAPAS, ETAPAS_DO_TOPO } from '../../trazer/etapas';

// #2894 — Enviar → Conferir → Pronto, no topo. Lista ordenada discreta, não é
// navegação: a etapa de agora leva aria-current="step"; as feitas, um ✓.
const props = defineProps({
  atual: { type: String, required: true },
  // Enquanto ainda está trazendo, o passo 3 se chama "Trazendo".
  trazendo: { type: Boolean, default: false },
});

const { t } = useI18n();

const NOMES = {
  [ETAPAS.ENVIAR]: 'RELACIONAMENTOS_TRAZER.ETAPAS.ENVIAR',
  [ETAPAS.CONFERIR]: 'RELACIONAMENTOS_TRAZER.ETAPAS.CONFERIR',
  [ETAPAS.PRONTO]: 'RELACIONAMENTOS_TRAZER.ETAPAS.PRONTO',
};

const itens = computed(() => {
  const indice = ETAPAS_DO_TOPO.indexOf(props.atual);
  return ETAPAS_DO_TOPO.map((id, posicao) => ({
    id,
    numero: posicao + 1,
    feita: posicao < indice,
    atual: posicao === indice,
  }));
});
</script>

<template>
  <ol
    data-relacionamentos="etapas"
    :aria-label="t('RELACIONAMENTOS_TRAZER.ETAPAS.LISTA')"
    class="flex items-center gap-3 p-0 m-0 text-sm list-none"
  >
    <li
      v-for="(item, posicao) in itens"
      :key="item.id"
      :data-etapa="item.id"
      :aria-current="item.atual ? 'step' : undefined"
      class="flex items-center gap-3"
      :class="item.atual ? 'text-n-slate-12 font-semibold' : 'text-n-slate-11'"
    >
      <span
        class="flex items-center justify-center text-xs font-semibold rounded-full size-6 tabular-nums"
        :class="
          item.atual
            ? 'bg-n-blue-11 text-white dark:text-n-slate-1'
            : item.feita
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-11'
        "
        aria-hidden="true"
      >
        <span v-if="item.feita" class="i-lucide-check size-3.5" />
        <template v-else>{{ item.numero }}</template>
      </span>
      <span>{{
        t(
          item.atual && trazendo && item.id === ETAPAS.PRONTO
            ? 'RELACIONAMENTOS_TRAZER.ETAPAS.TRAZENDO'
            : NOMES[item.id]
        )
      }}</span>
      <span v-if="item.feita" class="sr-only">
        {{ t('RELACIONAMENTOS_TRAZER.ETAPAS.FEITA') }}
      </span>
      <span
        v-if="posicao < itens.length - 1"
        class="w-6 h-px bg-n-weak md:w-12"
        aria-hidden="true"
      />
    </li>
  </ol>
</template>
