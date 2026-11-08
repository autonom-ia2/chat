<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteErro from '../AgenteErro.vue';
import { MAX_ARQUIVO } from '../../utils/pagina';

// #1427 (mockup 18 e 19) — o arquivo mandado no Testar não é lido no teste (decisão do Rodrigo, 19/10): a pessoa diz
// se o agente aprende com ele. "Sim, aprender" manda pela mesma API do que o agente sabe (autonomiaSources/create), e o
// material segue a leitura e a revisão do tema 4; "Não, obrigado" descarta, sem guardar nada. Um arquivo por vez, na
// ordem em que vieram. Só quem gerencia chega aqui (quem só vê tem o clipe só de foto).
const props = defineProps({
  arquivos: { type: Array, required: true },
  agenteId: { type: Number, required: true },
  nome: { type: String, required: true },
});

const emit = defineEmits(['resolvido', 'verSabe']);

const { t } = useI18n();
const store = useStore();
const enviando = ref(false);
const erro = ref(null);
const entrou = ref('');

const atual = computed(() => props.arquivos[0] || null);

watch(atual, () => {
  erro.value = null;
});

const aprender = async () => {
  const arquivo = atual.value;
  if (!arquivo || enviando.value) return;
  erro.value = null;
  if (arquivo.size > MAX_ARQUIVO) {
    erro.value = { mensagem: t('AGENTS.JORNADA.PAGINA.SABE.GRANDE') };
    return;
  }
  enviando.value = true;
  try {
    await store.dispatch('autonomiaSources/create', {
      agentId: props.agenteId,
      descriptor: { file: arquivo, kind: 'knowledge' },
    });
    entrou.value = arquivo.name;
    emit('resolvido', arquivo);
  } catch (falha) {
    // Recusa do servidor (422: tipo, tamanho, teto de materiais): o texto dele, sem "Tentar de novo".
    erro.value =
      falha?.status === 422
        ? { mensagem: falha.message }
        : { mensagem: '', tentar: true };
  } finally {
    enviando.value = false;
  }
};

const dispensar = () => {
  if (!atual.value || enviando.value) return;
  entrou.value = '';
  emit('resolvido', atual.value);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="entrou && !atual"
      data-aprendeu
      role="status"
      class="flex flex-col items-start gap-2 p-3 rounded-xl bg-n-teal-2 text-n-slate-12"
    >
      <p class="flex items-start gap-2 m-0 text-sm">
        <span
          class="i-lucide-book-open size-4 mt-0.5 shrink-0 text-n-teal-11"
          aria-hidden="true"
        />
        {{
          t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.ENTROU', {
            arquivo: entrou,
            nome,
          })
        }}
      </p>
      <button
        data-ver-sabe
        type="button"
        class="text-sm font-semibold underline ms-6 min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="emit('verSabe')"
      >
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.VER_SABE', { nome }) }}
      </button>
    </div>

    <section
      v-if="atual"
      data-aprender
      :aria-label="
        t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.PERGUNTA', {
          nome,
          arquivo: atual.name,
        })
      "
      class="flex flex-col gap-3 p-4 rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6"
    >
      <p
        class="flex items-start gap-2 m-0 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-file-text size-4 mt-0.5 shrink-0"
          aria-hidden="true"
        />
        <span class="min-w-0 [overflow-wrap:anywhere]">
          {{
            t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.PERGUNTA', {
              nome,
              arquivo: atual.name,
            })
          }}
        </span>
      </p>
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.TEXTO', { nome }) }}
      </p>
      <AgenteErro
        v-if="erro?.tentar"
        data-aprender-erro="falha"
        :titulo="t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.FALHOU')"
        :garantia="t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.FALHOU_GARANTIA')"
      />
      <AgenteErro
        v-else-if="erro"
        data-aprender-erro="recusa"
        tom="ambar"
        :titulo="erro.mensagem"
      />
      <div class="flex flex-wrap gap-2">
        <AgenteBotao data-sim :carregando="enviando" @click="aprender">
          {{
            erro?.tentar
              ? t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')
              : t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.SIM')
          }}
        </AgenteBotao>
        <AgenteBotao
          data-nao
          variante="contorno"
          :inativo="enviando"
          @click="dispensar"
        >
          {{ t('AGENTS.JORNADA.PAGINA.TESTE.APRENDER.NAO') }}
        </AgenteBotao>
      </div>
    </section>
  </div>
</template>
