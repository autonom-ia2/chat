<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  OUTRA_SEGURADORA,
  dadosParaCorrigir,
  faltasDoFormulario,
  formularioDoSeguro,
  primeiroCampoQueFalta,
} from '../../carteira/formularioDoSeguro';
import { TIPOS_DE_SEGURO, chaveDoTipo } from '../../carteira/tiposDeSeguro';
import CampoDoSeguro from './CampoDoSeguro.vue';

// #2897 — "Corrigir o seguro": o formulário que troca o conteúdo da gaveta. O
// botão Salvar (no rodapé da gaveta) está sempre ligado: quem usa chama
// `tentarSalvar()`. Se falta algo, o aviso aparece no campo, o foco vai até ele
// e nada é enviado; se nada mudou, o aviso diz isso e o foco vai ao primeiro
// campo. Com tudo certo, emite `salvar` só com o que mudou.
const props = defineProps({
  seguro: { type: Object, required: true },
  // As seguradoras que a conta já tem (a lista da escolha).
  seguradoras: { type: Array, default: () => [] },
});
const emit = defineEmits(['salvar']);

const { t } = useI18n();
const tc = chave => t(`RELACIONAMENTOS_CARTEIRA.CORRIGIR.${chave}`);
const base = useId();
const idDe = campo => `${base}-${campo}`;
const idDoNadaMudou = `${base}-nada-mudou`;

const inicial = formularioDoSeguro(props.seguro, props.seguradoras);
const formulario = ref(inicial);
const tentou = ref(false);
const nadaMudou = ref(false);

const mudar = (campo, valor) => {
  formulario.value = { ...formulario.value, [campo]: valor };
  nadaMudou.value = false;
};

// Os avisos só aparecem depois da primeira tentativa e somem conforme a pessoa
// conserta cada campo.
const faltas = computed(() =>
  tentou.value ? faltasDoFormulario(formulario.value) : {}
);
const falta = campo =>
  faltas.value[campo] ? tc(`FALTA.${faltas.value[campo]}`) : '';

const opcoesDeTipo = computed(() =>
  TIPOS_DE_SEGURO.map(tipo => ({ value: tipo, label: t(chaveDoTipo(tipo)) }))
);
const opcoesDeSeguradora = computed(() => [
  ...props.seguradoras.map(nome => ({ value: nome, label: nome })),
  { value: OUTRA_SEGURADORA, label: tc('OUTRA') },
]);
const outraEscolhida = computed(
  () => formulario.value.seguradora === OUTRA_SEGURADORA
);

const focar = async campo => {
  await nextTick();
  document.getElementById(idDe(campo))?.focus();
};

const tentarSalvar = () => {
  tentou.value = true;
  const oQueFalta = faltasDoFormulario(formulario.value);
  const primeiro = primeiroCampoQueFalta(oQueFalta);
  if (primeiro) {
    focar(primeiro);
    return;
  }
  const dados = dadosParaCorrigir(inicial, formulario.value);
  if (!Object.keys(dados).length) {
    nadaMudou.value = true;
    focar('tipo');
    return;
  }
  emit('salvar', dados);
};

defineExpose({ tentarSalvar });

const TEXTOS = [
  { campo: 'numero', rotulo: 'NUMERO' },
  { campo: 'comeca', rotulo: 'COMECA', tipo: 'date' },
  { campo: 'termina', rotulo: 'TERMINA', tipo: 'date' },
  { campo: 'valor', rotulo: 'VALOR', modo: 'decimal' },
  { campo: 'bem', rotulo: 'BEM' },
];
</script>

<template>
  <form class="flex flex-col gap-5" novalidate @submit.prevent="tentarSalvar">
    <p
      v-if="nadaMudou"
      :id="idDoNadaMudou"
      role="alert"
      data-carteira="nada-mudou"
      class="p-3 m-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
    >
      {{ tc('FALTA.NADA_MUDOU') }}
    </p>
    <div class="flex flex-col gap-1.5">
      <label :for="idDe('tipo')" class="text-sm font-medium text-n-slate-12">
        {{ tc('TIPO') }}
      </label>
      <ChoiceSelect
        :model-value="formulario.tipo"
        :options="opcoesDeTipo"
        :trigger-id="idDe('tipo')"
        :aria-label="tc('TIPO')"
        :described-by="nadaMudou ? idDoNadaMudou : undefined"
        @update:model-value="mudar('tipo', $event)"
      />
    </div>
    <div class="flex flex-col gap-1.5">
      <label
        :for="idDe('seguradora')"
        class="text-sm font-medium text-n-slate-12"
      >
        {{ tc('SEGURADORA') }}
      </label>
      <ChoiceSelect
        :model-value="formulario.seguradora"
        :options="opcoesDeSeguradora"
        :trigger-id="idDe('seguradora')"
        :aria-label="tc('SEGURADORA')"
        @update:model-value="mudar('seguradora', $event)"
      />
    </div>
    <CampoDoSeguro
      v-if="outraEscolhida"
      :id="idDe('outraSeguradora')"
      data-campo="outraSeguradora"
      :rotulo="tc('OUTRA_SEGURADORA')"
      :falta="falta('outraSeguradora')"
      :model-value="formulario.outraSeguradora"
      @update:model-value="mudar('outraSeguradora', $event)"
    />
    <CampoDoSeguro
      v-for="item in TEXTOS"
      :id="idDe(item.campo)"
      :key="item.campo"
      :data-campo="item.campo"
      :type="item.tipo || 'text'"
      :inputmode="item.modo"
      :rotulo="tc(item.rotulo)"
      :falta="falta(item.campo)"
      :model-value="formulario[item.campo]"
      @update:model-value="mudar(item.campo, $event)"
    />
    <p class="m-0 text-sm text-n-slate-11">{{ tc('APOIO') }}</p>
  </form>
</template>
