<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  comApagados,
  comColchetes,
  opcoesDosValores,
  textoDaTela,
  textoNaTela,
  valoresSemPermissao,
} from '../texto';
import { fraseDoValor } from '../frases';

// #2486 — o texto de "mensagem" e "avisar": uma caixa só, e o dado da conversa
// entra pela escolha "Pôr um dado", no ponto onde o cursor estava. A receita
// recebe os pedaços; a pessoa nunca vê {$valor}. O assunto do e-mail (G2) é uma
// linha curta; com mais de uma caixa no passo, o "Pôr um dado" diz em qual entra.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Array, default: () => [] },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  umaLinha: { type: Boolean, default: false },
  rotuloDoDado: { type: String, default: '' },
  // #2414 G16 — o campo de uma linha de uma ação (nome, descrição).
  curto: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idDado = useId();

const LIMITE = 5000;
const LIMITE_DA_LINHA = 150;
const rotuloPorDado = computed(
  () => props.rotuloDoDado || t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_VALOR')
);

// O dado de um campo que a conta apagou fica no texto, marcado; não volta
// para a lista do "Pôr um dado". O valor que a pessoa não pode ler (#2597)
// também fica fora da lista, mas o texto que já o usa mostra o nome dele.
const daConta = computed(() =>
  opcoesDosValores(props.catalogo, props.atributosDo, t)
);
const opcoes = computed(() =>
  comApagados(
    props.modelValue,
    [
      ...daConta.value,
      ...valoresSemPermissao(props.catalogo, t, props.modelValue || []),
    ],
    caminho =>
      t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DADO_APAGADO', {
        dado: fraseDoValor(caminho, props.catalogo, t),
      })
  )
);
const temApagado = computed(() =>
  opcoes.value.some(
    item =>
      item.apagado &&
      (props.modelValue || []).some(parte => parte?.$valor === item.value)
  )
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
    <Input
      v-if="umaLinha"
      v-model="texto"
      :label="rotulo"
      :maxlength="LIMITE_DA_LINHA"
      :message="`${texto.length} / ${LIMITE_DA_LINHA}`"
      @blur="lembrarCursor"
    />
    <TextArea
      v-else
      v-model="texto"
      :label="rotulo"
      :max-length="LIMITE"
      :min-height="curto ? '3rem' : '7rem'"
      auto-height
      show-character-count
      @blur="lembrarCursor"
    />
    <p class="-mt-1 mb-0 text-sm text-n-slate-11">
      {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TEXTO_DICA') }}
    </p>
    <p
      v-if="temApagado"
      data-dado-apagado
      role="status"
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TEM_DADO_APAGADO') }}
    </p>
    <div class="flex flex-col gap-1.5">
      <label :for="idDado" class="text-sm font-medium text-n-slate-12">
        {{ rotuloPorDado }}
      </label>
      <ChoiceSelect
        model-value=""
        data-por-dado
        :trigger-id="idDado"
        :aria-label="rotuloPorDado"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="daConta"
        @update:model-value="porDado"
      />
    </div>
  </div>
</template>
