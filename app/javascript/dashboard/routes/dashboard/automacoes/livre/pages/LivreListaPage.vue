<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useMapGetter } from 'dashboard/composables/store';
import AutomationAPI from 'dashboard/api/automation';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import LivreLinha from '../components/LivreLinha.vue';
import LivreConfirmarLigar from '../components/LivreConfirmarLigar.vue';
import AutomacaoHeroi from '../../components/AutomacaoHeroi.vue';
import AutomacaoPorta from '../../porta/components/AutomacaoPorta.vue';
import { usePorta } from '../../porta/usePorta';
import { useIrAoGuia } from '../../porta/useIrAoGuia';
import { useNomesDaConta } from '../../composables/useNomesDaConta';
import { carregarCatalogo, useCatalogo } from '../catalogo';
import { fraseDoGatilho, fraseDoPasso } from '../frases';
import { useEscolhasDosGatilhos } from '../useEscolhasDosGatilhos';
import { erroDaApi } from '../erroDaApi';
import { custoEmTexto } from '../custoDaIa';
import { oQueLigarFaz } from '../aoLigar';
import { useAccount } from 'dashboard/composables/useAccount';
import { FLAG as PASSOS_NOVOS } from '../passosNovos/passosNovos';
import { esquecerBlocos } from '../passosNovos/dadosDaConta';
import { resumoDaPesquisa } from '../passosNovos/frasesDosNovos';

// #2414 F5 — a lista única de Automações: as novas e as do jeito antigo (as
// regras de hoje, que abrem na tela de hoje), cada uma em frase. As automações
// das etapas do funil continuam no funil; uma linha leva até lá.
const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const podeMudar = useCanManage('automation_manage');
// #2889: com automacao_porta, a tela abre com a pergunta e os modelos; a lista vira "Suas automações".
// Só para quem pode montar: quem só vê fica com a lista, sem uma porta que não abre.
const { ligada: portaLigada } = usePorta();
const porta = computed(() => portaLigada.value && podeMudar.value);
const { pedir, falar } = useIrAoGuia();
const { catalogo } = useCatalogo();
const { nomes, carregarNomes } = useNomesDaConta();
const { escolhas: escolhasDoGatilho, carregar: carregarFunis } =
  useEscolhasDosGatilhos();
const globalConfig = useMapGetter('globalConfig/get');
const temFunil = computed(() => globalConfig.value?.crmKanbanEnabled === true);
// #2933: com os passos novos, a automação nova pode virar bloco.
const { isCloudFeatureEnabled } = useAccount();
const comBlocos = computed(() => isCloudFeatureEnabled(PASSOS_NOVOS));

const estado = ref('carregando');
const novas = ref([]);
const antigas = ref([]);
const mudando = ref(null);
// #2500 C2: { automacao_id: soma em US$ } dos últimos 30 dias; vazio sem
// financial_view. É só informação: se não carregar, a lista segue sem ele.
const custos = ref({});
const carregarCustos = async () => {
  try {
    custos.value = (await AutomacoesAPI.custos()).data.custos || {};
  } catch {
    custos.value = {};
  }
};

// #2499 — o gatilho de card diz a etapa e o funil pelo nome, e o de data, o
// campo. Os funis (ou os campos) só são lidos se alguma automação tem gatilho
// que os pede. Se a leitura falhar (ou quem vê não enxerga o funil), a linha
// fica com a frase do catálogo, que continua certa, só sem o nome.
const lerNomesDosFunis = async () => {
  const tipos = novas.value.map(item => item.versao?.receita?.gatilho?.tipo);
  const pecas = (catalogo.value?.gatilhos || [])
    .filter(item => tipos.includes(item.tipo))
    .flatMap(item => (item.parametros || []).map(parametro => parametro.peca));
  if (!pecas.length) return;
  try {
    await carregarFunis(pecas);
  } catch {
    // A frase do catálogo já está na tela.
  }
};

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const [respostaNovas, respostaAntigas] = await Promise.all([
      AutomacoesAPI.get(),
      AutomationAPI.get(),
      carregarCatalogo(),
    ]);
    novas.value = respostaNovas.data?.automacoes || [];
    antigas.value = respostaAntigas.data?.payload || [];
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
    return;
  }
  lerNomesDosFunis();
};

onMounted(() => {
  carregarNomes();
  carregar();
  carregarCustos();
});

// #2498 — o fato da semana: "Rodou 12 vezes esta semana · 1 parou".
const fatoDaSemana = semana => {
  if (!semana?.rodou) return t('AUTOMACAO_LIVRE.HISTORICO.SEMANA.NADA');
  const rodou = t(
    'AUTOMACAO_LIVRE.HISTORICO.SEMANA.RODOU',
    { n: semana.rodou },
    semana.rodou
  );
  if (!semana.parou) return rodou;
  const parou = t(
    'AUTOMACAO_LIVRE.HISTORICO.SEMANA.PAROU',
    { n: semana.parou },
    semana.parou
  );
  return `${rodou} · ${parou}`;
};

const alvoDoGatilho = automacao =>
  catalogo.value?.gatilhos.find(
    item => item.tipo === automacao.versao?.receita?.gatilho?.tipo
  )?.alvo;

const linhaDaNova = automacao => {
  const passos = automacao.versao?.receita?.passos || [];
  return {
    chave: `nova-${automacao.id}`,
    antiga: false,
    automacao,
    nome: automacao.nome,
    quando: fraseDoGatilho(
      automacao.versao?.receita?.gatilho,
      catalogo.value,
      t,
      escolhasDoGatilho.value.nomes,
      locale.value
    ),
    primeiro: passos[0] ? fraseDoPasso(passos[0], catalogo.value, t) : '',
    outros: Math.max(passos.length - 1, 0),
    ativa: automacao.ativa,
    bloco: Boolean(automacao.bloco),
    pausa: automacao.pausa?.frase || '',
    doCard: alvoDoGatilho(automacao) === 'Crm::Card',
    fato: [
      fatoDaSemana(automacao.semana),
      // #2936: a média da pesquisa e quantas pessoas responderam.
      resumoDaPesquisa(automacao.pesquisa, t, locale.value),
      custos.value[automacao.id] &&
        t('AUTOMACAO_LIVRE.LISTA.CUSTO_IA', {
          custo: custoEmTexto(custos.value[automacao.id], t, locale.value),
        }),
    ]
      .filter(Boolean)
      .join(' · '),
  };
};

const linhaDaAntiga = regra => {
  const descricao = descreverAutomacao(regra, { t, nomes: nomes.value });
  return {
    chave: `antiga-${regra.id}`,
    antiga: true,
    automacao: regra,
    nome: regra.name,
    quando: descricao.quando,
    primeiro: descricao.entao[0] || '',
    outros: Math.max(descricao.entao.length - 1, 0),
    ativa: regra.active,
  };
};

const linhas = computed(() => [
  ...[...novas.value].sort((a, b) => b.id - a.id).map(linhaDaNova),
  ...[...antigas.value].sort((a, b) => b.id - a.id).map(linhaDaAntiga),
]);
const ligadas = computed(
  () => linhas.value.filter(linha => linha.ativa).length
);

const ir = (name, params = {}) =>
  router.push({
    name,
    params: { accountId: route.params.accountId, ...params },
  });

const abrir = linha =>
  linha.antiga
    ? ir('automacoes_editar', { id: linha.automacao.id })
    : ir('automacoes_livre_editar', { id: linha.automacao.id });

const alternarAntiga = async regra => {
  const ligar = !regra.active;
  await AutomationAPI.update(regra.id, { active: ligar });
  antigas.value = antigas.value.map(item =>
    item.id === regra.id ? { ...item, active: ligar } : item
  );
  return ligar;
};

const alternarNova = async automacao => {
  const { data } = automacao.ativa
    ? await AutomacoesAPI.desligar(automacao.id)
    : await AutomacoesAPI.ligar(automacao.id, automacao.versao?.id);
  // Ligar e desligar respondem sem a receita: a frase da linha continua a dela.
  novas.value = novas.value.map(item =>
    item.id === automacao.id
      ? { ...item, ...data, versao: { ...item.versao, ...data.versao } }
      : item
  );
  return data.ativa;
};

// #2933: marcar desliga a automação (o bloco não liga sozinho); tirar a marca do
// bloco que uma automação ligada usa volta com os nomes delas.
const alternarBloco = async linha => {
  if (!podeMudar.value || mudando.value) return;
  mudando.value = linha.chave;
  try {
    const { data } = await AutomacoesAPI.marcarBloco(
      linha.automacao.id,
      !linha.bloco
    );
    novas.value = novas.value.map(item =>
      item.id === data.id ? { ...item, ...data } : item
    );
    esquecerBlocos();
    useAlert(
      t(
        data.bloco
          ? 'AUTOMACAO_LIVRE.LISTA.VIROU_BLOCO'
          : 'AUTOMACAO_LIVRE.LISTA.DEIXOU_DE_SER_BLOCO'
      )
    );
  } catch (erro) {
    const { mensagem } = erroDaApi(erro, t);
    useAlert(mensagem);
  } finally {
    mudando.value = null;
  }
};

const executarAlternar = async linha => {
  mudando.value = linha.chave;
  try {
    const ligou = linha.antiga
      ? await alternarAntiga(linha.automacao)
      : await alternarNova(linha.automacao);
    useAlert(
      ligou ? t('AUTOMACAO_LIVRE.LIGOU') : t('AUTOMACAO_LIVRE.DESLIGOU')
    );
  } catch (erro) {
    const { conflito, mensagem, problemas } = erroDaApi(erro, t);
    useAlert([mensagem, ...problemas].join(' '));
    if (conflito) carregar();
  } finally {
    mudando.value = null;
  }
};

// #2574 (F5.4): ligar a nova que manda mensagem, avisa a equipe ou usa IA
// pede confirmação, com o custo de cada passo de IA (a média dos últimos 30
// dias). Se o custo não carregar, a confirmação segue sem o valor.
const confirmarLigar = ref(null);
const aConfirmar = ref({ linha: null, custos: { com_valores: false } });
const lerCustos = async id => {
  try {
    return (await AutomacoesAPI.custosDaAutomacao(id)).data;
  } catch {
    return { com_valores: false };
  }
};

const pedeConfirmacao = linha =>
  !linha.antiga &&
  !linha.ativa &&
  oQueLigarFaz(linha.automacao.versao?.receita).pede;

const alternar = async linha => {
  if (!podeMudar.value || mudando.value) return;
  if (!pedeConfirmacao(linha)) {
    await executarAlternar(linha);
    return;
  }
  mudando.value = linha.chave;
  const custosDaLinha = await lerCustos(linha.automacao.id);
  mudando.value = null;
  aConfirmar.value = { linha, custos: custosDaLinha };
  confirmarLigar.value?.abrir();
};

const ligarConfirmada = () => {
  const { linha } = aConfirmar.value;
  if (linha) executarAlternar(linha);
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-6xl gap-8 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <AutomacaoHeroi
          v-if="porta"
          data-pergunta
          @pedir="pedir"
          @falar="falar"
        />

        <div
          v-if="estado === 'carregando'"
          data-carregando
          aria-busy="true"
          class="flex flex-col gap-4"
        >
          <span class="sr-only">{{
            $t('AUTOMACAO_LIVRE.LISTA.CARREGANDO')
          }}</span>
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <div
          v-else-if="estado === 'erro'"
          data-erro
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.LISTA.ERRO') }}
          </p>
          <Button
            :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <div
          v-else-if="!linhas.length && !porta"
          data-vazio
          class="flex flex-col items-center gap-5 px-6 py-16 text-center border rounded-3xl border-n-weak bg-n-solid-1"
        >
          <span
            class="grid text-white place-items-center size-16 rounded-2xl bg-n-heroi dark:bg-n-heroi-escuro"
          >
            <span class="i-lucide-zap size-8" aria-hidden="true" />
          </span>
          <p class="max-w-md mb-0 text-xl font-semibold text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.LISTA.VAZIO') }}
          </p>
          <Button
            data-comecar
            :label="$t('AUTOMACAO_LIVRE.LISTA.COMECAR')"
            icon="i-lucide-plus"
            size="lg"
            class="!min-h-12 !rounded-xl"
            :disabled="!podeMudar"
            @click="ir('automacoes_livre_nova')"
          />
        </div>

        <template v-else-if="linhas.length">
          <header
            v-if="porta"
            data-suas
            class="flex flex-wrap items-end justify-between gap-5"
          >
            <h2
              class="mb-0 text-2xl font-semibold tracking-tight text-n-slate-12"
            >
              {{ $t('AUTOMACAO_MODELOS.SUAS') }}
            </h2>
            <Button
              data-do-zero
              :label="$t('AUTOMACAO_MODELOS.DO_ZERO')"
              icon="i-lucide-list-plus"
              slate
              faded
              class="!min-h-11 !rounded-xl"
              @click="ir('automacoes_livre_nova')"
            />
          </header>
          <header v-else class="flex flex-wrap items-end justify-between gap-5">
            <div class="min-w-0">
              <h1
                class="text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
              >
                {{ $t('AUTOMACAO_LIVRE.LISTA.TITULO') }}
              </h1>
              <p class="mt-2 mb-0 text-base md:text-lg text-n-slate-11">
                {{ $t('AUTOMACAO_LIVRE.LISTA.SUBTITULO') }}
              </p>
            </div>
            <Button
              v-if="podeMudar"
              data-nova
              :label="$t('AUTOMACAO_LIVRE.LISTA.NOVA')"
              icon="i-lucide-plus"
              size="lg"
              class="!min-h-12 !rounded-xl"
              @click="ir('automacoes_livre_nova')"
            />
          </header>

          <div class="flex flex-wrap gap-3">
            <span
              class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <span
                class="rounded-full size-2.5 bg-n-teal-9"
                aria-hidden="true"
              />
              {{ $t('AUTOMACAO_LIVRE.LISTA.LIGADAS', { n: ligadas }, ligadas) }}
            </span>
            <span
              v-if="antigas.length"
              class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-amber-6 bg-n-amber-2 text-n-slate-12"
            >
              <span
                class="i-lucide-history size-4 text-n-amber-11"
                aria-hidden="true"
              />
              {{
                $t(
                  'AUTOMACAO_LIVRE.LISTA.ANTIGAS',
                  { n: antigas.length },
                  antigas.length
                )
              }}
            </span>
          </div>

          <ul class="flex flex-col gap-3.5 p-0 m-0 list-none">
            <LivreLinha
              v-for="linha in linhas"
              :key="linha.chave"
              :nome="linha.nome"
              :quando="linha.quando"
              :primeiro="linha.primeiro"
              :outros="linha.outros"
              :fato="linha.fato"
              :ativa="linha.ativa"
              :antiga="linha.antiga"
              :do-card="linha.doCard"
              :pausa="linha.pausa || ''"
              :bloco="Boolean(linha.bloco)"
              :pode-ser-bloco="comBlocos && !linha.antiga"
              :pode-mudar="podeMudar"
              :mudando="mudando === linha.chave"
              @abrir="abrir(linha)"
              @alternar="alternar(linha)"
              @bloco="alternarBloco(linha)"
            />
          </ul>
        </template>

        <div
          v-if="estado === 'pronto' && temFunil"
          data-do-funil
          class="flex flex-wrap items-center gap-3 px-4 py-2 text-[0.9375rem] rounded-xl bg-n-alpha-1 text-n-slate-11"
        >
          <span class="i-lucide-square-kanban size-5" aria-hidden="true" />
          <span class="flex-1 min-w-0">
            {{ $t('AUTOMACAO_LIVRE.LISTA.DO_FUNIL') }}
          </span>
          <Button
            data-ver-funil
            :label="$t('AUTOMACAO_LIVRE.LISTA.VER_FUNIL')"
            icon="i-lucide-arrow-right"
            slate
            link
            class="min-h-11"
            @click="ir('crm_kanban_index')"
          />
        </div>

        <div
          v-if="porta && estado === 'pronto' && !linhas.length"
          data-do-zero-vazio
          class="flex justify-end"
        >
          <Button
            data-do-zero
            :label="$t('AUTOMACAO_MODELOS.DO_ZERO')"
            icon="i-lucide-list-plus"
            slate
            faded
            class="!min-h-11 !rounded-xl"
            @click="ir('automacoes_livre_nova')"
          />
        </div>

        <!-- #2889: com a porta, os modelos vêm depois das automações da pessoa, para ela achar as dela primeiro. -->
        <AutomacaoPorta v-if="porta" />

        <LivreConfirmarLigar
          ref="confirmarLigar"
          :receita="aConfirmar.linha?.automacao.versao?.receita || null"
          :custos="aConfirmar.custos"
          @ligar="ligarConfirmada"
        />
      </div>
    </main>
  </section>
</template>
