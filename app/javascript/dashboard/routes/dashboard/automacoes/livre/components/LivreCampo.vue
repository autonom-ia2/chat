<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LivreValor from './LivreValor.vue';
import { PADROES_DE_CONDICAO, TIPOS_DE_CONDICAO } from '../prototipo/catalogo';
import {
  CAIXAS,
  CAMPOS_DO_CARTAO,
  EQUIPES,
  ETAPAS,
  FUNIS,
  MODELOS_WHATSAPP,
} from '../prototipo/dados';
import { fraseDaCondicao, modeloPorId } from '../prototipo/frases';

// #2414 F0 — um campo do "Alterar", desenhado pelo tipo do campo no catálogo
// (o editor gerado da F5 terá um renderizador por nó do esquema). Escolha é
// sempre o ChoiceSelect; nunca <select>.
const props = defineProps({
  campo: { type: Object, required: true },
  modelValue: { type: [String, Number, Array, Object], default: '' },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();

const rotulo = computed(() =>
  t(`AUTOMACAO_LIVRE.CAMPOS.${props.campo.nome.toUpperCase()}`)
);
const valor = computed({
  get: () => props.modelValue,
  set: novo => emit('update:modelValue', novo),
});
const numero = computed({
  get: () => String(props.modelValue ?? ''),
  set: novo => emit('update:modelValue', Number(novo) || 0),
});

const opcoes = lista =>
  lista.map(item => ({ value: item.id, label: item.nome }));
const gruposDeEtapa = computed(() =>
  FUNIS.map(funil => ({
    label: funil.nome,
    options: opcoes(ETAPAS.filter(etapa => etapa.funil === funil.id)),
  }))
);
const ESCOLHAS = {
  modelo: () => opcoes(MODELOS_WHATSAPP),
  equipe: () => opcoes(EQUIPES),
  caixa: () => opcoes(CAIXAS),
  campo_data: () =>
    opcoes(CAMPOS_DO_CARTAO.filter(campo => campo.tipo === 'data')),
  pessoa: () =>
    ['responsavel', 'dono'].map(chave => ({
      value: chave,
      label: t(`AUTOMACAO_LIVRE.PESSOAS.${chave.toUpperCase()}`),
    })),
  resultado: () =>
    ['perdido', 'ganho'].map(chave => ({
      value: chave,
      label: t(`AUTOMACAO_LIVRE.CAMPOS.RESULTADO_${chave.toUpperCase()}`),
    })),
};
const opcoesDaEscolha = computed(() => ESCOLHAS[props.campo.tipo]?.() || []);

const camposDeTexto = CAMPOS_DO_CARTAO.filter(campo => campo.tipo === 'texto');
const marcado = campoId => (props.modelValue || []).includes(campoId);
const alternarCampo = campoId =>
  emit(
    'update:modelValue',
    marcado(campoId)
      ? props.modelValue.filter(item => item !== campoId)
      : [...(props.modelValue || []), campoId]
  );

const opcoesDeCondicao = computed(() =>
  TIPOS_DE_CONDICAO.map(item => ({
    value: item.tipo,
    label: fraseDaCondicao(
      { tipo: item.tipo, ...PADROES_DE_CONDICAO[item.tipo] },
      t
    ),
  }))
);
const subcampos = computed(
  () =>
    TIPOS_DE_CONDICAO.find(item => item.tipo === props.modelValue?.tipo)
      ?.campos || []
);
const trocarCondicao = tipo =>
  emit('update:modelValue', { tipo, ...PADROES_DE_CONDICAO[tipo] });
const trocarSubcampo = (nome, novo) =>
  emit('update:modelValue', { ...props.modelValue, [nome]: novo });
</script>

<template>
  <div class="flex flex-col gap-1.5" :data-campo="campo.nome">
    <template v-if="campo.tipo === 'etapa' || ESCOLHAS[campo.tipo]">
      <label :for="id" class="text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <ChoiceSelect
        v-model="valor"
        :trigger-id="id"
        :aria-label="rotulo"
        :options="campo.tipo === 'etapa' ? [] : opcoesDaEscolha"
        :groups="campo.tipo === 'etapa' ? gruposDeEtapa : []"
      />
      <p
        v-if="campo.tipo === 'modelo' && modeloPorId(modelValue)"
        class="self-start px-3.5 py-2.5 mt-1 mb-0 text-[0.9375rem] rounded-xl rounded-bl-sm bg-n-teal-2 text-n-slate-12"
      >
        <LivreValor :pedacos="modeloPorId(modelValue).texto" />
      </p>
    </template>

    <Input v-else-if="campo.tipo === 'texto'" v-model="valor" :label="rotulo" />

    <Input
      v-else-if="campo.tipo === 'dias' || campo.tipo === 'numero'"
      v-model="numero"
      type="number"
      min="0"
      :label="rotulo"
    />

    <fieldset v-else-if="campo.tipo === 'campos'" class="flex flex-col gap-2">
      <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </legend>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="item in camposDeTexto"
          :key="item.id"
          type="button"
          :aria-pressed="marcado(item.id)"
          class="inline-flex items-center gap-2 px-3 text-sm font-medium border rounded-xl min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            marcado(item.id)
              ? 'border-n-blue-8 bg-n-blue-3 text-n-blue-11'
              : 'border-n-weak bg-n-solid-1 text-n-slate-11'
          "
          @click="alternarCampo(item.id)"
        >
          <span
            class="size-4"
            :class="marcado(item.id) ? 'i-lucide-check' : 'i-lucide-plus'"
            aria-hidden="true"
          />
          {{ item.nome }}
        </button>
      </div>
    </fieldset>

    <div v-else-if="campo.tipo === 'mensagem'" class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <p
        class="self-start px-3.5 py-2.5 mb-0 text-[0.9375rem] rounded-xl rounded-bl-sm bg-n-teal-2 text-n-slate-12"
      >
        <LivreValor :pedacos="modelValue" />
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.CAMPOS.MENSAGEM_DICA') }}
      </p>
    </div>

    <div v-else-if="campo.tipo === 'condicao'" class="flex flex-col gap-3">
      <label :for="id" class="text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.tipo || ''"
        :trigger-id="id"
        :aria-label="rotulo"
        :options="opcoesDeCondicao"
        @update:model-value="trocarCondicao"
      />
      <LivreCampo
        v-for="sub in subcampos"
        :key="sub.nome"
        :campo="sub"
        :model-value="modelValue[sub.nome]"
        @update:model-value="novo => trocarSubcampo(sub.nome, novo)"
      />
    </div>
  </div>
</template>
