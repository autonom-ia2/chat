<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import LivreEmpresa from './LivreEmpresa.vue';
import LivreTexto from './LivreTexto.vue';
import LivreData from './LivreData.vue';
import { fraseDoCalculado } from '../frases';
import { campoDasPartes, opcoesDosValores, partesDoCampo } from '../texto';

// #2414 F5 — um campo de uma ação, desenhado pela peça que o catálogo deu a ele.
// Escolha de uma é sempre o ChoiceSelect, nunca <select>; de várias, botões que
// marcam. O campo de texto aceita dado da conversa ("[Nome do contato]"), que
// vira `{ $texto }` (#2414 G16). O atributo do tipo data escolhe um dia certo ou
// uma data calculada (`{ $data }`, G16b). Outro valor calculado que só o Guia
// monta ({ $valor } sozinho, { $data } num campo de texto) aparece em frase e
// passa intacto.
const props = defineProps({
  campo: { type: Object, required: true },
  modelValue: { type: [String, Number, Boolean, Array, Object], default: null },
  catalogo: { type: Object, required: true },
  opcoes: { type: Object, required: true },
  atributos: { type: Array, default: () => [] },
  bloqueadas: { type: Array, default: () => [] },
  atributosDo: { type: Function, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();

const rotulo = computed(() => t(props.campo.rotulo));
const peca = computed(() => props.campo.peca);
const calculado = valor =>
  Boolean(valor?.$valor || valor?.$texto || valor?.$data);
const comoTexto = computed(
  () => peca.value === 'texto' && !props.modelValue?.$data
);
// #2594: a data do card (data prevista de fechamento) é a peça do G16b: o dia
// certo ou a data calculada; o `{ $valor }` que o Guia pôs continua em frase.
const comoData = computed(
  () =>
    peca.value === 'data' &&
    !props.modelValue?.$valor &&
    !props.modelValue?.$texto
);
const soMostra = computed(
  () => calculado(props.modelValue) && !comoTexto.value && !comoData.value
);
const mudar = novo => emit('update:modelValue', novo);
// #2702 G29 — o "Pôr" etiqueta aceita um dado: a etiqueta com o nome do anúncio.
const dadosDaEtiqueta = computed(() =>
  peca.value === 'etiquetas' && props.campo.nome === 'por'
    ? opcoesDosValores(props.catalogo, props.atributosDo, t)
    : []
);

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

// #2594: o valor de venda é digitado em reais e vai em centavos, como o card
// guarda.
const CENTAVOS = 100;
const reais = computed({
  get: () =>
    Number.isInteger(props.modelValue)
      ? String(props.modelValue / CENTAVOS)
      : '',
  set: texto => {
    const numero = Number(texto);
    mudar(
      String(texto).trim() === '' || Number.isNaN(numero)
        ? null
        : Math.round(numero * CENTAVOS)
    );
  },
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
// O atributo de texto aceita dado da conversa, como o campo de texto.
const atributoDeTexto = atributo =>
  atributo.attribute_display_type === 'text' &&
  !valorDoAtributo(atributo.attribute_key)?.$data;
// O atributo de data monta o dia certo ou a data calculada; o `{ $valor }` que o
// Guia pôs nele continua em frase.
const atributoDeData = atributo => {
  const valor = valorDoAtributo(atributo.attribute_key);
  return (
    atributo.attribute_display_type === 'date' &&
    !valor?.$valor &&
    !valor?.$texto
  );
};
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
    <!-- #2594: o valor que a pessoa não pode ver fica escondido; ela só tira. -->
    <div
      v-if="campo.sem_permissao"
      data-campo-protegido
      class="flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-n-alpha-2"
    >
      <p class="mb-0 text-base text-n-slate-12">
        {{
          $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMPO_PROTEGIDO', {
            campo: rotulo,
          })
        }}
      </p>
      <Button
        data-tirar-protegido
        :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIRAR')"
        slate
        faded
        class="min-h-11 shrink-0"
        @click="mudar(null)"
      />
    </div>

    <template v-else-if="soMostra">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <p
        data-calculado
        class="px-4 py-3 mb-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ fraseDoCalculado(modelValue, catalogo, t) }}
      </p>
    </template>

    <LivreData
      v-else-if="comoData"
      :rotulo="rotulo"
      :model-value="modelValue ?? null"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="mudar"
    />

    <Input
      v-else-if="peca === 'dinheiro'"
      v-model="reais"
      type="number"
      min="0"
      step="0.01"
      inputmode="decimal"
      :label="rotulo"
    />

    <LivreTexto
      v-else-if="comoTexto"
      curto
      :rotulo="rotulo"
      :model-value="partesDoCampo(modelValue)"
      :catalogo="catalogo"
      :atributos-do="atributosDo"
      @update:model-value="novo => mudar(campoDasPartes(novo))"
    />

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
      :dados="dadosDaEtiqueta"
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
      :aria-busy="!atributos.length && opcoes.atributosEstado === 'carregando'"
    >
      <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </legend>
      <!-- #2744: sem nenhum campo do tipo, o título não fica sozinho. "A conta
      não tem" só com a lista carregada; se ela não veio, diz que não carregou. -->
      <p
        v-if="!atributos.length && opcoes.atributosEstado === 'falhou'"
        data-atributos-falhou
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ATRIBUTOS_FALHOU') }}
      </p>
      <p
        v-else-if="!atributos.length && opcoes.atributosEstado === 'carregou'"
        data-sem-atributos
        class="mb-0 text-sm text-n-slate-11"
      >
        {{
          $t(
            `AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_ATRIBUTOS.${peca.toUpperCase()}`
          )
        }}
      </p>
      <template v-for="atributo in atributos" :key="atributo.attribute_key">
        <LivreTexto
          v-if="atributoDeTexto(atributo)"
          curto
          :rotulo="atributo.attribute_display_name"
          :model-value="partesDoCampo(valorDoAtributo(atributo.attribute_key))"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="
            novo => mudarAtributo(atributo.attribute_key, campoDasPartes(novo))
          "
        />
        <LivreData
          v-else-if="atributoDeData(atributo)"
          :rotulo="atributo.attribute_display_name"
          :model-value="valorDoAtributo(atributo.attribute_key) ?? null"
          :catalogo="catalogo"
          :atributos-do="atributosDo"
          @update:model-value="
            novo => mudarAtributo(atributo.attribute_key, novo)
          "
        />
        <p
          v-else-if="calculado(valorDoAtributo(atributo.attribute_key))"
          data-calculado
          class="px-4 py-3 mb-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
        >
          {{
            $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ATRIBUTO_CALCULADO', {
              nome: atributo.attribute_display_name,
              valor: fraseDoCalculado(
                valorDoAtributo(atributo.attribute_key),
                catalogo,
                t
              ),
            })
          }}
        </p>
        <ChoiceSelect
          v-else-if="atributo.attribute_display_type === 'list'"
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
