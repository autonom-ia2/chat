<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharBuscaCartao from '../components/AcharBuscaCartao.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { fatoDaBusca } from '../utils/acharQuando';
import { ROTAS } from '../utils/acharRotas';

// #2692 — T4, "Suas buscas" (v4): um cartão por busca com "Abrir" explícito.
// Quem só vê abre e lê; não há rodapé para ele. Com "Ver buscas de todos", o
// cartão diz quem fez e o título vira "Buscas da equipe". Rodada 2: menu
// "Mais" (só Editar) com "Buscar de novo", "Baixar planilha" e "Apagar", que
// pede confirmação. Na demonstração nada é apagado nem baixado.
const { t } = useI18n();
const { route, router, demo, fonte, permissoes, irPara, mudarEstado } =
  useAcharTela();

const NS = 'PROSPECTING_ACHAR.BUSCAS';
const carregando = ref(true);
const erro = ref(false);
const buscas = ref([]);
const menuDe = ref(null);
const apagando = ref(null);

// Quem só vê está sempre nas buscas da equipe, também com a lista vazia; o
// mesmo papel tem sempre o mesmo título (rodada 3).
const daEquipe = computed(
  () =>
    permissoes.value.verTodas &&
    (!permissoes.value.buscar || buscas.value.some(busca => busca.feitaPor))
);
const feitaPor = busca => {
  if (!daEquipe.value) return '';
  return t(`${NS}.FEITA_POR`, {
    pessoa: busca.feitaPor || t('PROSPECTING_ACHAR.COMUM.VOCE'),
  });
};

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

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    buscas.value = await fonte.value.buscas();
  } catch {
    erro.value = true;
  }
  carregando.value = false;
  // Estados da demonstração com o menu ou a confirmação já abertos.
  menuDe.value = demo.value === 'buscas-mais' ? buscas.value[0]?.id : null;
  apagando.value = demo.value === 'apagar' ? buscas.value[0] : null;
};

const agirNaBusca = (busca, acao) => {
  menuDe.value = null;
  if (acao === 'apagar') {
    apagando.value = busca;
    return;
  }
  if (acao === 'buscarDeNovo') {
    irPara(ROTAS.BUSCA, { params: { searchId: busca.id }, estado: 'buscando' });
    return;
  }
  useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_NAO_GRAVA'));
};
const confirmarApagar = () => {
  buscas.value = buscas.value.filter(busca => busca.id !== apagando.value.id);
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
            :titulo="`${busca.oQue} · ${busca.lugar}`"
            :fato="fatoDaBusca(t, busca)"
            :feita-por="feitaPor(busca)"
            :com-mais="permissoes.buscar"
            :pode-apagar="!busca.feitaPor"
            :mais-aberto="menuDe === busca.id"
            @abrir="abrir(busca)"
            @mais="menuDe = menuDe === busca.id ? null : busca.id"
            @acao="agirNaBusca(busca, $event)"
          />
        </ul>

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
          {{ apagando.oQue }} · {{ apagando.lugar }}
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
