<script setup>
import { computed, ref } from 'vue';
import DialogoDaCasa from './DialogoDaCasa.vue';
import { useTextos } from './useTextos';

// Perda de acesso (#2308, especificação 5.F), só para o administrador: ao salvar uma alteração que tira algo de
// quem já tem a função, diz quem perde o quê antes de gravar. `perdas` são ids de FUNCOES_EQUIPE.PODE.
const props = defineProps({
  nome: { type: String, required: true },
  pessoas: { type: Array, default: () => [] },
  perdas: { type: Array, default: () => [] },
});

const emit = defineEmits(['salvar']);

const { t, lista, minuscula } = useTextos();
const dialogo = ref(null);

const n = computed(() => props.pessoas.length);
const titulo = computed(() =>
  t(
    'FUNCOES_EQUIPE.PERDA.TITULO',
    {
      n: n.value,
      coisas: lista(
        props.perdas.map(id => minuscula(t(`FUNCOES_EQUIPE.PODE.${id}`)))
      ),
    },
    n.value
  )
);
const nomes = computed(() => lista(props.pessoas.map(pessoa => pessoa.name)));

defineExpose({ abrir: () => dialogo.value?.abrir() });
</script>

<template>
  <DialogoDaCasa
    ref="dialogo"
    tipo="destrutivo"
    icone="i-lucide-user-minus"
    :titulo="titulo"
    :seguro="$t('FUNCOES_EQUIPE.PERDA.VOLTAR')"
    :acao="$t('FUNCOES_EQUIPE.PERDA.SALVAR')"
    @acao="emit('salvar')"
  >
    <p data-nomes class="m-0 text-sm font-medium text-n-slate-12">
      {{ nomes }}
    </p>
    <p class="m-0 text-[0.9375rem] text-n-slate-11">
      {{ $t('FUNCOES_EQUIPE.PERDA.TEXTO', { nome }, n) }}
    </p>
  </DialogoDaCasa>
</template>
