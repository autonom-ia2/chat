<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { I18nT, useI18n } from 'vue-i18n';
import AgenteErro from '../AgenteErro.vue';
import CompositorAA from '../CompositorAA.vue';
import RespostasRapidas from '../RespostasRapidas.vue';
import MaterialDaConversa from './MaterialDaConversa.vue';

// #1181 PR2 (protótipo T03) — a conversa com o Construtor, à esquerda (no celular, a tela inteira,
// com o campo fixo embaixo). A IA fala primeiro; "ideias para começar" só antes da primeira resposta
// (preenchem o campo, a pessoa edita e manda). Clipe opcional para arquivo ou foto; nada é
// obrigatório. Falha vira cartão no lugar da resposta, com "Tentar de novo".
// Recebe o estado pronto (useConversaDeCriacao na página) e só emite o que a pessoa fez. O texto do
// campo é `v-model:rascunho`: a página o preenche ("Respondeu errado?") e o devolve quando o turno
// não entra (409).
const props = defineProps({
  falas: { type: Array, required: true },
  estadoDoMaterial: { type: Function, required: true },
  pensando: { type: Boolean, default: false },
  demorando: { type: Boolean, default: false },
  falhou: { type: Boolean, default: false },
  aviso: { type: String, default: null },
  fechada: { type: Boolean, default: false },
  respostas: { type: Number, default: 0 },
  ideias: { type: Array, default: () => [] },
  exemploDoCampo: { type: String, default: '' },
  // No celular a etapa é a tela inteira e o campo fica fixo embaixo, com a barra do slot `barra`.
  celular: { type: Boolean, default: false },
});

const emit = defineEmits(['enviar', 'tentarDeNovo', 'tirar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.CRIAR.CONTE';

const rascunho = defineModel('rascunho', { type: String, default: '' });
const compositor = ref(null);
const rolagem = ref(null);

const offline = computed(
  () =>
    props.falhou &&
    typeof navigator !== 'undefined' &&
    navigator.onLine === false
);
const mostrarIdeias = computed(
  () => props.ideias.length > 0 && props.respostas === 0 && !props.fechada
);
const mostrarLinhaDoAnexo = computed(
  () => props.respostas >= 1 && !props.fechada
);
const silencioso = computed(() => props.fechada && !props.celular);
const placeholder = computed(() =>
  props.respostas === 0 && props.exemploDoCampo
    ? props.exemploDoCampo
    : t('AGENTS.JORNADA.COMPOSITOR.ESCREVA')
);

const usarIdeia = async ideia => {
  rascunho.value = ideia;
  await nextTick();
  compositor.value?.focar();
};

const enviar = carga => {
  emit('enviar', carga);
  rascunho.value = '';
};

const abrirArquivos = () => compositor.value?.abrirArquivos();

// A conversa acompanha o fim a cada fala nova.
watch(
  () => [props.falas.length, props.pensando, props.falhou],
  async () => {
    await nextTick();
    const caixa = rolagem.value;
    if (caixa) caixa.scrollTop = caixa.scrollHeight;
  }
);

defineExpose({ abrirArquivos, focar: () => compositor.value?.focar() });
</script>

<template>
  <section
    :aria-label="t(`${NS}.ROTULO`)"
    class="flex flex-col min-w-0 min-h-0"
    :class="
      celular
        ? 'pb-64'
        : 'h-full overflow-hidden rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6'
    "
  >
    <div
      ref="rolagem"
      class="flex flex-col flex-1 min-h-0 gap-3"
      :class="celular ? '' : 'p-5 overflow-y-auto'"
    >
      <p
        class="flex items-start gap-2 p-3 m-0 text-sm rounded-xl bg-n-blue-2 text-n-slate-12"
      >
        <span class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
        <span>{{ t(`${NS}.INTRO`) }}</span>
      </p>
      <div
        data-conversa
        role="log"
        aria-live="polite"
        :aria-label="t(`${NS}.CONVERSA`)"
        class="flex flex-col gap-3"
      >
        <template v-for="fala in falas" :key="fala.chave">
          <MaterialDaConversa
            v-if="fala.de === 'material'"
            :material="fala.material"
            :estado="estadoDoMaterial(fala.material)"
            @mandar-outro="abrirArquivos"
            @tirar="emit('tirar', $event)"
          />
          <div
            v-else
            :data-fala="fala.de"
            class="flex items-end gap-2"
            :class="fala.de === 'voce' ? 'justify-end' : ''"
          >
            <span
              v-if="fala.de === 'assistente'"
              aria-hidden="true"
              class="grid rounded-full place-items-center size-8 shrink-0 bg-n-iris-3 text-n-iris-11"
            >
              <span class="i-lucide-sparkles size-4" />
            </span>
            <p
              class="px-4 py-2.5 m-0 text-base leading-relaxed whitespace-pre-line rounded-2xl max-w-[85%] text-n-slate-12"
              :class="
                fala.de === 'voce'
                  ? 'bg-n-blue-3 rounded-ee-md'
                  : 'bg-n-slate-2 rounded-es-md'
              "
            >
              <span class="sr-only">{{
                fala.de === 'voce' ? t(`${NS}.VOCE`) : t(`${NS}.ASSISTENTE`)
              }}</span>
              {{ fala.texto }}
            </p>
          </div>
        </template>
        <div
          v-if="pensando"
          data-pensando
          class="flex items-center gap-2 text-sm text-n-slate-11"
        >
          <span
            aria-hidden="true"
            class="grid rounded-full place-items-center size-8 shrink-0 bg-n-iris-3 text-n-iris-11"
          >
            <span class="i-lucide-sparkles size-4" />
          </span>
          <span class="flex gap-1" aria-hidden="true">
            <span
              v-for="ponto in 3"
              :key="ponto"
              class="rounded-full size-1.5 bg-n-slate-9 motion-safe:animate-pulse"
            />
          </span>
          <span>{{ t(`${NS}.PENSANDO`) }}</span>
        </div>
        <p
          v-if="pensando && demorando"
          role="status"
          data-demorando
          class="m-0 text-sm text-n-slate-11"
        >
          {{ t(`${NS}.DEMORANDO`) }}
        </p>
        <AgenteErro
          v-if="falhou && !pensando"
          data-erro-conversa
          :tom="offline ? 'ambar' : 'rubi'"
          :titulo="offline ? t('AGENTS.JORNADA.ERRO.OFFLINE') : t(`${NS}.ERRO`)"
          :garantia="t(`${NS}.ERRO_GARANTIA`)"
          :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
          @acao="emit('tentarDeNovo')"
        />
      </div>
      <RespostasRapidas
        v-if="mostrarIdeias"
        data-ideias
        :rotulo="t('AGENTS.JORNADA.COMUM.IDEIAS')"
        :opcoes="ideias"
        @escolher="usarIdeia"
      />
      <p
        v-if="mostrarLinhaDoAnexo"
        data-linha-anexo
        class="flex items-start gap-1.5 m-0 text-sm text-n-slate-11"
      >
        <span
          class="i-lucide-paperclip size-4 mt-3.5 shrink-0"
          aria-hidden="true"
        />
        <I18nT :keypath="`${NS}.ANEXO_FRASE`" tag="span" scope="global">
          <template #acao>
            <button
              type="button"
              data-mande-aqui
              class="font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @click="abrirArquivos"
            >
              {{ t(`${NS}.ANEXO_ACAO`) }}
            </button>
          </template>
        </I18nT>
      </p>
    </div>
    <div
      class="flex flex-col gap-2"
      :class="
        celular
          ? 'fixed inset-x-0 bottom-0 z-20 p-4 border-t bg-n-solid-1 border-n-weak'
          : 'p-4 border-t border-n-weak'
      "
    >
      <slot name="barra" />
      <p v-if="silencioso" class="px-1 m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.MAIS`) }}
      </p>
      <CompositorAA
        ref="compositor"
        v-model="rascunho"
        anexar
        :placeholder="placeholder"
        :enviando="pensando"
        @enviar="enviar"
      />
      <p
        v-if="pensando || aviso === 'espere'"
        data-espere
        role="status"
        class="px-1 m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.ESPERE`) }}
      </p>
    </div>
  </section>
</template>
