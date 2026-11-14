<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import ListaDoRamo from './ListaDoRamo.vue';
import {
  alternarPergunta,
  blocosDe,
  comToques,
  contar,
  ligada,
  mudarBloco,
  soltas,
  toquesEntre,
} from '../../utils/perguntasEmBlocos';

// #3020 — as perguntas de um agente pronto por ramo, em blocos: o dono abre o bloco e liga ou desliga cada pergunta.
// No topo, quantas estão ligadas: é o que o cliente dele vai responder. O modelo já vem com o mínimo ligado.
// A pergunta inteira é o botão (alvo de toque grande, `role="switch"`). A que depende de outra fica recuada embaixo
// dela: desligar a de cima desliga as que seguem, e ligar uma que segue liga a de cima.
// As perguntas que o dono escreve ficam no fim, em "Suas perguntas" (ListaDoRamo: editar, tirar e incluir).
//
// A lista que vale é a do servidor (`itens`), e cada mudança sai como a lista inteira nova (`mudar`). Para o botão
// responder na hora, a tela mostra uma cópia (`local`) que muda no toque. Enquanto uma mudança está indo (`gravando`),
// o toque seguinte fica guardado (`tocadas`, só o que ligou ou desligou) e sai quando ela termina, por cima da lista
// que o servidor devolveu: assim a pergunta que a pessoa acabou de incluir ou editar não se perde. Se o servidor
// recusar a mudança que ia, os toques guardados caem junto e a cópia volta a ser a lista dele.
// `pendente` (exposto): há toque guardado. Quem abre a gaveta espera ele sair antes de fechar.
// Não há botão de salvar: ao lado do título do contador a tela diz "Salvando…" enquanto a mudança vai e "Salvo"
// quando o servidor guardou (o aviso de "gravou", o segundo valor do `mudar`). O contador fica preso no topo da gaveta:
// a pessoa rola os blocos sem perder de vista quantas perguntas o cliente dela vai responder.
const props = defineProps({
  itens: { type: Array, required: true },
  nome: { type: String, required: true },
  rotuloIncluir: { type: String, required: true },
  exemplo: { type: String, default: '' },
  podeMudar: { type: Boolean, default: false },
  gravando: { type: Boolean, default: false },
});

const emit = defineEmits(['mudar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.RAMOS.CONFIRA.BLOCOS';
const idBase = useId();

const local = ref(props.itens);
const tocadas = ref({});
const pendente = computed(() => Object.keys(tocadas.value).length > 0);
const salvo = ref(false);
// Manda a lista e, junto, o aviso de "gravou": só ele acende o "Salvo". `depois`: o aviso de quem pediu (ListaDoRamo).
const enviar = (lista, depois) => {
  salvo.value = false;
  emit('mudar', lista, () => {
    salvo.value = true;
    depois?.();
  });
};
watch(
  () => props.itens,
  itens => {
    local.value = comToques(itens, tocadas.value);
  }
);
watch(
  () => props.gravando,
  gravando => {
    if (gravando) return;
    const guardou = salvo.value;
    const havia = pendente.value;
    const lista = guardou ? comToques(props.itens, tocadas.value) : props.itens;
    tocadas.value = {};
    local.value = lista;
    if (guardou && havia) enviar(lista);
  }
);
const mudar = nova => {
  if (props.gravando) {
    tocadas.value = { ...tocadas.value, ...toquesEntre(local.value, nova) };
  }
  local.value = nova;
  if (!props.gravando) enviar(nova);
};
defineExpose({ pendente });
// '' enquanto a pessoa ainda não mudou nada (ou o servidor recusou a última mudança).
const estado = computed(() => {
  if (props.gravando || pendente.value) return 'SALVANDO';
  return salvo.value ? 'SALVO' : '';
});

const blocos = computed(() => blocosDe(local.value));
const conta = computed(() => contar(local.value));
const proprias = computed(() => soltas(local.value));
const doModelo = computed(() => local.value.filter(item => item.bloco));

// O primeiro bloco já vem aberto, para a pessoa ver como funciona.
const abertos = ref(blocos.value.length ? [blocos.value[0].nome] : []);
const aberto = nome => abertos.value.includes(nome);
const abrirOuFechar = nome => {
  abertos.value = aberto(nome)
    ? abertos.value.filter(outro => outro !== nome)
    : [...abertos.value, nome];
};
const idDoBloco = indice => `${idBase}-bloco-${indice}`;
const ligadasDo = bloco => bloco.perguntas.filter(ligada).length;

// A condição aparece uma vez: a pergunta que segue outra com a mesma condição da de cima não a repete na tela (o
// leitor de tela ouve a condição em todas).
const mostraCondicao = (bloco, indice) => {
  const pergunta = bloco.perguntas[indice];
  if (!pergunta.se) return false;
  const anterior = bloco.perguntas[indice - 1];
  return !(pergunta.segue && anterior?.se === pergunta.se);
};

const mudarProprias = (novas, aoGravar) =>
  enviar([...doModelo.value, ...novas], aoGravar);
</script>

<template>
  <div data-perguntas-em-blocos class="flex flex-col gap-4">
    <div class="sticky z-10 pt-4 pb-2 -mt-4 -mb-2 -top-4 bg-n-solid-1">
      <div
        data-contador
        aria-live="polite"
        class="flex items-center gap-4 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-4"
      >
        <span
          data-ligadas
          class="text-4xl font-semibold leading-none text-center min-w-12 tabular-nums text-n-blue-11"
        >
          {{ conta.ligadas }}
        </span>
        <div class="flex flex-col flex-1 min-w-0">
          <div class="flex flex-wrap items-center justify-between gap-x-3">
            <span class="text-base font-semibold text-n-slate-12">
              {{ t(`${NS}.LIGADAS`) }}
            </span>
            <span
              v-if="estado"
              data-estado
              class="flex items-center gap-1 text-sm font-medium"
              :class="estado === 'SALVO' ? 'text-n-teal-11' : 'text-n-slate-11'"
            >
              <span
                class="size-4 shrink-0"
                :class="
                  estado === 'SALVO'
                    ? 'i-lucide-check'
                    : 'i-lucide-loader-circle animate-spin motion-reduce:animate-none'
                "
                aria-hidden="true"
              />
              {{ t(`${NS}.${estado}`) }}
            </span>
          </div>
          <span class="text-sm leading-relaxed text-n-slate-11">
            {{
              t(`${NS}.RESUMO`, {
                todos: conta.todos,
                conforme: conta.conforme,
              })
            }}
          </span>
        </div>
      </div>
    </div>

    <section
      v-for="(bloco, numero) in blocos"
      :key="bloco.nome"
      :data-bloco="bloco.nome"
      class="overflow-hidden rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
    >
      <h3 class="m-0">
        <button
          type="button"
          data-abrir-bloco
          :aria-expanded="aberto(bloco.nome)"
          :aria-controls="idDoBloco(numero)"
          class="flex items-center w-full gap-3 px-4 py-3 transition-colors bg-transparent border-0 cursor-pointer min-h-14 text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-blue-9"
          @click="abrirOuFechar(bloco.nome)"
        >
          <span class="flex flex-col flex-1 min-w-0">
            <span class="text-base font-semibold text-n-slate-12">
              {{ bloco.nome }}
            </span>
            <span
              data-ligadas-do-bloco
              class="text-sm"
              :class="ligadasDo(bloco) ? 'text-n-blue-11' : 'text-n-slate-11'"
            >
              {{
                t(`${NS}.DO_BLOCO`, {
                  n: ligadasDo(bloco),
                  total: bloco.perguntas.length,
                })
              }}
            </span>
          </span>
          <span
            class="transition-transform size-5 shrink-0 text-n-slate-11 i-lucide-chevron-down"
            :class="aberto(bloco.nome) ? 'rotate-180' : ''"
            aria-hidden="true"
          />
        </button>
      </h3>

      <Transition
        enter-active-class="transition-opacity duration-200 motion-reduce:transition-none"
        enter-from-class="opacity-0"
      >
        <div
          v-if="aberto(bloco.nome)"
          :id="idDoBloco(numero)"
          class="flex flex-col border-t border-n-weak"
        >
          <div v-if="podeMudar" class="flex flex-wrap gap-1 px-1 pt-1">
            <AgenteBotao
              data-ligar-todas
              variante="fantasma"
              :inativo="ligadasDo(bloco) === bloco.perguntas.length"
              :aria-label="t(`${NS}.LIGAR_TODAS_SR`, { bloco: bloco.nome })"
              @click="mudar(mudarBloco(local, bloco.nome, true))"
            >
              {{ t(`${NS}.LIGAR_TODAS`) }}
            </AgenteBotao>
            <AgenteBotao
              data-desligar-todas
              variante="fantasma"
              :inativo="ligadasDo(bloco) === 0"
              :aria-label="t(`${NS}.DESLIGAR_TODAS_SR`, { bloco: bloco.nome })"
              @click="mudar(mudarBloco(local, bloco.nome, false))"
            >
              {{ t(`${NS}.DESLIGAR_TODAS`) }}
            </AgenteBotao>
          </div>
          <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
            <li
              v-for="(pergunta, indice) in bloco.perguntas"
              :key="pergunta.id"
            >
              <button
                type="button"
                role="switch"
                :data-pergunta="pergunta.id"
                :aria-checked="ligada(pergunta)"
                :disabled="!podeMudar"
                class="flex items-center w-full gap-3 py-3 transition-colors bg-transparent border-0 pe-4 min-h-12 text-start focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-blue-9"
                :class="[
                  pergunta.segue ? 'ps-6' : 'ps-4',
                  podeMudar
                    ? 'cursor-pointer hover:bg-n-alpha-1 active:bg-n-alpha-2'
                    : 'cursor-default',
                ]"
                @click="mudar(alternarPergunta(local, pergunta.id))"
              >
                <span
                  v-if="pergunta.segue"
                  data-segue
                  class="self-start mt-1 size-4 shrink-0 text-n-slate-9 i-lucide-corner-down-right rtl:-scale-x-100"
                  aria-hidden="true"
                />
                <span class="flex flex-col flex-1 min-w-0 gap-0.5">
                  <span
                    data-texto-da-pergunta
                    class="text-base leading-snug"
                    :class="
                      ligada(pergunta) ? 'text-n-slate-12' : 'text-n-slate-11'
                    "
                  >
                    {{ pergunta.texto }}
                  </span>
                  <span
                    v-if="mostraCondicao(bloco, indice)"
                    data-condicao
                    class="text-sm text-n-slate-11"
                  >
                    {{ t(`${NS}.SO_SE`, { condicao: pergunta.se }) }}
                  </span>
                  <span v-else-if="pergunta.se" class="sr-only">
                    {{ t(`${NS}.SO_SE`, { condicao: pergunta.se }) }}
                  </span>
                </span>
                <span
                  aria-hidden="true"
                  class="relative h-6 transition-colors duration-200 ease-in-out rounded-full w-11 shrink-0"
                  :class="[
                    ligada(pergunta) ? 'bg-n-brand' : 'bg-n-slate-7',
                    podeMudar ? '' : 'opacity-60',
                  ]"
                >
                  <span
                    class="absolute bg-white rounded-full shadow-md top-0.5 size-5 transition-transform duration-[350ms] ease-[cubic-bezier(0.34,1.56,0.64,1)] motion-reduce:transition-none ltr:left-0.5 rtl:right-0.5"
                    :class="
                      ligada(pergunta)
                        ? 'ltr:translate-x-5 rtl:-translate-x-5'
                        : ''
                    "
                  />
                </span>
              </button>
            </li>
          </ul>
        </div>
      </Transition>
    </section>

    <section
      v-if="podeMudar || proprias.length"
      data-suas-perguntas
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
    >
      <div class="flex flex-col gap-1">
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.SUAS`) }}
        </h3>
        <p class="m-0 text-sm leading-relaxed text-n-slate-11">
          {{ t(`${NS}.SUAS_NOTA`, { nome }) }}
        </p>
      </div>
      <ListaDoRamo
        :itens="proprias"
        :rotulo-incluir="rotuloIncluir"
        :exemplo="exemplo"
        :pode-mudar="podeMudar"
        :gravando="gravando"
        @mudar="mudarProprias"
      />
    </section>
  </div>
</template>
