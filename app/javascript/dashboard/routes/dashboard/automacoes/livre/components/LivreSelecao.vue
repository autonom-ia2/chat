<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2635 (G7) — a seleção do gatilho recorrente: quais cards ou contatos ele
// pega. Lista fechada, igual à do servidor. Card: funil, etapa, situação,
// responsável e "fechado entre N e M dias atrás". Contato: com a etiqueta, sem
// a etiqueta e um campo personalizado igual a um valor. Condição em branco não
// vai na receita; sem nenhuma, o servidor não salva (pegaria a conta inteira).
const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  alvo: { type: String, default: '' },
  // { funis, etapas } (useEscolhasDosGatilhos)
  escolhas: { type: Object, default: () => ({}) },
  // { pessoa, etiquetaPorNome, atributoDoContato } (useOpcoesDaConta)
  opcoes: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const S = 'AUTOMACAO_LIVRE.SELECAO';

const doCard = computed(() => props.alvo === 'Crm::Card');
const qualquer = { value: '', label: t(`${S}.QUALQUER`) };
const comQualquer = lista => [qualquer, ...(lista || [])];

const SITUACOES = ['aberto', 'ganho', 'perdido'];
const situacoes = computed(() =>
  comQualquer(
    SITUACOES.map(valor => ({
      value: valor,
      label: t(`${S}.SITUACOES.${valor.toUpperCase()}`),
    }))
  )
);

const mudar = (nome, valor) => {
  const { [nome]: _antes, ...resto } = props.modelValue || {};
  emit(
    'update:modelValue',
    valor === '' || valor === null || valor === undefined
      ? resto
      : { ...resto, [nome]: valor }
  );
};

// "Fechado entre": os dois números juntos. O rascunho guarda o que já foi
// digitado enquanto falta a outra ponta; a receita só recebe a faixa inteira, e
// apagar uma ponta de uma faixa que estava inteira tira a condição.
const MAXIMO_DE_DIAS = 3650;
const lerDias = texto => {
  if (texto === '') return null;
  const dias = Math.trunc(Number(texto));
  return Number.isFinite(dias)
    ? Math.min(Math.max(dias, 0), MAXIMO_DE_DIAS)
    : 0;
};
const inteira = pontas =>
  Number.isInteger(pontas.de) && Number.isInteger(pontas.ate);
const faixa = computed(() => props.modelValue?.fechado_entre_dias || {});
const rascunho = ref({ ...faixa.value });
watch(faixa, nova => {
  if (inteira(nova)) rascunho.value = { ...nova };
});
const mudarFaixa = (ponta, texto) => {
  rascunho.value = { ...rascunho.value, [ponta]: lerDias(texto) };
  if (inteira(rascunho.value)) {
    mudar('fechado_entre_dias', rascunho.value);
  } else if (inteira(faixa.value)) {
    mudar('fechado_entre_dias', null);
  }
};
const textoDaFaixa = ponta => {
  const valor = rascunho.value[ponta];
  return Number.isInteger(valor) ? String(valor) : '';
};

// O campo do contato e o valor andam juntos: sem o campo, não há condição.
const atributo = computed(() => props.modelValue?.atributo || {});
const mudarAtributo = (parte, valor) => {
  const novo = { ...atributo.value, [parte]: valor };
  mudar(
    'atributo',
    novo.chave ? { chave: novo.chave, valor: novo.valor || '' } : null
  );
};
</script>

<template>
  <div class="flex flex-col gap-3 ps-3 border-s-2 border-n-weak" data-selecao>
    <p class="mb-0 text-sm text-n-slate-11">
      {{ $t(doCard ? `${S}.DICA_CARD` : `${S}.DICA_CONTATO`) }}
    </p>

    <template v-if="doCard">
      <div class="flex flex-col gap-1.5" data-condicao="funil_id">
        <span class="text-sm text-n-slate-12">{{ $t(`${S}.FUNIL`) }}</span>
        <ChoiceSelect
          :model-value="modelValue.funil_id ?? ''"
          :aria-label="$t(`${S}.FUNIL`)"
          :options="comQualquer(escolhas.funis)"
          @update:model-value="valor => mudar('funil_id', valor)"
        />
      </div>
      <div class="flex flex-col gap-1.5" data-condicao="etapa_id">
        <span class="text-sm text-n-slate-12">{{ $t(`${S}.ETAPA`) }}</span>
        <ChoiceSelect
          :model-value="modelValue.etapa_id ?? ''"
          :aria-label="$t(`${S}.ETAPA`)"
          :placeholder="$t(`${S}.QUALQUER`)"
          :groups="escolhas.etapas || []"
          @update:model-value="valor => mudar('etapa_id', valor)"
        />
      </div>
      <div class="flex flex-col gap-1.5" data-condicao="situacao">
        <span class="text-sm text-n-slate-12">{{ $t(`${S}.SITUACAO`) }}</span>
        <ChoiceSelect
          :model-value="modelValue.situacao ?? ''"
          :aria-label="$t(`${S}.SITUACAO`)"
          :options="situacoes"
          @update:model-value="valor => mudar('situacao', valor)"
        />
      </div>
      <div class="flex flex-col gap-1.5" data-condicao="responsavel_id">
        <span class="text-sm text-n-slate-12">
          {{ $t(`${S}.RESPONSAVEL`) }}
        </span>
        <ChoiceSelect
          :model-value="modelValue.responsavel_id ?? ''"
          :aria-label="$t(`${S}.RESPONSAVEL`)"
          :options="comQualquer(opcoes.pessoa)"
          @update:model-value="valor => mudar('responsavel_id', valor)"
        />
      </div>
      <fieldset
        class="flex flex-col gap-1.5"
        data-condicao="fechado_entre_dias"
      >
        <legend class="mb-1.5 text-sm text-n-slate-12">
          {{ $t(`${S}.FECHADO_ENTRE`) }}
        </legend>
        <div class="flex flex-wrap items-center gap-2">
          <Input
            :model-value="textoDaFaixa('de')"
            type="number"
            min="0"
            :max="String(MAXIMO_DE_DIAS)"
            class="w-24"
            :aria-label="$t(`${S}.FECHADO_DE`)"
            @update:model-value="valor => mudarFaixa('de', valor)"
          />
          <span class="text-sm text-n-slate-11">{{ $t(`${S}.E`) }}</span>
          <Input
            :model-value="textoDaFaixa('ate')"
            type="number"
            min="0"
            :max="String(MAXIMO_DE_DIAS)"
            class="w-24"
            :aria-label="$t(`${S}.FECHADO_ATE`)"
            @update:model-value="valor => mudarFaixa('ate', valor)"
          />
          <span class="text-sm text-n-slate-11">
            {{ $t(`${S}.DIAS_ATRAS`) }}
          </span>
        </div>
      </fieldset>
    </template>

    <template v-else>
      <div class="flex flex-col gap-1.5" data-condicao="etiqueta">
        <span class="text-sm text-n-slate-12">{{ $t(`${S}.ETIQUETA`) }}</span>
        <ChoiceSelect
          :model-value="modelValue.etiqueta ?? ''"
          :aria-label="$t(`${S}.ETIQUETA`)"
          :options="comQualquer(opcoes.etiquetaPorNome)"
          @update:model-value="valor => mudar('etiqueta', valor)"
        />
      </div>
      <div class="flex flex-col gap-1.5" data-condicao="sem_etiqueta">
        <span class="text-sm text-n-slate-12">
          {{ $t(`${S}.SEM_ETIQUETA`) }}
        </span>
        <ChoiceSelect
          :model-value="modelValue.sem_etiqueta ?? ''"
          :aria-label="$t(`${S}.SEM_ETIQUETA`)"
          :options="comQualquer(opcoes.etiquetaPorNome)"
          @update:model-value="valor => mudar('sem_etiqueta', valor)"
        />
      </div>
      <div class="flex flex-col gap-1.5" data-condicao="atributo">
        <span class="text-sm text-n-slate-12">{{ $t(`${S}.ATRIBUTO`) }}</span>
        <div class="flex flex-wrap items-center gap-2">
          <ChoiceSelect
            :model-value="atributo.chave ?? ''"
            :aria-label="$t(`${S}.ATRIBUTO`)"
            :options="comQualquer(opcoes.atributoDoContato)"
            @update:model-value="valor => mudarAtributo('chave', valor)"
          />
          <Input
            v-if="atributo.chave"
            :model-value="atributo.valor ?? ''"
            class="w-40"
            :aria-label="$t(`${S}.VALOR`)"
            :placeholder="$t(`${S}.VALOR`)"
            @update:model-value="valor => mudarAtributo('valor', valor)"
          />
        </div>
      </div>
    </template>
  </div>
</template>
