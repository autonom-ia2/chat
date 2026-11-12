<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { fraseDaCondicao, operadoresDoValor, opcoesDoValor } from '../frases';
import { nomeDoValor, opcoesDosValores } from '../texto';

// #2414 F5 — uma condição: o que olhar, como comparar e com o quê. O que olhar
// sai do catálogo (os valores que o motor lê) e, para campo personalizado, dos
// campos que a conta tem. Condição com várias partes (todas/alguma), que só o
// Guia monta, aparece em frase e passa intacta.
const props = defineProps({
  // Sem rótulo quando o painel inteiro é a condição (o título já diz).
  rotulo: { type: String, default: '' },
  modelValue: { type: Object, default: null },
  catalogo: { type: Object, required: true },
  atributosDo: { type: Function, required: true },
  // O gatilho, quando a condição é do "Só se" dele: só aí entra o valor da
  // mensagem (#2496).
  gatilho: { type: String, default: null },
  // A condição do "esperar até": só aí entra a resposta durante a espera (G11).
  naEspera: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idCampo = useId();
const idOp = useId();
const idValor = useId();

const composta = computed(() =>
  Boolean(props.modelValue?.todas || props.modelValue?.alguma)
);

// O valor que só o Guia monta (`so_guia`) e o que a pessoa não pode ler
// (`sem_permissao`, #2597) não entram na escolha; a condição que já usa um
// deles continua mostrando o que olha.
const opcoesDeCampo = computed(() => {
  const lista = opcoesDosValores(
    props.catalogo,
    props.atributosDo,
    t,
    props.gatilho,
    props.naEspera
  );
  const campo = props.modelValue?.campo?.$valor;
  const foraDaEscolha = props.catalogo.valores?.find(
    item => (item.so_guia || item.sem_permissao) && item.caminho === campo
  );
  return foraDaEscolha
    ? [...lista, { value: campo, label: nomeDoValor(foraDaEscolha, t) }]
    : lista;
});

const operadoresDe = campo => operadoresDoValor(campo, props.catalogo);
const opcoesDeOp = computed(() =>
  operadoresDe(props.modelValue?.campo?.$valor).map(item => ({
    value: item.op,
    label: t(item.frase),
  }))
);
const operador = computed(() =>
  operadoresDe(props.modelValue?.campo?.$valor).find(
    item => item.op === props.modelValue?.op
  )
);

// "Maior" e "menor" comparam número: o texto vira número quando é um.
const NUMERICOS = ['maior', 'menor'];
const lerValor = (op, texto) =>
  NUMERICOS.includes(op) && texto !== '' && Number.isFinite(Number(texto))
    ? Number(texto)
    : texto;

// Trocar o que olhar leva o operador para um que o novo valor aceita.
const montar = ({ campo, op: pedido, valor }) => {
  const aceitos = operadoresDe(campo);
  const op = aceitos.some(item => item.op === pedido) ? pedido : aceitos[0].op;
  const condicao = { campo: { $valor: campo }, op };
  const pedeValor = aceitos.find(item => item.op === op)?.pede_valor;
  return pedeValor
    ? { ...condicao, valor: lerValor(op, valor ?? '') }
    : condicao;
};

const atual = computed(() => ({
  campo: props.modelValue?.campo?.$valor || '',
  op: props.modelValue?.op || 'igual',
  valor: props.modelValue?.valor ?? '',
}));

const opcoesDeValor = computed(() =>
  (opcoesDoValor(atual.value.campo, props.catalogo) || []).map(item => ({
    value: item.valor,
    label: t(item.frase),
  }))
);

// O valor do campo anterior não serve para o novo ("open" não é tipo de
// mensagem): trocar o que olhar começa pela 1ª opção, ou vazio.
const valorInicial = campo =>
  (opcoesDoValor(campo, props.catalogo) || [])[0]?.valor ?? '';
const mudar = (chave, novo) => {
  const valor = chave === 'campo' ? valorInicial(novo) : atual.value.valor;
  emit('update:modelValue', montar({ ...atual.value, valor, [chave]: novo }));
};
</script>

<template>
  <fieldset class="flex flex-col gap-3" data-peca="condicao">
    <legend v-if="rotulo" class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <template v-if="composta">
      <p
        class="px-4 py-3 mb-0 text-base rounded-xl bg-n-alpha-2 text-n-slate-12"
      >
        {{ fraseDaCondicao(modelValue, catalogo, t) }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.COMPOSTA') }}
      </p>
    </template>
    <template v-else>
      <div class="flex flex-col gap-1.5">
        <label :for="idCampo" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMPO') }}
        </label>
        <!-- #2754: o que olhar costuma ser longo; em 390 px quebra linha. -->
        <ChoiceSelect
          data-campo-condicao
          wrap-selected
          :model-value="atual.campo"
          :trigger-id="idCampo"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.CAMPO')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDeCampo"
          @update:model-value="novo => mudar('campo', novo)"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <label :for="idOp" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.OPERADOR') }}
        </label>
        <ChoiceSelect
          :model-value="atual.op"
          :trigger-id="idOp"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.OPERADOR')"
          :options="opcoesDeOp"
          @update:model-value="novo => mudar('op', novo)"
        />
      </div>
      <div
        v-if="operador?.pede_valor && opcoesDeValor.length"
        class="flex flex-col gap-1.5"
      >
        <label :for="idValor" class="text-sm text-n-slate-11">
          {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR') }}
        </label>
        <ChoiceSelect
          data-valor-condicao
          :model-value="atual.valor"
          :trigger-id="idValor"
          :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR')"
          :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
          :options="opcoesDeValor"
          @update:model-value="novo => mudar('valor', novo)"
        />
      </div>
      <Input
        v-else-if="operador?.pede_valor"
        data-valor-condicao
        :model-value="String(atual.valor)"
        :label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.VALOR')"
        @update:model-value="novo => mudar('valor', novo)"
      />
    </template>
  </fieldset>
</template>
