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
import { useNomesDaConta } from '../../composables/useNomesDaConta';
import { carregarCatalogo, useCatalogo } from '../catalogo';
import { fraseDoGatilho, fraseDoPasso } from '../frases';
import { useEscolhasDosGatilhos } from '../useEscolhasDosGatilhos';
import { erroDaApi } from '../erroDaApi';

// #2414 F5 — a lista única de Automações: as novas e as do jeito antigo (as
// regras de hoje, que abrem na tela de hoje), cada uma em frase. As automações
// das etapas do funil continuam no funil; uma linha leva até lá.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const podeMudar = useCanManage('automation_manage');
const { catalogo } = useCatalogo();
const { nomes, carregarNomes } = useNomesDaConta();
const { escolhas: escolhasDoGatilho, carregar: carregarFunis } =
  useEscolhasDosGatilhos();
const globalConfig = useMapGetter('globalConfig/get');
const temFunil = computed(() => globalConfig.value?.crmKanbanEnabled === true);

const estado = ref('carregando');
const novas = ref([]);
const antigas = ref([]);
const mudando = ref(null);

// #2499 — o gatilho de card diz a etapa e o funil pelo nome. Os funis só são
// lidos se alguma automação tem gatilho com etapa ou funil. Se a leitura falhar
// (ou quem vê não enxerga o funil), a linha fica com a frase do catálogo, que
// continua certa, só sem o nome.
const lerNomesDosFunis = async () => {
  const tipos = novas.value.map(item => item.versao?.receita?.gatilho?.tipo);
  const deCard = (catalogo.value?.gatilhos || []).some(
    item => item.parametros?.length && tipos.includes(item.tipo)
  );
  if (!deCard) return;
  try {
    await carregarFunis();
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
      escolhasDoGatilho.value.nomes
    ),
    primeiro: passos[0] ? fraseDoPasso(passos[0], catalogo.value, t) : '',
    outros: Math.max(passos.length - 1, 0),
    ativa: automacao.ativa,
    doCard: alvoDoGatilho(automacao) === 'Crm::Card',
    fato: fatoDaSemana(automacao.semana),
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

const alternar = async linha => {
  if (!podeMudar.value || mudando.value) return;
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
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-6xl gap-8 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
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
          v-else-if="!linhas.length"
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

        <template v-else>
          <header class="flex flex-wrap items-end justify-between gap-5">
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
              :pode-mudar="podeMudar"
              :mudando="mudando === linha.chave"
              @abrir="abrir(linha)"
              @alternar="alternar(linha)"
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
      </div>
    </main>
  </section>
</template>
