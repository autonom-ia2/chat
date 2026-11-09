<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { basesDaResposta } from '../webhook';

// G13 (#2670) — o que guardar da resposta do outro sistema: o nome da
// informação na resposta e o campo personalizado onde ela fica. Só os lugares
// que o gatilho alcança (o catálogo do alvo já vem filtrado) e os campos que a
// conta tem.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Array, default: () => [] },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const W = 'AUTOMACAO_LIVRE.WEBHOOK';
const LIMITE = 10;

const lista = computed(() => props.modelValue || []);

const bases = computed(() => basesDaResposta(props.catalogo));

const destinos = computed(() =>
  (props.catalogo?.valores || [])
    .filter(item => bases.value.includes(item.caminho) && item.atributos)
    .flatMap(item =>
      props.atributosDo(item.atributos).map(atributo => ({
        value: `${item.caminho}.${atributo.attribute_key}`,
        label: t('AUTOMACAO_LIVRE.FRASES.ATRIBUTO', {
          base: t(item.frase),
          chave: atributo.attribute_display_name,
        }),
      }))
    )
);

const trocar = (indice, chave, valor) =>
  emit(
    'update:modelValue',
    lista.value.map((item, i) =>
      i === indice ? { ...item, [chave]: valor } : item
    )
  );
const tirar = indice =>
  emit(
    'update:modelValue',
    lista.value.filter((_item, i) => i !== indice)
  );
const novo = () =>
  emit('update:modelValue', [...lista.value, { chave: '', destino: '' }]);

const ROTULO_DO_ITEM =
  'flex flex-col gap-1 text-xs font-medium text-n-slate-11';
const CAIXA =
  'w-full px-3 py-2 text-[0.9375rem] border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="resposta_do_webhook">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${W}.GRAVAR_DICA`) }}</p>
    <p
      v-if="!destinos.length"
      class="mb-0 text-sm text-n-slate-11"
      data-sem-campo
    >
      {{ $t(`${W}.GRAVAR_SEM_CAMPO`) }}
    </p>
    <div
      v-for="(item, indice) in lista"
      :key="indice"
      data-item-gravar
      class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak"
    >
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${W}.GRAVAR_CHAVE`) }}
        <input
          maxlength="80"
          :class="CAIXA"
          :value="item.chave"
          @input="evento => trocar(indice, 'chave', evento.target.value)"
        />
      </label>
      <div :class="ROTULO_DO_ITEM">
        <span aria-hidden="true">{{ $t(`${W}.GRAVAR_DESTINO`) }}</span>
        <ChoiceSelect
          :model-value="item.destino || ''"
          :aria-label="$t(`${W}.GRAVAR_DESTINO`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="destinos"
          @update:model-value="valor => trocar(indice, 'destino', valor)"
        />
      </div>
      <Button
        :label="$t(`${W}.GRAVAR_TIRAR`)"
        icon="i-lucide-trash-2"
        ruby
        link
        class="self-start min-h-11"
        @click="tirar(indice)"
      />
    </div>
    <Button
      v-if="destinos.length && lista.length < LIMITE"
      data-novo-gravar
      :label="$t(`${W}.GRAVAR_NOVO`)"
      icon="i-lucide-plus"
      faded
      class="self-start min-h-11"
      @click="novo"
    />
  </fieldset>
</template>
