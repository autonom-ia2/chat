<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import ListaDoRamo from './ListaDoRamo.vue';

// #2881 — no Confira de um agente pronto por ramo: o que ele já traz, em linhas curtas. "Mostrar antes de fazer":
// cada linha abre uma gaveta com a lista inteira. Nas perguntas e nos documentos o dono pode tirar (e voltar), editar
// e incluir (ListaDoRamo). A tela principal continua com uma ação só, o "Começar a atender", e o celular do teste
// fica logo abaixo.
// As listas são as do servidor ([{ id, texto, tirada }]): a mudança sai como `mudar` ({ lista, itens }, a lista
// inteira nova) e a tela só muda quando o servidor responde. As ferramentas são de quem chama: a gaveta delas mostra
// o slot `ferramentas`, e a linha só aparece quando há o que mostrar (`ferramentas` com um número).
// Mudança que veio de um campo de texto (editar, incluir) leva também `aoGravar`, o aviso de "gravou" da ListaDoRamo:
// quem grava chama quando o servidor guardou, e só então o campo fecha.
// `gravando`: { perguntas, documentos }, a lista cuja mudança ainda está indo.
// Serve também à página do agente que já atende (#2976, RamoNaPagina): `naPagina` dá ao bloco a moldura dos blocos da
// página, `titulo` troca o título e `nota` põe uma frase curta embaixo dele.
const props = defineProps({
  nome: { type: String, required: true },
  titulo: { type: String, default: '' },
  nota: { type: String, default: '' },
  naPagina: { type: Boolean, default: false },
  perguntas: { type: Array, default: () => [] },
  documentos: { type: Array, default: () => [] },
  // Quantas ferramentas prontas o agente leva. null: a conta não tem ferramentas para mostrar.
  ferramentas: { type: Number, default: null },
  podeMudar: { type: Boolean, default: false },
  gravando: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['mudar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.RAMOS.CONFIRA';
const PERGUNTAS = 'perguntas';
const DOCUMENTOS = 'documentos';
const FERRAMENTAS = 'ferramentas';

const aberta = ref(null);
const restam = itens => itens.filter(item => !item.tirada).length;

const linhas = computed(() => [
  {
    chave: PERGUNTAS,
    icone: 'i-lucide-list-checks',
    texto: t(`${NS}.PERGUNTA`, { n: restam(props.perguntas) }),
    rotulo: t(`${NS}.VER_PERGUNTAS`, { nome: props.nome }),
  },
  {
    chave: DOCUMENTOS,
    icone: 'i-lucide-file-text',
    texto: t(`${NS}.PEDE`, { n: restam(props.documentos) }),
    rotulo: t(`${NS}.VER_DOCUMENTOS`, { nome: props.nome }),
  },
  ...(props.ferramentas === null
    ? []
    : [
        {
          chave: FERRAMENTAS,
          icone: 'i-lucide-wrench',
          texto: t(`${NS}.JA_VEM`, { n: props.ferramentas }),
          rotulo: t(`${NS}.VER_FERRAMENTAS`, { nome: props.nome }),
        },
      ]),
]);

// A nota da gaveta; a frase "Você pode tirar, editar e incluir." só para quem pode (#2976: quem só vê não tem botão).
const notaDe = (chave, nome) =>
  [t(chave, nome), props.podeMudar ? t(`${NS}.PODE_MUDAR`) : '']
    .filter(Boolean)
    .join(' ');

const gaveta = computed(() => {
  const nome = { nome: props.nome };
  const MOLDE = {
    [PERGUNTAS]: {
      titulo: t(`${NS}.PERGUNTAS_TITULO`, nome),
      nota: notaDe(`${NS}.PERGUNTAS_NOTA`, nome),
      incluir: t(`${NS}.INCLUIR_PERGUNTA`),
      exemplo: t(`${NS}.NOVA_PERGUNTA`),
      itens: props.perguntas,
    },
    [DOCUMENTOS]: {
      titulo: t(`${NS}.DOCUMENTOS_TITULO`, nome),
      nota: notaDe(`${NS}.DOCUMENTOS_NOTA`, nome),
      incluir: t(`${NS}.INCLUIR_DOCUMENTO`),
      exemplo: t(`${NS}.NOVO_DOCUMENTO`),
      itens: props.documentos,
    },
  };
  const molde = MOLDE[aberta.value];
  return molde ? { ...molde, lista: aberta.value } : null;
});
</script>

<template>
  <section
    data-pronto-do-ramo
    aria-labelledby="pronto-do-ramo-titulo"
    class="flex flex-col gap-1 rounded-2xl ring-1 ring-inset ring-n-weak"
    :class="
      naPagina
        ? 'p-5 shadow-sm bg-n-solid-1 dark:ring-n-slate-6'
        : 'p-4 bg-n-solid-2'
    "
  >
    <component
      :is="naPagina ? 'h2' : 'h3'"
      id="pronto-do-ramo-titulo"
      class="m-0 text-base font-semibold text-n-slate-12"
    >
      {{ titulo || t(`${NS}.TITULO`, { nome }) }}
    </component>
    <p v-if="nota" data-nota-do-ramo class="m-0 text-sm text-n-slate-11">
      {{ nota }}
    </p>
    <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
      <li
        v-for="linha in linhas"
        :key="linha.chave"
        :data-linha="linha.chave"
        class="flex items-center gap-3 py-1"
      >
        <span
          class="size-5 shrink-0 text-n-slate-11"
          :class="linha.icone"
          aria-hidden="true"
        />
        <span class="flex-1 min-w-0 text-sm text-n-slate-12">
          {{ linha.texto }}
        </span>
        <AgenteBotao
          variante="fantasma"
          class="shrink-0"
          :aria-label="linha.rotulo"
          @click="aberta = linha.chave"
        >
          {{ t(`${NS}.VER`) }}
        </AgenteBotao>
      </li>
    </ul>

    <AgenteGaveta
      v-if="aberta === FERRAMENTAS"
      :titulo="t(`${NS}.FERRAMENTAS_TITULO`, { nome })"
      @fechar="aberta = null"
    >
      <slot name="ferramentas" />
    </AgenteGaveta>

    <AgenteGaveta v-if="gaveta" :titulo="gaveta.titulo" @fechar="aberta = null">
      <div class="flex flex-col gap-4">
        <p class="m-0 text-sm leading-relaxed text-n-slate-11">
          {{ gaveta.nota }}
        </p>
        <ListaDoRamo
          :itens="gaveta.itens"
          :rotulo-incluir="gaveta.incluir"
          :exemplo="gaveta.exemplo"
          :pode-mudar="podeMudar"
          :gravando="gravando[gaveta.lista] === true"
          @mudar="
            (itens, aoGravar) =>
              emit('mudar', { lista: gaveta.lista, itens, aoGravar })
          "
        />
      </div>
    </AgenteGaveta>
  </section>
</template>
