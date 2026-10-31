<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import AutomacaoEtapas from '../../components/AutomacaoEtapas.vue';
import LivreConfira from '../components/LivreConfira.vue';
import LivreEnsaio from '../components/LivreEnsaio.vue';
import LivreHistorico from '../components/LivreHistorico.vue';
import LivreLigar from '../components/LivreLigar.vue';
import LivreSeletorPasso from '../components/LivreSeletorPasso.vue';
import LivreAlterar from '../components/LivreAlterar.vue';
import LivreConfirmaLigar from '../components/LivreConfirmaLigar.vue';
import LivreNoMeio from '../components/LivreNoMeio.vue';
import LivreSeloOrigem from '../components/LivreSeloOrigem.vue';
import { fraseDoGatilho } from '../prototipo/frases';
import { useEditorLivre } from '../prototipo/useEditorLivre';

// #2414 F0 — o editor único (Guia, receita, do zero e manual caem aqui).
// Abas: Confira (a lista Quando/Só se/Faça), Ensaiar, O que aconteceu e Ver
// como dado. Tudo que abre por cima (seletor, Alterar, confirmações) tem a
// própria URL, para dar para mostrar cada momento.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const podeGerenciar = useCanManage('automation_manage');
const editor = useEditorLivre(route);
const { automacao, ehNova, rascunho, receitaBase, loja } = editor;

const seletor = ref(null);
const alterar = ref(null);
const confirma = ref(null);
const noMeio = ref(null);
const trazer = ref(null);

const podeMudar = computed(
  () => podeGerenciar.value && !automacao.value?.jeitoAntigo
);
const nome = computed(() => automacao.value?.nome || editor.nomeDaNova.value);
const ativa = computed(() => Boolean(automacao.value?.ativa));
const tudo = computed(() => route.query.tudo === '1');

// --- URL: cada painel e diálogo abre por um parâmetro -----------------------
const trocarQuery = mudanca => {
  const query = { ...route.query, ...mudanca };
  Object.keys(query).forEach(chave => {
    if (query[chave] === null) delete query[chave];
  });
  router.replace({ query });
};
const fechar = chave => trocarQuery({ [chave]: null });

const posicaoDoSeletor = computed(() => {
  const valor = route.query.seletor;
  if (!valor) return null;
  const corte = valor.lastIndexOf('@');
  return {
    listaId: valor.slice(0, corte),
    indice: Number(valor.slice(corte + 1)),
  };
});

const abrirPelaUrl = () => {
  const { query } = route;
  if (query.seletor) seletor.value?.open();
  if (query.alterar) {
    const item = editor.itemDaUrl(query.alterar);
    if (item) alterar.value?.abrir(item);
  }
  if (query.ligar === '1') confirma.value?.pedir(rascunho.value);
  if (query.pessoas === '1') noMeio.value?.open();
  if (query.trazer === '1') trazer.value?.open();
};
onMounted(() => nextTick(abrirPelaUrl));
watch(
  () => [
    route.query.seletor,
    route.query.alterar,
    route.query.ligar,
    route.query.pessoas,
    route.query.trazer,
  ],
  (novo, velho = []) => {
    if (novo.some((valor, i) => valor && valor !== velho[i])) abrirPelaUrl();
  }
);

const chaveDoAlterar = item => {
  if (item.tipo === 'passo') return item.id;
  if (item.tipo === 'condicao') return `condicao@${item.indice}`;
  return item.tipo;
};
const abrirAlterar = item => trocarQuery({ alterar: chaveDoAlterar(item) });
const abrirSeletor = posicao =>
  trocarQuery({ seletor: `${posicao.listaId}@${posicao.indice}` });

// --- Abas --------------------------------------------------------------------
const ABAS = computed(() =>
  ['confira', 'ensaiar', ehNova.value ? null : 'historico', 'dado'].filter(
    Boolean
  )
);
const abas = computed(() =>
  ABAS.value.map(chave => ({
    chave,
    label: t(`AUTOMACAO_LIVRE.EDITOR.ABAS.${chave.toUpperCase()}`),
  }))
);
const aba = computed(() =>
  ABAS.value.includes(route.query.aba) ? route.query.aba : 'confira'
);
const trocarAba = item =>
  trocarQuery({ aba: item.chave === 'confira' ? null : item.chave });

// --- Mudanças ----------------------------------------------------------------
const depoisDeAplicar = resultado => {
  if (resultado === 'pendente') trocarQuery({ pessoas: '1' });
  else if (automacao.value) useAlert(t('AUTOMACAO_LIVRE.EDITOR.SALVOU'));
};

const aoSalvarAlterar = item =>
  depoisDeAplicar(editor.aplicar(editor.mudancaDoAlterar(item)));
const aoTirar = item =>
  depoisDeAplicar(editor.aplicar(editor.mudancaDoTirar(item)));

const aoEscolherPasso = escolha => {
  const posicao = posicaoDoSeletor.value;
  seletor.value?.close();
  if (!posicao) return;
  const { passo, receita } = editor.mudancaDoInserir(posicao, escolha);
  const resultado = editor.aplicar(receita);
  depoisDeAplicar(resultado);
  if (resultado === 'feito')
    nextTick(() => trocarQuery({ seletor: null, alterar: passo.id }));
};

const aoConfirmarNoMeio = escolha => {
  const versao = editor.confirmarPendente(escolha);
  if (versao)
    useAlert(
      t(`AUTOMACAO_LIVRE.NO_MEIO.SALVOU_${escolha.toUpperCase()}`, {
        n: versao.numero,
      })
    );
};

// --- Ligar, guardar, trazer ---------------------------------------------------
const irPara = id =>
  router.replace({
    name: 'automacoes_livre_editar',
    params: { accountId: route.params.accountId, id },
  });

const criar = ativar =>
  loja.criar({
    nome: nome.value,
    receita: rascunho.value,
    ativa: ativar,
    extra: {
      criadaPor: receitaBase.value ? 'receita' : 'manual',
      pacote: receitaBase.value?.pacote?.nome || null,
      exemplo: receitaBase.value?.exemplo || null,
    },
  });

const aoLigar = () => {
  fechar('ligar');
  if (ehNova.value) {
    irPara(criar(true));
  } else {
    loja.alternar(automacao.value.id, true);
  }
  useAlert(t('AUTOMACAO_LIVRE.LIGOU'));
};
const aoGuardar = () => {
  irPara(criar(false));
  useAlert(t('AUTOMACAO_LIVRE.EDITOR.GUARDOU'));
};
const aoDesligar = () => {
  loja.alternar(automacao.value.id, false);
  useAlert(t('AUTOMACAO_LIVRE.DESLIGOU'));
};
const aoTrazer = () => {
  trazer.value?.close();
  const novoId = loja.trazerParaONovo(automacao.value.id);
  irPara(novoId);
  useAlert(t('AUTOMACAO_LIVRE.EDITOR.TROUXE'));
};

const voltar = () =>
  router.push({
    name: 'automacoes_livre_lista',
    params: { accountId: route.params.accountId },
  });

// Conte → Confira → Ligue: aqui já está montada; ligada, as três ficam feitas.
const etapa = computed(() => (ativa.value ? 3 : 2));
const exemploDoEnsaio = computed(
  () =>
    automacao.value?.exemplo ||
    automacao.value?.id ||
    receitaBase.value?.exemplo ||
    null
);
const registros = computed(() =>
  automacao.value ? loja.registrosDe({ automacaoId: automacao.value.id }) : []
);
const comoDado = computed(() =>
  JSON.stringify(
    {
      automacao: automacao.value
        ? {
            id: automacao.value.id,
            nome: automacao.value.nome,
            ativa: automacao.value.ativa,
            origem: automacao.value.origem,
          }
        : { nome: nome.value, ativa: false },
      versao: automacao.value?.versao?.numero || null,
      receita: rascunho.value,
    },
    null,
    2
  )
);
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full max-w-6xl gap-6 px-5 py-8 pb-40 mx-auto md:px-8 md:py-10"
    >
      <button
        type="button"
        class="inline-flex items-center self-start gap-2 text-sm font-medium min-h-11 text-n-slate-11 hover:text-n-slate-12"
        @click="voltar"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ $t('AUTOMACAO_LIVRE.VOLTAR_LISTA') }}
      </button>

      <header class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-3">
          <h1
            data-nome
            class="mb-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
          >
            {{ nome }}
          </h1>
          <LivreSeloOrigem v-if="automacao" :automacao="automacao" />
        </div>
        <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
          <AutomacaoEtapas :atual="etapa" :concluida="ativa" />
          <span v-if="automacao?.versao" class="text-sm text-n-slate-11">
            {{
              $t('AUTOMACAO_LIVRE.EDITOR.VERSAO', {
                n: automacao.versao.numero,
                autor: automacao.versao.autor,
              })
            }}
          </span>
        </div>
      </header>

      <p
        v-if="route.query.guia === '1'"
        data-aviso-guia
        class="flex items-center gap-2 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-iris-2 text-n-slate-12"
      >
        <span
          class="i-lucide-sparkles size-5 text-n-iris-11"
          aria-hidden="true"
        />
        {{ $t('AUTOMACAO_LIVRE.EDITOR.AVISO_GUIA') }}
      </p>
      <p
        v-else-if="ehNova && receitaBase"
        data-aviso-receita
        class="flex items-center gap-2 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-teal-2 text-n-slate-12"
      >
        <span
          class="i-lucide-book-open-check size-5 text-n-teal-11"
          aria-hidden="true"
        />
        {{ $t('AUTOMACAO_LIVRE.EDITOR.AVISO_RECEITA', { nome }) }}
      </p>
      <p
        v-else-if="ehNova && route.query.etapa"
        data-aviso-etapa
        class="flex items-center gap-2 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-violet-2 text-n-slate-12"
      >
        <span
          class="i-lucide-square-kanban size-5 text-n-violet-11"
          aria-hidden="true"
        />
        {{
          $t('AUTOMACAO_LIVRE.EDITOR.AVISO_ETAPA', {
            frase: fraseDoGatilho(rascunho.gatilho, t),
          })
        }}
      </p>
      <div
        v-if="automacao?.jeitoAntigo"
        data-aviso-antigo
        class="flex flex-wrap items-center gap-4 px-4 py-3 border rounded-xl border-n-amber-6 bg-n-amber-2"
      >
        <span
          class="i-lucide-history size-5 text-n-amber-11"
          aria-hidden="true"
        />
        <p class="flex-1 mb-0 text-[0.9375rem] text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.EDITOR.AVISO_ANTIGO') }}
        </p>
        <Button
          v-if="podeGerenciar"
          data-trazer
          :label="$t('AUTOMACAO_LIVRE.TRAZER')"
          icon="i-lucide-arrow-up-right"
          amber
          class="min-h-11"
          @click="trocarQuery({ trazer: '1' })"
        />
      </div>

      <div class="grid items-start gap-7 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <section
          class="flex flex-col min-w-0 gap-5 p-6 border shadow-sm rounded-3xl border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <TabBar
              :tabs="abas"
              :initial-active-tab="ABAS.indexOf(aba)"
              @tab-changed="trocarAba"
            />
            <Button
              v-if="aba === 'confira'"
              data-mostrar-tudo
              :label="
                tudo
                  ? $t('AUTOMACAO_LIVRE.EDITOR.MOSTRAR_MENOS')
                  : $t('AUTOMACAO_LIVRE.EDITOR.MOSTRAR_TUDO')
              "
              :icon="
                tudo ? 'i-lucide-chevrons-down-up' : 'i-lucide-chevrons-up-down'
              "
              link
              slate
              class="min-h-11"
              @click="trocarQuery({ tudo: tudo ? null : '1' })"
            />
          </div>

          <LivreConfira
            v-if="aba === 'confira'"
            :receita="rascunho"
            :pode-mudar="podeMudar"
            :tudo="tudo"
            @alterar="abrirAlterar"
            @inserir="abrirSeletor"
            @adicionar-condicao="trocarQuery({ alterar: 'condicao@novo' })"
          />
          <LivreEnsaio
            v-else-if="aba === 'ensaiar'"
            :alvo="route.query.alvo || ''"
            :receita="rascunho"
            :automacao-id="exemploDoEnsaio"
            @update:alvo="alvo => trocarQuery({ alvo })"
          />
          <LivreHistorico
            v-else-if="aba === 'historico'"
            :registros="registros"
          />
          <div v-else data-dado class="flex flex-col gap-3">
            <p class="mb-0 text-[0.9375rem] text-n-slate-11">
              {{ $t('AUTOMACAO_LIVRE.EDITOR.DADO_EXPLICA') }}
            </p>
            <textarea
              data-json
              readonly
              rows="22"
              :value="comoDado"
              :aria-label="$t('AUTOMACAO_LIVRE.EDITOR.ABAS.DADO')"
              class="w-full p-4 m-0 font-mono text-xs leading-relaxed border-0 resize-y rounded-xl bg-n-alpha-2 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand !mb-0"
            />
          </div>
        </section>

        <aside class="flex flex-col gap-4 lg:sticky lg:top-6">
          <LivreLigar
            v-if="!automacao?.jeitoAntigo"
            :ativa="ativa"
            :receita="rascunho"
            :nova="ehNova"
            :no-meio="automacao?.noMeio || 0"
            :pode-mudar="podeGerenciar"
            @ligar="trocarQuery({ ligar: '1' })"
            @desligar="aoDesligar"
            @guardar="aoGuardar"
          />
          <p
            v-if="aba !== 'ensaiar'"
            class="flex items-start gap-2 p-4 mb-0 text-sm rounded-2xl bg-n-alpha-1 text-n-slate-11"
          >
            <span
              class="i-lucide-flask-conical size-4 mt-0.5 shrink-0"
              aria-hidden="true"
            />
            {{ $t('AUTOMACAO_LIVRE.EDITOR.DICA_ENSAIO') }}
          </p>
        </aside>
      </div>
    </div>

    <LivreSeletorPasso
      ref="seletor"
      @escolher="aoEscolherPasso"
      @close="fechar('seletor')"
    />
    <LivreAlterar
      ref="alterar"
      @salvar="aoSalvarAlterar"
      @tirar="aoTirar"
      @close="fechar('alterar')"
    />
    <LivreConfirmaLigar
      ref="confirma"
      @ligar="aoLigar"
      @close="fechar('ligar')"
    />
    <LivreNoMeio
      ref="noMeio"
      :quantas="automacao?.noMeio || 8"
      @confirmar="aoConfirmarNoMeio"
      @close="fechar('pessoas')"
    />
    <Dialog
      ref="trazer"
      :title="$t('AUTOMACAO_LIVRE.TRAZER_DIALOGO.TITULO')"
      :description="$t('AUTOMACAO_LIVRE.TRAZER_DIALOGO.TEXTO')"
      :confirm-button-label="$t('AUTOMACAO_LIVRE.TRAZER')"
      @confirm="aoTrazer"
      @close="fechar('trazer')"
    />
  </main>
</template>
