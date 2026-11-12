<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';
import { usePodeMontarAutomacao } from 'dashboard/composables/usePodeMontarAutomacao';
import AutomacaoLinha from 'dashboard/routes/dashboard/automacoes/components/AutomacaoLinha.vue';
import { carregarCatalogo } from 'dashboard/routes/dashboard/automacoes/livre/catalogo';
import {
  fraseDoGatilho,
  fraseDoPasso,
} from 'dashboard/routes/dashboard/automacoes/livre/frases';
import { semPermissao, useFonteDasAutomacoes } from './useAutomacaoNoCrm';

// #2414 F6.5 (protótipo só da demo) — "Automações desta etapa", na etapa aberta do funil: as regras antigas da etapa
// (reais, do store, com o selo "Jeito antigo") e as automações novas com gatilho nesta etapa (entrou, saiu ou
// parado), numa lista só, na mesma linha da lista de Automações (AutomacaoLinha: frase, "Alterar" e interruptor).
// A ação principal é "Nova automação para esta etapa", que abre o editor com o gatilho da etapa. O aviso da F6.4
// aparece quando há automação de entrar ou sair. Sair da gaveta com o funil mudado pergunta antes.
const props = defineProps({
  etapaId: { type: [Number, String], required: true },
  etapaNome: { type: String, default: '' },
  // A marca do seed no funil (marcaDaDemo).
  marca: { type: Object, required: true },
  // A gaveta "Editar funil" tem mudança ainda não salva.
  temMudanca: { type: Boolean, default: false },
});

const emit = defineEmits(['antigas']);

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const fonte = useFonteDasAutomacoes(props.marca);
const podeMontar = usePodeMontarAutomacao();
const tituloId = `etapa-automacoes-${useId()}`;

const E = 'AUTOMACAO_NO_CRM.ETAPA';
const DE_ENTRAR_OU_SAIR = ['card.entrou_na_etapa', 'card.saiu_da_etapa'];
const ACAO_ANTIGA = {
  create_follow_up: 'CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_FOLLOW_UP',
  assign_owner: 'CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_ASSIGN',
  move_stage: 'CRM_KANBAN.STAGE_AUTOMATIONS.ACTION_MOVE',
};

const antigas = ref([]);
const novas = ref([]);
const catalogo = ref(null);
const estado = ref('carregando');
const mudando = ref(null);
const erroLigar = ref('');
const saindo = ref(null);
const botaoSair = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  saindo.value = null;
  erroLigar.value = '';
  try {
    const [daEtapa, doMotor] = await Promise.all([
      store.dispatch('crmKanban/fetchStageAutomations', props.etapaId),
      fonte.automacoesDaEtapa(props.etapaId),
    ]);
    catalogo.value = doMotor.length ? await carregarCatalogo() : null;
    antigas.value = daEtapa || [];
    novas.value = doMotor;
    estado.value = 'pronto';
  } catch (erro) {
    antigas.value = [];
    novas.value = [];
    estado.value = semPermissao(erro) ? 'sem-acesso' : 'erro';
  }
};
watch(() => props.etapaId, carregar, { immediate: true });

const passoAntigo = passo => {
  const titulo = passo.action_config?.title;
  if (passo.action_type === 'create_follow_up' && titulo)
    return t(`${E}.PASSO_RETORNO`, { titulo });
  return ACAO_ANTIGA[passo.action_type]
    ? t(ACAO_ANTIGA[passo.action_type])
    : t(`${E}.PASSO_OUTRO`);
};

const linhaDaAntiga = regra => ({
  chave: `antiga-${regra.id}`,
  antiga: true,
  original: regra,
  automacao: { name: regra.name, active: regra.enabled !== false },
  descricao: {
    quando: t(
      regra.trigger_event === 'on_exit'
        ? `${E}.QUANDO_SAI`
        : `${E}.QUANDO_ENTRA`
    ),
    entao: (regra.steps || []).map(passoAntigo),
  },
  entraOuSai: true,
});

const linhaDaNova = item => ({
  chave: `nova-${item.id}`,
  antiga: false,
  original: item,
  automacao: { name: item.nome, active: item.ativa },
  descricao: {
    quando: fraseDoGatilho(
      item.receita.gatilho,
      catalogo.value,
      t,
      { etapa: { [props.etapaId]: props.etapaNome } },
      locale.value
    ),
    entao: item.receita.passos.map(passo =>
      fraseDoPasso(passo, catalogo.value, t)
    ),
  },
  entraOuSai: DE_ENTRAR_OU_SAIR.includes(item.receita.gatilho.tipo),
});

const linhas = computed(() => [
  ...antigas.value.map(linhaDaAntiga),
  ...novas.value.map(linhaDaNova),
]);
const mostraAviso = computed(
  () => estado.value === 'pronto' && linhas.value.some(item => item.entraOuSai)
);

const trocar = (lista, id, novo) =>
  lista.map(item => (item.id === id ? novo : item));

const alternar = async linha => {
  mudando.value = linha.chave;
  erroLigar.value = '';
  const ligar = !linha.automacao.active;
  try {
    if (linha.antiga) {
      const salva = await store.dispatch('crmKanban/saveStageAutomation', {
        stageId: props.etapaId,
        automation: { id: linha.original.id, enabled: ligar },
      });
      antigas.value = trocar(
        antigas.value,
        linha.original.id,
        salva || { ...linha.original, enabled: ligar }
      );
    } else {
      const ativa = await fonte.ligarNaEtapa(linha.original, ligar);
      novas.value = trocar(novas.value, linha.original.id, {
        ...linha.original,
        ativa,
      });
    }
  } catch {
    erroLigar.value = t(`${E}.ERRO_LIGAR`);
  } finally {
    mudando.value = null;
  }
};

const conta = () => ({ accountId: route.params.accountId });

// Sair da gaveta perde o que não foi salvo no funil: com mudança, pergunta antes.
const sair = async destino => {
  if (!props.temMudanca) {
    router.push(destino);
    return;
  }
  saindo.value = destino;
  await nextTick();
  botaoSair.value?.$el?.focus();
};

// As automações novas do ensaio não existem no motor: "Alterar" abre a lista de Automações.
const abrir = linha =>
  linha.antiga
    ? emit('antigas')
    : sair({ name: 'automacoes_lista', params: conta() });

const nova = () =>
  sair({
    name: 'automacoes_livre_nova',
    params: conta(),
    query: { gatilho: 'card.entrou_na_etapa', etapa: String(props.etapaId) },
  });
</script>

<template>
  <!-- `contents`: sem permissão, a parte some sem deixar espaço. -->
  <div class="contents">
    <section
      v-if="estado !== 'sem-acesso'"
      data-etapa-automacoes
      class="flex flex-col gap-4"
      :aria-labelledby="tituloId"
    >
      <div class="flex flex-col gap-1">
        <h4 :id="tituloId" class="mb-0 text-base font-semibold text-n-slate-12">
          {{ t(`${E}.TITULO`) }}
        </h4>
        <p
          v-if="linhas.length"
          class="mb-0 text-[0.9375rem] leading-relaxed text-n-slate-11"
        >
          {{ t(`${E}.AJUDA`) }}
        </p>
      </div>

      <p
        v-if="estado === 'carregando'"
        class="mb-0 text-[0.9375rem] text-n-slate-11"
      >
        {{ t(`${E}.CARREGANDO`) }}
      </p>
      <div
        v-else-if="estado === 'erro'"
        data-etapa-automacoes-erro
        class="flex flex-wrap items-center gap-2"
      >
        <p class="mb-0 text-base text-n-slate-12">{{ t(`${E}.ERRO_LISTA`) }}</p>
        <Button
          :label="t(`${E}.TENTAR`)"
          slate
          faded
          class="!min-h-11"
          @click="carregar"
        />
      </div>
      <p
        v-else-if="!linhas.length"
        data-etapa-automacoes-vazio
        class="mb-0 text-base text-n-slate-12"
      >
        {{ t(`${E}.VAZIO`) }}
      </p>
      <ul v-else class="m-0 flex list-none flex-col gap-3 p-0">
        <AutomacaoLinha
          v-for="linha in linhas"
          :key="linha.chave"
          :data-automacao-da-etapa="linha.chave"
          :automacao="linha.automacao"
          :descricao="linha.descricao"
          :pode-mudar="podeMontar"
          :mudando="mudando === linha.chave"
          @abrir="abrir(linha)"
          @alternar="alternar(linha)"
        >
          <template v-if="linha.antiga" #selo>
            <span
              data-jeito-antigo
              class="rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-xs font-medium text-n-slate-11"
            >
              {{ t(`${E}.JEITO_ANTIGO`) }}
            </span>
          </template>
        </AutomacaoLinha>
      </ul>

      <p v-if="erroLigar" role="alert" class="mb-0 text-sm text-n-ruby-11">
        {{ erroLigar }}
      </p>

      <div
        v-if="saindo"
        data-sair-sem-salvar
        class="flex flex-col gap-3 rounded-xl bg-n-amber-2 px-4 py-3"
      >
        <p class="mb-0 text-base text-n-amber-12">
          {{ t(`${E}.SAIR_PERGUNTA`) }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            :ref="el => (botaoSair = el)"
            data-sair-sim
            :label="t(`${E}.SAIR_SIM`)"
            ruby
            class="!min-h-11"
            @click="router.push(saindo)"
          />
          <Button
            data-sair-ficar
            :label="t(`${E}.FICAR`)"
            slate
            faded
            class="!min-h-11"
            @click="saindo = null"
          />
        </div>
      </div>
      <template v-else-if="estado === 'pronto'">
        <Button
          v-if="podeMontar"
          data-nova-automacao
          :label="t(`${E}.NOVA`)"
          icon="i-lucide-plus"
          blue
          class="!min-h-11 w-full sm:w-auto sm:self-start"
          @click="nova"
        />
        <p v-else class="mb-0 text-sm text-n-amber-11">
          {{ t(`${E}.SO_VER`) }}
        </p>
      </template>

      <p
        v-if="mostraAviso"
        data-aviso-nao-dispara
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-2 px-4 py-3 text-sm text-n-amber-11"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" aria-hidden="true" />
        {{ t(`${E}.AVISO`) }}
      </p>
    </section>
  </div>
</template>
