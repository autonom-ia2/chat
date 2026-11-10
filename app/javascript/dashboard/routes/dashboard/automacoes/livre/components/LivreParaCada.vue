<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import LivreEtapa from './LivreEtapa.vue';
import LivreIaCampo from './LivreIaCampo.vue';
import { CHAVE_DO_TELEFONE, MAXIMO_DE_ITENS, maximoServe } from '../paraCada';

// #2414 G24 (#2771) — o passo "para cada item" inteiro: o que a IA lê, o que é
// cada item da lista, os campos de cada um (os do "extrair", sem o "onde
// gravar"), a etapa do card e o máximo de itens. O servidor confere tudo de
// novo ao salvar, inclusive a etapa e a permissão de importar contatos.
const props = defineProps({
  modelValue: { type: Object, required: true },
  // [{ label: funil, options: [{ value: id, label: etapa }] }]
  etapas: { type: Array, default: () => [] },
  opcoes: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const P = 'AUTOMACAO_LIVRE.PARA_CADA';
const CAMPOS = 'AUTOMACAO_LIVRE.CAMPOS';

const passo = computed(() => props.modelValue);
const mudar = mudanca =>
  emit('update:modelValue', { ...passo.value, ...mudanca });

const temTelefone = computed(() =>
  (passo.value.campos || []).some(campo => campo.chave === CHAVE_DO_TELEFONE)
);
// O telefone é por onde o contato é achado; sem ele, cada item vira um contato
// só com o nome.
const porTelefone = () =>
  mudar({
    campos: [
      ...(passo.value.campos || []),
      { chave: CHAVE_DO_TELEFONE, descricao: '' },
    ],
  });

const maximoFora = computed(
  () => passo.value.maximo != null && !maximoServe(passo.value.maximo)
);
const mudarMaximo = texto => {
  const numero = Number(texto);
  mudar({ maximo: texto === '' || Number.isNaN(numero) ? null : numero });
};
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="para_cada">
    <LivreIaCampo
      :campo="{ peca: 'leituras', rotulo: `${CAMPOS}.LE` }"
      :model-value="passo.le"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="le => mudar({ le })"
    />

    <Input
      data-para-cada-descricao
      :model-value="passo.descricao || ''"
      :label="$t(`${CAMPOS}.DESCRICAO`)"
      :message="$t(`${P}.DESCRICAO_DICA`)"
      @update:model-value="descricao => mudar({ descricao })"
    />

    <LivreIaCampo
      :campo="{ peca: 'campos_para_cada', rotulo: `${CAMPOS}.CAMPOS` }"
      :model-value="passo.campos"
      :opcoes="opcoes"
      :atributos-do="atributosDo"
      @update:model-value="campos => mudar({ campos })"
    />

    <div v-if="!temTelefone" class="flex flex-col gap-1.5">
      <p
        data-para-cada-sem-telefone
        role="status"
        class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
      >
        {{ $t(`${P}.SEM_TELEFONE`) }}
      </p>
      <Button
        data-para-cada-por-telefone
        :label="$t(`${P}.POR_TELEFONE`)"
        icon="i-lucide-phone"
        faded
        class="self-start min-h-11"
        @click="porTelefone"
      />
    </div>

    <LivreEtapa
      :rotulo="$t(`${CAMPOS}.ETAPA_ID`)"
      :model-value="passo.etapa_id"
      :grupos="etapas"
      @update:model-value="id => mudar({ etapa_id: id })"
    />

    <Input
      data-para-cada-maximo
      type="number"
      :model-value="passo.maximo ?? ''"
      :label="$t(`${CAMPOS}.MAXIMO`)"
      :message="
        $t(maximoFora ? `${P}.MAXIMO_FORA` : `${P}.MAXIMO_DICA`, {
          maximo: MAXIMO_DE_ITENS,
        })
      "
      :message-type="maximoFora ? 'error' : 'info'"
      @update:model-value="mudarMaximo"
    />

    <p class="mb-0 text-sm text-n-slate-11" data-para-cada-contato-dica>
      {{ $t(`${P}.CONTATO_DICA`) }}
    </p>
  </div>
</template>
