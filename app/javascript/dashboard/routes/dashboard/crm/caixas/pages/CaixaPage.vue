<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmCaixasAPI from 'dashboard/api/crmCaixas';
import { useFase2 } from 'dashboard/routes/dashboard/autonomia/agentes/composables/useFase2';
import CaixaEtapas from '../components/CaixaEtapas.vue';
import CaixaIcone from '../components/CaixaIcone.vue';
import EtapaFunis from '../components/EtapaFunis.vue';
import EtapaPessoas from '../components/EtapaPessoas.vue';
import EtapaSozinho from '../components/EtapaSozinho.vue';
import EtapaConfira from '../components/EtapaConfira.vue';
import {
  faltaTriagem,
  funisDaCaixa,
  faltaEscolherLegado,
  legadoPendente,
  paraSalvar,
  primeiroNome,
} from '../helpers/caixa';
import {
  formularioDaCaixa,
  salvarDaCaixa,
  temAgentesIa,
  temAgentesNaTela,
  erroDosAgentes,
} from '../helpers/agentesIa';

// #1149 — uma caixa em quatro etapas e um Salvar só (R16): o que chega, quem
// cuida do quê, o que o sistema faz sozinho e a conferência em frases.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
// #1570 — a Fase 2 dos Agentes vem da conta, a mesma fonte da tela dos Agentes.
const fase2 = useFase2();

const ULTIMA = 4;
const CHAVES = ['CHEGA', 'CUIDAM', 'SOZINHO', 'CONFIRA'];

const estado = ref('carregando');
const funis = ref([]);
const original = ref(null);
const form = ref(null);
const etapa = ref(1);
const alcancada = ref(1);
const salvando = ref(false);
const caixaSalva = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const dados = await CrmCaixasAPI.buscar(route.params.inboxId);
    funis.value = dados.funis;
    caixaSalva.value = dados.caixa;
    original.value = formularioDaCaixa(dados.caixa, fase2.value);
    form.value = formularioDaCaixa(dados.caixa, fase2.value);
    // Caixa já no CRM: todas as etapas abertas para ir direto ao que mudar.
    alcancada.value = dados.caixa.crm_enabled ? ULTIMA : 1;
    etapa.value = Number(route.query.etapa) || 1;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(carregar);

// O payload da conta pode chegar (ou mudar) depois da caixa: os agentes de IA
// aparecem ou somem com ele, a partir do que está salvo. Se continuam como
// estavam, a edição em curso fica.
watch(fase2, ligada => {
  if (!caixaSalva.value || !form.value) return;
  const aparece = temAgentesIa(caixaSalva.value, ligada);
  if (aparece === Boolean(form.value.ai_agents)) return;
  // Uma cópia para cada: o formulário muda a lista, o original não.
  const agentes = () => formularioDaCaixa(caixaSalva.value, ligada).ai_agents;
  original.value = { ...original.value, ai_agents: agentes() };
  form.value = { ...form.value, ai_agents: agentes() };
});

const funisMarcados = computed(() =>
  form.value ? funisDaCaixa(form.value, funis.value) : []
);
const umFunil = computed(() => funisMarcados.value.length === 1);
const semTriagem = computed(() =>
  form.value ? faltaTriagem(form.value) : false
);

// O modo precisa existir na quantidade de funis atual: "assim que chega" é só
// de caixa com um funil; sugerir e criar ao entender, de caixa com vários.
watch(umFunil, unico => {
  if (!form.value) return;
  const { modo } = form.value;
  if (unico && modo !== 'off') form.value.modo = 'chegou';
  if (!unico && modo === 'chegou') form.value.modo = 'auto';
});

// Com um funil só, a etapa inicial precisa ser dele: trocar de funil volta para
// a primeira etapa do novo.
watch(funisMarcados, marcados => {
  if (!form.value || marcados.length !== 1) return;
  const { stages } = marcados[0];
  const daquiMesmo = stages.some(
    stage => stage.id === form.value.default_stage_id
  );
  if (!daquiMesmo) form.value.default_stage_id = stages[0]?.id || null;
});

// Funil novo na caixa entra para quem já cuidava de todos os funis dela (o
// "Todos os funis" de hoje, que também é o padrão de quem nunca foi mexido).
watch(
  () => form.value?.pipeline_ids,
  (atuais, anteriores) => {
    if (!atuais || !anteriores) return;
    const novos = atuais.filter(id => !anteriores.includes(id));
    if (!novos.length) return;
    form.value.people = form.value.people.map(pessoa => {
      const cuidavaDeTodos = anteriores.every(id =>
        pessoa.pipeline_ids.includes(id)
      );
      if (pessoa.administrator || !cuidavaDeTodos) return pessoa;
      return { ...pessoa, pipeline_ids: [...pessoa.pipeline_ids, ...novos] };
    });
  }
);

// #1140 — quem recebe cada assunto vem do servidor, pela regra do motor de
// entrega, com o que está marcado agora (ainda sem salvar). A tela não decide
// quem recebe. Só a última pergunta vale.
const quemRecebe = ref(null);
const quemRecebeErro = ref(false);
let perguntaAtual = '';
const conferirQuemRecebe = async ({ deNovo = false } = {}) => {
  const dados = paraSalvar(form.value);
  const pergunta = JSON.stringify([dados.pipeline_ids, dados.people]);
  if (!deNovo && pergunta === perguntaAtual) return;
  perguntaAtual = pergunta;
  quemRecebe.value = null;
  quemRecebeErro.value = false;
  try {
    const resposta = await CrmCaixasAPI.quemRecebe(route.params.inboxId, dados);
    if (pergunta === perguntaAtual) quemRecebe.value = resposta;
  } catch {
    if (pergunta !== perguntaAtual) return;
    quemRecebeErro.value = true;
    // Voltar às etapas 3 e 4 pergunta de novo.
    perguntaAtual = '';
  }
};

// Nas etapas 3 e 4 o exemplo e a conferência dizem quem recebe.
watch(
  () => estado.value === 'pronto' && etapa.value >= 3,
  precisa => {
    if (precisa) conferirQuemRecebe();
  },
  { immediate: true }
);

const exemplo = computed(() => {
  const funil = funisMarcados.value[0];
  if (!funil) return {};
  const etapaInicial =
    funil.stages.find(item => item.id === form.value.default_stage_id) ||
    funil.stages[0];
  const primeiroId = quemRecebe.value?.funis?.[String(funil.id)]?.[0];
  const proxima = form.value.people.find(pessoa => pessoa.id === primeiroId);
  return {
    funil: funil.name,
    etapa: etapaInicial?.name || '',
    pessoa: proxima ? primeiroNome(proxima) : t('CRM_CAIXAS.SOZINHO.ALGUEM'),
  };
});

const funisSemIa = computed(() =>
  funisMarcados.value
    .filter(funil => !funil.ai_enabled)
    .map(funil => funil.name)
);

const bloqueio = computed(() => {
  if (etapa.value === 2 && semTriagem.value) {
    return t('CRM_CAIXAS.PESSOAS.FALTA_TRIAGEM_CURTO');
  }
  if (etapa.value >= 2 && faltaEscolherLegado(form.value)) {
    return t('CRM_CAIXAS.PESSOAS.LEGADO_CURTO');
  }
  return '';
});

// #1447: com os agentes de IA na etapa 2, o subtítulo fala deles também.
const subtitulo = computed(() =>
  etapa.value === 2 && temAgentesNaTela(form.value?.ai_agents)
    ? t('CRM_CAIXAS.CUIDAM.SUBTITULO_COM_AGENTES')
    : t(`CRM_CAIXAS.${CHAVES[etapa.value - 1]}.SUBTITULO`)
);

const ir = numero => {
  etapa.value = numero;
  alcancada.value = Math.max(alcancada.value, numero);
  document.querySelector('[data-caixa-editor]')?.scrollTo({ top: 0 });
};

const continuar = () => {
  if (bloqueio.value) return;
  // Sem funil nenhum, não há quem cuida nem o que fazer: vai direto conferir.
  ir(funisMarcados.value.length ? etapa.value + 1 : ULTIMA);
};

const voltarParaLista = (query = {}) =>
  router.push({ name: 'crm_caixas', params: route.params, query });

// R6: manter deixa cada agente em "Só as que atende" (o que vê hoje); mudar
// vale o que estiver marcado. A escolha vai junto no salvamento.
const escolherLegado = escolha => {
  form.value.legado = escolha;
  if (escolha !== 'manter') return;
  form.value.people = form.value.people.map(pessoa =>
    pessoa.administrator ? pessoa : { ...pessoa, only_own: true }
  );
};

const salvar = async () => {
  if (semTriagem.value || faltaEscolherLegado(form.value)) {
    ir(2);
    return;
  }
  salvando.value = true;
  try {
    await CrmCaixasAPI.salvar(
      route.params.inboxId,
      salvarDaCaixa(form.value, original.value)
    );
    useAlert(t('CRM_CAIXAS.EDITOR.SALVOU'));
    voltarParaLista({ salva: route.params.inboxId });
  } catch (error) {
    // R7 e os agentes de IA (#1447) conferidos também no servidor: volta para
    // a etapa que resolve.
    const codigo = error?.response?.data?.error?.code;
    const { ehDosAgentes: dosAgentes, alerta } = erroDosAgentes(codigo);
    if (codigo === 'crm.caixas.sem_triagem' || dosAgentes) ir(2);
    if (alerta) {
      useAlert(t(`CRM_CAIXAS.EDITOR.${alerta}`));
    } else if (dosAgentes) {
      useAlert(t('CRM_CAIXAS.EDITOR.ERRO_AGENTES'));
    } else {
      useAlert(t('CRM_CAIXAS.EDITOR.FALHOU'));
    }
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <section class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
    <main data-caixa-editor class="flex-1 overflow-y-auto">
      <div
        class="mx-auto flex w-full max-w-4xl flex-col gap-6 px-4 pb-32 pt-6 md:px-8 md:pt-8"
      >
        <button
          type="button"
          class="-ms-2 inline-flex min-h-11 items-center gap-1.5 self-start rounded-lg px-2 text-[0.9375rem] font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="voltarParaLista()"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ $t('CRM_CAIXAS.LISTA.TITULO') }}
        </button>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{ $t('CRM_CAIXAS.LISTA.CARREGANDO') }}</span>
          <div class="h-12 w-72 animate-pulse rounded-xl bg-n-alpha-2" />
          <div class="h-80 animate-pulse rounded-2xl bg-n-alpha-2" />
        </div>

        <div
          v-else-if="estado === 'erro'"
          role="alert"
          class="flex flex-col items-start gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-8"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('CRM_CAIXAS.EDITOR.ERRO') }}
          </p>
          <Button
            :label="$t('CRM_CAIXAS.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="!min-h-11"
            @click="carregar"
          />
        </div>

        <template v-else>
          <header class="flex items-center gap-3">
            <CaixaIcone
              :canal="form.inbox.channel_type"
              :caixa-id="form.inbox.id"
              grande
            />
            <h1
              class="mb-0 min-w-0 truncate text-2xl font-bold tracking-tight text-n-slate-12 md:text-3xl"
            >
              {{ form.inbox.name }}
            </h1>
          </header>

          <CaixaEtapas :atual="etapa" :alcancada="alcancada" @ir="ir" />

          <div class="flex flex-col gap-1">
            <h2 class="mb-0 text-xl font-semibold text-n-slate-12 md:text-2xl">
              {{ $t(`CRM_CAIXAS.${CHAVES[etapa - 1]}.TITULO`) }}
            </h2>
            <p class="mb-0 text-base text-n-slate-11">
              {{ subtitulo }}
            </p>
          </div>

          <EtapaFunis
            v-if="etapa === 1"
            v-model:pipeline-ids="form.pipeline_ids"
            v-model:etapa-inicial="form.default_stage_id"
            :funis="funis"
          />
          <EtapaPessoas
            v-else-if="etapa === 2"
            v-model:pessoas="form.people"
            v-model:ai-agents="form.ai_agents"
            :funis="funisMarcados"
            :todos-os-funis="funis"
            :falta-triagem="semTriagem"
            :legado="legadoPendente(form)"
            :escolha="form.legado || null"
            :robo="form.agent_bot || null"
            @escolher-legado="escolherLegado"
          />
          <EtapaSozinho
            v-else-if="etapa === 3"
            v-model:modo="form.modo"
            :um-funil="umFunil"
            :funis-sem-ia="funisSemIa"
            v-bind="exemplo"
          />
          <EtapaConfira
            v-else
            :form="form"
            :original="original"
            :funis="funis"
            :quem-recebe="quemRecebe"
            :quem-recebe-erro="quemRecebeErro"
            @conferir-de-novo="conferirQuemRecebe({ deNovo: true })"
          />
        </template>
      </div>
    </main>

    <footer
      v-if="estado === 'pronto'"
      class="border-t border-n-weak bg-n-solid-1 px-4 py-3 md:px-8"
    >
      <div
        class="mx-auto flex w-full max-w-4xl flex-wrap items-center justify-end gap-3"
      >
        <p
          v-if="bloqueio"
          role="status"
          class="mb-0 me-auto text-[0.9375rem] text-n-ruby-11"
        >
          {{ bloqueio }}
        </p>
        <Button
          v-if="etapa > 1"
          :label="$t('CRM_CAIXAS.EDITOR.VOLTAR')"
          slate
          ghost
          class="!min-h-11"
          @click="ir(etapa - 1)"
        />
        <Button
          v-if="etapa < 4"
          data-continuar
          :label="$t('CRM_CAIXAS.EDITOR.CONTINUAR')"
          icon="i-lucide-arrow-right"
          trailing-icon
          :disabled="Boolean(bloqueio)"
          class="!min-h-11"
          @click="continuar"
        />
        <Button
          v-else
          data-salvar
          :label="$t('CRM_CAIXAS.EDITOR.SALVAR')"
          icon="i-lucide-check"
          :is-loading="salvando"
          class="!min-h-11"
          @click="salvar"
        />
      </div>
    </footer>
  </section>
</template>
