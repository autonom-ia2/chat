<script setup>
import { useI18n } from 'vue-i18n';
import AgenteAvatar from '../AgenteAvatar.vue';
import AgenteStatus from '../AgenteStatus.vue';
import AgenteInterruptor from '../AgenteInterruptor.vue';
import AgenteBotao from '../AgenteBotao.vue';
import MaisOpcoes from './MaisOpcoes.vue';
import { ESTADO } from '../../utils/estadoDoAgente';

// #1181 PR3 (protótipo T07, heroT07) — o único bloco navy da página: volta para a lista, foto, nome e
// onde responde. Quem gerencia tem o interruptor Atendendo/Parado (o estado fica só nele), a ação
// principal (Mudar conversando, ou Editar instruções no agente escrito à mão) e Mais opções. Quem só
// vê tem a pílula de estado no lugar do interruptor. Anéis decorativos como no AutomacaoHeroi.
defineProps({
  nome: { type: String, required: true },
  foto: { type: String, default: '' },
  estado: { type: String, required: true },
  onde: { type: String, default: '' },
  hrefLista: { type: String, required: true },
  podeGerenciar: { type: Boolean, default: false },
  // 'mudar' | 'instrucoes' | null
  acaoPrincipal: { type: String, default: null },
  itensMais: { type: Array, default: () => [] },
  alternando: { type: Boolean, default: false },
});

const emit = defineEmits(['voltarLista', 'alternar', 'acaoPrincipal', 'mais']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA';

const aoVoltar = evento => {
  if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.button) {
    return;
  }
  evento.preventDefault();
  emit('voltarLista');
};
</script>

<template>
  <section
    data-heroi
    aria-labelledby="agente-titulo"
    class="relative rounded-3xl bg-[#0D2344] dark:bg-[#12305E] text-white px-4 pt-4 pb-5 md:px-10 md:pt-7 md:pb-9"
  >
    <!-- Só os anéis são recortados: o menu de Mais opções precisa sair do herói. -->
    <span
      aria-hidden="true"
      class="absolute inset-0 overflow-hidden pointer-events-none rounded-3xl"
    >
      <span
        class="absolute rounded-full -end-16 -top-24 size-80 border-[3rem] border-n-blue-9 opacity-15"
      />
      <span
        class="absolute rounded-full end-32 -bottom-36 size-56 border-[2rem] border-n-blue-7 opacity-10"
      />
    </span>
    <div class="relative flex flex-col gap-3">
      <a
        data-voltar-lista
        :href="hrefLista"
        class="inline-flex items-center gap-2 text-sm font-semibold min-h-11 w-fit text-white/85 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
        @click="aoVoltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ t(`${NS}.VOLTAR_LISTA`) }}
      </a>
      <!-- Grade do protótipo (heroT07): celular = nome / interruptor + Mais / ação principal;
           tablet = nome + Mais / interruptor + ação; desktop = nome + ação + Mais / interruptor. -->
      <div
        data-grade
        class="grid items-center gap-x-4 gap-y-3 grid-cols-[minmax(0,1fr)_auto] [grid-template-areas:'id_id'_'sw_more'_'act_act'] md:[grid-template-areas:'id_more'_'sw_act'] lg:grid-cols-[minmax(0,1fr)_auto_auto] lg:[grid-template-areas:'id_act_more'_'sw_._.']"
      >
        <div
          class="flex items-start gap-3 md:items-center md:gap-4 min-w-0 [grid-area:id]"
        >
          <AgenteAvatar
            class="!size-12 !text-lg md:!size-16 md:!text-2xl ring-2 ring-white/30"
            :nome="nome"
            :src="foto"
            tom="atendendo"
          />
          <div class="flex flex-col gap-1 min-w-0">
            <div class="flex flex-wrap items-center gap-3">
              <h1
                id="agente-titulo"
                class="m-0 text-2xl font-bold leading-tight tracking-tight text-white break-words md:text-3xl"
              >
                {{ nome }}
              </h1>
              <AgenteStatus v-if="!podeGerenciar" :estado="estado" />
            </div>
            <p v-if="onde" data-onde class="m-0 text-base text-white/80">
              {{ onde }}
            </p>
          </div>
        </div>
        <div
          v-if="podeGerenciar && estado !== ESTADO.FALTA_TERMINAR"
          class="[grid-area:sw] justify-self-start lg:ps-20"
        >
          <AgenteInterruptor
            data-interruptor
            :ligado="estado === ESTADO.ATENDENDO"
            :rotulo="t(`${NS}.INTERRUPTOR`, { nome })"
            :desabilitado="alternando"
            @alternar="emit('alternar', $event)"
          />
        </div>
        <div
          v-if="podeGerenciar && acaoPrincipal"
          class="flex flex-col gap-1 [grid-area:act]"
        >
          <AgenteBotao
            data-acao-principal
            variante="branco"
            tamanho="lg"
            class="w-full md:w-auto max-md:min-h-14 max-md:text-lg"
            :icone="
              acaoPrincipal === 'mudar'
                ? 'i-lucide-message-circle'
                : 'i-lucide-pencil'
            "
            @click="emit('acaoPrincipal')"
          >
            {{
              acaoPrincipal === 'mudar'
                ? t(`${NS}.MUDAR`)
                : t(`${NS}.EDITAR_INSTRUCOES`)
            }}
          </AgenteBotao>
          <p
            v-if="acaoPrincipal === 'instrucoes'"
            class="m-0 text-sm text-center text-white/80"
          >
            {{ t(`${NS}.MANUAL_TEXTO`, { nome }) }}
          </p>
        </div>
        <MaisOpcoes
          v-if="itensMais.length"
          class="[grid-area:more] justify-self-end self-center"
          :rotulo="t(`${NS}.MAIS`)"
          :itens="itensMais"
          @escolher="emit('mais', $event)"
        />
      </div>
    </div>
  </section>
</template>
