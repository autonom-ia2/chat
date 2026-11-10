<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { opcoesDosValores } from '../texto';
import { corpoDasLinhas, linhasDoCorpo, origemDoValor } from '../webhook';

// G13 (#2670) — o que vai para o outro sistema: uma linha por informação, com
// o nome que o outro sistema espera e o dado do cliente que vai nela. As linhas
// moram aqui (a que ainda não tem nome não cabe no objeto da receita) e saem
// como o corpo; linha incompleta segura o "Salvar" (corpoDasLinhas).
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const W = 'AUTOMACAO_LIVRE.WEBHOOK';
const LIMITE = 30;

const linhas = ref(linhasDoCorpo(props.modelValue));
// Outro passo aberto no mesmo painel traz outro corpo.
watch(
  () => props.modelValue,
  novo => {
    if (
      JSON.stringify(novo || {}) !==
      JSON.stringify(corpoDasLinhas(linhas.value))
    )
      linhas.value = linhasDoCorpo(novo);
  }
);

const opcoes = computed(() =>
  opcoesDosValores(props.catalogo, props.atributosDo, t)
);

const trocar = novas => {
  linhas.value = novas;
  emit('update:modelValue', corpoDasLinhas(novas));
};
const trocarNome = (indice, nome) =>
  trocar(
    linhas.value.map((linha, i) => (i === indice ? { ...linha, nome } : linha))
  );
const trocarValor = (indice, caminho) =>
  trocar(
    linhas.value.map((linha, i) =>
      i === indice ? { ...linha, valor: { $valor: caminho } } : linha
    )
  );
const trocarTexto = (indice, texto) =>
  trocar(
    linhas.value.map((linha, i) =>
      i === indice ? { ...linha, valor: texto } : linha
    )
  );
// Trocar a origem zera o valor: dado começa sem escolha, texto começa vazio.
const trocarOrigem = (indice, origem) =>
  trocar(
    linhas.value.map((linha, i) =>
      i === indice
        ? { ...linha, valor: origem === 'texto' ? '' : { $valor: '' } }
        : linha
    )
  );
const ORIGENS = computed(() => [
  { value: 'dado', label: t(`${W}.CORPO_ORIGEM_DADO`) },
  { value: 'texto', label: t(`${W}.CORPO_ORIGEM_TEXTO`) },
]);

const tirar = indice =>
  trocar(linhas.value.filter((_linha, i) => i !== indice));
const nova = () => trocar([...linhas.value, { nome: '', valor: null }]);

const repetido = indice => {
  const nome = linhas.value[indice].nome.trim();
  return (
    Boolean(nome) &&
    linhas.value.findIndex(l => l.nome.trim() === nome) !== indice
  );
};

const ROTULO_DO_ITEM =
  'flex flex-col gap-1 text-xs font-medium text-n-slate-11';
const CAIXA =
  'w-full px-3 py-2 text-[0.9375rem] border rounded-xl min-h-11 border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="corpo_do_webhook">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <p class="mb-0 text-sm text-n-slate-11">{{ $t(`${W}.CORPO_DICA`) }}</p>
    <div
      v-for="(linha, indice) in linhas"
      :key="indice"
      data-linha-do-corpo
      class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak"
    >
      <label :class="ROTULO_DO_ITEM">
        {{ $t(`${W}.CORPO_NOME`) }}
        <input
          maxlength="80"
          :class="CAIXA"
          :value="linha.nome"
          @input="evento => trocarNome(indice, evento.target.value)"
        />
      </label>
      <p
        v-if="repetido(indice)"
        class="mb-0 text-sm text-n-ruby-11"
        data-nome-repetido
      >
        {{ $t(`${W}.CORPO_NOME_REPETIDO`) }}
      </p>
      <p
        v-if="origemDoValor(linha.valor) === 'outro'"
        class="mb-0 text-sm text-n-slate-11"
        data-linha-do-guia
      >
        {{ $t(`${W}.CORPO_OUTRO`) }}
      </p>
      <div v-else :class="ROTULO_DO_ITEM">
        <span aria-hidden="true">{{ $t(`${W}.CORPO_ORIGEM`) }}</span>
        <ChoiceSelect
          data-origem
          :model-value="origemDoValor(linha.valor) || 'dado'"
          :aria-label="$t(`${W}.CORPO_ORIGEM`)"
          :options="ORIGENS"
          @update:model-value="origem => trocarOrigem(indice, origem)"
        />
      </div>
      <label
        v-if="origemDoValor(linha.valor) === 'texto'"
        :class="ROTULO_DO_ITEM"
      >
        {{ $t(`${W}.CORPO_TEXTO`) }}
        <input
          data-texto-fixo
          maxlength="500"
          :class="CAIXA"
          :value="String(linha.valor)"
          @input="evento => trocarTexto(indice, evento.target.value)"
        />
      </label>
      <div
        v-if="[null, 'dado'].includes(origemDoValor(linha.valor))"
        :class="ROTULO_DO_ITEM"
      >
        <span aria-hidden="true">{{ $t(`${W}.CORPO_VALOR`) }}</span>
        <ChoiceSelect
          :model-value="linha.valor?.$valor || ''"
          :aria-label="$t(`${W}.CORPO_VALOR`)"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoes"
          @update:model-value="caminho => trocarValor(indice, caminho)"
        />
      </div>
      <Button
        :label="$t(`${W}.CORPO_TIRAR`)"
        icon="i-lucide-trash-2"
        ruby
        link
        class="self-start min-h-11"
        @click="tirar(indice)"
      />
    </div>
    <Button
      v-if="linhas.length < LIMITE"
      data-nova-linha
      :label="$t(`${W}.CORPO_NOVA`)"
      icon="i-lucide-plus"
      faded
      class="self-start min-h-11"
      @click="nova"
    />
  </fieldset>
</template>
