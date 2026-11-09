<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import AcharAbasDasBuscas from '../components/AcharAbasDasBuscas.vue';
import AcharListaCartao from '../components/AcharListaCartao.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { ROTAS } from '../utils/acharRotas';

// #2775 — F6, a aba "Suas listas" de "Suas buscas": as listas guardadas pela
// Prospecção (os Públicos de Campanhas que ela criou), da mais nova para a mais
// velha, com os números de cada uma. Uma ação principal: "Abrir". Sem a
// permissão de guardar listas, a tela diz por que não mostra nada.
const { demo, fonte, permissoes, irPara, mudarEstado } = useAcharTela();

const NS = 'PROSPECTING_ACHAR.LISTAS';
const carregando = ref(true);
const erro = ref(false);
const listas = ref([]);

const temRodape = computed(
  () =>
    permissoes.value.buscar &&
    !carregando.value &&
    !erro.value &&
    listas.value.length > 0
);

const carregar = async () => {
  if (!permissoes.value.lista) {
    carregando.value = false;
    return;
  }
  carregando.value = true;
  erro.value = false;
  try {
    listas.value = await fonte.value.listas();
  } catch {
    erro.value = true;
  }
  carregando.value = false;
};

const abrir = lista =>
  irPara(ROTAS.LISTA, {
    params: { listaId: lista.id },
    estado: lista.enviada ? 'lista-enviada' : 'lista',
  });
const acharEmpresas = () => irPara(ROTAS.PORTA, { estado: 'porta' });
const tentarDeNovo = () => (demo.value ? mudarEstado('listas') : carregar());

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
          {{ $t(`${NS}.TITULO`) }}
        </h1>
        <AcharAbasDasBuscas atual="listas" />

        <AcharEstado
          v-if="!permissoes.lista"
          :texto="$t(`${NS}.SEM_PERMISSAO`)"
          data-sem-permissao
        />
        <div
          v-else-if="carregando"
          class="flex flex-col gap-3"
          aria-busy="true"
        >
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
          v-else-if="!listas.length"
          :texto="$t(`${NS}.VAZIO`)"
          :botao="permissoes.buscar ? $t('PROSPECTING_ACHAR.PORTA.BOTAO') : ''"
          data-listas-vazio
          @acao="acharEmpresas"
        />
        <ul v-else class="flex flex-col gap-3 p-0 m-0 list-none">
          <AcharListaCartao
            v-for="lista in listas"
            :key="lista.id"
            :lista="lista"
            @abrir="abrir(lista)"
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
  </section>
</template>
