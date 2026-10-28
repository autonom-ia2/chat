<script setup>
import { computed, nextTick, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { CONTACT_EXPORT_PERMISSION } from 'dashboard/constants/permissions';
import { CRM_AI_INTEGRATION_ID } from 'dashboard/helper/crmAiKey';
import desempenhoApi from 'dashboard/api/autonomia/desempenho';
import { useAgenteDaPagina } from '../composables/useAgenteDaPagina';
import { useFormatoDoPainel } from '../composables/useFormatoDoPainel';
import { agentesDeOutroSistema } from '../utils/outroSistema';
import { VARIANTES } from '../utils/desempenhoEstados';
import {
  FORMATOS,
  PERIODOS,
  PERIODO_PADRAO,
  fonteDoPainel,
} from '../utils/desempenhoFonte';
import FaixaDoPainel from '../components/desempenho/FaixaDoPainel.vue';
import BarraDoPainel from '../components/desempenho/BarraDoPainel.vue';
import EstadoDoPainel from '../components/desempenho/EstadoDoPainel.vue';
import DemoInterruptor from '../components/desempenho/DemoInterruptor.vue';
import Segmento from '../components/desempenho/comum/Segmento.vue';
import Ressalva from '../components/desempenho/comum/Ressalva.vue';
import AbaDetalhe from '../components/desempenho/detalhe/AbaDetalhe.vue';
import SecaoNumeros from '../components/desempenho/resumo/SecaoNumeros.vue';
import SecaoEvolucao from '../components/desempenho/resumo/SecaoEvolucao.vue';
import SecaoFunil from '../components/desempenho/resumo/SecaoFunil.vue';
import SecaoTemas from '../components/desempenho/resumo/SecaoTemas.vue';
import SecaoOrigem from '../components/desempenho/resumo/SecaoOrigem.vue';
import SecaoHorarios from '../components/desempenho/resumo/SecaoHorarios.vue';
import SecaoQualidade from '../components/desempenho/resumo/SecaoQualidade.vue';
import SecaoPessoa from '../components/desempenho/resumo/SecaoPessoa.vue';
import SecaoQuemProcura from '../components/desempenho/resumo/SecaoQuemProcura.vue';
import SecaoPerdas from '../components/desempenho/resumo/SecaoPerdas.vue';
import SecaoAcoes from '../components/desempenho/resumo/SecaoAcoes.vue';
import SecaoComoLer from '../components/desempenho/resumo/SecaoComoLer.vue';

// #2226 v2 — o painel de desempenho do agente. Faixa compacta (nome, período, exportar), barra fixa
// (Resumo | Detalhe, período, base e selo de conferência) e as abas. Mesma rota para o agente nosso
// e o de outro sistema (`?origem=webhook`, porque os ids podem coincidir, #1648). Tudo que muda a
// tela vive no endereço, para cada recorte ter link: ?aba=resumo|detalhe, ?periodo=7|30|90|tudo e,
// no protótipo, ?fonte=, ?anuncio=0 e ?estado=. Os números vêm do contrato v2 (desempenhoFonte).
const props = defineProps({
  agentId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const fmt = useFormatoDoPainel();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isAdmin: ehAdmin } = useAdmin();
const contaId = useMapGetter('getCurrentAccountId');
const bots = useMapGetter('agentBots/getBots');
// #2251: os números vêm da API; ?fonte=demo (e, no desenvolvimento, ?fonte=vida_real) continua para montar a tela.
const fonte = fonteDoPainel({ api: desempenhoApi });

const NS = 'AGENTS.DESEMPENHO2.A';
const ABAS = ['resumo', 'detalhe'];
// O que é da página (e não do filtro da aba Detalhe): sobrevive à troca de aba.
const DA_PAGINA = ['periodo', 'origem', 'fonte', 'anuncio', 'estado'];

const trocar = mudanca => {
  const query = Object.fromEntries(
    Object.entries({ ...route.query, ...mudanca }).filter(
      ([, valor]) => valor !== undefined && valor !== null
    )
  );
  router.replace({ query });
};

const deFora = computed(() => route.query?.origem === 'webhook');
const { agente: nosso, carregar: carregarNosso } = useAgenteDaPagina(
  toRef(props, 'agentId')
);
const dele = computed(() =>
  agentesDeOutroSistema(bots.value).find(
    bot => String(bot.id) === String(props.agentId)
  )
);

const aba = computed({
  get: () => (ABAS.includes(route.query?.aba) ? route.query.aba : 'resumo'),
  set: valor => trocar({ aba: valor }),
});
const periodo = computed({
  get: () =>
    PERIODOS.includes(route.query?.periodo)
      ? route.query.periodo
      : PERIODO_PADRAO,
  set: valor => trocar({ periodo: valor }),
});

const painel = ref(null);
const vidaReal = ref(false);
const exportacao = ref({});

const pedido = computed(() => ({
  accountId: contaId.value,
  agentId: props.agentId,
  origem: deFora.value ? 'webhook' : 'nosso',
  periodo: periodo.value,
  demo: {
    fonte: route.query?.fonte,
    anuncios: route.query?.anuncio !== '0',
    situacao: route.query?.estado,
  },
}));

// Cada formato: 'verificando' enquanto pergunta se o arquivo existe, 'pronto' ou 'sem_arquivo'.
// A conta de pedidos descarta a resposta de um período que a pessoa já trocou.
let pedidos = 0;
// Baixar o arquivo pede também contact_export (ESPEC 6.3); sem ela, os botões nem aparecem.
const podeExportar = usePermissionGranted(CONTACT_EXPORT_PERMISSION);
const verificarExportacao = async (atual, numero) => {
  if (!podeExportar.value) {
    exportacao.value = {};
    return;
  }
  exportacao.value = Object.fromEntries(
    FORMATOS.map(formato => [formato, { estado: 'verificando' }])
  );
  const achados = await Promise.all(
    FORMATOS.map(formato => fonte.exportar(atual, formato, pedido.value))
  );
  if (numero !== pedidos) return;
  exportacao.value = Object.fromEntries(
    FORMATOS.map((formato, i) => [
      formato,
      achados[i]
        ? { estado: 'pronto', ...achados[i] }
        : { estado: 'sem_arquivo' },
    ])
  );
};

const carregar = async () => {
  pedidos += 1;
  const numero = pedidos;
  const atual = await fonte.carregar(pedido.value);
  if (numero !== pedidos) return;
  painel.value = atual;
  verificarExportacao(atual, numero);
};
// A troca de aba não recarrega: só o que muda os números (período, fonte, anúncio, estado).
watch(() => JSON.stringify(pedido.value), carregar, { immediate: true });

// O interruptor da demonstração é ferramenta de quem monta o painel: só no ambiente de desenvolvimento
// (em produção a fonte é sempre a API).
const mostrarInterruptor = computed(() => Boolean(import.meta.env.DEV));

onMounted(async () => {
  // O nome e a foto do agente não seguram a página: sem eles, vale o nome dos dados.
  if (deFora.value) store.dispatch('agentBots/get');
  else carregarNosso();
  if (mostrarInterruptor.value) vidaReal.value = await fonte.temVidaReal();
});

const meta = computed(() => painel.value?.meta || null);
const ehDemo = computed(() => meta.value?.fonte === 'demo');
// Na vida real o nome vem dos dados (é o agente que foi lido); fora dela, do agente da conta.
const nome = computed(() => {
  const dosDados = meta.value?.agente?.nome || '';
  if (meta.value?.fonte === 'vida_real' && dosDados) return dosDados;
  return (deFora.value ? dele.value?.name : nosso.value?.name) || dosDados;
});
const abas = computed(() => [
  { value: 'resumo', label: t(`${NS}.BARRA.ABA.RESUMO`) },
  { value: 'detalhe', label: t(`${NS}.BARRA.ABA.DETALHE`) },
]);
const foto = computed(() =>
  deFora.value
    ? dele.value?.thumbnail || ''
    : nosso.value?.avatar_url || meta.value?.agente?.foto_url || ''
);

const situacao = computed(() => meta.value?.situacao || null);
// Sem números para mostrar: sem conversas no período, ou o painel vazio da API (sem leitura ou com falha).
const semConversas = computed(
  () => situacao.value === 'sem_conversas' || Boolean(painel.value?.vazio)
);
const estado = computed(() =>
  situacao.value && VARIANTES[situacao.value] ? situacao.value : null
);

const textoDoPeriodo = computed(() => {
  if (!meta.value?.periodo?.inicio) return '';
  const { chave } = meta.value.periodo;
  return t(`${NS}.FAIXA.PERIODO.${String(chave).toUpperCase()}`, {
    datas: fmt.periodo(meta.value.periodo),
  });
});

const hrefDe = destino => router.resolve(destino).href;
const destinoDoAgente = computed(() => ({
  name: 'autonomia_agent_panel',
  params: { agentId: props.agentId },
  query: deFora.value ? { origem: 'webhook' } : {},
}));
const migalha = computed(() => [
  {
    texto: t('AGENTS.DESEMPENHO.MIGALHA.AGENTES'),
    destino: { name: 'autonomia_agents_index' },
    href: hrefDe({ name: 'autonomia_agents_index' }),
  },
  {
    texto: nome.value,
    destino: destinoDoAgente.value,
    href: hrefDe(destinoDoAgente.value),
  },
  { texto: t('AGENTS.DESEMPENHO.MIGALHA.DESEMPENHO') },
]);
const DESTINO_ANUNCIOS = { name: 'campaigns_meta_ads_index' };

const rolarAte = id =>
  document
    .getElementById(id)
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });

const irParaConfianca = async () => {
  if (aba.value !== 'resumo') {
    aba.value = 'resumo';
    await nextTick();
  }
  rolarAte('como-ler');
};

// Do Resumo para a aba Detalhe já filtrada (tema, corte, perda ou outra tabela).
const irParaDetalhe = filtros => {
  const daPagina = Object.fromEntries(
    DA_PAGINA.filter(chave => route.query?.[chave] !== undefined).map(chave => [
      chave,
      route.query[chave],
    ])
  );
  router.replace({ query: { ...daPagina, aba: 'detalhe', ...filtros } });
};

const baixarPeloLink = (url, nomeDoArquivo) => {
  const link = document.createElement('a');
  link.href = url;
  link.download = nomeDoArquivo;
  link.rel = 'noopener';
  link.click();
};

// O arquivo da API (#2251) vem pelo axios, com a autenticação; o do protótipo é um link direto.
const exportar = async formato => {
  const arquivo = exportacao.value[formato];
  if (arquivo?.estado !== 'pronto') return;
  if (!arquivo.baixar) {
    baixarPeloLink(arquivo.url, arquivo.nome);
    return;
  }
  exportacao.value = {
    ...exportacao.value,
    [formato]: { ...arquivo, estado: 'baixando' },
  };
  try {
    const url = URL.createObjectURL(await arquivo.baixar());
    baixarPeloLink(url, arquivo.nome);
    setTimeout(() => URL.revokeObjectURL(url), 0);
  } catch {
    useAlert(t(`${NS}.FAIXA.EXPORTAR_FALHOU`));
  } finally {
    exportacao.value = { ...exportacao.value, [formato]: arquivo };
  }
};

const aoEstado = variante => {
  if (variante === 'sem_conversas') periodo.value = 'tudo';
  else if (variante === 'leitura_desligada') trocar({ estado: undefined });
  else if (['sem_ia', 'chave_recusada'].includes(variante) && ehAdmin.value) {
    router.push({
      name: 'settings_applications_integration',
      params: { integration_id: CRM_AI_INTEGRATION_ID },
    });
  } else rolarAte('pessoa');
};

const aoMigalha = item => router.push(item.destino);
</script>

<template>
  <div class="relative w-full h-full overflow-y-auto bg-n-background">
    <template v-if="!painel">
      <p role="status" class="sr-only">
        {{ t('AGENTS.DESEMPENHO.CARREGANDO') }}
      </p>
      <div data-esqueleto aria-hidden="true" class="flex flex-col">
        <div class="w-full px-4 py-4 md:px-6 bg-n-heroi dark:bg-n-heroi-escuro">
          <div class="flex items-center gap-3 mx-auto max-w-screen-2xl">
            <span
              class="rounded-full size-10 bg-white/15 motion-safe:animate-pulse"
            />
            <span
              class="w-1/4 h-6 rounded-lg bg-white/15 motion-safe:animate-pulse"
            />
          </div>
        </div>
        <div
          class="flex flex-col w-full gap-4 px-4 py-6 mx-auto md:px-6 max-w-screen-2xl"
        >
          <div class="grid grid-cols-2 gap-3 md:grid-cols-4 2xl:grid-cols-8">
            <span
              v-for="i in 8"
              :key="i"
              class="h-32 rounded-2xl bg-n-slate-3 motion-safe:animate-pulse"
            />
          </div>
          <div class="grid gap-4 xl:grid-cols-[1.45fr_1fr]">
            <span
              class="h-80 rounded-2xl bg-n-slate-3 motion-safe:animate-pulse"
            />
            <span
              class="h-80 rounded-2xl bg-n-slate-3 motion-safe:animate-pulse"
            />
          </div>
        </div>
      </div>
    </template>

    <template v-else>
      <FaixaDoPainel
        :nome="nome"
        :foto="foto"
        :migalha="migalha"
        :periodo="textoDoPeriodo"
        :dados-ate="meta.dados_ate || ''"
        :lido-ate="meta.lido_ate || ''"
        :exportacao="exportacao"
        :pode-exportar="podeExportar"
        @migalha="aoMigalha"
        @exportar="exportar"
      />
      <BarraDoPainel
        v-model:aba="aba"
        v-model:periodo="periodo"
        :periodos="PERIODOS"
        :base="semConversas ? null : meta.base"
        :conferidas="painel.confianca?.conferidas || 0"
        @confianca="irParaConfianca"
      />

      <main
        class="flex flex-col w-full gap-8 px-4 pt-6 mx-auto pb-28 md:pb-20 md:px-6 max-w-screen-2xl"
        aria-labelledby="desempenho-titulo"
      >
        <div class="md:hidden">
          <Segmento
            v-model="aba"
            data-abas-celular
            :opcoes="abas"
            :rotulo="t(`${NS}.BARRA.ABAS`)"
          />
        </div>
        <Ressalva
          v-if="meta.aviso_fonte"
          data-aviso-fonte
          :destaque="t(`${NS}.FONTE.FALHOU_TITULO`)"
          :texto="t(`${NS}.FONTE.FALHOU.${meta.aviso_fonte.toUpperCase()}`)"
        />
        <Ressalva
          v-if="meta.visibilidade?.ocultas"
          data-aviso-caixas
          :destaque="t(`${NS}.FONTE.CAIXAS_TITULO`)"
          :texto="
            t(`${NS}.FONTE.CAIXAS_TEXTO`, {
              n: fmt.n(meta.visibilidade.ocultas),
            })
          "
        />
        <Ressalva
          v-if="meta.lista"
          data-aviso-lista
          :destaque="t(`${NS}.FONTE.LISTA_TITULO`)"
          :texto="
            t(`${NS}.FONTE.LISTA_TEXTO`, {
              mostradas: fmt.n(meta.lista.mostradas),
              total: fmt.n(meta.lista.total),
            })
          "
        />
        <Ressalva
          v-if="meta.instrucao_mudou"
          data-aviso-instrucao
          :destaque="t(`${NS}.FONTE.INSTRUCAO_TITULO`)"
          :texto="t(`${NS}.FONTE.INSTRUCAO_TEXTO`)"
        />
        <Ressalva
          v-if="meta.pendentes > 0"
          data-aviso-pendentes
          :destaque="
            t(
              `${NS}.FONTE.PENDENTES_TITULO`,
              { n: fmt.n(meta.pendentes) },
              meta.pendentes
            )
          "
          :texto="t(`${NS}.FONTE.PENDENTES_TEXTO`)"
        />
        <Ressalva
          v-if="meta.nao_lidas > 0"
          data-aviso-nao-lidas
          :destaque="
            t(
              `${NS}.FONTE.NAO_LIDAS_TITULO`,
              { n: fmt.n(meta.nao_lidas) },
              meta.nao_lidas
            )
          "
          :texto="t(`${NS}.FONTE.NAO_LIDAS_TEXTO`)"
        />
        <Ressalva
          v-if="ehDemo"
          data-aviso-demo
          :destaque="t(`${NS}.FONTE.DEMO_TITULO`)"
          :texto="t(`${NS}.FONTE.DEMO_TEXTO`)"
        />
        <div v-if="deFora" data-de-fora class="flex flex-col gap-1">
          <p
            class="flex flex-wrap items-center gap-2 m-0 text-sm text-n-slate-12"
          >
            <span
              class="i-lucide-plug size-4 text-n-slate-11"
              aria-hidden="true"
            />
            {{ t('AGENTS.DESEMPENHO.DE_FORA') }}
            <template v-if="meta.instrucao">
              <span aria-hidden="true">{{
                t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR')
              }}</span>
              <span data-instrucao-colada>
                {{
                  t('AGENTS.DESEMPENHO.INSTRUCAO.COLADA', {
                    autor: meta.instrucao.autor,
                    data: fmt.data(meta.instrucao.data),
                  })
                }}
              </span>
            </template>
          </p>
          <p v-if="meta.instrucao" class="m-0 text-xs text-n-slate-11">
            {{ t('AGENTS.DESEMPENHO.INSTRUCAO.AVISO') }}
          </p>
        </div>

        <EstadoDoPainel
          v-if="estado"
          :variante="estado"
          :nome="nome"
          :pode-gerenciar="
            ehAdmin && (!painel.vazio || estado !== 'leitura_desligada')
          "
          :vazio="Boolean(painel.vazio)"
          @acao="aoEstado"
        />

        <template v-if="!semConversas">
          <template v-if="aba === 'resumo'">
            <SecaoNumeros :painel="painel" />
            <SecaoEvolucao :painel="painel" />
            <SecaoFunil :painel="painel" />
            <SecaoTemas :painel="painel" @detalhe="irParaDetalhe" />
            <SecaoOrigem
              :painel="painel"
              :eh-admin="ehAdmin"
              :href-ligar-anuncios="hrefDe(DESTINO_ANUNCIOS)"
              @ligar-anuncios="router.push(DESTINO_ANUNCIOS)"
            />
            <SecaoHorarios :painel="painel" />
            <SecaoQualidade :painel="painel" />
            <SecaoPessoa :painel="painel" />
            <SecaoQuemProcura :painel="painel" @detalhe="irParaDetalhe" />
            <SecaoPerdas :painel="painel" @detalhe="irParaDetalhe" />
            <SecaoAcoes :painel="painel" />
            <SecaoComoLer :painel="painel" />
          </template>
          <AbaDetalhe v-else :painel="painel" :nome="nome" />
        </template>

        <DemoInterruptor
          v-if="mostrarInterruptor"
          :fonte="meta.fonte || 'demo'"
          :anuncios="route.query?.anuncio !== '0'"
          :situacao="route.query?.estado || ''"
          :vida-real-disponivel="vidaReal"
          @trocar="trocar"
        />
      </main>
    </template>
  </div>
</template>
