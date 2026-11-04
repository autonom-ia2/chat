<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import LivreEmpresa from './LivreEmpresa.vue';
import { fraseDoValor } from '../frases';

// #2414 F5 — um campo de uma ação, desenhado pela peça que o catálogo deu a ele.
// Escolha de uma é sempre o ChoiceSelect, nunca <select>; de várias, botões que
// marcam. Valor que vem da conversa ({ $valor }), que só o Guia monta, aparece
// em frase e passa intacto.
const props = defineProps({
  campo: { type: Object, required: true },
  modelValue: { type: [String, Number, Boolean, Array, Object], default: null },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributos: { type: Array, default: () => [] },
  bloqueadas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();

const rotulo = computed(() => t(props.campo.rotulo));
const peca = computed(() => props.campo.peca);
const daConversa = computed(() => Boolean(props.modelValue?.$valor));
const mudar = novo => emit('update:modelValue', novo);

const UMA = { pessoa: 'pessoa', time: 'time', caixa: 'caixa' };
const opcoesDeUma = computed(() => {
  if (peca.value === 'escolha')
    return props.campo.opcoes.map(item => ({
      value: item.valor,
      label: t(item.frase),
    }));
  return props.opcoes[UMA[peca.value]] || [];
});
const ehUma = computed(() => peca.value === 'escolha' || UMA[peca.value]);

const opcoesDeVarias = computed(() =>
  peca.value === 'etiquetas'
    ? props.opcoes.etiquetaPorNome
    : props.opcoes.pessoa
);

// A data vai em segundos (é o que a conversa espera em "adiar até").
const SEGUNDO = 1000;
const dataHora = computed({
  get: () => {
    if (!props.modelValue) return '';
    const data = new Date(Number(props.modelValue) * SEGUNDO);
    const local = new Date(
      data.getTime() - data.getTimezoneOffset() * 60 * SEGUNDO
    );
    return local.toISOString().slice(0, 16);
  },
  set: texto =>
    mudar(texto ? Math.floor(new Date(texto).getTime() / SEGUNDO) : null),
});

const linhas = computed({
  get: () => (props.modelValue || []).join('\n'),
  set: texto =>
    mudar(
      texto
        .split('\n')
        .map(linha => linha.trim())
        .filter(Boolean)
    ),
});

const valorDoAtributo = chave => props.modelValue?.[chave];
const mudarAtributo = (chave, novo) => {
  const { [chave]: _antes, ...resto } = props.modelValue || {};
  mudar(novo === '' || novo === null ? resto : { ...resto, [chave]: novo });
};
const opcoesDoAtributo = atributo =>
  (atributo.attribute_values || []).map(valor => ({
    value: valor,
    label: valor,
  }));
</script>

<template>
  <div class="flex flex-col gap-1.5" :data-campo="campo.nome">
    <template v-if="daConversa">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <p
        class="px-4 py-3 mb-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{
          $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DA_CONVERSA', {
            valor: fraseDoValor(modelValue.$valor, catalogo, t),
          })
        }}
      </p>
    </template>

    <template v-else-if="ehUma">
      <label :for="id" class="text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <ChoiceSelect
        :model-value="modelValue ?? ''"
        :trigger-id="id"
        :aria-label="rotulo"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoesDeUma"
        @update:model-value="mudar"
      />
    </template>

    <LivreMarcar
      v-else-if="peca === 'etiquetas' || peca === 'pessoas'"
      :rotulo="rotulo"
      :opcoes="opcoesDeVarias"
      :model-value="modelValue || []"
      :bloqueadas="bloqueadas"
      @update:model-value="mudar"
    />

    <LivreEmpresa
      v-else-if="peca === 'empresa'"
      :rotulo="rotulo"
      :model-value="modelValue"
      @update:model-value="mudar"
    />

    <label
      v-else-if="peca === 'sim_nao'"
      class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
    >
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <Switch
        class="mx-1.5 scale-[1.4]"
        :model-value="Boolean(modelValue)"
        :aria-label="rotulo"
        @update:model-value="mudar"
      />
    </label>

    <template v-else-if="peca === 'cor'">
      <label :for="id" class="text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <input
        :id="id"
        type="color"
        :value="modelValue || campo.padrao || '#1f93ff'"
        class="w-16 p-1 border rounded-xl h-11 border-n-weak bg-n-solid-1"
        @input="evento => mudar(evento.target.value)"
      />
    </template>

    <Input
      v-else-if="peca === 'data_hora'"
      v-model="dataHora"
      type="datetime-local"
      :label="rotulo"
    />

    <TextArea
      v-else-if="peca === 'lista_de_textos'"
      v-model="linhas"
      :label="rotulo"
      :max-length="5000"
      :message="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.UMA_POR_LINHA')"
    />

    <fieldset
      v-else-if="peca.startsWith('atributos_')"
      class="flex flex-col gap-3"
    >
      <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </legend>
      <template v-for="atributo in atributos" :key="atributo.attribute_key">
        <ChoiceSelect
          v-if="atributo.attribute_display_type === 'list'"
          :model-value="valorDoAtributo(atributo.attribute_key) ?? ''"
          :aria-label="atributo.attribute_display_name"
          :placeholder="atributo.attribute_display_name"
          :options="opcoesDoAtributo(atributo)"
          @update:model-value="
            novo => mudarAtributo(atributo.attribute_key, novo)
          "
        />
        <Input
          v-else
          :model-value="String(valorDoAtributo(atributo.attribute_key) ?? '')"
          :label="atributo.attribute_display_name"
          @update:model-value="
            novo => mudarAtributo(atributo.attribute_key, novo)
          "
        />
      </template>
    </fieldset>

    <Input
      v-else
      :model-value="String(modelValue ?? '')"
      :label="rotulo"
      @update:model-value="mudar"
    />
  </div>
</template>
