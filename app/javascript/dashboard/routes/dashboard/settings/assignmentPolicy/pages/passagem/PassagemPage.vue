<script setup>
import { computed, nextTick, provide, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import PassagemHeroi from './PassagemHeroi.vue';
import PassagemResumo from './PassagemResumo.vue';
import PassagemQuando from './PassagemQuando.vue';
import PassagemQuem from './PassagemQuem.vue';
import PassagemComo from './PassagemComo.vue';
import PassagemEtapas from './PassagemEtapas.vue';
import PassagemEtapa from './PassagemEtapa.vue';
import PassagemAvisos from './PassagemAvisos.vue';
import PassagemLado from './PassagemLado.vue';
import { usePassagem } from './usePassagem';
import { usePassagemRodape } from './usePassagemRodape';
import { usePassagemVolta } from './usePassagemVolta';
import { ETAPA_PROPRIA } from './passagem';

// #1385 — a tela "Atribuição e transferência para humano", na família das telas de funil (#1384): herói
// escuro com o nome do funil, cartões-frase com "Alterar", prévia com a cliente de exemplo à direita e um botão azul por
// tela. Como no funil, cada tela de detalhe salva na hora; o resumo só tem "Fechar". A seta, o X e o "Fechar" voltam
// para de onde a pessoa veio: a lista de funis ou, aberto pelo Kanban, o Kanban no mesmo funil (usePassagemVolta).
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const H = 'CRM_KANBAN.PASSAGEM.HEROI';
const todas = useMapGetter('agents/getAgents');
const { doFunil } = usePassagemVolta();

const passagem = usePassagem();
const {
  carregando,
  falhou,
  funis,
  caixas,
  equipe,
  iaDoFunilLigada,
  agentesIa,
  regra,
  etapas,
  alterado,
  regrasIncompletas,
} = passagem;

// #1593: os agentes de IA entram na lista de quem pode receber como "ia:<id>", com o selo; as pessoas continuam
// com o id do usuário. Os nomes saem dessa lista em todas as telas e na prévia.
const agentesDaPassagem = computed(() => agentesIa?.value || []);
const todasComIa = computed(() => [
  ...(Array.isArray(todas.value) ? todas.value : []),
  ...agentesDaPassagem.value.map(agente => ({
    id: `ia:${agente.id}`,
    name: agente.name,
    ia: true,
    parado: agente.parado,
    caixas: agente.caixas,
  })),
]);
provide('passagemIa', { agentes: agentesDaPassagem, caixas });

const view = ref('home');
const passo = ref(0);
const etapaId = ref(null);
const mostrarErros = ref(false);
const rolagem = useTemplateRef('rolagem');

const funilId = computed(() => Number(route.params.pipelineId));
const funil = computed(
  () => funis.value.find(item => item.id === funilId.value)?.name || ''
);
const etapa = computed({
  get: () => etapas.value.find(item => item.id === etapaId.value) || null,
  set: nova => {
    etapas.value = etapas.value.map(item =>
      item.id === nova.id ? nova : item
    );
  },
});

const irPara = async (novaView, { guardar = true } = {}) => {
  if (guardar) passagem.guardarCopia();
  mostrarErros.value = false;
  view.value = novaView;
  await nextTick();
  rolagem.value?.scrollTo({ top: 0 });
  document.querySelector('[data-view-title]')?.focus();
};

const abrirEtapa = item => {
  etapaId.value = item.id;
  passo.value = 0;
  irPara('etapa');
};

// Fechar volta para de onde a pessoa veio. Numa tela de detalhe com alteração, pede para salvar ou cancelar antes.
const fechar = () => {
  if (alterado.value) {
    useAlert(t('CRM_KANBAN.PASSAGEM.SALVE_ANTES_DE_SAIR'));
    return;
  }
  router.push(doFunil.value.destino);
};

const { rodape, voltar } = usePassagemRodape({
  passagem,
  view,
  passo,
  etapa,
  funilId,
  mostrarErros,
  irPara,
  fechar,
  t,
});
const temRodape = computed(
  () =>
    !carregando.value &&
    !falhou.value &&
    Boolean(rodape.value.principal || rodape.value.status)
);

// A frase do herói diz o que acontece hoje neste funil, e não uma promessa.
const textoDoResumo = computed(() => {
  if (!iaDoFunilLigada.value || !caixas.value.length) {
    return t(`${H}.HOME_TEXTO_FALTA`);
  }
  if (!regra.value.enabled) {
    const algumaEtapa = etapas.value.some(item => item.modo === ETAPA_PROPRIA);
    return t(
      algumaEtapa ? `${H}.HOME_TEXTO_SO_ETAPAS` : `${H}.HOME_TEXTO_DESLIGADA`
    );
  }
  return t(`${H}.HOME_TEXTO`);
});

const heroi = computed(() => {
  const chave = view.value.toUpperCase();
  if (view.value === 'home') {
    return {
      voltar: doFunil.value.rotulo,
      rotulo: t(`${H}.HOME_ROTULO`),
      titulo: funil.value,
      texto: textoDoResumo.value,
    };
  }
  if (view.value === 'etapa') {
    return {
      voltar: t(`${H}.ETAPAS_ROTULO`),
      rotulo: t(`${H}.ETAPA_ROTULO`),
      icone: 'i-lucide-columns-3',
      titulo: etapa.value?.nome || '',
      texto: t(`${H}.ETAPA_TEXTO`),
    };
  }
  const icones = {
    QUANDO: 'i-lucide-message-circle-question',
    QUEM: 'i-lucide-users',
    COMO: 'i-lucide-send',
    ETAPAS: 'i-lucide-columns-3',
  };
  return {
    voltar: funil.value,
    rotulo: t(`${H}.${chave}_ROTULO`),
    icone: icones[chave],
    titulo: t(`${H}.${chave}_TITULO`),
    texto: t(`${H}.${chave}_TEXTO`),
  };
});

const aoVoltar = () => {
  if (view.value === 'home') {
    fechar();
    return;
  }
  voltar();
};

// Do resumo, o liga/desliga e o "Corrigir agora" gravam na hora, como o resto. Se não der, volta como estava.
const salvarJa = async campos => {
  const antes = regra.value;
  regra.value = { ...antes, ...campos };
  const deuCerto = await passagem.salvar(funilId.value);
  if (deuCerto) return;
  regra.value = antes;
  useAlert(t('CRM_KANBAN.PASSAGEM.ERRO_SALVAR'));
};

// A lista de etapas não edita nada: só as telas de detalhe guardam uma cópia para o "Cancelar".
const abrir = novaView => irPara(novaView, { guardar: novaView !== 'etapas' });

watch(
  funilId,
  id => {
    view.value = 'home';
    mostrarErros.value = false;
    store.dispatch('agents/get');
    if (id) passagem.carregar(id);
  },
  { immediate: true }
);
</script>

<template>
  <section
    data-passagem
    class="flex h-full w-full flex-col overflow-hidden bg-n-solid-1 font-inter"
  >
    <PassagemHeroi v-bind="heroi" @voltar="aoVoltar" @fechar="fechar" />

    <div ref="rolagem" class="min-h-0 flex-1 overflow-y-auto">
      <div
        v-if="carregando"
        aria-busy="true"
        class="flex flex-col gap-4 px-5 py-7 sm:px-8"
      >
        <span class="sr-only">{{ t('CRM_KANBAN.PASSAGEM.CARREGANDO') }}</span>
        <div class="h-11 w-72 animate-pulse rounded-xl bg-n-alpha-2" />
        <div
          v-for="n in 4"
          :key="n"
          class="h-24 max-w-3xl animate-pulse rounded-2xl bg-n-alpha-2"
        />
      </div>

      <div v-else-if="falhou" class="px-5 py-7 sm:px-8">
        <div
          role="alert"
          class="flex max-w-3xl flex-wrap items-center gap-3 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-[0.9375rem] text-n-ruby-11"
        >
          <span class="min-w-0 flex-1">{{
            t('CRM_KANBAN.PASSAGEM.ERRO_CARREGAR')
          }}</span>
          <Button
            :label="t('CRM_KANBAN.PASSAGEM.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="!min-h-11"
            @click="passagem.carregar(funilId)"
          />
        </div>
      </div>

      <div
        v-else
        class="grid min-h-full grid-cols-[minmax(0,1fr)] lg:grid-cols-[minmax(0,1fr)_30rem]"
        :class="{ 'max-md:pb-24': !temRodape }"
      >
        <main class="flex min-w-0 flex-col gap-5 px-5 py-7 sm:px-8">
          <template v-if="view === 'home'">
            <PassagemAvisos
              v-if="!iaDoFunilLigada || !caixas.length"
              :ia-ligada="iaDoFunilLigada"
              :sem-caixa="!caixas.length"
              :funil-id="funilId"
            />
            <PassagemResumo
              :regra="regra"
              :etapas="etapas"
              :pessoas="todasComIa"
              :incompletas="regrasIncompletas"
              :mostrar-erros="mostrarErros"
              :salvando="passagem.salvando.value"
              :ia-ligada="iaDoFunilLigada"
              @abrir="abrir"
              @ligar="salvarJa({ enabled: $event })"
              @corrigir="salvarJa({ prefer_online: true })"
            />
          </template>
          <PassagemQuando
            v-else-if="view === 'quando'"
            v-model="regra"
            nome="funil"
          />
          <PassagemQuem
            v-else-if="view === 'quem'"
            v-model="regra"
            nome="funil"
            :equipe="equipe"
            :todas="todasComIa"
            :mostrar-erros="mostrarErros"
          />
          <PassagemComo
            v-else-if="view === 'como'"
            v-model="regra"
            nome="funil"
            :equipe="equipe"
            :todas="todasComIa"
            :mostrar-erros="mostrarErros"
          />
          <PassagemEtapas
            v-else-if="view === 'etapas'"
            :etapas="etapas"
            :pessoas="todasComIa"
            :funil-ligado="regra.enabled"
            :incompletas="regrasIncompletas"
            :mostrar-erros="mostrarErros"
            @alterar="abrirEtapa"
          />
          <PassagemEtapa
            v-else-if="view === 'etapa' && etapa"
            v-model="etapa"
            v-model:passo="passo"
            :funil-ligado="regra.enabled"
            :equipe="equipe"
            :todas="todasComIa"
            :mostrar-erros="mostrarErros"
          />
        </main>

        <aside
          class="min-w-0 border-t border-n-weak bg-n-alpha-1 px-5 py-7 sm:px-8 lg:border-s lg:border-t-0 lg:px-5"
        >
          <PassagemLado
            :view="view"
            :passo="passo"
            :regra="regra"
            :etapas="etapas"
            :etapa="etapa"
            :funil="funil"
            :equipe="equipe"
            :todas="todasComIa"
            :ia-ligada="iaDoFunilLigada"
            :sem-caixa="!caixas.length"
          />
        </aside>
      </div>
    </div>

    <!-- No celular, o rodapé fica por cima do botão de menu flutuante (z-40 no Dashboard): com o rodapé na tela, o
         menu some e não cobre "Cancelar"/"Voltar"; sem rodapé, a folga embaixo da página deixa o menu sobre o vazio. -->
    <footer
      v-if="temRodape"
      data-passagem-rodape
      class="relative z-50 flex min-h-[4.5rem] flex-wrap items-center gap-x-2 gap-y-3 border-t border-n-weak bg-n-solid-1 px-5 py-3 sm:px-8"
    >
      <p
        v-if="rodape.status"
        role="status"
        class="mb-0 flex min-w-0 basis-full items-center gap-2 text-[0.9375rem] font-medium sm:basis-auto"
        :class="rodape.status.tom"
      >
        <span
          class="size-4 shrink-0"
          :class="rodape.status.icone"
          aria-hidden="true"
        />
        {{ rodape.status.texto }}
      </p>
      <span
        class="flex-1"
        :class="{ 'max-sm:hidden': !rodape.principal?.neutro }"
        aria-hidden="true"
      />
      <Button
        v-if="rodape.secundaria"
        :label="rodape.secundaria.rotulo"
        slate
        ghost
        :disabled="passagem.salvando.value"
        class="!min-h-11"
        @click="rodape.secundaria.acao"
      />
      <Button
        v-if="rodape.principal"
        data-passagem-principal
        :label="rodape.principal.rotulo"
        :icon="rodape.principal.icone"
        :trailing-icon="Boolean(rodape.principal.depois)"
        :is-loading="Boolean(rodape.principal.carregando)"
        :color="rodape.principal.neutro ? 'slate' : 'blue'"
        :variant="rodape.principal.neutro ? 'faded' : 'solid'"
        class="!min-h-11 min-w-32"
        :class="{ 'max-sm:flex-1': !rodape.principal.neutro }"
        @click="rodape.principal.acao"
      />
    </footer>
  </section>
</template>
