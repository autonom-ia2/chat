<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../AgenteBotao.vue';
import ListaDoRamo from './ListaDoRamo.vue';
import {
  alternarPergunta,
  blocosDe,
  contar,
  ligada,
  mudarBloco,
  soltas,
} from '../../utils/perguntasEmBlocos';

// #3020 — as perguntas de um agente pronto por ramo, em blocos: o dono abre o bloco e liga ou desliga cada pergunta.
// No topo, quantas estão ligadas: é o que o cliente dele vai responder. O modelo já vem com o mínimo ligado.
// A pergunta inteira é o botão (alvo de toque grande, `role="switch"`). A que depende de outra fica recuada embaixo
// dela: desligar a de cima desliga as que seguem, e ligar uma que segue liga a de cima.
// As perguntas que o dono escreve ficam no fim, em "Suas perguntas" (ListaDoRamo: editar, tirar e incluir).
//
// A lista que vale é a do servidor (`itens`), e cada mudança sai como a lista inteira nova (`mudar`). Para o botão
// responder na hora, a tela mostra uma cópia (`local`) que muda no toque. Enquanto uma mudança está indo (`gravando`),
// o toque seguinte fica guardado e sai quando ela termina, já com tudo o que a pessoa tocou. Se o servidor recusar, a
// cópia volta a ser a lista dele.
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
const pendente = ref(false);
watch(
  () => props.itens,
  itens => {
    if (!pendente.value) local.value = itens;
  }
);
watch(
  () => props.gravando,
  gravando => {
    if (gravando) return;
    if (pendente.value) {
      pendente.value = false;
      emit('mudar', local.value);
      return;
    }
    local.value = props.itens;
  }
);
const mudar = nova => {
  local.value = nova;
  if (props.gravando) pendente.value = true;
  else emit('mudar', nova);
};

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

// A condição aparece uma vez: a pergunta que segue outra com a mesma condição da de cima não a repete.
const mostraCondicao = (bloco, indice) => {
  const pergunta = bloco.perguntas[indice];
  if (!pergunta.se) return false;
  const anterior = bloco.perguntas[indice - 1];
  return !(pergunta.segue && anterior?.se === pergunta.se);
};

const mudarProprias = (novas, aoGravar) =>
  emit('mudar', [...doModelo.value, ...novas], aoGravar);
</script>

<template>
  <div data-perguntas-em-blocos class="flex flex-col gap-4">
    <div
      data-contador
      aria-live="polite"
      class="flex items-center gap-4 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-4"
    >
      <span
        data-ligadas
        class="text-4xl font-semibold leading-none tabular-nums text-n-blue-11"
      >
        {{ conta.ligadas }}
      </span>
      <div class="flex flex-col min-w-0">
        <span class="text-base font-semibold text-n-slate-12">
          {{ t(`${NS}.LIGADAS`) }}
        </span>
        <span class="text-sm leading-relaxed text-n-slate-11">
          {{
            t(`${NS}.RESUMO`, { todos: conta.todos, conforme: conta.conforme })
          }}
        </span>
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
          class="flex items-center w-full gap-3 px-4 py-3 bg-transparent border-0 cursor-pointer min-h-14 text-start focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-blue-9"
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

      <div
        v-if="aberto(bloco.nome)"
        :id="idDoBloco(numero)"
        class="flex flex-col border-t border-n-weak"
      >
        <div v-if="podeMudar" class="flex flex-wrap gap-1 px-1 pt-1">
          <AgenteBotao
            v-if="ligadasDo(bloco) < bloco.perguntas.length"
            data-ligar-todas
            variante="fantasma"
            :aria-label="t(`${NS}.LIGAR_TODAS_SR`, { bloco: bloco.nome })"
            @click="mudar(mudarBloco(local, bloco.nome, true))"
          >
            {{ t(`${NS}.LIGAR_TODAS`) }}
          </AgenteBotao>
          <AgenteBotao
            v-if="ligadasDo(bloco) > 0"
            data-desligar-todas
            variante="fantasma"
            :aria-label="t(`${NS}.DESLIGAR_TODAS_SR`, { bloco: bloco.nome })"
            @click="mudar(mudarBloco(local, bloco.nome, false))"
          >
            {{ t(`${NS}.DESLIGAR_TODAS`) }}
          </AgenteBotao>
        </div>
        <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
          <li v-for="(pergunta, indice) in bloco.perguntas" :key="pergunta.id">
            <button
              type="button"
              role="switch"
              :data-pergunta="pergunta.id"
              :aria-checked="ligada(pergunta)"
              :disabled="!podeMudar"
              class="flex items-center w-full gap-3 py-3 bg-transparent border-0 pe-4 min-h-11 text-start focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-blue-9"
              :class="[
                pergunta.segue ? 'ps-9' : 'ps-4',
                podeMudar ? 'cursor-pointer' : 'cursor-default',
              ]"
              @click="mudar(alternarPergunta(local, pergunta.id))"
            >
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
              </span>
              <span
                aria-hidden="true"
                class="relative h-6 transition-colors rounded-full w-11 shrink-0"
                :class="ligada(pergunta) ? 'bg-n-blue-9' : 'bg-n-slate-8'"
              >
                <span
                  class="absolute bg-white rounded-full shadow top-0.5 size-5 transition-transform ltr:left-0.5 rtl:right-0.5"
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
