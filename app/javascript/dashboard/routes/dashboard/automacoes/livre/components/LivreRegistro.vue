<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import { fraseDoValor } from '../frases';
import { LIGACOES, SITUACOES, USOS } from '../outroRegistro';

// G18 (#2671) — onde os passos de dentro do "em outro registro" rodam: no
// contato guardado num campo (o card do João guarda quem o indicou) ou nos
// outros cards do mesmo contato. Os cards pedem a chave de funis, como o
// gatilho de card: sem ela, a opção não aparece (o servidor recusa também).
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  // O catálogo do alvo do gatilho (`alvo`, `alvos`, `valores`).
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  // Os funis e as etapas (useEscolhasDosGatilhos).
  escolhas: { type: Object, default: () => ({}) },
  podeLerCards: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const O = 'AUTOMACAO_LIVRE.OUTRO_REGISTRO';
// Decisão 16: só o campo do card do tipo contato guarda quem é a pessoa ligada
// (a equipe escolhe o contato numa lista). Campo de número não serve: um engano
// mandaria a mensagem a outro cliente, e o servidor o recusa
// (CAMPOS_DO_CONTATO).
const MODELO_DA_BASE = { card: 'card_attribute' };
const TIPO_DO_CAMPO = 'contato';

const registro = computed(() => props.modelValue || {});
const de = computed(() => registro.value.de || null);
const opcoesDeLigacao = computed(() =>
  LIGACOES.filter(
    valor => valor !== 'cards_do_contato' || props.podeLerCards
  ).map(valor => ({
    value: valor,
    label: t(`${O}.LIGACOES.${valor.toUpperCase()}`),
  }))
);

// O id do contato fica num campo do tipo contato do card do alvo do gatilho.
// Decisão 19: na conversa, o card dela só para ler, e só com a chave de funis.
const bases = computed(() => {
  const doAlvo =
    props.catalogo.alvos?.[props.catalogo.alvo] || Object.keys(MODELO_DA_BASE);
  const semCard = props.catalogo.alvo === 'Conversation' && !props.podeLerCards;
  return doAlvo.filter(base => !(semCard && base === 'card'));
});
const opcoesDeCampo = computed(() =>
  bases.value
    .filter(base => MODELO_DA_BASE[base])
    .flatMap(base =>
      props
        .atributosDo(MODELO_DA_BASE[base])
        .filter(atributo => atributo.attribute_display_type === TIPO_DO_CAMPO)
        .map(atributo => {
          const caminho = `${base}.atributos.${atributo.attribute_key}`;
          return {
            value: caminho,
            label: fraseDoValor(caminho, props.catalogo, t),
          };
        })
    )
);
const opcoesDeUso = computed(() =>
  USOS.map(valor => ({
    value: valor,
    label: t(`${O}.USOS.${valor.toUpperCase()}`),
  }))
);
const opcoesDeSituacao = computed(() =>
  SITUACOES.map(valor => ({
    value: valor,
    label: t(`${O}.SITUACOES.${valor.toUpperCase()}`),
  }))
);
const opcoesDeFunil = computed(() => [
  { value: null, label: t(`${O}.QUALQUER_FUNIL`) },
  ...(props.escolhas.funis || []),
]);
// As etapas vêm agrupadas por funil, na mesma ordem dos funis.
const opcoesDeEtapa = computed(() => {
  const indice = (props.escolhas.funis || []).findIndex(
    funil => funil.value === registro.value.funil_id
  );
  return [
    { value: null, label: t(`${O}.QUALQUER_ETAPA`) },
    ...((props.escolhas.etapas || [])[indice]?.options || []),
  ];
});
const opcoesDoMaisRecente = computed(() => [
  { value: false, label: t(`${O}.TODOS`) },
  { value: true, label: t(`${O}.SO_O_MAIS_RECENTE`) },
]);

// O registro sai inteiro a cada troca, sem o que ficou vazio (o esquema recusa
// funil nulo ou situação vazia).
const trocar = mudanca => {
  const novo = { ...registro.value, ...mudanca };
  const limpo = Object.entries(novo).filter(
    ([, valor]) =>
      valor !== null &&
      valor !== undefined &&
      !(Array.isArray(valor) && !valor.length)
  );
  emit('update:modelValue', Object.fromEntries(limpo));
};
const trocarLigacao = valor =>
  emit(
    'update:modelValue',
    valor === 'contato_do_campo'
      ? { de: valor, usar: 'conversa' }
      : { de: valor }
  );
// Trocar o funil tira a etapa: ela era do funil anterior.
const trocarFunil = valor => trocar({ funil_id: valor, etapa_id: null });
</script>

<template>
  <fieldset class="flex flex-col gap-4" data-peca="registro_ligado">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <ChoiceSelect
      data-ligacao
      :model-value="de ?? ''"
      :aria-label="rotulo"
      :placeholder="$t(`${O}.ESCOLHA`)"
      :options="opcoesDeLigacao"
      @update:model-value="trocarLigacao"
    />

    <template v-if="de === 'contato_do_campo'">
      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${O}.CAMPO`) }}
        </span>
        <ChoiceSelect
          v-if="opcoesDeCampo.length"
          data-campo
          :model-value="registro.campo?.$valor ?? ''"
          :aria-label="$t(`${O}.CAMPO`)"
          :placeholder="$t(`${O}.ESCOLHA`)"
          :options="opcoesDeCampo"
          @update:model-value="valor => trocar({ campo: { $valor: valor } })"
        />
        <p v-else class="mb-0 text-sm text-n-slate-11" data-sem-campo>
          {{ $t(`${O}.SEM_CAMPO`) }}
        </p>
        <p class="mb-0 text-sm text-n-amber-11" data-aviso-do-campo>
          {{ $t(`${O}.AVISO_DO_CAMPO`) }}
        </p>
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${O}.USAR`) }}
        </span>
        <ChoiceSelect
          data-usar
          :model-value="registro.usar || 'conversa'"
          :aria-label="$t(`${O}.USAR`)"
          :options="opcoesDeUso"
          @update:model-value="valor => trocar({ usar: valor })"
        />
      </div>
    </template>

    <template v-if="de === 'cards_do_contato'">
      <LivreMarcar
        data-situacao
        :rotulo="$t(`${O}.SITUACAO`)"
        :opcoes="opcoesDeSituacao"
        :model-value="registro.situacao || []"
        @update:model-value="valor => trocar({ situacao: valor })"
      />
      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${O}.FUNIL`) }}
        </span>
        <ChoiceSelect
          data-funil
          :model-value="registro.funil_id ?? null"
          :aria-label="$t(`${O}.FUNIL`)"
          :options="opcoesDeFunil"
          @update:model-value="trocarFunil"
        />
      </div>
      <div v-if="registro.funil_id" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${O}.ETAPA`) }}
        </span>
        <ChoiceSelect
          data-etapa
          :model-value="registro.etapa_id ?? null"
          :aria-label="$t(`${O}.ETAPA`)"
          :options="opcoesDeEtapa"
          @update:model-value="valor => trocar({ etapa_id: valor })"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`${O}.QUANTOS`) }}
        </span>
        <ChoiceSelect
          data-mais-recente
          :model-value="Boolean(registro.mais_recente)"
          :aria-label="$t(`${O}.QUANTOS`)"
          :options="opcoesDoMaisRecente"
          @update:model-value="valor => trocar({ mais_recente: valor || null })"
        />
      </div>
    </template>

    <p v-if="de" class="mb-0 text-sm text-n-slate-11" data-explicacao>
      {{ $t(`${O}.EXPLICACAO.${de.toUpperCase()}`) }}
    </p>
  </fieldset>
</template>
