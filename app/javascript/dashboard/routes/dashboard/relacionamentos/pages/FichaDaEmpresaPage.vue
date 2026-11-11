<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import CabecalhoDaEmpresa from '../components/ficha/CabecalhoDaEmpresa.vue';
import CartaoDaSecao from '../components/ficha/CartaoDaSecao.vue';
import EsqueletoDaFicha from '../components/ficha/EsqueletoDaFicha.vue';
import GavetaDoCard from '../components/ficha/GavetaDoCard.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import ListaDeInformacoes from '../components/ficha/ListaDeInformacoes.vue';
import SecaoCards from '../components/ficha/SecaoCards.vue';
import SecaoConversas from '../components/ficha/SecaoConversas.vue';
import SecaoPessoasDaEmpresa from '../components/ficha/SecaoPessoasDaEmpresa.vue';
import { fichaFonte } from '../fonte/fichaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { ABAS } from '../fonte/grupos';
import { linhasDaEmpresa } from '../ficha/informacoes';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { ESTADOS_DA_FICHA as ESTADOS } from '../ficha/useEstadoDaFicha';
import { useFichaDaEmpresa } from '../ficha/useFichaDaEmpresa';

// #2894 — a ficha da empresa: o mesmo desenho da pessoa, mais simples. Cabeçalho,
// as pessoas dela, as conversas, os cards e as informações. Só leitura.
const { t } = useI18n();
const route = useRoute();
const acoes = useAcoesDaFicha();
const fonte = fichaFonte({ demo: usarDemo(route.query) });
const id = computed(() => Number(route.params?.companyId));
const ficha = useFichaDaEmpresa(fonte, id);
const agora = Date.now();
const cardAberto = ref(null);

const nome = computed(() => ficha.empresa.value?.name ?? '');
const linhas = computed(() =>
  ficha.empresa.value ? linhasDaEmpresa(ficha.empresa.value) : []
);
const avisar = chave =>
  acoes.avisar(`RELACIONAMENTOS_FICHA.EMPRESA.${chave}`, nome.value);

const abrirNoCrm = () => {
  cardAberto.value = null;
  acoes.abrirNoCrm();
};

onMounted(ficha.carregar);
watch(id, ficha.carregar);
</script>

<template>
  <section
    class="flex flex-col h-full bg-n-surface-1"
    data-relacionamentos="empresa"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col max-w-6xl gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <LinkDeVolta
          :texto="t('RELACIONAMENTOS_FICHA.VOLTAR.EMPRESAS')"
          :rotulo="t('RELACIONAMENTOS_FICHA.VOLTAR.ROTULO_EMPRESAS')"
          @voltar="acoes.voltarParaLista(ABAS.EMPRESAS)"
        />

        <EsqueletoDaFicha v-if="ficha.estado.value === ESTADOS.CARREGANDO" />

        <div
          v-else-if="ficha.estado.value === ESTADOS.ERRO"
          data-relacionamentos="erro"
        >
          <ErroComTentarDeNovo
            :mensagem="t('RELACIONAMENTOS_FICHA.ESTADOS.ERRO')"
            @tentar="ficha.carregar"
          />
        </div>

        <div
          v-else-if="ficha.estado.value === ESTADOS.NAO_ACHEI"
          data-relacionamentos="vazio"
        >
          <VazioComUmBotao
            :frase="t('RELACIONAMENTOS_FICHA.ESTADOS.NAO_ACHEI_EMPRESA')"
            :botao="t('RELACIONAMENTOS_FICHA.ESTADOS.VOLTAR_PARA_LISTA')"
            @acao="acoes.voltarParaLista(ABAS.EMPRESAS)"
          />
        </div>

        <div
          v-else
          data-relacionamentos="ficha-empresa"
          class="flex flex-col gap-6"
        >
          <CabecalhoDaEmpresa :empresa="ficha.empresa.value" />
          <div
            class="flex flex-col gap-6 lg:grid lg:grid-cols-3 lg:items-start"
          >
            <div class="flex flex-col gap-6 lg:col-span-2">
              <SecaoPessoasDaEmpresa
                :pessoas="ficha.pessoas.value"
                @abrir="acoes.abrirPessoa"
              />
              <SecaoConversas
                :conversas="ficha.conversas.value"
                :agora="agora"
                @conversar="avisar('CONVERSAR')"
                @ver-todas="avisar('VER_TODAS')"
              />
              <SecaoCards
                :cards="ficha.cards.value"
                @abrir="card => (cardAberto = card)"
                @novo-card="avisar('NOVO_CARD')"
              />
            </div>
            <CartaoDaSecao
              :titulo="t('RELACIONAMENTOS_FICHA.INFORMACOES.TITULO')"
              data-relacionamentos="informacoes"
            >
              <ListaDeInformacoes
                raiz="RELACIONAMENTOS_FICHA.EMPRESA.INFORMACOES"
                :linhas="linhas"
              />
            </CartaoDaSecao>
          </div>
        </div>
      </div>
    </main>

    <GavetaDoCard
      :card="cardAberto"
      @fechar="cardAberto = null"
      @abrir-no-crm="abrirNoCrm"
    />
  </section>
</template>
