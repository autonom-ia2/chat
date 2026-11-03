<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import { ICONE_DA_REDE } from '../../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436) — "Testar" do cartão do post: o dono escreve uma pergunta como se fosse um comentário, e o
// agente da porta escreve de verdade (a mesma Escrita do motor), no comentário ou no privado, sem publicar nada. No
// anúncio nas duas redes, o dono escolhe a rede: a tela não escolhe por ele. O que volta é o que o agente escreveria
// (só a Escrita: a decisão do motor de responder ou não o comentário fica fora do teste): o texto escrito, "Fica com você" (o agente não sabe), as frases fixas (sem agente que escreva, com o motivo) ou, no
// privado do Facebook, que ele ainda não sai. #2487: a resposta que saiu de um arquivo só deste post diz qual ("Do seu
// material: …"). Na rede em que o privado não sai, o motor também não publica a frase
// (ela só acompanha o privado): o texto escrito vem com esse aviso, para o teste não prometer o que o motor não faz. Sem teto: só o botão fica parado enquanto a resposta não chega.
const props = defineProps({
  detalhe: { type: Object, required: true },
  // testar({ pergunta, formato, network }) do useAgenteDoPost.
  testar: { type: Function, required: true },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.TESTAR';
const FIELD =
  '!mb-0 w-full resize-none rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';
const CHIP =
  'inline-flex items-center gap-2 px-4 text-sm font-medium border-0 rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11';
const FORMATOS = ['publico', 'privado'];

const redes = computed(() => props.detalhe.portas.map(porta => porta.network));
const pergunta = ref('');
const formato = ref('publico');
// Com uma rede só, ela; com duas, o dono escolhe.
const rede = ref(redes.value.length === 1 ? redes.value[0] : '');
const perguntando = ref(false);
const resultado = ref(null);
const perguntado = ref('');

const podePerguntar = computed(
  () => pergunta.value.trim() && rede.value && !perguntando.value
);

const perguntar = async () => {
  if (!podePerguntar.value) return;
  perguntando.value = true;
  perguntado.value = pergunta.value.trim();
  resultado.value = null;
  resultado.value = {
    ...(await props.testar({
      pergunta: perguntado.value,
      formato: formato.value,
      network: rede.value,
    })),
    formato: formato.value,
    rede: rede.value,
  };
  perguntando.value = false;
};

// A rede do teste deixa a IA mandar o privado? (o servidor diz por porta; hoje só o Instagram)
const publica = computed(
  () =>
    props.detalhe.portas.find(porta => porta.network === resultado.value?.rede)
      ?.private === true
);

const aviso = computed(() => {
  const r = resultado.value;
  if (!r) return '';
  if (r.status === 'no_private') return t(`${KEY}.SEM_PRIVADO`);
  if (r.status === 'erro') return t(`${KEY}.${r.ia ? 'IA_FORA' : 'ERRO'}`);
  if (r.status === 'frases_fixas') {
    const motivo = t(`${KEY}.MOTIVO.${r.motivo}`);
    return `${t(`${KEY}.FRASES_FIXAS`)} ${motivo}`;
  }
  return '';
});
</script>

<template>
  <AgenteGaveta :titulo="t(`${KEY}.TITULO`)" @fechar="emit('fechar')">
    <form
      data-gaveta-testar
      class="relative flex flex-col gap-4"
      @submit.prevent="perguntar"
    >
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ t(`${KEY}.ESCOLHA`) }}
      </p>
      <div
        v-if="redes.length > 1"
        data-testar-redes
        role="group"
        :aria-label="t(`${KEY}.REDE`)"
        class="flex flex-col gap-2"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t(`${KEY}.REDE`) }}
        </span>
        <span class="flex flex-wrap gap-2">
          <button
            v-for="item in redes"
            :key="item"
            type="button"
            :data-testar-rede="item"
            :aria-pressed="rede === item"
            :class="[
              CHIP,
              rede === item
                ? 'bg-n-slate-12 text-n-solid-1'
                : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1',
            ]"
            @click="rede = item"
          >
            <span class="size-4" :class="ICONE_DA_REDE[item]" />
            {{ t(`AGENTS.AGENTE_DO_POST.REDE.${item.toUpperCase()}`) }}
          </button>
        </span>
      </div>
      <div
        data-testar-formatos
        role="group"
        :aria-label="t(`${KEY}.ONDE`)"
        class="flex flex-col gap-2"
      >
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t(`${KEY}.ONDE`) }}
        </span>
        <span class="flex flex-wrap gap-2">
          <button
            v-for="item in FORMATOS"
            :key="item"
            type="button"
            :data-testar-formato="item"
            :aria-pressed="formato === item"
            :class="[
              CHIP,
              formato === item
                ? 'bg-n-slate-12 text-n-solid-1'
                : 'bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-1',
            ]"
            @click="formato = item"
          >
            {{ t(`${KEY}.${item.toUpperCase()}`) }}
          </button>
        </span>
      </div>
      <label for="post-pergunta" class="sr-only">
        {{ t(`${KEY}.SUA_PERGUNTA`) }}
      </label>
      <div class="flex flex-col gap-2 sm:flex-row">
        <input
          id="post-pergunta"
          v-model="pergunta"
          data-testar-pergunta
          type="text"
          maxlength="1000"
          :placeholder="t(`${KEY}.SUA_PERGUNTA`)"
          :class="FIELD"
          class="min-h-11"
        />
        <AgenteBotao
          type="submit"
          data-testar-perguntar
          :desabilitado="!podePerguntar"
        >
          {{ t(`${KEY}.PERGUNTAR`) }}
        </AgenteBotao>
      </div>
      <p class="m-0 text-xs leading-5 text-n-slate-11">
        {{ t(`${KEY}.SO_TESTE`) }}
      </p>

      <div
        v-if="perguntando || resultado"
        data-resposta
        aria-live="polite"
        class="flex flex-col gap-3 p-4 rounded-2xl ring-1 ring-inset ring-n-weak"
      >
        <p
          class="self-start max-w-[85%] px-3 py-2 m-0 text-sm leading-6 rounded-2xl rounded-es-md bg-n-alpha-2 text-n-slate-12"
        >
          {{ perguntado }}
        </p>
        <span
          v-if="perguntando"
          class="w-40 h-4 rounded bg-n-alpha-2 animate-pulse"
          aria-hidden="true"
        />
        <template v-else-if="resultado.status === 'escrito'">
          <div
            v-if="resultado.formato === 'publico'"
            data-resposta-comentario
            class="flex flex-col gap-1 px-3 py-2 rounded-xl bg-n-alpha-1"
          >
            <span class="text-xs font-semibold text-n-slate-11">
              {{ t(`${KEY}.PUBLICO`) }}
            </span>
            <span class="text-sm leading-6 text-n-slate-12">
              {{ resultado.texto }}
            </span>
          </div>
          <p
            v-if="resultado.formato === 'publico' && !publica"
            data-resposta-sem-publicar
            class="m-0 text-sm leading-6 text-n-slate-11"
          >
            {{ t(`${KEY}.SEM_PUBLICAR`) }}
          </p>
          <div
            v-if="resultado.formato === 'privado'"
            data-resposta-privado
            class="flex flex-col items-end gap-1"
          >
            <span class="text-xs font-semibold text-n-slate-11">
              {{ t(`${KEY}.PRIVADO`) }}
            </span>
            <span
              class="max-w-[85%] px-3 py-2 text-sm leading-6 break-words rounded-2xl rounded-ee-md bg-n-blue-11 text-white dark:text-n-slate-1"
            >
              {{ resultado.texto }}
            </span>
          </div>
          <p
            v-if="resultado.material?.length"
            data-resposta-material
            class="flex items-center gap-1.5 m-0 text-xs leading-5 text-n-slate-11"
          >
            <span
              class="i-lucide-paperclip size-4 shrink-0"
              aria-hidden="true"
            />
            {{
              t(`${KEY}.DO_MATERIAL`, {
                arquivos: resultado.material.join(', '),
              })
            }}
          </p>
        </template>
        <div
          v-else-if="resultado.status === 'fica_com_o_dono'"
          data-resposta-fica
          class="flex flex-col items-start gap-2"
        >
          <span
            class="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold rounded-full bg-n-amber-3 text-n-amber-11"
          >
            <span class="i-lucide-hand size-4" aria-hidden="true" />
            {{ t(`${KEY}.FICA`) }}
          </span>
          <p class="m-0 text-sm leading-6 text-n-slate-12">
            {{ t(`${KEY}.FICA_TEXTO`) }}
          </p>
        </div>
        <p
          v-else
          data-resposta-aviso
          :role="resultado.status === 'erro' ? 'alert' : null"
          class="m-0 text-sm leading-6 text-n-slate-12"
        >
          {{ aviso }}
        </p>
      </div>
    </form>
  </AgenteGaveta>
</template>
