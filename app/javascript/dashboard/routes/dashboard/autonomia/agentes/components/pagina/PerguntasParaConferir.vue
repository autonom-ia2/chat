<script setup>
import { nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';

// #1181 PR3 (protótipo T09, sugCard) — "Perguntas dos seus clientes": as sugestões de FAQ que já
// existem (tiradas de conversas resolvidas), com "Ensinar esta", "Mudar e ensinar" e "Agora não".
// Usa a API de sugestões como está (approve, approve com edição, ignore). Só para quem gerencia;
// quem usa só monta com alguma pergunta na lista.
const props = defineProps({
  agentId: { type: Number, required: true },
  nomeAgente: { type: String, required: true },
  perguntas: { type: Array, required: true },
});

const emit = defineEmits(['resolvida']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.PAGINA.SABE';
const base = `pergunta-${useId()}`;
const editando = ref(null);
const formulario = ref({ question: '', answer: '' });
const ocupada = ref(null);
const falhou = ref(null);
const campoPergunta = ref(null);

const executar = async (sugestao, acao) => {
  if (ocupada.value) return;
  ocupada.value = sugestao.id;
  falhou.value = null;
  try {
    await acao();
    emit('resolvida', sugestao.id);
    editando.value = null;
  } catch {
    falhou.value = sugestao.id;
  } finally {
    ocupada.value = null;
  }
};

const ensinar = sugestao =>
  executar(sugestao, async () => {
    await FaqSuggestionsAPI.approve(props.agentId, sugestao.id);
    useAlert(t(`${NS}.ENSINOU`, { nome: props.nomeAgente }));
  });

const agoraNao = sugestao =>
  executar(sugestao, () =>
    FaqSuggestionsAPI.ignore(props.agentId, sugestao.id)
  );

const editar = async sugestao => {
  editando.value = sugestao.id;
  formulario.value = { question: sugestao.question, answer: sugestao.answer };
  await nextTick();
  campoPergunta.value?.[0]?.focus();
};

const ensinarEditada = sugestao => {
  const question = formulario.value.question.trim();
  const answer = formulario.value.answer.trim();
  if (!question || !answer) return;
  executar(sugestao, async () => {
    await FaqSuggestionsAPI.approve(props.agentId, sugestao.id, {
      question,
      answer,
    });
    useAlert(t(`${NS}.ENSINOU`, { nome: props.nomeAgente }));
  });
};
</script>

<template>
  <section
    data-perguntas
    :aria-labelledby="`${base}-titulo`"
    class="flex flex-col gap-3"
  >
    <div class="flex flex-col gap-1">
      <h3
        :id="`${base}-titulo`"
        class="m-0 text-base font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.PERGUNTAS`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.PERGUNTAS_TEXTO`) }}
      </p>
    </div>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="sugestao in perguntas"
        :key="sugestao.id"
        data-pergunta
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <form
          v-if="editando === sugestao.id"
          class="flex flex-col gap-3"
          @submit.prevent="ensinarEditada(sugestao)"
        >
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
          >
            {{ t(`${NS}.PERGUNTA`) }}
            <input
              ref="campoPergunta"
              v-model="formulario.question"
              class="px-3 text-base font-normal rounded-xl min-h-11 bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12"
            />
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-12"
          >
            {{ t(`${NS}.RESPOSTA_ROTULO`) }}
            <textarea
              v-model="formulario.answer"
              rows="3"
              class="px-3 py-2 text-base font-normal rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-slate-7 border-0 !mb-0 text-n-slate-12"
            />
          </label>
          <div class="flex flex-wrap gap-2">
            <AgenteBotao type="submit" :carregando="ocupada === sugestao.id">
              {{ t(`${NS}.ENSINAR`) }}
            </AgenteBotao>
            <AgenteBotao variante="contorno" @click="editando = null">
              {{ t('AGENTS.JORNADA.COMUM.CANCELAR') }}
            </AgenteBotao>
          </div>
        </form>
        <template v-else>
          <p
            :id="`${base}-${sugestao.id}`"
            class="m-0 text-sm font-semibold text-n-slate-12"
          >
            {{ sugestao.question }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t(`${NS}.RESPOSTA`, { texto: sugestao.answer }) }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <AgenteBotao
              data-ensinar
              variante="contorno"
              icone="i-lucide-check"
              :carregando="ocupada === sugestao.id"
              :aria-describedby="`${base}-${sugestao.id}`"
              @click="ensinar(sugestao)"
            >
              {{ t(`${NS}.ENSINAR_ESTA`) }}
            </AgenteBotao>
            <AgenteBotao
              data-mudar
              variante="fantasma"
              :aria-describedby="`${base}-${sugestao.id}`"
              @click="editar(sugestao)"
            >
              {{ t(`${NS}.MUDAR_E_ENSINAR`) }}
            </AgenteBotao>
            <AgenteBotao
              data-agora-nao
              variante="fantasma"
              :aria-describedby="`${base}-${sugestao.id}`"
              @click="agoraNao(sugestao)"
            >
              {{ t(`${NS}.AGORA_NAO`) }}
            </AgenteBotao>
          </div>
        </template>
        <AgenteErro
          v-if="falhou === sugestao.id"
          :titulo="t(`${NS}.ERRO`)"
          :garantia="t(`${NS}.ERRO_GARANTIA`)"
        />
      </li>
    </ul>
  </section>
</template>
