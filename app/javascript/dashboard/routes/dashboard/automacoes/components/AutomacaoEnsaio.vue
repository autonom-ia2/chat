<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  nomeDaAcao,
  nomeDoAtributo,
} from 'dashboard/helper/automacaoEmPortugues';

// #859 — "Testar com casos reais": a regra roda nas conversas mais recentes só
// para mostrar o que faria. O servidor não executa nada (AutomationRules::Ensaio).
const props = defineProps({
  regraId: { type: Number, required: true },
  accountId: { type: Number, required: true },
});

const { t } = useI18n();

const QUANTIDADE = 10;

const estado = ref('parado');
const resultados = ref([]);
const semTeste = ref([]);
const erro = ref('');

const casaram = computed(
  () => resultados.value.filter(item => item.casou).length
);

const testar = async () => {
  estado.value = 'testando';
  erro.value = '';
  try {
    const { data } = await AutomationAPI.ensaio(props.regraId, QUANTIDADE);
    resultados.value = data?.resultados || [];
    semTeste.value = data?.sem_teste || [];
    estado.value = 'pronto';
  } catch (error) {
    erro.value = error?.response?.data?.error || t('AUTOMACOES.ENSAIO.ERRO');
    estado.value = 'erro';
  }
};

const fariaTexto = item =>
  t('AUTOMACOES.ENSAIO.FARIA', {
    acoes: item.faria.map(acao => nomeDaAcao(acao, t)).join(', '),
  });

const partesSemTeste = computed(() =>
  semTeste.value.map(chave => nomeDoAtributo(chave, t)).join(', ')
);

const linkDaConversa = item => ({
  name: 'inbox_conversation',
  params: { accountId: props.accountId, conversation_id: item.display_id },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    :aria-label="$t('AUTOMACOES.ENSAIO.TITULO')"
  >
    <h2 class="text-base font-medium text-n-slate-12">
      {{ $t('AUTOMACOES.ENSAIO.TITULO') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ $t('AUTOMACOES.ENSAIO.EXPLICA') }}
    </p>
    <Button
      data-testar
      :label="$t('AUTOMACOES.ENSAIO.BOTAO')"
      icon="i-lucide-flask-conical"
      slate
      faded
      class="min-h-11"
      :is-loading="estado === 'testando'"
      :disabled="estado === 'testando'"
      @click="testar"
    />

    <div role="status" aria-live="polite" class="flex flex-col gap-3">
      <p v-if="estado === 'testando'" class="text-sm text-n-slate-11">
        {{ $t('AUTOMACOES.ENSAIO.TESTANDO') }}
      </p>
      <p
        v-else-if="estado === 'erro'"
        data-ensaio-erro
        class="text-sm text-n-ruby-11"
      >
        {{ erro }}
      </p>
      <template v-else-if="estado === 'pronto'">
        <p
          v-if="!resultados.length"
          data-ensaio-vazio
          class="text-sm text-n-slate-11"
        >
          {{ $t('AUTOMACOES.ENSAIO.SEM_CONVERSA') }}
        </p>
        <p
          v-else
          data-ensaio-resumo
          class="text-sm font-medium text-n-slate-12"
        >
          {{
            $t('AUTOMACOES.ENSAIO.RESUMO', {
              casaram,
              total: resultados.length,
            })
          }}
        </p>
        <p
          v-if="semTeste.length"
          data-sem-teste
          class="text-sm text-n-amber-11"
        >
          {{ $t('AUTOMACOES.ENSAIO.SEM_TESTE', { partes: partesSemTeste }) }}
        </p>
        <ul v-if="resultados.length" class="flex flex-col gap-2">
          <li
            v-for="item in resultados"
            :key="item.conversation_id"
            data-ensaio-item
            class="flex flex-col gap-1 rounded-lg bg-n-alpha-1 p-3"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm text-n-slate-12 truncate">
                {{ item.contato || $t('AUTOMACOES.ENSAIO.CONTATO_SEM_NOME') }}
              </span>
              <span
                class="shrink-0 text-xs font-medium"
                :class="item.casou ? 'text-n-teal-11' : 'text-n-slate-11'"
              >
                {{
                  item.casou
                    ? $t('AUTOMACOES.ENSAIO.CASARIA')
                    : $t('AUTOMACOES.ENSAIO.NAO_CASARIA')
                }}
              </span>
            </div>
            <span v-if="item.casou" class="text-xs text-n-slate-11">
              {{ fariaTexto(item) }}
            </span>
            <router-link
              :to="linkDaConversa(item)"
              class="inline-flex items-center min-h-11 text-xs text-n-blue-11 hover:underline"
            >
              {{ $t('AUTOMACOES.ENSAIO.ABRIR_CONVERSA') }}
            </router-link>
          </li>
        </ul>
      </template>
    </div>
  </section>
</template>
