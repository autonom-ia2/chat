<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreDuracao from './LivreDuracao.vue';
import LivreSelecao from './LivreSelecao.vue';
import { mostraNaFrequencia } from '../recorrente';

// #2499 — o gatilho no "Alterar": o seletor, agrupado quando há mais de um
// grupo (conversa e mensagem, card do funil), e o que o gatilho escolhido pede
// pelo catálogo (`parametros`): a etapa, agrupada pelo funil, ou o funil
// (vazio = todos). Os de card só chegam aqui com a flag e para quem pode mexer
// no funil. Os de tempo (PR3a) pedem também os dias, o campo de data do alvo,
// antes ou depois e a hora. O lembrete antes da reunião (#2709) pede quanto
// tempo antes. O recorrente (#2635, G7) pede a frequência, o dia (da semana ou
// do mês, conforme a frequência), a hora e a seleção dos cards ou contatos
// (LivreSelecao). #2680: no gatilho de card ou de contato, a caixa por onde a
// mensagem abre a conversa de quem ainda não tem uma. G60: a página de agenda
// de reserva, para o link da agenda quando ninguém atende.
const props = defineProps({
  modelValue: { type: Object, default: null },
  gatilhos: { type: Array, required: true },
  // { funis: [{ value, label }], etapas: [{ label, options }],
  //   campos: { 'Crm::Card': [{ value, label }], Contact: [...] },
  //   caixas: [{ value, label }] (as que abrem conversa, #2680) }
  escolhas: { type: Object, default: () => ({}) },
  // As escolhas da conta (useOpcoesDaConta): pessoas, etiquetas, atributos.
  opcoes: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idTipo = useId();
const idCaixa = useId();
const idAgenda = useId();

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
const pede = peca => pedePeca(entrada.value, peca);
const parametros = computed(() =>
  (entrada.value?.parametros || []).filter(parametro =>
    mostraNaFrequencia(parametro.nome, props.modelValue?.frequencia)
  )
);
// O aviso de mover a etapa vale para "entrou" e "saiu da etapa". O "parado na
// etapa" pede a etapa, mas é de tempo (pede os dias) e tem o aviso dele.
const deEtapa = computed(() => pede('etapa') && !pede('dias'));
const avisoDeTempo = computed(() => {
  if (pede('antes')) return 'AUTOMACAO_LIVRE.GATILHO_DE_TEMPO.AVISO_LEMBRETE';
  if (pede('frequencia')) {
    // G39: o "uma vez só" não tem dia 29 a 31 nem vez anterior.
    if (props.modelValue?.frequencia === 'uma_vez')
      return pede('selecao')
        ? 'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.AVISO_UMA_VEZ'
        : 'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.AVISO_UMA_VEZ_CONTA';
    return pede('selecao')
      ? 'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.AVISO'
      : 'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.AVISO_CONTA';
  }
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
const FREQUENCIAS = ['diaria', 'semanal', 'mensal', 'uma_vez'];
const frequencias = computed(() =>
  FREQUENCIAS.map(valor => ({
    value: valor,
    label: t(`AUTOMACAO_LIVRE.GATILHO_RECORRENTE.${valor.toUpperCase()}`),
  }))
);
const DIAS_NA_SEMANA = 7;
const diasDaSemana = computed(() =>
  Array.from({ length: DIAS_NA_SEMANA }, (_, dia) => ({
    value: dia,
    label: t(`AUTOMACAO_LIVRE.GATILHO_RECORRENTE.DIAS_DA_SEMANA.${dia}`),
  }))
);
const DIAS_NO_MES = 31;
const diasDoMes = computed(() =>
  Array.from({ length: DIAS_NO_MES }, (_, i) => ({
    value: i + 1,
    label: t('AUTOMACAO_LIVRE.GATILHO_RECORRENTE.DIA_DO_MES', { dia: i + 1 }),
  }))
);
// #2678: a data vale uma vez (com o ano) ou todo ano (só dia e mês). "Uma vez"
// é a ausência da chave na receita.
const repete = computed(() =>
  ['uma_vez', 'todo_ano'].map(valor => ({
    value: valor,
    label: t(`AUTOMACAO_LIVRE.REPETE_DA_DATA.${valor.toUpperCase()}`),
  }))
);
// Os campos de data do alvo do gatilho: do card ou do contato.
const campos = computed(
  () => props.escolhas.campos?.[entrada.value?.alvo] || []
);

// O que já vem escolhido ao trocar o tipo: o "parado" em 3 dias; o de data, 30
// dias antes, a partir das 8h; o recorrente, todo dia às 8h, sem seleção (a
// pessoa escolhe; vazia, não salva).
const PADRAO_DO_PARADO = { dias: 3 };
const PADRAO_DA_DATA = { dias: 30, quando: 'antes', hora: 8 };
const PADRAO_DO_LEMBRETE = { antes: { valor: 1, unidade: 'dias' } };
const PADRAO_DO_RECORRENTE = { frequencia: 'diaria', hora: 8, selecao: {} };
// O da conta não tem seleção: roda uma vez por ocorrência.
const PADRAO_DA_CONTA = { frequencia: 'diaria', hora: 8 };
const padraoDo = tipo => {
  const item = entradaDo(tipo);
  if (pedePeca(item, 'antes')) return PADRAO_DO_LEMBRETE;
  if (pedePeca(item, 'frequencia'))
    return pedePeca(item, 'selecao') ? PADRAO_DO_RECORRENTE : PADRAO_DA_CONTA;
  if (pedePeca(item, 'campo')) return PADRAO_DA_DATA;
  if (pedePeca(item, 'dias')) return PADRAO_DO_PARADO;
  return {};
};

const funis = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.GATILHO_DO_CARD.TODOS_OS_FUNIS') },
  ...(props.escolhas.funis || []),
]);
// As unidades do "quanto tempo antes" (as mesmas do esperar).
const UNIDADES = ['minutos', 'horas', 'dias'].map(valor => ({
  valor,
  frase: `AUTOMACAO_LIVRE.UNIDADES.${valor.toUpperCase()}`,
}));
// G32: a página de agendamento da reunião ("a reunião da renovação").
const paginas = computed(() => [
  {
    value: '',
    label: t('AUTOMACAO_LIVRE.GATILHO_DE_REUNIAO.QUALQUER_PAGINA'),
  },
  ...(props.escolhas.paginas || []),
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

// G60 (decisão 10): a página fixa do link da agenda quando ninguém atende.
// Vale onde há conversa, card ou contato; só aparece para quem lê as páginas
// (a lista vem vazia para quem não lê).
const ALVOS_DA_AGENDA = ['Conversation', 'Crm::Card', 'Contact'];
const temAgenda = tipo => ALVOS_DA_AGENDA.includes(entradaDo(tipo)?.alvo);
const pedeAgendaDeReserva = computed(
  () =>
    temAgenda(props.modelValue?.tipo) &&
    ((props.escolhas.paginas || []).length > 0 ||
      Boolean(props.modelValue?.agenda_de_reserva))
);
const paginasDeReserva = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.AGENDA_DE_RESERVA.NENHUMA') },
  ...(props.escolhas.paginas || []),
]);

// Trocar o tipo apaga o que o anterior pedia (etapa, funil), mas mantém os
// filtros: o painel mostra o que entra e o que sai deles. A caixa da conversa
// nova fica enquanto o novo gatilho também pode não ter conversa; a página de
// reserva, enquanto ele tem conversa, card ou contato.
const trocarTipo = tipo => {
  const {
    filtros,
    conversa_nova: conversaNova,
    agenda_de_reserva: agendaDeReserva,
  } = props.modelValue || {};
  const novo = {
    tipo,
    ...padraoDo(tipo),
    ...(conversaNova && podeNaoTerConversa(tipo)
      ? { conversa_nova: conversaNova }
      : {}),
    ...(agendaDeReserva && temAgenda(tipo)
      ? { agenda_de_reserva: agendaDeReserva }
      : {}),
  };
  emit('update:modelValue', filtros ? { ...novo, filtros } : novo);
};
// Trocar a frequência troca o dia que ela pede: segunda no semanal, dia 1 no
// mensal; o diário não pede dia, e o "uma vez" espera a pessoa escolher a data.
const DIA_PADRAO = { semanal: { dia_da_semana: 1 }, mensal: { dia_do_mes: 1 } };
const trocarFrequencia = frequencia => {
  const {
    dia_da_semana: _semana,
    dia_do_mes: _mes,
    data: _data,
    ...resto
  } = props.modelValue || {};
  emit('update:modelValue', {
    ...resto,
    frequencia,
    ...DIA_PADRAO[frequencia],
  });
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
      <span
        v-if="parametro.peca !== 'antes'"
        class="text-sm font-medium text-n-slate-12"
      >
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
      <LivreDuracao
        v-else-if="parametro.peca === 'antes'"
        data-antes
        :rotulo="$t(parametro.frase)"
        :model-value="modelValue?.[parametro.nome]"
        :unidades="UNIDADES"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <ChoiceSelect
        v-else-if="parametro.peca === 'frequencia'"
        :model-value="modelValue?.frequencia ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="frequencias"
        @update:model-value="trocarFrequencia"
      />
      <ChoiceSelect
        v-else-if="parametro.peca === 'dia_da_semana'"
        :model-value="modelValue?.dia_da_semana ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="diasDaSemana"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <ChoiceSelect
        v-else-if="parametro.peca === 'dia_do_mes'"
        :model-value="modelValue?.dia_do_mes ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="diasDoMes"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <Input
        v-else-if="parametro.peca === 'data'"
        :model-value="modelValue?.data ?? ''"
        type="date"
        class="w-44"
        :aria-label="$t(parametro.frase)"
        data-gatilho-data
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <LivreSelecao
        v-else-if="parametro.peca === 'selecao'"
        :model-value="modelValue?.selecao || {}"
        :alvo="entrada?.alvo"
        :escolhas="escolhas"
        :opcoes="opcoes"
        @update:model-value="valor => mudar(parametro.nome, valor)"
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
      <ChoiceSelect
        v-else-if="parametro.peca === 'repete'"
        :model-value="modelValue?.[parametro.nome] || 'uma_vez'"
        :aria-label="$t(parametro.frase)"
        :options="repete"
        @update:model-value="
          valor => mudar(parametro.nome, valor === 'uma_vez' ? '' : valor)
        "
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
        v-else-if="parametro.peca === 'pagina'"
        data-pagina
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :options="paginas"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
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

    <div
      v-if="pedeAgendaDeReserva"
      class="flex flex-col gap-1.5"
      data-parametro="agenda_de_reserva"
    >
      <label :for="idAgenda" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.AGENDA_DE_RESERVA.TITULO') }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.agenda_de_reserva?.pagina_id ?? ''"
        :trigger-id="idAgenda"
        :aria-label="$t('AUTOMACAO_LIVRE.AGENDA_DE_RESERVA.TITULO')"
        :options="paginasDeReserva"
        @update:model-value="
          valor =>
            mudar(
              'agenda_de_reserva',
              valor === '' ? null : { pagina_id: valor }
            )
        "
      />
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.AGENDA_DE_RESERVA.AJUDA') }}
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
