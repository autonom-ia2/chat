<script setup>
import { computed, ref } from 'vue';
import DialogoDaCasa from './DialogoDaCasa.vue';
import { useTextos } from './useTextos';

// Perda de acesso (#2308, especificação 5.F), só para o administrador: ao salvar uma alteração que tira algo de
// quem já tem a função, diz quem perde o quê antes de gravar. Com uma perda só, o título diz qual ("5 pessoas vão
// deixar de mudar os dados dos contatos") e a lista não a repete; com mais, quantas, e a lista vem embaixo, um item
// por coisa (a contagem bate com a lista). `perdas` sai de perdasDeAcesso: { id } de FUNCOES_EQUIPE.PODE ou { area }
// que deixa de ser vista ("Ver os Relatórios"). Os nomes param em 3, com "e mais N pessoas". Com uma perda só numa
// queda de nível, o texto diz também o que fica ("A partir de agora, só vão olhar os contatos."; `fica` sai de
// nivelQueFica, revisão do #2308, rodada 4).
const props = defineProps({
  nome: { type: String, required: true },
  pessoas: { type: Array, default: () => [] },
  perdas: { type: Array, default: () => [] },
  fica: { type: Object, default: null },
});

const emit = defineEmits(['salvar']);

const { t, lista, minuscula } = useTextos();
const dialogo = ref(null);
const MAX_NOMES = 3;

const n = computed(() => props.pessoas.length);
const itens = computed(() =>
  props.perdas.map(perda =>
    perda.area
      ? t('FUNCOES_EQUIPE.PERDA.VER_AREA', {
          area: t(`FUNCOES_EQUIPE.AREAS.${perda.area}.NA_FRASE`),
        })
      : t(`FUNCOES_EQUIPE.PODE.${perda.id}`)
  )
);
const umaSo = computed(() => itens.value.length === 1);
const titulo = computed(() =>
  umaSo.value
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

const texto = computed(() => {
  const quem = t(
    `FUNCOES_EQUIPE.PERDA.${umaSo.value ? 'TEXTO_UMA' : 'TEXTO'}`,
    { nome: props.nome },
    n.value
  );
  if (!umaSo.value || !props.fica) return quem;
  // A área no meio da frase, em minúscula ("só vão olhar as vendas"), a mesma forma do título (rodada 6).
  const area = t(`FUNCOES_EQUIPE.AREAS.${props.fica.area}.NA_FRASE`);
  const fica = t(
    `FUNCOES_EQUIPE.PERDA.FICA.${props.fica.nivel}`,
    { area },
    n.value
  );
  return `${quem} ${fica}`;
});

defineExpose({ abrir: () => dialogo.value?.abrir() });
</script>

<template>
  <DialogoDaCasa
    ref="dialogo"
    tipo="destrutivo"
    icone="i-lucide-door-open"
    :titulo="titulo"
    :seguro="$t('FUNCOES_EQUIPE.PERDA.VOLTAR')"
    :acao="$t('FUNCOES_EQUIPE.PERDA.SALVAR')"
    @acao="emit('salvar')"
  >
    <p data-nomes class="m-0 text-sm font-medium text-n-slate-12">
      {{ nomes }}
    </p>
    <p data-texto-perda class="m-0 text-[0.9375rem] text-n-slate-11">
      {{ texto }}
    </p>
    <ul
      v-if="!umaSo"
      data-perdas
      class="flex flex-col gap-1.5 p-0 m-0 list-none"
    >
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
