<script setup>
import { computed, ref } from 'vue';
import DialogoDaCasa from './DialogoDaCasa.vue';
import { useTextos } from './useTextos';

// Perda de acesso (#2308, especificação 5.F), só para o administrador: ao salvar uma alteração que tira algo de
// quem já tem a função, diz quem perde o quê antes de gravar. Título curto; a lista vem embaixo. `perdas` sai de
// perdasDeAcesso: { id } de FUNCOES_EQUIPE.PODE ou { area } que deixa de ser vista.
const props = defineProps({
  nome: { type: String, required: true },
  pessoas: { type: Array, default: () => [] },
  perdas: { type: Array, default: () => [] },
});

const emit = defineEmits(['salvar']);

const { t, lista, nomeDaArea } = useTextos();
const dialogo = ref(null);

const n = computed(() => props.pessoas.length);
const itens = computed(() =>
  props.perdas.map(perda =>
    perda.area
      ? t('FUNCOES_EQUIPE.SEM_FUNCAO.AREA.VER.LISTA', {
          area: nomeDaArea(perda.area),
        })
      : t(`FUNCOES_EQUIPE.PODE.${perda.id}`)
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
    :titulo="$t('FUNCOES_EQUIPE.PERDA.TITULO', { n }, n)"
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
    <ul data-perdas class="flex flex-col gap-1.5 p-0 m-0 list-none">
      <li
        v-for="item in itens"
        :key="item"
        class="flex items-start gap-2 text-[0.9375rem] text-n-slate-12"
      >
        <span
          class="i-lucide-x size-4 mt-1 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        {{ item }}
      </li>
    </ul>
  </DialogoDaCasa>
</template>
