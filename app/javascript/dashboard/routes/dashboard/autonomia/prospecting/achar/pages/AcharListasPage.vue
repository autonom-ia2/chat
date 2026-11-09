<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
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
// permissão de guardar listas, a tela diz por que não mostra nada. O servidor
// manda 25 por vez: "Ver mais listas" traz as seguintes, pelo cursor.
const { t } = useI18n();
const { demo, fonte, permissoes, irPara, mudarEstado } = useAcharTela();

const NS = 'PROSPECTING_ACHAR.LISTAS';
const carregando = ref(true);
const erro = ref(false);
const listas = ref([]);
const depois = ref(null);
const temMais = ref(false);
const carregandoMais = ref(false);

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
    const lidas = await fonte.value.listas();
    listas.value = lidas.listas;
    temMais.value = lidas.temMais;
    depois.value = lidas.depois;
  } catch {
    erro.value = true;
  }
  carregando.value = false;
};

// Por cursor (a última lista mostrada), e um pedido por vez: o clique duplo
// não pede a mesma página duas vezes nem pula uma.
const verMais = async () => {
  if (carregandoMais.value) return;
  carregandoMais.value = true;
  try {
    const lidas = await fonte.value.listas({ depois: depois.value });
    const jaTem = new Set(listas.value.map(lista => lista.id));
    listas.value = [
      ...listas.value,
      ...lidas.listas.filter(lista => !jaTem.has(lista.id)),
    ];
    temMais.value = lidas.temMais && Boolean(lidas.depois);
    depois.value = lidas.depois;
  } catch {
    useAlert(t(`${NS}.ERRO_VER_MAIS`));
  } finally {
    carregandoMais.value = false;
  }
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
        <Button
          v-if="!carregando && !erro && permissoes.lista && temMais"
          :label="$t(`${NS}.VER_MAIS`)"
          :is-loading="carregandoMais"
          :disabled="carregandoMais"
          slate
          faded
          class="!min-h-12 !rounded-xl !text-base self-center"
          data-ver-mais-listas
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
  </section>
</template>
