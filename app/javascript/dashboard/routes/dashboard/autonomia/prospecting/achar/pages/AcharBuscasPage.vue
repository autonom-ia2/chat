<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharBuscaCartao from '../components/AcharBuscaCartao.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import AcharAbasDasBuscas from '../components/AcharAbasDasBuscas.vue';
import { useAcharTela } from '../composables/useAcharTela';
import {
  fatoDaBusca,
  feitaPorDaBusca,
  tituloDaBusca,
} from '../utils/acharQuando';
import { ROTAS } from '../utils/acharRotas';
import {
  buscasVisiveis,
  ehDaEquipe,
  podeApagarBusca,
} from '../utils/acharPapeis';

// #2692 — T4, "Suas buscas" (v4): um cartão por busca com "Abrir" explícito.
// Quem só vê abre e lê; não há rodapé para ele. Com "Ver buscas de todos", o
// cartão diz quem fez e o título vira "Buscas da equipe". Rodada 2: menu
// "Mais" (só Editar) com "Buscar de novo", "Baixar planilha" e "Apagar", que
// pede confirmação. Na demonstração nada é apagado nem baixado.
const { t } = useI18n();
const {
  route,
  router,
  demo,
  fonte,
  permissoes,
  irPara,
  mudarEstado,
  usuarioId,
} = useAcharTela();

const NS = 'PROSPECTING_ACHAR.BUSCAS';
const carregando = ref(true);
const erro = ref(false);
const buscas = ref([]);
const menuDe = ref(null);
const apagando = ref(null);
// "Ver mais": o servidor manda uma página por vez (meta.has_more).
const pagina = ref(1);
const temMais = ref(false);
const carregandoMais = ref(false);
// A paginação do servidor é por posição: depois de apagar, a próxima página
// começa adiantada e pularia buscas. Aí "Ver mais" relê da página 1 até a
// próxima, sem repetir nenhuma.
const apagadas = ref(0);

// Quem só vê está sempre nas buscas da equipe, também com a lista vazia; o
// mesmo papel tem sempre o mesmo título (rodada 3).
// "Buscas da equipe" só quando há busca de outra pessoa (feitaPorId diferente
// do usuário), com a mesma regra na demonstração e na API.
const daEquipe = computed(() =>
  ehDaEquipe({
    buscas: buscas.value,
    usuarioId: usuarioId.value,
    permissoes: permissoes.value,
  })
);
const feitaPor = busca =>
  daEquipe.value ? feitaPorDaBusca(t, busca, usuarioId.value) : '';

const temRodape = computed(
  () =>
    permissoes.value.buscar &&
    !carregando.value &&
    !erro.value &&
    buscas.value.length > 0
);
const avisoSoVer = computed(
  () => route.query.aviso === 'so-ver' && !permissoes.value.buscar
);

const lerPagina = async numero => {
  const lida = await fonte.value.buscas(numero);
  pagina.value = numero;
  temMais.value = lida.temMais;
  return buscasVisiveis({
    buscas: lida.buscas,
    usuarioId: usuarioId.value,
    verTodas: permissoes.value.verTodas,
  });
};

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    buscas.value = await lerPagina(1);
    apagadas.value = 0;
  } catch {
    erro.value = true;
  }
  carregando.value = false;
  // Estados da demonstração com o menu ou a confirmação já abertos.
  menuDe.value = demo.value === 'buscas-mais' ? buscas.value[0]?.id : null;
  apagando.value = demo.value === 'apagar' ? buscas.value[0] : null;
};

const juntarSemRepetir = (lista, mais) => {
  const jaTem = new Set(lista.map(busca => busca.id));
  return [...lista, ...mais.filter(busca => !jaTem.has(busca.id))];
};
const lerAte = async ultima => {
  const paginas = Array.from({ length: ultima }, (_, indice) => indice + 1);
  return paginas.reduce(
    async (lidas, numero) =>
      juntarSemRepetir(await lidas, await lerPagina(numero)),
    Promise.resolve([])
  );
};

const verMais = async () => {
  carregandoMais.value = true;
  try {
    const proxima = pagina.value + 1;
    buscas.value = apagadas.value
      ? await lerAte(proxima)
      : juntarSemRepetir(buscas.value, await lerPagina(proxima));
    apagadas.value = 0;
  } catch {
    useAlert(t(`${NS}.ERRO_VER_MAIS`));
  } finally {
    carregandoMais.value = false;
  }
};

const podeApagar = busca =>
  podeApagarBusca({
    busca,
    usuarioId: usuarioId.value,
    demo: Boolean(demo.value),
  });

const baixar = async busca => {
  try {
    await fonte.value.baixarBusca(busca.id);
    if (demo.value) useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_NAO_GRAVA'));
  } catch {
    useAlert(t(`${NS}.ERRO_BAIXAR`));
  }
};

// A mesma busca de novo, sem cache: uma busca nova no servidor, aberta na rota
// da busca nova (a de agora fica guardada como estava).
const buscarDeNovo = async busca => {
  try {
    const { searchId } = await fonte.value.repetirBusca({ busca });
    await irPara(ROTAS.NOVA, { params: { searchId }, estado: 'buscando' });
  } catch {
    useAlert(t('PROSPECTING_ACHAR.COMUM.ERRO_BUSCAR_DE_NOVO'));
  }
};

const agirNaBusca = (busca, acao) => {
  menuDe.value = null;
  if (acao === 'apagar') {
    apagando.value = busca;
    return;
  }
  if (acao === 'buscarDeNovo') {
    buscarDeNovo(busca);
    return;
  }
  baixar(busca);
};
const confirmarApagar = async () => {
  const { id } = apagando.value;
  try {
    await fonte.value.apagarBusca(id);
  } catch {
    useAlert(t(`${NS}.ERRO_APAGAR`));
    return;
  }
  buscas.value = buscas.value.filter(busca => busca.id !== id);
  apagadas.value += 1;
  apagando.value = null;
  useAlert(t(`${NS}.APAGADA`));
};

const abrir = busca =>
  irPara(ROTAS.BUSCA, {
    params: { searchId: busca.id },
    estado: permissoes.value.buscar ? 'confira' : 'leitura',
  });
const acharEmpresas = () => irPara(ROTAS.PORTA, { estado: 'porta' });
const verFunil = () =>
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: route.params.accountId },
  });
const tentarDeNovo = () => (demo.value ? mudarEstado('buscas') : carregar());

onMounted(carregar);
watch(demo, carregar);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-4xl gap-6 px-4 pt-6 mx-auto min-h-full md:px-8 md:pt-10"
        :class="temRodape ? 'pb-0' : 'md:pb-10'"
      >
        <h1
          class="m-0 text-2xl font-bold tracking-tight md:text-[2rem] text-n-slate-12"
        >
          {{ daEquipe ? $t(`${NS}.TITULO_EQUIPE`) : $t(`${NS}.TITULO`) }}
        </h1>
        <!-- #2775 (F6): a aba "Suas listas" fica ao lado. -->
        <AcharAbasDasBuscas v-if="permissoes.lista" atual="buscas" />

        <AcharEstado
          v-if="avisoSoVer"
          faixa
          tom="aviso"
          :texto="$t('PROSPECTING_ACHAR.PORTA.SO_VER')"
        />

        <div v-if="carregando" class="flex flex-col gap-3" aria-busy="true">
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-24 rounded-2xl bg-n-slate-3 animate-pulse"
          />
        </div>
        <AcharEstado
          v-else-if="erro"
          tom="erro"
          :texto="$t(`${NS}.ERRO`)"
          :botao="$t('PROSPECTING_ACHAR.COMUM.TENTAR_DE_NOVO')"
          @acao="tentarDeNovo"
        />
        <AcharEstado
          v-else-if="!buscas.length && permissoes.buscar"
          :texto="$t(`${NS}.VAZIO`)"
          :botao="$t('PROSPECTING_ACHAR.PORTA.BOTAO')"
          @acao="acharEmpresas"
        />
        <AcharEstado
          v-else-if="!buscas.length"
          :texto="$t(`${NS}.VAZIO_SO_VER`)"
          :botao="$t(`${NS}.VER_FUNIL`)"
          @acao="verFunil"
        />
        <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
          <AcharBuscaCartao
            v-for="busca in buscas"
            :key="busca.id"
            :titulo="tituloDaBusca(t, busca)"
            :fato="fatoDaBusca(t, busca)"
            :feita-por="feitaPor(busca)"
            :com-mais="permissoes.buscar"
            :pode-apagar="podeApagar(busca)"
            :mais-aberto="menuDe === busca.id"
            @abrir="abrir(busca)"
            @mais="menuDe = menuDe === busca.id ? null : busca.id"
            @acao="agirNaBusca(busca, $event)"
          />
        </ul>
        <Button
          v-if="temMais && !carregando && !erro"
          :label="$t(`${NS}.VER_MAIS`)"
          :is-loading="carregandoMais"
          slate
          faded
          class="!min-h-12 !rounded-xl !text-base self-center"
          data-ver-mais
          @click="verMais"
        />

        <AcharRodape
          v-if="temRodape"
          :rotulo="$t('PROSPECTING_ACHAR.PORTA.BOTAO')"
          icone="i-lucide-search"
          @principal="acharEmpresas"
        />
        <AcharFaixaDoMenu v-if="!temRodape" />
      </div>
    </main>
    <div
      v-if="apagando"
      class="fixed inset-0 z-50 grid p-4 place-items-center bg-n-slate-12/30"
      @click.self="apagando = null"
    >
      <section
        role="alertdialog"
        aria-modal="true"
        :aria-label="$t(`${NS}.APAGAR_TITULO`)"
        class="flex flex-col w-full max-w-md gap-4 p-6 shadow-2xl rounded-3xl bg-n-solid-1"
        data-apagar
      >
        <h2 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ $t(`${NS}.APAGAR_TITULO`) }}
        </h2>
        <p class="m-0 text-base text-n-slate-11">
          {{ tituloDaBusca(t, apagando) }}
        </p>
        <p class="m-0 text-base text-n-slate-12">
          {{ $t(`${NS}.APAGAR_TEXTO`) }}
        </p>
        <div class="grid grid-cols-2 gap-2 sm:flex sm:justify-end">
          <Button
            :label="$t('PROSPECTING_ACHAR.COMUM.VOLTAR')"
            slate
            faded
            class="!min-h-12 !rounded-xl !px-6 !text-base"
            @click="apagando = null"
          />
          <Button
            :label="$t('PROSPECTING_ACHAR.COMUM.APAGAR')"
            ruby
            class="!min-h-12 !rounded-xl !px-6 !text-base"
            data-confirmar-apagar
            @click="confirmarApagar"
          />
        </div>
      </section>
    </div>
  </section>
</template>
