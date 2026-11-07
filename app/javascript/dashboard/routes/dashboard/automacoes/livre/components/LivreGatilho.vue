<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2499 — o gatilho no "Alterar": o seletor, agrupado quando há mais de um
// grupo (conversa e mensagem, card do funil), e o que o gatilho escolhido pede
// pelo catálogo (`parametros`): a etapa, agrupada pelo funil, ou o funil
// (vazio = todos). Os de card só chegam aqui com a flag e para quem pode mexer
// no funil. Os de tempo (PR3a) pedem também os dias, o campo de data do alvo,
// antes ou depois e a hora. #2680: no gatilho de card ou de contato, a caixa por
// onde a mensagem abre a conversa de quem ainda não tem uma.
const props = defineProps({
  modelValue: { type: Object, default: null },
  gatilhos: { type: Array, required: true },
  // { funis: [{ value, label }], etapas: [{ label, options }],
  //   campos: { 'Crm::Card': [{ value, label }], Contact: [...] },
  //   caixas: [{ value, label }] (as que abrem conversa, #2680) }
  escolhas: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idTipo = useId();
const idCaixa = useId();

const opcao = item => ({ value: item.tipo, label: t(item.frase) });
const grupos = computed(() => {
  const nomes = [...new Set(props.gatilhos.map(item => item.grupo))];
  if (nomes.length < 2) return null;
  return nomes.map(grupo => ({
    label: t(
      `AUTOMACAO_LIVRE.GRUPOS_DO_GATILHO.${(grupo || '').toUpperCase()}`
    ),
    options: props.gatilhos.filter(item => item.grupo === grupo).map(opcao),
  }));
});
const opcoes = computed(() => props.gatilhos.map(opcao));

const entradaDo = tipo => props.gatilhos.find(item => item.tipo === tipo);
const pedePeca = (item, peca) =>
  (item?.parametros || []).some(parametro => parametro.peca === peca);

const entrada = computed(() => entradaDo(props.modelValue?.tipo));
const parametros = computed(() => entrada.value?.parametros || []);
const pede = peca => pedePeca(entrada.value, peca);
// O aviso de mover a etapa vale para "entrou" e "saiu da etapa". O "parado na
// etapa" pede a etapa, mas é de tempo (pede os dias) e tem o aviso dele.
const deEtapa = computed(() => pede('etapa') && !pede('dias'));
const avisoDeTempo = computed(() => {
  if (pede('campo')) return 'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_DATA';
  if (pede('dias')) return 'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_PARADO';
  return null;
});

// Dias: o "parado" conta de 1 dia em diante; o de data aceita 0 (o próprio dia).
const MAXIMO_DE_DIAS = 365;
const minimoDeDias = computed(() => (pede('campo') ? 0 : 1));
const lerDias = texto => {
  if (texto === '') return null;
  const dias = Math.trunc(Number(texto));
  if (!Number.isFinite(dias)) return minimoDeDias.value;
  return Math.min(Math.max(dias, minimoDeDias.value), MAXIMO_DE_DIAS);
};

const HORAS_DO_DIA = 24;
const horas = computed(() =>
  Array.from({ length: HORAS_DO_DIA }, (_, hora) => ({
    value: hora,
    label: t('AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.HORA', { hora }),
  }))
);
const quando = computed(() =>
  ['antes', 'depois'].map(valor => ({
    value: valor,
    label: t(`AUTOMACAO_LIVRE.QUANDO_DA_DATA.${valor.toUpperCase()}`),
  }))
);
// Os campos de data do alvo do gatilho: do card ou do contato.
const campos = computed(
  () => props.escolhas.campos?.[entrada.value?.alvo] || []
);

// O que já vem escolhido ao trocar o tipo: o "parado" em 3 dias; o de data, 30
// dias antes, a partir das 8h.
const PADRAO_DO_PARADO = { dias: 3 };
const PADRAO_DA_DATA = { dias: 30, quando: 'antes', hora: 8 };
const padraoDo = tipo => {
  const item = entradaDo(tipo);
  if (pedePeca(item, 'campo')) return PADRAO_DA_DATA;
  if (pedePeca(item, 'dias')) return PADRAO_DO_PARADO;
  return {};
};

const funis = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.GATILHO_DO_CARD.TODOS_OS_FUNIS') },
  ...(props.escolhas.funis || []),
]);

// #2680: só card e contato podem não ter conversa; a do gatilho de conversa
// já existe.
const ALVOS_SEM_CONVERSA = ['Crm::Card', 'Contact'];
const podeNaoTerConversa = tipo =>
  ALVOS_SEM_CONVERSA.includes(entradaDo(tipo)?.alvo);
const abreConversa = computed(() => podeNaoTerConversa(props.modelValue?.tipo));
const caixasDaConversa = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.CONVERSA_NOVA.NENHUMA') },
  ...(props.escolhas.caixas || []),
]);

// Trocar o tipo apaga o que o anterior pedia (etapa, funil), mas mantém os
// filtros: o painel mostra o que entra e o que sai deles. A caixa da conversa
// nova fica enquanto o novo gatilho também pode não ter conversa.
const trocarTipo = tipo => {
  const { filtros, conversa_nova: conversaNova } = props.modelValue || {};
  const novo = {
    tipo,
    ...padraoDo(tipo),
    ...(conversaNova && podeNaoTerConversa(tipo)
      ? { conversa_nova: conversaNova }
      : {}),
  };
  emit('update:modelValue', filtros ? { ...novo, filtros } : novo);
};
// Sem escolha (o funil vazio), a chave não vai na receita.
const mudar = (nome, valor) => {
  const { [nome]: _antes, ...resto } = props.modelValue || {};
  emit(
    'update:modelValue',
    valor === '' || valor === null ? resto : { ...resto, [nome]: valor }
  );
};
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="gatilho">
    <div class="flex flex-col gap-1.5">
      <label :for="idTipo" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO') }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.tipo || ''"
        :trigger-id="idTipo"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoes"
        :groups="grupos || []"
        @update:model-value="trocarTipo"
      />
    </div>

    <div
      v-for="parametro in parametros"
      :key="parametro.nome"
      class="flex flex-col gap-1.5"
      :data-parametro="parametro.nome"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(parametro.frase) }}
      </span>
      <ChoiceSelect
        v-if="parametro.peca === 'etapa'"
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :groups="escolhas.etapas || []"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <Input
        v-else-if="parametro.peca === 'dias'"
        :model-value="String(modelValue?.[parametro.nome] ?? '')"
        type="number"
        :min="String(minimoDeDias)"
        :max="String(MAXIMO_DE_DIAS)"
        class="w-28"
        :aria-label="$t(parametro.frase)"
        @update:model-value="valor => mudar(parametro.nome, lerDias(valor))"
      />
      <ChoiceSelect
        v-else-if="parametro.peca === 'hora'"
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="horas"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <ChoiceSelect
        v-else-if="parametro.peca === 'quando'"
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="quando"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <template v-else-if="parametro.peca === 'campo'">
        <ChoiceSelect
          v-if="campos.length"
          :model-value="modelValue?.[parametro.nome] ?? ''"
          :aria-label="$t(parametro.frase)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="campos"
          @update:model-value="valor => mudar(parametro.nome, valor)"
        />
        <p
          v-else
          data-sem-campo
          class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
        >
          {{ $t('AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.SEM_CAMPO') }}
        </p>
      </template>
      <ChoiceSelect
        v-else
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :options="funis"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
    </div>

    <div
      v-if="abreConversa"
      class="flex flex-col gap-1.5"
      data-parametro="conversa_nova"
    >
      <label :for="idCaixa" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.CONVERSA_NOVA.CAIXA') }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.conversa_nova?.caixa_id ?? ''"
        :trigger-id="idCaixa"
        :aria-label="$t('AUTOMACAO_LIVRE.CONVERSA_NOVA.CAIXA')"
        :options="caixasDaConversa"
        @update:model-value="
          valor =>
            mudar('conversa_nova', valor === '' ? null : { caixa_id: valor })
        "
      />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.CONVERSA_NOVA.AJUDA') }}
      </p>
    </div>

    <p
      v-if="deEtapa"
      data-nao-dispara
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      {{ $t('AUTOMACAO_LIVRE.GATILHO_NAO_DISPARA') }}
    </p>
    <p
      v-if="avisoDeTempo"
      data-aviso-tempo
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      {{ $t(avisoDeTempo) }}
    </p>
  </div>
</template>
