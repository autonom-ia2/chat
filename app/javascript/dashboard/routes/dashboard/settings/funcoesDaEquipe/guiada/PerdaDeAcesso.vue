<script setup>
import { computed, ref } from 'vue';
import { itemDoMenu } from '../fraseDaFuncao';
import DialogoDaCasa from './DialogoDaCasa.vue';
import { useTextos } from './useTextos';

// Perda de acesso (#2308, especificação 5.F), só para o administrador: ao salvar uma alteração que tira algo de
// quem já tem a função, diz quem perde o quê antes de gravar. Com uma perda só, o título diz qual ("5 pessoas vão
// deixar de mudar os dados dos contatos"); com mais, quantas, e a lista vem embaixo. `perdas` sai de perdasDeAcesso:
// { id } de FUNCOES_EQUIPE.PODE ou { areas } que deixam de ser vistas (numa linha, com dois-pontos e sem artigo, pelo
// nome do menu: "Ver: Clientes novos", nunca "Ver Procurar clientes novos").
// Os nomes param em 3, com "e mais N pessoas".
const props = defineProps({
  nome: { type: String, required: true },
  pessoas: { type: Array, default: () => [] },
  perdas: { type: Array, default: () => [] },
});

const emit = defineEmits(['salvar']);

const { t, lista, minuscula, nomeDaArea } = useTextos();
const dialogo = ref(null);
const MAX_NOMES = 3;
const nomeNoMenu = area => {
  const item = itemDoMenu(area);
  return item ? t(`FUNCOES_EQUIPE.MENU.${item}`) : nomeDaArea(area);
};

const n = computed(() => props.pessoas.length);
const itens = computed(() =>
  props.perdas.map(perda =>
    perda.areas
      ? t('FUNCOES_EQUIPE.PERDA.VER_AREAS', {
          areas: lista(perda.areas.map(nomeNoMenu)),
        })
      : t(`FUNCOES_EQUIPE.PODE.${perda.id}`)
  )
);
const titulo = computed(() =>
  itens.value.length === 1
    ? t(
        'FUNCOES_EQUIPE.PERDA.TITULO_UMA',
        { n: n.value, coisa: minuscula(itens.value[0]) },
        n.value
      )
    : t(
        'FUNCOES_EQUIPE.PERDA.TITULO_VARIAS',
        { n: n.value, coisas: itens.value.length },
        n.value
      )
);
const nomes = computed(() => {
  const todos = props.pessoas.map(pessoa => pessoa.name);
  if (todos.length <= MAX_NOMES) return lista(todos);
  const resto = todos.length - MAX_NOMES;
  return t(
    'FUNCOES_EQUIPE.PERDA.NOMES_E_MAIS',
    { nomes: todos.slice(0, MAX_NOMES).join(', '), n: resto },
    resto
  );
});

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
