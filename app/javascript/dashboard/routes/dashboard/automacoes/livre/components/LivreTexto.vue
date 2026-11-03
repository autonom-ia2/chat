<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  comColchetes,
  opcoesDosValores,
  textoDaTela,
  textoNaTela,
} from '../texto';

// #2486 — o texto de "mensagem" e "avisar": uma caixa só, e o dado da conversa
// entra pela escolha "Pôr um dado", no ponto onde o cursor estava. A receita
// recebe os pedaços; a pessoa nunca vê {$valor}.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Array, default: () => [] },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idDado = useId();

const LIMITE = 5000;

const opcoes = computed(() =>
  opcoesDosValores(props.catalogo, props.atributosDo, t)
);

const texto = computed({
  get: () => textoNaTela(props.modelValue, opcoes.value),
  set: novo => emit('update:modelValue', textoDaTela(novo, opcoes.value)),
});

// Onde o cursor estava quando a pessoa saiu da caixa para escolher o dado.
const cursor = ref(null);
const lembrarCursor = evento => {
  cursor.value = evento.target.selectionStart;
};

const porDado = caminho => {
  const opcao = opcoes.value.find(item => item.value === caminho);
  if (!opcao) return;
  const atual = texto.value;
  const ponto = cursor.value ?? atual.length;
  const dado = comColchetes(opcao.label);
  texto.value = atual.slice(0, ponto) + dado + atual.slice(ponto);
  cursor.value = ponto + dado.length;
};
</script>

<template>
  <div class="flex flex-col gap-3" data-peca="texto">
    <TextArea
      v-model="texto"
      :label="rotulo"
      :max-length="LIMITE"
      min-height="7rem"
      auto-height
      show-character-count
      @blur="lembrarCursor"
    />
    <p class="-mt-1 mb-0 text-sm text-n-slate-11">
      {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TEXTO_DICA') }}
    </p>
    <div class="flex flex-col gap-1.5">
      <label :for="idDado" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR') }}
      </label>
      <ChoiceSelect
        model-value=""
        data-por-dado
        :trigger-id="idDado"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoes"
        @update:model-value="porDado"
      />
    </div>
  </div>
</template>
