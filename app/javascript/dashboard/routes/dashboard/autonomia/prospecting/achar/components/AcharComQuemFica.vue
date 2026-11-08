<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AcharPainel from './AcharPainel.vue';
import AcharEscolhaCartao from './AcharEscolhaCartao.vue';

// #2692 — painel "Com quem ficam as empresas?" (v4, F1; molde
// crm/components/card/telas/TelaQuemCuida.vue). Só pessoas da conta com acesso
// ao funil, "Você" no topo. Até 6 pessoas, cartões de um toque com avatar;
// mais que isso, ChoiceSelect. O "Alterar" que abre este painel é decisão do
// Rodrigo (caso A); o servidor ainda não aceita o dono escolhido (v4, PR 2a).
// Rodada 2: aberto de dentro da folha, tem "Voltar" no topo e "Cancelar" no
// rodapé (uma saída de cada tipo); cada pessoa com borda e iniciais.
const props = defineProps({
  pessoas: { type: Array, required: true },
  escolhida: { type: [String, Number], default: 'voce' },
});
const emit = defineEmits(['salvar', 'close']);

const { t } = useI18n();
const MAX_CARTOES = 6;
const rascunho = ref(props.escolhida);
const nomeDe = pessoa =>
  pessoa.voce
    ? t('PROSPECTING_ACHAR.COM_QUEM_PAINEL.VOCE', { nome: pessoa.nome })
    : pessoa.nome;
const iniciaisDe = pessoa =>
  pessoa.nome
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase();
const ordenadas = computed(() => [
  ...props.pessoas.filter(pessoa => pessoa.voce),
  ...props.pessoas.filter(pessoa => !pessoa.voce),
]);
const opcoes = computed(() =>
  ordenadas.value.map(pessoa => ({ value: pessoa.id, label: nomeDe(pessoa) }))
);
</script>

<template>
  <AcharPainel
    :titulo="$t('PROSPECTING_ACHAR.COM_QUEM_PAINEL.TITULO')"
    voltar
    @close="emit('close')"
  >
    <div
      v-if="pessoas.length <= MAX_CARTOES"
      role="radiogroup"
      class="grid gap-3"
      data-pessoas
    >
      <AcharEscolhaCartao
        v-for="pessoa in ordenadas"
        :key="pessoa.id"
        :titulo="nomeDe(pessoa)"
        :iniciais="iniciaisDe(pessoa)"
        :escolhido="rascunho === pessoa.id"
        @escolher="rascunho = pessoa.id"
      />
    </div>
    <ChoiceSelect
      v-else
      v-model="rascunho"
      :options="opcoes"
      :aria-label="$t('PROSPECTING_ACHAR.COM_QUEM_PAINEL.PESSOA')"
    />
    <template #rodape>
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.USAR_ESCOLHA')"
        class="!min-h-12 !rounded-xl !text-base"
        data-salvar-pessoa
        @click="emit('salvar', rascunho)"
      />
      <Button
        :label="$t('PROSPECTING_ACHAR.COMUM.CANCELAR')"
        variant="link"
        class="!min-h-11 justify-center"
        @click="emit('close')"
      />
    </template>
  </AcharPainel>
</template>
