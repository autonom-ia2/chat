<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteGaveta from '../AgenteGaveta.vue';
import AgenteBotao from '../AgenteBotao.vue';
import { ICONE_DA_REDE } from '../../composables/useAgentesDoPost';

// #2469 (PR 3a do #2436) — "Testar" do cartão do post: o dono escreve uma pergunta como se fosse um comentário, sem
// publicar nada. #2510: a tela mostra primeiro o que o motor faria com ele (a mesma decisão do Classificador, com o
// "para quem" e o assunto proibido do cuidado): mandar no privado, mandar o preço, passar para o dono, esconder, não
// responder. Só quando a decisão é mandar o privado vem o que o agente da porta escreveria (a mesma Escrita do motor):
// a mensagem do privado e a frase do comentário, as frases fixas (sem agente que escreva, com o motivo) ou "fica com
// você" (o agente não sabe). O dono não escolhe onde a resposta sai: quem escolhe é a decisão. No anúncio nas duas
// redes, o dono escolhe a rede (no Facebook o privado ainda não sai). #2487: a resposta que saiu de um arquivo só deste
// post diz qual ("Do seu material: …"). Sem teto: só o botão fica parado enquanto a resposta não chega.
const props = defineProps({
  detalhe: { type: Object, required: true },
  // testar({ pergunta, network }) do useAgenteDoPost.
  testar: { type: Function, required: true },
});

const emit = defineEmits(['fechar']);

const { t } = useI18n();
const KEY = 'AGENTS.AGENTE_DO_POST.TESTAR';
const FIELD =
  '!mb-0 w-full resize-none rounded-xl bg-n-solid-1 px-3 py-2 text-base leading-6 text-n-slate-12 ring-1 ring-inset ring-n-weak focus:outline-none focus:ring-2 focus:ring-n-brand';
const CHIP =
  'inline-flex items-center gap-2 px-4 text-sm font-medium border-0 rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11';
// Como cada decisão aparece: o privado sai (azul), fica com o dono (âmbar) ou a IA não faz nada em público (cinza).
const RECEBE = ['private', 'price'];
const COM_O_DONO = [
  'to_you',
  'owner_topic',
  'sem_certeza',
  'no_private',
  'kept_for_owner',
  'nao_sei',
];
const ICONE = {
  private: 'i-lucide-send',
  price: 'i-lucide-send',
  hide: 'i-lucide-eye-off',
  no_reply: 'i-lucide-message-circle-off',
};
const COR = {
  recebe: 'bg-n-blue-3 text-n-blue-11',
  dono: 'bg-n-amber-3 text-n-amber-11',
  nada: 'bg-n-alpha-2 text-n-slate-12',
};

const redes = computed(() => props.detalhe.portas.map(porta => porta.network));
const pergunta = ref('');
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
  resultado.value = await props.testar({
    pergunta: perguntado.value,
    network: rede.value,
  });
  perguntando.value = false;
};

const escrita = computed(() => resultado.value?.escrita);
// Era o caso do privado, mas o agente não sabe responder: o motor deixa com o dono, e o selo diz isso.
const decisao = computed(() =>
  escrita.value?.status === 'fica_com_o_dono'
    ? 'nao_sei'
    : resultado.value?.decisao
);
const tom = computed(() => {
  if (RECEBE.includes(decisao.value)) return 'recebe';
  return COM_O_DONO.includes(decisao.value) ? 'dono' : 'nada';
});
const icone = computed(() => ICONE[decisao.value] || 'i-lucide-hand');
const escreveu = computed(() =>
  ['escrito', 'frases_fixas'].includes(escrita.value?.status)
);

// A IA não respondeu agora (tentar de novo resolve) ou a conta está sem a chave; o resto é "não consegui testar".
const aviso = computed(() => {
  const codigo = resultado.value?.codigo;
  if (codigo === 'no_credential') return t(`${KEY}.MOTIVO.sem_chave`);
  return t(`${KEY}.${codigo === 'ai_unavailable' ? 'IA_FORA' : 'ERRO'}`);
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
        <template v-else-if="resultado.status === 'ready'">
          <div
            :data-decisao="decisao"
            :data-resposta-fica="decisao === 'nao_sei' || null"
            class="flex flex-col items-start gap-2"
          >
            <span class="text-xs font-semibold text-n-slate-11">
              {{ t(`${KEY}.FAZ`) }}
            </span>
            <span
              class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-semibold rounded-full"
              :class="COR[tom]"
            >
              <span class="size-4 shrink-0" :class="icone" aria-hidden="true" />
              {{ t(`${KEY}.DECISAO.${decisao}`) }}
            </span>
            <p
              v-if="resultado.motivo"
              data-decisao-motivo
              class="m-0 text-sm leading-6 text-n-slate-11"
            >
              {{ t(`${KEY}.POR_QUE`, { motivo: resultado.motivo }) }}
            </p>
          </div>
          <template v-if="escreveu">
            <div data-resposta-privado class="flex flex-col items-end gap-1">
              <span class="text-xs font-semibold text-n-slate-11">
                {{ t(`${KEY}.PRIVADO`) }}
              </span>
              <span
                class="max-w-[85%] px-3 py-2 text-sm leading-6 break-words rounded-2xl rounded-ee-md bg-n-blue-11 text-white dark:text-n-slate-1"
              >
                {{ escrita.privado }}
              </span>
            </div>
            <div
              v-if="escrita.publico"
              data-resposta-comentario
              class="flex flex-col gap-1 px-3 py-2 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xs font-semibold text-n-slate-11">
                {{ t(`${KEY}.PUBLICO`) }}
              </span>
              <span class="text-sm leading-6 text-n-slate-12">
                {{ escrita.publico }}
              </span>
            </div>
            <p
              v-if="escrita.status === 'frases_fixas'"
              data-resposta-frases-fixas
              class="m-0 text-xs leading-5 text-n-slate-11"
            >
              {{ t(`${KEY}.FRASES_FIXAS`) }}
              {{ t(`${KEY}.MOTIVO.${escrita.motivo}`) }}
            </p>
            <p
              v-if="escrita.material?.length"
              data-resposta-material
              class="flex items-center gap-1.5 m-0 text-xs leading-5 text-n-slate-11"
            >
              <span
                class="i-lucide-paperclip size-4 shrink-0"
                aria-hidden="true"
              />
              {{
                t(`${KEY}.DO_MATERIAL`, {
                  arquivos: escrita.material.join(', '),
                })
              }}
            </p>
          </template>
        </template>
        <p
          v-else
          data-resposta-aviso
          role="alert"
          class="m-0 text-sm leading-6 text-n-slate-12"
        >
          {{ aviso }}
        </p>
      </div>
    </form>
  </AgenteGaveta>
</template>
