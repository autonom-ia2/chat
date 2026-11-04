<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import LivreConfira from '../components/LivreConfira.vue';
import LivreSeletorPasso from '../components/LivreSeletorPasso.vue';
import LivreAlterar from '../components/LivreAlterar.vue';
import LivreLigar from '../components/LivreLigar.vue';
import LivreHistorico from '../components/LivreHistorico.vue';
import DialogoDaCasa from 'dashboard/routes/dashboard/settings/funcoesDaEquipe/guiada/DialogoDaCasa.vue';
import {
  carregarCatalogo,
  doAlvoDoGatilho,
  novoPasso,
  useCatalogo,
} from '../catalogo';
import {
  acharPasso,
  falta,
  inserirPasso,
  novoId,
  tirarPasso,
  trocarPasso,
} from '../receita';
import { useEditorLivre } from '../useEditorLivre';
import { useOpcoesDaConta } from '../useOpcoesDaConta';

// #2414 F5 — o editor da Automação livre: o "Confira" à esquerda e, ao lado, a
// ação principal (Ligar). A URL diz o painel aberto: ?alterar=<item>,
// ?seletor=<lista>@<posição> e ?tudo=1, para recarregar a página ou mandar o
// endereço e cair no mesmo painel.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const podeMudar = useCanManage('automation_manage');
const { catalogo } = useCatalogo();
const { opcoes, atributosDaPeca, atributosDo, carregarOpcoes } =
  useOpcoesDaConta();
const { isCloudFeatureEnabled } = useAccount();
const editor = useEditorLivre();
const {
  automacao,
  receita,
  nome,
  estado,
  problemas,
  ocupado,
  conflito,
  nova,
  mudou,
} = editor;

// Ligada, o "Salvar tudo" vale na hora só para quem a ligou; quando outra
// pessoa salva, ela pausa até ser ligada de novo.
const meuId = useMapGetter('getCurrentUserID');
const avisoDeLigada = computed(() => {
  if (!automacao.value?.ativa) return '';
  return automacao.value.ligada_por?.id === meuId.value
    ? t('AUTOMACAO_LIVRE.EDITOR.LIGADA_AVISO')
    : t('AUTOMACAO_LIVRE.EDITOR.LIGADA_POR_OUTRA');
});

// O "Alterar" só oferece o valor que o alvo do gatilho alcança (#2499).
const catalogoDoAlvo = computed(() =>
  doAlvoDoGatilho(catalogo.value, receita.value.gatilho?.tipo)
);

const seletor = ref(null);
const alterar = ref(null);
const guarda = ref(null);
// O passo escolhido no seletor ainda não está na receita: espera o "Salvar".
const passoNovo = ref(null);

const tudo = computed(() => route.query.tudo === '1');

const mudarUrl = query =>
  router.replace({ query: { ...(tudo.value ? { tudo: '1' } : {}), ...query } });
// Cada painel, ao fechar, tira só a chave dele: o seletor fecha porque a URL
// passou a pedir o "Alterar" do passo escolhido, e isso não pode apagar o pedido.
const fecharPainel = chave => {
  if (!route.query[chave]) return;
  const { [chave]: _fechado, ...resto } = route.query;
  router.replace({ query: resto });
};

const alternarTudo = () =>
  router.replace({
    query: { ...route.query, tudo: tudo.value ? undefined : '1' },
  });

const itemDaUrl = chave => {
  const r = receita.value;
  const filtros = r.gatilho?.filtros || [];
  if (chave === 'gatilho') return { tipo: 'gatilho', valor: r.gatilho };
  if (chave === 'novo') return passoNovo.value;
  if (chave.startsWith('condicao@')) {
    if (!r.gatilho) return null;
    const resto = chave.slice('condicao@'.length);
    const gatilho = r.gatilho.tipo;
    if (resto === 'novo')
      return { tipo: 'condicao', indice: -1, gatilho, valor: null };
    const indice = Number(resto);
    return filtros[indice]
      ? { tipo: 'condicao', indice, gatilho, valor: filtros[indice] }
      : null;
  }
  const passo = acharPasso(r.passos, chave);
  return passo ? { tipo: 'passo', valor: passo } : null;
};

const abrirDaUrl = async () => {
  if (estado.value !== 'pronto' || !catalogo.value) return;
  await nextTick();
  const { alterar: chave, seletor: posicao } = route.query;
  if (posicao && podeMudar.value) seletor.value?.open();
  else seletor.value?.close();
  const item = chave && podeMudar.value ? itemDaUrl(String(chave)) : null;
  if (item) alterar.value?.abrir(item);
  else if (chave) mudarUrl({});
};

const posicaoDoSeletor = () => {
  const texto = String(route.query.seletor || '');
  const corte = texto.lastIndexOf('@');
  return {
    listaId: texto.slice(0, corte),
    indice: Number(texto.slice(corte + 1)),
  };
};

const inserir = ({ listaId, indice }) =>
  mudarUrl({ seletor: `${listaId}@${indice}` });

const escolherPasso = entrada => {
  const { listaId, indice } = posicaoDoSeletor();
  const passo = novoPasso(entrada, novoId(receita.value.passos), t);
  passoNovo.value = {
    tipo: 'passo',
    novo: true,
    listaId,
    indice,
    valor: passo,
  };
  mudarUrl({ alterar: 'novo' });
};

const filtrosDe = r => r.gatilho?.filtros || [];
const comFiltros = (r, filtros) => {
  const { filtros: _antes, ...gatilho } = r.gatilho;
  return { ...r, gatilho: filtros.length ? { ...gatilho, filtros } : gatilho };
};

const receitaDoSalvar = ({ tipo, indice, novo, listaId, valor }) => {
  const r = receita.value;
  if (tipo === 'gatilho') {
    const comGatilho = { ...r, gatilho: { ...(r.gatilho || {}), ...valor } };
    return comFiltros(comGatilho, comGatilho.gatilho.filtros || []);
  }
  if (tipo === 'condicao') {
    const filtros = filtrosDe(r);
    return comFiltros(
      r,
      indice < 0
        ? [...filtros, valor]
        : filtros.map((item, i) => (i === indice ? valor : item))
    );
  }
  if (novo)
    return { ...r, passos: inserirPasso(r.passos, listaId, indice, valor) };
  return { ...r, passos: trocarPasso(r.passos, valor) };
};

const receitaDoTirar = ({ tipo, indice, valor }) => {
  const r = receita.value;
  if (tipo === 'condicao')
    return comFiltros(
      r,
      filtrosDe(r).filter((_, i) => i !== indice)
    );
  return { ...r, passos: tirarPasso(r.passos, valor.id) };
};

// A mudança entra no rascunho da tela; vira versão no "Salvar tudo".
const salvar = async item => {
  if (!(await editor.aplicar(receitaDoSalvar(item)))) return;
  passoNovo.value = null;
  alterar.value?.fechar();
};
const tirar = async item => {
  if (await editor.aplicar(receitaDoTirar(item))) alterar.value?.fechar();
};

// O que só está na tela: a nova antes de guardar, ou o rascunho da salva.
// Sair sem salvar perde isso, então a tela pergunta antes.
const naoSalva = computed(() =>
  nova.value
    ? Boolean(receita.value.gatilho || receita.value.passos.length)
    : mudou.value
);
const faltaCompletar = computed(() => Boolean(falta(receita.value)));
let responderGuarda = null;
onBeforeRouteLeave(() => {
  if (!podeMudar.value || !naoSalva.value) return true;
  guarda.value?.abrir();
  return new Promise(resolve => {
    responderGuarda = resolve;
  });
});
// Recarregar ou fechar a aba também perde o rascunho: o navegador pergunta.
const avisarAoFechar = evento => {
  if (!podeMudar.value || !naoSalva.value) return;
  evento.preventDefault();
  evento.returnValue = '';
};
onMounted(() => window.addEventListener('beforeunload', avisarAoFechar));
onUnmounted(() => window.removeEventListener('beforeunload', avisarAoFechar));
const responder = sair => {
  responderGuarda?.(sair);
  responderGuarda = null;
};

const voltar = () =>
  router.push({
    name: 'automacoes_lista',
    params: { accountId: route.params.accountId },
  });

// A nova ganhou id (guardou ou ligou): a URL passa a ser a dela.
watch(
  () => automacao.value?.id,
  id => {
    if (id && route.name === 'automacoes_livre_nova')
      router.replace({
        name: 'automacoes_livre_editar',
        params: { ...route.params, id },
      });
  }
);

watch(() => [route.query.alterar, route.query.seletor], abrirDaUrl);

// Sem o catálogo a tela não sabe desenhar os passos: falha vira o aviso com
// "Tentar de novo", como na lista.
const carregarTudo = async () => {
  try {
    await Promise.all([carregarCatalogo(), editor.carregar(route.params.id)]);
  } catch {
    estado.value = 'erro';
    return;
  }
  abrirDaUrl();
};

onMounted(() => {
  carregarOpcoes();
  carregarTudo();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-6xl gap-6 px-5 py-6 mx-auto md:px-8 md:py-8"
      >
        <Button
          data-voltar
          :label="$t('AUTOMACAO_LIVRE.VOLTAR_LISTA')"
          icon="i-lucide-arrow-left"
          slate
          link
          class="self-start min-h-11"
          @click="voltar"
        />

        <div
          v-if="estado === 'carregando' || (estado === 'pronto' && !catalogo)"
          data-carregando
          aria-busy="true"
          class="h-64 rounded-2xl bg-n-alpha-2 animate-pulse"
        />

        <p
          v-else-if="estado === 'nao_achou'"
          data-nao-achou
          role="alert"
          class="p-8 mb-0 text-base border rounded-2xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ $t('AUTOMACAO_LIVRE.EDITOR.NAO_ACHOU') }}
        </p>

        <div
          v-else-if="estado === 'erro'"
          data-erro
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('AUTOMACAO_LIVRE.FALHOU') }}
          </p>
          <Button
            :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="min-h-11"
            @click="carregarTudo"
          />
        </div>

        <template v-else>
          <Banner v-if="avisoDeLigada" data-ligada role="status" color="slate">
            {{ avisoDeLigada }}
          </Banner>

          <header class="flex flex-col gap-2">
            <Input
              v-if="podeMudar"
              v-model="nome"
              data-nome
              :label="$t('AUTOMACAO_LIVRE.EDITOR.NOME')"
              custom-input-class="!text-2xl !font-bold !h-14"
              @blur="editor.renomear"
              @enter="editor.renomear"
            />
            <h1
              v-else
              class="text-3xl font-bold tracking-tight text-n-slate-12"
            >
              {{ nome }}
            </h1>
            <p v-if="automacao?.versao" class="mb-0 text-sm text-n-slate-11">
              {{
                $t('AUTOMACAO_LIVRE.EDITOR.VERSAO', {
                  n: automacao.versao.numero,
                })
              }}
            </p>
          </header>

          <div
            v-if="conflito"
            data-conflito
            role="alert"
            class="sticky top-0 z-10 flex flex-col gap-3 p-4 shadow-lg md:flex-row md:items-center rounded-2xl bg-n-ruby-3 text-n-ruby-12"
          >
            <p class="flex-1 mb-0 text-[0.9375rem] font-medium">
              {{
                mudou
                  ? $t('AUTOMACAO_LIVRE.EDITOR.CONFLITO')
                  : $t('AUTOMACAO_LIVRE.MUDOU')
              }}
            </p>
            <Button
              data-ver-nova
              :label="$t('AUTOMACAO_LIVRE.EDITOR.VER_NOVA')"
              icon="i-lucide-refresh-cw"
              ruby
              class="min-h-11"
              @click="editor.verNova"
            />
          </div>

          <div
            v-else-if="!nova && naoSalva"
            data-rascunho
            role="status"
            class="sticky top-0 z-10 flex flex-col gap-3 p-4 shadow-lg md:flex-row md:items-center rounded-2xl bg-n-amber-3 text-n-amber-12"
          >
            <div class="flex flex-col flex-1 gap-1">
              <p class="mb-0 text-[0.9375rem] font-medium">
                {{ $t('AUTOMACAO_LIVRE.EDITOR.RASCUNHO') }}
              </p>
              <p v-if="faltaCompletar" data-nao-salva class="mb-0 text-sm">
                {{ $t('AUTOMACAO_LIVRE.EDITOR.NAO_SALVA') }}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <Button
                data-descartar
                :label="$t('AUTOMACAO_LIVRE.EDITOR.DESCARTAR')"
                slate
                link
                class="min-h-11"
                :disabled="ocupado"
                @click="editor.descartar"
              />
              <Button
                data-salvar-tudo
                :label="$t('AUTOMACAO_LIVRE.EDITOR.SALVAR_TUDO')"
                icon="i-lucide-save"
                class="min-h-11"
                :disabled="faltaCompletar || ocupado"
                @click="editor.salvarTudo"
              />
            </div>
          </div>

          <div
            v-if="problemas.length"
            data-problemas
            role="alert"
            class="flex flex-col gap-2 p-4 rounded-2xl bg-n-ruby-2 text-n-ruby-11"
          >
            <p class="mb-0 font-semibold">
              {{ $t('AUTOMACAO_LIVRE.EDITOR.PROBLEMAS') }}
            </p>
            <ul class="flex flex-col gap-1 m-0 ps-5">
              <li v-for="problema in problemas" :key="problema">
                {{ problema }}
              </li>
            </ul>
          </div>

          <div
            class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_20rem] items-start"
          >
            <div class="flex flex-col gap-4">
              <LivreConfira
                :receita="receita"
                :catalogo="catalogo"
                :pode-mudar="podeMudar && !ocupado && !conflito"
                :tudo="tudo"
                @alterar="chave => mudarUrl({ alterar: chave })"
                @inserir="inserir"
              />
              <Button
                data-mostrar-tudo
                :label="
                  tudo
                    ? $t('AUTOMACAO_LIVRE.EDITOR.MOSTRAR_MENOS')
                    : $t('AUTOMACAO_LIVRE.EDITOR.MOSTRAR_TUDO')
                "
                :icon="
                  tudo
                    ? 'i-lucide-chevrons-down-up'
                    : 'i-lucide-chevrons-up-down'
                "
                slate
                link
                class="self-start min-h-11"
                @click="alternarTudo"
              />
              <LivreHistorico
                v-if="automacao?.id && catalogo"
                :automacao-id="automacao.id"
                :catalogo="catalogo"
                :account-id="Number(route.params.accountId)"
              />
            </div>
            <aside class="flex flex-col gap-3 lg:sticky lg:top-6">
              <LivreLigar
                :ativa="Boolean(automacao?.ativa)"
                :receita="receita"
                :nova="nova"
                :pode-mudar="podeMudar"
                :ocupado="ocupado"
                :conflito="conflito"
                @ligar="editor.ligar"
                @guardar="editor.guardar"
                @desligar="editor.desligar"
              />
              <p v-if="!nova" class="mb-0 text-sm text-n-slate-11">
                {{ $t('AUTOMACAO_LIVRE.EDITOR.NO_MEIO') }}
              </p>
            </aside>
          </div>

          <template v-if="catalogo && podeMudar">
            <LivreSeletorPasso
              ref="seletor"
              :catalogo="catalogo"
              :liberado="isCloudFeatureEnabled"
              @escolher="escolherPasso"
              @close="fecharPainel('seletor')"
            />
            <LivreAlterar
              ref="alterar"
              :catalogo="catalogoDoAlvo"
              :opcoes="opcoes"
              :atributos-da-peca="atributosDaPeca"
              :atributos-do="atributosDo"
              @salvar="salvar"
              @tirar="tirar"
              @close="fecharPainel('alterar')"
            />
          </template>
          <DialogoDaCasa
            ref="guarda"
            tipo="destrutivo"
            icone="i-lucide-door-open"
            :titulo="$t('AUTOMACAO_LIVRE.EDITOR.SAIR.TITULO')"
            :texto="$t('AUTOMACAO_LIVRE.EDITOR.SAIR.TEXTO')"
            :seguro="$t('AUTOMACAO_LIVRE.EDITOR.SAIR.CONTINUAR')"
            :acao="$t('AUTOMACAO_LIVRE.EDITOR.SAIR.SAIR')"
            @seguro="responder(false)"
            @acao="responder(true)"
          />
        </template>
      </div>
    </main>
  </section>
</template>
