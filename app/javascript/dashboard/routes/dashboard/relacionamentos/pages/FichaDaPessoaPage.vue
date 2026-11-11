<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import CabecalhoDaPessoa from '../components/ficha/CabecalhoDaPessoa.vue';
import CartaoDaSecao from '../components/ficha/CartaoDaSecao.vue';
import DeOndeVeio from '../components/ficha/DeOndeVeio.vue';
import EsqueletoDaFicha from '../components/ficha/EsqueletoDaFicha.vue';
import FaixaNaoQuer from '../components/ficha/FaixaNaoQuer.vue';
import GavetaDeInformacoes from '../components/ficha/GavetaDeInformacoes.vue';
import GavetaDoCard from '../components/ficha/GavetaDoCard.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import ListaDeInformacoes from '../components/ficha/ListaDeInformacoes.vue';
import SecaoArquivos from '../components/ficha/SecaoArquivos.vue';
import SecaoCards from '../components/ficha/SecaoCards.vue';
import SecaoConversas from '../components/ficha/SecaoConversas.vue';
import SecaoNotas from '../components/ficha/SecaoNotas.vue';
import { fichaFonte } from '../fonte/fichaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { linhasDaPessoa, redesPreenchidas } from '../ficha/informacoes';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { ESTADOS_DA_FICHA as ESTADOS } from '../ficha/useEstadoDaFicha';
import { useFichaDaPessoa } from '../ficha/useFichaDaPessoa';

// #2894 — a ficha da pessoa: primeiro "quem é e o que tem comigo". Editar é um
// passo a mais, de propósito (a gaveta "Alterar informações"). Em 390 px a ordem é
// cabeçalho, faixa, Conversas, Cards, Informações, Notas, Arquivos, De onde veio.
const { t } = useI18n();
const route = useRoute();
const acoes = useAcoesDaFicha();
const fonte = fichaFonte({ demo: usarDemo(route.query) });
const id = computed(() => Number(route.params?.contactId));
const ficha = useFichaDaPessoa(fonte, id);
const agora = Date.now();

const gavetaAberta = ref(false);
const cardAberto = ref(null);
const caixaDeNotas = ref(null);

const nome = computed(() => ficha.pessoa.value?.name ?? '');
const linhas = computed(() =>
  ficha.pessoa.value ? linhasDaPessoa(ficha.pessoa.value) : []
);
const redes = computed(() =>
  ficha.pessoa.value ? redesPreenchidas(ficha.pessoa.value) : []
);
const avisar = chave =>
  acoes.avisar(`RELACIONAMENTOS_FICHA.AVISOS.${chave}`, nome.value);

const resultado = (deuCerto, certo, erro, valores) =>
  useAlert(t(deuCerto ? certo : erro, valores));

const marcarCliente = async () =>
  resultado(
    await ficha.marcarCliente(),
    'RELACIONAMENTOS_FICHA.CABECALHO.CLIENTE_MARCADO',
    'RELACIONAMENTOS_FICHA.CABECALHO.ERRO_MARCAR',
    { nome: nome.value }
  );

const liberar = async () =>
  resultado(
    await ficha.liberar(),
    'RELACIONAMENTOS_FICHA.FAIXA.LIBERADO',
    'RELACIONAMENTOS_FICHA.FAIXA.ERRO',
    { nome: nome.value }
  );

const guardarNota = async texto => {
  const certo = await ficha.guardarNota(texto);
  if (certo) caixaDeNotas.value?.limpar();
  resultado(
    certo,
    'RELACIONAMENTOS_FICHA.NOTAS.GUARDADA',
    'RELACIONAMENTOS_FICHA.NOTAS.ERRO'
  );
};

const salvar = async dados => {
  const certo = await ficha.salvar(dados);
  if (certo) gavetaAberta.value = false;
  resultado(
    certo,
    'RELACIONAMENTOS_FICHA.GAVETA.SALVO',
    'RELACIONAMENTOS_FICHA.GAVETA.ERRO_AO_SALVAR'
  );
};

const AVISO_DO_MAIS = {
  juntar: 'JUNTAR',
  bloquear: 'BLOQUEAR',
  apagar: 'APAGAR',
};

// "Alterar informações" abre a gaveta; as outras escolhas só avisam, por ora.
const escolherNoMais = escolha => {
  if (escolha === 'alterar') gavetaAberta.value = true;
  else avisar(AVISO_DO_MAIS[escolha]);
};

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
    data-relacionamentos="pessoa"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col max-w-6xl gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <LinkDeVolta
          :texto="t('RELACIONAMENTOS_FICHA.VOLTAR.PESSOAS')"
          :rotulo="t('RELACIONAMENTOS_FICHA.VOLTAR.ROTULO_PESSOAS')"
          @voltar="acoes.voltarParaLista()"
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
            :frase="t('RELACIONAMENTOS_FICHA.ESTADOS.NAO_ACHEI_PESSOA')"
            :botao="t('RELACIONAMENTOS_FICHA.ESTADOS.VOLTAR_PARA_LISTA')"
            @acao="acoes.voltarParaLista()"
          />
        </div>

        <div
          v-else
          data-relacionamentos="ficha-pessoa"
          class="flex flex-col gap-6"
        >
          <CabecalhoDaPessoa
            :pessoa="ficha.pessoa.value"
            :marcando-cliente="ficha.ocupado.value === 'marcarCliente'"
            @conversar="avisar('CONVERSAR')"
            @novo-card="avisar('NOVO_CARD')"
            @lembrete="avisar('LEMBRETE')"
            @mais-acao="escolherNoMais"
            @marcar-cliente="marcarCliente"
            @abrir-empresa="acoes.abrirEmpresa"
          />

          <FaixaNaoQuer
            v-if="ficha.pessoa.value.opted_out_at"
            :pessoa="ficha.pessoa.value"
            :liberando="ficha.ocupado.value === 'liberar'"
            @liberar="liberar"
          />

          <div
            class="flex flex-col gap-6 lg:grid lg:grid-cols-3 lg:items-start"
          >
            <div class="contents lg:flex lg:flex-col lg:gap-6 lg:col-span-2">
              <SecaoConversas
                class="order-1 lg:order-none"
                :conversas="ficha.conversas.value"
                :agora="agora"
                @conversar="avisar('CONVERSAR')"
                @ver-todas="avisar('VER_TODAS')"
              />
              <SecaoCards
                class="order-2 lg:order-none"
                :cards="ficha.cards.value"
                @abrir="card => (cardAberto = card)"
                @novo-card="avisar('NOVO_CARD')"
              />
              <SecaoNotas
                ref="caixaDeNotas"
                class="order-4 lg:order-none"
                :notas="ficha.notas.value"
                :guardando="ficha.ocupado.value === 'guardarNota'"
                :agora="agora"
                @guardar="guardarNota"
              />
              <SecaoArquivos
                class="order-5 lg:order-none"
                :arquivos="ficha.arquivos.value"
                :agora="agora"
              />
            </div>
            <div class="contents lg:flex lg:flex-col lg:gap-6">
              <CartaoDaSecao
                class="order-3 lg:order-none"
                :titulo="t('RELACIONAMENTOS_FICHA.INFORMACOES.TITULO')"
                data-relacionamentos="informacoes"
              >
                <template #acao>
                  <Button
                    data-relacionamentos="alterar"
                    slate
                    faded
                    class="min-h-11"
                    :label="t('RELACIONAMENTOS_FICHA.INFORMACOES.ALTERAR')"
                    @click="gavetaAberta = true"
                  />
                </template>
                <ListaDeInformacoes :linhas="linhas" :redes="redes" />
              </CartaoDaSecao>
              <DeOndeVeio
                class="order-6 lg:order-none"
                :origem="ficha.origem.value"
              />
            </div>
          </div>
        </div>
      </div>
    </main>

    <GavetaDeInformacoes
      :aberta="gavetaAberta"
      :pessoa="ficha.pessoa.value"
      :salvando="ficha.ocupado.value === 'salvar'"
      @fechar="gavetaAberta = false"
      @salvar="salvar"
    />
    <GavetaDoCard
      :card="cardAberto"
      @fechar="cardAberto = null"
      @abrir-no-crm="abrirNoCrm"
    />
  </section>
</template>
