<script setup>
import { computed, ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AcharPainel from './AcharPainel.vue';
import AcharEscolhaCartao from './AcharEscolhaCartao.vue';
import AcharLinhaFrase from './AcharLinhaFrase.vue';

// #2692 — painel "Alterar" de "Para onde" (v4, F1): só funis de Vender que a
// pessoa vê. Até 4 funis, cartões; mais, ChoiceSelect. A etapa vem marcada.
// Aberto de dentro da folha, tem "Voltar" no topo (rodada 2).
// Rodada 4: a etapa vem marcada numa linha ("Etapa: Novo contato · Alterar");
// a lista de etapas só abre no "Alterar".
const props = defineProps({
  funis: { type: Array, required: true },
  destino: { type: Object, default: null },
  voltar: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar', 'close']);

const MAX_CARTOES = 4;
const vendas = computed(() => props.funis.filter(funil => funil.venda));
const funilId = ref(props.destino?.funil.id ?? null);
const etapaId = ref(props.destino?.etapa.id ?? null);
const funil = computed(() =>
  vendas.value.find(item => item.id === funilId.value)
);
const opcoesFunil = computed(() =>
  vendas.value.map(item => ({ value: item.id, label: item.nome }))
);
const opcoesEtapa = computed(() =>
  (funil.value?.etapas || []).map(etapa => ({
    value: etapa.id,
    label: etapa.nome,
  }))
);

const mudandoEtapa = ref(false);
const nomeDaEtapa = computed(
  () => funil.value?.etapas.find(item => item.id === etapaId.value)?.nome || ''
);
const escolherFunil = id => {
  funilId.value = id;
  etapaId.value = funil.value?.etapas[0]?.id ?? null;
};

const salvar = () => {
  const etapa = funil.value?.etapas.find(item => item.id === etapaId.value);
  if (funil.value && etapa) emit('salvar', { funil: funil.value, etapa });
};
</script>

<template>
  <AcharPainel
    :titulo="$t('PROSPECTING_ACHAR.PARA_ONDE_PAINEL.TITULO')"
    :voltar="voltar"
    @close="emit('close')"
  >
    <section class="flex flex-col gap-3">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t('PROSPECTING_ACHAR.PARA_ONDE_PAINEL.FUNIL') }}
      </h3>
      <div
        v-if="vendas.length <= MAX_CARTOES"
        role="radiogroup"
        class="grid gap-3"
      >
        <AcharEscolhaCartao
          v-for="item in vendas"
          :key="item.id"
          :titulo="item.nome"
          :escolhido="funilId === item.id"
          @escolher="escolherFunil(item.id)"
        />
      </div>
      <ChoiceSelect
        v-else
        :model-value="funilId"
        :options="opcoesFunil"
        :aria-label="$t('PROSPECTING_ACHAR.PARA_ONDE_PAINEL.FUNIL')"
        @update:model-value="escolherFunil"
      />
    </section>
    <section v-if="funil" class="flex flex-col gap-3" data-etapa>
      <AcharLinhaFrase
        icone="i-lucide-columns-3"
        :rotulo="$t('PROSPECTING_ACHAR.PARA_ONDE_PAINEL.ETAPA')"
        :texto="nomeDaEtapa"
        pode-alterar
        @alterar="mudandoEtapa = !mudandoEtapa"
      />
      <ChoiceSelect
        v-if="mudandoEtapa"
        v-model="etapaId"
        :options="opcoesEtapa"
        :aria-label="$t('PROSPECTING_ACHAR.PARA_ONDE_PAINEL.ETAPA')"
      />
    </section>
    <template #rodape>
      <p
        v-if="!funil"
        class="m-0 text-sm text-center text-n-slate-11"
        role="status"
      >
        {{ $t('PROSPECTING_ACHAR.FOLHA.DICA_FUNIL') }}
      </p>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.USAR_ESCOLHA')"
        :disabled="!funil"
        class="!min-h-12 !rounded-xl !text-base"
        data-salvar-destino
        @click="salvar"
      />
      <Button
        v-if="voltar"
        :label="$t('PROSPECTING_ACHAR.COMUM.CANCELAR')"
        variant="link"
        class="!min-h-11 justify-center"
        @click="emit('close')"
      />
    </template>
  </AcharPainel>
</template>
