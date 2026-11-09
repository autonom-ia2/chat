<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import LivreDestinatarios from './LivreDestinatarios.vue';
import { chaveDoNome, problemaDoCaminho } from '../ia';

// #2500 F7 — os campos dos passos de IA no "Alterar": o que a IA lê, a pergunta
// e os caminhos do "decidir", o que o "extrair" procura e onde grava, a
// instrução e o destino do "escrever" e do "resumir". Os passos de dentro de
// cada caminho ficam na lista do Confira, como os galhos do "se".
const props = defineProps({
  campo: { type: Object, required: true },
  modelValue: { type: [Array, Object, String, Number, Boolean], default: null },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();
const I = 'AUTOMACAO_LIVRE.IA';

const LEITURAS = [
  'mensagens_recentes',
  'mensagens_com_respostas',
  'ultima_mensagem',
  'conversa',
  'contato',
  'empresa',
  // #2414 G20: a foto, o PDF e o áudio que o cliente mandou.
  'anexos',
  // #2679: o card e as notas internas da conversa.
  'card',
  'notas',
];
const opcoesDeLeitura = computed(() =>
  LEITURAS.map(valor => ({
    value: valor,
    label: t(`${I}.LEITURAS.${valor.toUpperCase()}`),
  }))
);

// Onde o "extrair" grava: o nome do contato e da empresa, e os campos
// personalizados que a conta tem no contato e na conversa.
const destinosDeGravar = computed(() => [
  { value: 'contato.nome', label: t(`${I}.DESTINO_GRAVAR.CONTATO_NOME`) },
  { value: 'empresa.nome', label: t(`${I}.DESTINO_GRAVAR.EMPRESA_NOME`) },
  ...props.atributosDo('contact_attribute').map(atributo => ({
    value: `contato.atributos.${atributo.attribute_key}`,
    label: t(`${I}.DESTINO_GRAVAR.CONTATO_ATRIBUTO`, {
      nome: atributo.attribute_display_name,
    }),
  })),
  ...props.atributosDo('conversation_attribute').map(atributo => ({
    value: `conversa.atributos.${atributo.attribute_key}`,
    label: t(`${I}.DESTINO_GRAVAR.CONVERSA_ATRIBUTO`, {
      nome: atributo.attribute_display_name,
    }),
  })),
]);

// Computados: o pt_BR chega depois do setup, e uma lista montada antes fica em inglês.
const opcoesDeDestino = valores =>
  computed(() =>
    valores.map(valor => ({
      value: valor,
      label: t(`${I}.DESTINOS.${valor.toUpperCase()}`),
    }))
  );
const opcoesDoEscrever = opcoesDeDestino(['mensagem', 'sugestao', 'guardar']);
const opcoesDoResumir = opcoesDeDestino(['nota', 'avisar']);

const lista = computed(() =>
  Array.isArray(props.modelValue) ? props.modelValue : []
);
const trocarItem = (indice, chave, valor) =>
  emit(
    'update:modelValue',
    lista.value.map((item, i) =>
      i === indice ? { ...item, [chave]: valor } : item
    )
  );
const trocarNomeDoCaminho = (indice, nome) =>
  emit(
    'update:modelValue',
    lista.value.map((item, i) =>
      i === indice ? { ...item, nome, chave: chaveDoNome(nome) } : item
    )
  );
const tirarItem = indice =>
  emit(
    'update:modelValue',
    lista.value.filter((_item, i) => i !== indice)
  );
const novoCaminho = () =>
  emit('update:modelValue', [
    ...lista.value,
    { chave: '', descricao: '', passos: [] },
  ]);
const novoCampo = () =>
  emit('update:modelValue', [
    ...lista.value,
    { chave: '', descricao: '', destino: '' },
  ]);

const destinoDoResumir = computed(() =>
  props.modelValue && typeof props.modelValue === 'object'
    ? 'avisar'
    : props.modelValue || ''
);
const trocarDestinoDoResumir = valor =>
  emit(
    'update:modelValue',
    valor === 'avisar' ? { avisar: { responsavel: true } } : valor
  );

// Cada caixa do caminho e do dado tem o rótulo à vista: preenchida, o placeholder some.
const ROTULO_DO_ITEM =
  'flex flex-col gap-1 text-xs font-medium text-n-slate-11';
const ROTULO_DA_CAIXA =
  'w-full px-3 py-2 text-[0.9375rem] border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <LivreMarcar
    v-if="campo.peca === 'leituras'"
    data-peca="leituras"
    :rotulo="$t(campo.rotulo)"
    :opcoes="opcoesDeLeitura"
    :model-value="modelValue || ['mensagens_recentes']"
    @update:model-value="valor => emit('update:modelValue', valor)"
  />

  <div
    v-else-if="campo.peca === 'instrucao'"
    class="flex flex-col gap-1.5"
    data-peca="instrucao"
  >
    <label :for="id" class="text-sm font-medium text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </label>
    <textarea
      :id="id"
      rows="4"
      maxlength="2000"
      :class="ROTULO_DA_CAIXA"
      :value="modelValue || ''"
      @input="evento => emit('update:modelValue', evento.target.value || null)"
    />
  </div>

  <fieldset
    v-else-if="campo.peca === 'caminhos'"
    class="flex flex-col gap-3"
    data-peca="caminhos"
  >
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </legend>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${I}.CAMINHO.DICA`) }}</p>
    <div
      v-for="(caminho, indice) in lista"
      :key="indice"
      data-caminho
      class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak"
    >
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${I}.CAMINHO.NOME`) }}
        <input
          maxlength="40"
          :class="ROTULO_DA_CAIXA"
          :value="caminho.nome"
          @input="evento => trocarNomeDoCaminho(indice, evento.target.value)"
        />
      </label>
      <p
        v-if="problemaDoCaminho(lista, indice)"
        data-problema-do-caminho
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ $t(`${I}.CAMINHO.${problemaDoCaminho(lista, indice)}`) }}
      </p>
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${I}.CAMINHO.QUANDO`) }}
        <input
          maxlength="300"
          :class="ROTULO_DA_CAIXA"
          :value="caminho.descricao"
          @input="
            evento => trocarItem(indice, 'descricao', evento.target.value)
          "
        />
      </label>
      <Button
        v-if="lista.length > 2"
        :label="$t(`${I}.CAMINHO.TIRAR`)"
        icon="i-lucide-trash-2"
        ruby
        link
        class="self-start min-h-11"
        @click="tirarItem(indice)"
      />
    </div>
    <Button
      v-if="lista.length < 8"
      data-novo-caminho
      :label="$t(`${I}.CAMINHO.NOVO`)"
      icon="i-lucide-plus"
      faded
      class="self-start min-h-11"
      @click="novoCaminho"
    />
  </fieldset>

  <fieldset
    v-else-if="campo.peca === 'campos_extrair'"
    class="flex flex-col gap-3"
    data-peca="campos_extrair"
  >
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </legend>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${I}.CAMPO.DICA`) }}</p>
    <div
      v-for="(item, indice) in lista"
      :key="indice"
      data-campo-extrair
      class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak"
    >
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${I}.CAMPO.CHAVE`) }}
        <input
          maxlength="40"
          :class="ROTULO_DA_CAIXA"
          :value="item.chave"
          @input="evento => trocarItem(indice, 'chave', evento.target.value)"
        />
      </label>
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${I}.CAMPO.DESCRICAO`) }}
        <input
          maxlength="300"
          :class="ROTULO_DA_CAIXA"
          :value="item.descricao"
          @input="
            evento => trocarItem(indice, 'descricao', evento.target.value)
          "
        />
      </label>
      <div :class="ROTULO_DO_ITEM">
        <span aria-hidden="true">{{ $t(`${I}.CAMPO.DESTINO`) }}</span>
        <ChoiceSelect
          :model-value="item.destino || ''"
          :aria-label="$t(`${I}.CAMPO.DESTINO`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="destinosDeGravar"
          @update:model-value="valor => trocarItem(indice, 'destino', valor)"
        />
      </div>
      <Button
        v-if="lista.length > 1"
        :label="$t(`${I}.CAMPO.TIRAR`)"
        icon="i-lucide-trash-2"
        ruby
        link
        class="self-start min-h-11"
        @click="tirarItem(indice)"
      />
    </div>
    <Button
      v-if="lista.length < 10"
      data-novo-campo
      :label="$t(`${I}.CAMPO.NOVO`)"
      icon="i-lucide-plus"
      faded
      class="self-start min-h-11"
      @click="novoCampo"
    />
  </fieldset>

  <label
    v-else-if="campo.peca === 'sim_nao'"
    class="flex items-center justify-between gap-3 cursor-pointer min-h-11"
  >
    <span class="text-[0.9375rem] text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </span>
    <Switch
      class="mx-1.5 scale-[1.4]"
      :model-value="Boolean(modelValue)"
      :aria-label="$t(campo.rotulo)"
      @update:model-value="valor => emit('update:modelValue', valor || null)"
    />
  </label>

  <div
    v-else-if="campo.peca === 'numero'"
    class="flex flex-col gap-1.5"
    data-peca="numero"
  >
    <label :for="id" class="text-sm font-medium text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </label>
    <input
      :id="id"
      type="number"
      min="1"
      max="10"
      :class="ROTULO_DA_CAIXA"
      :value="modelValue ?? 3"
      @input="
        evento => emit('update:modelValue', Number(evento.target.value) || null)
      "
    />
  </div>

  <div
    v-else-if="campo.peca === 'destino_escrever'"
    class="flex flex-col gap-1.5"
    data-peca="destino_escrever"
  >
    <span class="text-sm font-medium text-n-slate-12">
      {{ $t(campo.rotulo) }}
    </span>
    <ChoiceSelect
      :model-value="modelValue || ''"
      :aria-label="$t(campo.rotulo)"
      :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
      :options="opcoesDoEscrever"
      @update:model-value="valor => emit('update:modelValue', valor)"
    />
  </div>

  <div
    v-else-if="campo.peca === 'destino_resumir'"
    class="flex flex-col gap-4"
    data-peca="destino_resumir"
  >
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(campo.rotulo) }}
      </span>
      <ChoiceSelect
        :model-value="destinoDoResumir"
        :aria-label="$t(campo.rotulo)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoesDoResumir"
        @update:model-value="trocarDestinoDoResumir"
      />
    </div>
    <LivreDestinatarios
      v-if="destinoDoResumir === 'avisar'"
      :rotulo="$t(`${I}.DESTINOS.AVISAR`)"
      :model-value="modelValue.avisar"
      :opcoes="opcoes"
      @update:model-value="
        valor => emit('update:modelValue', { avisar: valor })
      "
    />
  </div>
</template>
