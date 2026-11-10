<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import AgenteErro from '../../AgenteErro.vue';
import FerramentaInterruptor from './FerramentaInterruptor.vue';

// #1301 (protótipo F01) — lista das ferramentas do agente: frase do que cada uma faz, o
// interruptor Ligada/Desligada. Sem limite de quantidade (#1430). A linha inteira abre a ferramenta.
// Ligar sempre passa pelo teste e desligar pede confirmação: quem decide é a gaveta.
// #2858 F2 — com a vitrine (`vitrine`), as prontas que o agente já tem vêm em cima das feitas à mão, com o
// interruptor e "Tirar"; a ação principal passa a ser escolher uma pronta, e o cadastro manual vira "Criar a minha
// (avançado)", só para quem pode usá-lo (`cadastroManual`). `prontas`: [{ id, nome, frase, icone, ligada }], já com
// os textos (a gaveta resolve).
const props = defineProps({
  nome: { type: String, required: true },
  ferramentas: { type: Array, required: true },
  carregando: { type: Boolean, default: false },
  erro: { type: Boolean, default: false },
  rodape: { type: String, required: true },
  vitrine: { type: Boolean, default: false },
  prontas: { type: Array, default: () => [] },
  cadastroManual: { type: Boolean, default: true },
});

const emit = defineEmits([
  'abrir',
  'alternar',
  'adicionar',
  'tentar',
  'criar',
  'alternarPronta',
  'tirarPronta',
]);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const NS_VITRINE = 'AGENTS.VITRINE.PRONTAS';
const { t } = useI18n();

const vazia = computed(
  () => !props.ferramentas.length && !props.prontas.length
);
const mostraCriarAMinha = computed(() => props.vitrine && props.cadastroManual);
const mostraRodape = computed(
  () => !props.carregando && !props.erro && !vazia.value
);
const iconeDoMetodo = ferramenta =>
  ferramenta.http_method === 'POST' ? 'i-lucide-send' : 'i-lucide-search';
</script>

<template>
  <div data-ferramentas class="flex flex-col gap-4">
    <p class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.LISTA.CONTEXTO`, { nome }) }}
    </p>

    <div v-if="carregando" class="relative flex flex-col gap-2">
      <p role="status" class="sr-only">{{ t(`${NS}.LISTA.CARREGANDO`) }}</p>
      <div
        v-for="linha in 3"
        :key="linha"
        aria-hidden="true"
        class="flex flex-col gap-2 p-4 rounded-xl ring-1 ring-inset ring-n-weak"
      >
        <span class="w-5/12 h-4 rounded bg-n-alpha-2 animate-pulse" />
        <span class="w-9/12 h-3.5 rounded bg-n-alpha-2 animate-pulse" />
      </div>
    </div>

    <AgenteErro
      v-else-if="erro"
      data-erro-lista
      :titulo="t(`${NS}.LISTA.ERRO`)"
      :garantia="t(`${NS}.LISTA.ERRO_GARANTIA`)"
      :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
      @acao="emit('tentar')"
    />

    <div
      v-else-if="vazia"
      data-vazia
      class="flex flex-col items-center gap-3 px-4 py-8 text-center rounded-2xl bg-n-alpha-1"
    >
      <span aria-hidden="true" class="i-lucide-wrench size-8 text-n-slate-11" />
      <p class="m-0 text-sm text-n-slate-12">
        {{
          vitrine ? t(`${NS_VITRINE}.VAZIO`, { nome }) : t(`${NS}.LISTA.VAZIO`)
        }}
      </p>
      <AgenteBotao
        data-adicionar
        tamanho="lg"
        :icone="vitrine ? 'i-lucide-package-open' : 'i-lucide-plus'"
        @click="emit('adicionar')"
      >
        {{ vitrine ? t(`${NS_VITRINE}.ESCOLHER`) : t(`${NS}.LISTA.ADICIONAR`) }}
      </AgenteBotao>
      <AgenteBotao
        v-if="mostraCriarAMinha"
        data-criar-minha
        variante="fantasma"
        @click="emit('criar')"
      >
        {{ t(`${NS_VITRINE}.CRIAR_MINHA`) }}
      </AgenteBotao>
    </div>

    <template v-else>
      <template v-if="prontas.length">
        <h3
          id="ferramentas-prontas"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t(`${NS_VITRINE}.TITULO`) }}
        </h3>
        <ul
          data-prontas
          aria-labelledby="ferramentas-prontas"
          class="flex flex-col p-0 m-0 list-none divide-y shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak divide-n-weak"
        >
          <li
            v-for="item in prontas"
            :key="item.id"
            :data-pronta="item.fonte"
            class="flex items-start gap-3 px-4 py-3"
          >
            <span
              aria-hidden="true"
              class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-blue-3 text-n-blue-11"
            >
              <span :class="item.icone" class="size-5" />
            </span>
            <span class="flex flex-col flex-1 min-w-0 gap-0.5">
              <span class="text-sm font-semibold break-words text-n-slate-12">
                {{ item.nome }}
              </span>
              <span class="text-sm text-n-slate-11 line-clamp-2">
                {{ item.frase }}
              </span>
              <button
                type="button"
                data-tirar
                :aria-label="
                  t(`${NS_VITRINE}.TIRAR_SR`, {
                    ferramenta: item.nome,
                    agente: nome,
                  })
                "
                class="self-start px-2 -ms-2 text-sm font-medium rounded-lg min-h-11 text-n-ruby-11 hover:bg-n-ruby-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
                @click="emit('tirarPronta', item)"
              >
                {{ t(`${NS_VITRINE}.TIRAR`) }}
              </button>
            </span>
            <FerramentaInterruptor
              :id="`pronta-interruptor-${item.id}`"
              class="mt-1"
              :ligado="item.ligada"
              :rotulo="t(`${NS}.USAR`, { ferramenta: item.nome })"
              :texto-ligado="t(`${NS}.LIGADA`)"
              :texto-desligado="t(`${NS}.DESLIGADA`)"
              @alternar="emit('alternarPronta', item, $event)"
            />
          </li>
        </ul>
      </template>
      <template v-if="ferramentas.length">
        <h3
          id="ferramentas-feitas"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t(`${NS}.LISTA.FEITAS`) }}
        </h3>
        <ul
          aria-labelledby="ferramentas-feitas"
          class="flex flex-col p-0 m-0 list-none divide-y shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak divide-n-weak"
        >
          <li
            v-for="ferramenta in ferramentas"
            :key="ferramenta.id"
            :data-ferramenta="ferramenta.id"
            class="flex items-start gap-2 px-2 py-1"
          >
            <button
              type="button"
              data-abrir
              class="flex items-start flex-1 min-w-0 gap-3 p-2 rounded-xl min-h-16 text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @click="emit('abrir', ferramenta)"
            >
              <span
                aria-hidden="true"
                class="grid rounded-lg place-items-center size-9 shrink-0 bg-n-alpha-2"
              >
                <span
                  :class="iconeDoMetodo(ferramenta)"
                  class="size-5 text-n-slate-11"
                />
              </span>
              <span class="relative flex flex-col min-w-0 gap-0.5">
                <span class="text-sm font-semibold break-words text-n-slate-12">
                  {{ ferramenta.name }}
                </span>
                <span class="sr-only">
                  {{
                    ferramenta.enabled
                      ? t(`${NS}.LISTA.ABRIR_LIGADA`)
                      : t(`${NS}.LISTA.ABRIR_DESLIGADA`)
                  }}
                </span>
                <span class="text-sm text-n-slate-11 line-clamp-2">
                  {{ ferramenta.description || t(`${NS}.LISTA.SEM_QUANDO`) }}
                </span>
              </span>
            </button>
            <FerramentaInterruptor
              :id="`ferramenta-interruptor-${ferramenta.id}`"
              class="mt-2"
              :ligado="ferramenta.enabled"
              :rotulo="t(`${NS}.USAR`, { ferramenta: ferramenta.name })"
              :texto-ligado="t(`${NS}.LIGADA`)"
              :texto-desligado="t(`${NS}.DESLIGADA`)"
              @alternar="emit('alternar', ferramenta, $event)"
            />
          </li>
        </ul>
      </template>
    </template>

    <AgenteBotao
      v-if="mostraCriarAMinha && mostraRodape"
      data-criar-minha
      variante="fantasma"
      icone="i-lucide-wrench"
      class="self-start"
      @click="emit('criar')"
    >
      {{ t(`${NS_VITRINE}.CRIAR_MINHA`) }}
    </AgenteBotao>

    <Teleport v-if="mostraRodape" defer :to="`#${rodape}`">
      <AgenteBotao
        id="ferramentas-adicionar"
        data-adicionar
        tamanho="lg"
        icone="i-lucide-plus"
        class="w-full sm:w-auto"
        @click="emit('adicionar')"
      >
        {{ t(`${NS}.LISTA.ADICIONAR`) }}
      </AgenteBotao>
    </Teleport>
  </div>
</template>
