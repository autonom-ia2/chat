<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AbasDaLista from '../components/lista/AbasDaLista.vue';
import BarraDeAcaoEmGrupo from '../components/lista/BarraDeAcaoEmGrupo.vue';
import BarraDeControles from '../components/lista/BarraDeControles.vue';
import DialogoApagar from '../components/lista/DialogoApagar.vue';
import DialogoCriarCards from '../components/lista/DialogoCriarCards.vue';
import DialogoEtiqueta from '../components/lista/DialogoEtiqueta.vue';
import DialogoMandarMensagem from '../components/lista/DialogoMandarMensagem.vue';
import EstadoSemResultado from '../components/lista/EstadoSemResultado.vue';
import GavetaDeFiltros from '../components/lista/GavetaDeFiltros.vue';
import HeroiDaLista from '../components/lista/HeroiDaLista.vue';
import LinhaDeEmpresa from '../components/lista/LinhaDeEmpresa.vue';
import LinhaDePessoa from '../components/lista/LinhaDePessoa.vue';
import ListaDeLinhas from '../components/lista/ListaDeLinhas.vue';
import MarcarTodas from '../components/lista/MarcarTodas.vue';
import MostrarMais from '../components/lista/MostrarMais.vue';
import { acoesDaListaFonte } from '../fonte/acoesDaListaFonte';
import { ABAS, gruposDaAba } from '../fonte/grupos';
import { listaFonte } from '../fonte/listaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { PAINEL_DAS_ABAS, idDaAba } from '../lista/idsDasAbas';
import { useLista } from '../lista/useLista';
import { useMarcados } from '../lista/useMarcados';

// #2894 — a lista de Relacionamentos: herói com a frase do dia, abas
// Pessoas · Empresas (na URL, `?aba=empresas`), grupos, busca, ordem, "Mais
// filtros", a lista com ações em grupo e os estados (vazio, carregando, erro).
// Fala só com `listaFonte` e `acoesDaListaFonte`; em `?demo=` tudo é inventado
// e as escritas só simulam.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const demo = usarDemo(route.query);
const acoes = acoesDaListaFonte({ demo });

const aba = computed(() =>
  route.query.aba === ABAS.EMPRESAS ? ABAS.EMPRESAS : ABAS.PESSOAS
);
const ehEmpresas = computed(() => aba.value === ABAS.EMPRESAS);

const marcados = useMarcados();
const lista = useLista({
  fonte: listaFonte({ demo }),
  aba,
  aoMudarConsulta: marcados.limpar,
});

const trocarAba = nova => {
  const resto = Object.fromEntries(
    Object.entries(route.query).filter(([chave]) => chave !== 'aba')
  );
  router.push({
    query: nova === ABAS.EMPRESAS ? { ...resto, aba: nova } : resto,
  });
};

const grupos = computed(() =>
  gruposDaAba(aba.value).map(({ id, nome }) => ({
    id,
    nome: t(nome),
    total: lista.contagens.value[id],
  }))
);
const explicacao = computed(() => {
  const atual = gruposDaAba(aba.value).find(g => g.id === lista.grupo.value);
  return atual ? t(atual.explicacao) : '';
});

const contaVazia = computed(() => lista.resumo.value?.total === 0);
const placeholder = computed(() =>
  t(
    `RELACIONAMENTOS.LISTA.BUSCA.PLACEHOLDER_${ehEmpresas.value ? 'EMPRESAS' : 'PESSOAS'}`
  )
);
const faltamMarcar = computed(
  () => marcados.quantos.value > 0 && marcados.quantos.value < lista.total.value
);

const trazer = () => router.push({ name: 'relacionamentos_trazer' });
const abrirPessoa = ({ id }) =>
  router.push({ name: 'relacionamentos_pessoa', params: { contactId: id } });
const abrirEmpresa = ({ id }) =>
  router.push({ name: 'relacionamentos_empresa', params: { companyId: id } });
// Simulado: a conversa e a campanha reais ainda não recebem a pessoa de fora.
const conversar = ({ name }) =>
  useAlert(t('RELACIONAMENTOS.LISTA.LINHA.ABRINDO_CONVERSA', { nome: name }));
const abrirCampanha = quantas =>
  useAlert(
    t(
      'RELACIONAMENTOS.LISTA.MENSAGEM.ABRINDO_CAMPANHA',
      { count: quantas },
      quantas
    )
  );

const marcarTodas = async () => {
  try {
    marcados.marcarVarias(await lista.todosDoGrupo());
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
  }
};

const dialogoDeMensagem = useTemplateRef('dialogoDeMensagem');
const dialogoDeCards = useTemplateRef('dialogoDeCards');
const dialogoDeEtiqueta = useTemplateRef('dialogoDeEtiqueta');
const dialogoDeApagar = useTemplateRef('dialogoDeApagar');

const gavetaAberta = ref(false);
const opcoesDeFiltro = ref({ empresas: [], etiquetas: [], cidades: [] });
const abrirFiltros = async () => {
  gavetaAberta.value = true;
  try {
    opcoesDeFiltro.value = await listaFonte({ demo }).opcoesDeFiltro();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
  }
};
const aplicarFiltros = novos => {
  gavetaAberta.value = false;
  lista.mudarFiltros(novos);
};
const limparFiltros = () => {
  gavetaAberta.value = false;
  lista.limparFiltros();
};

onMounted(lista.iniciar);
</script>

<template>
  <section
    class="flex flex-col h-full bg-n-surface-1"
    data-relacionamentos="lista"
  >
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col max-w-6xl min-h-full gap-6 px-5 py-8 mx-auto md:px-8 md:py-10"
      >
        <h1 class="sr-only">{{ t('RELACIONAMENTOS.LISTA.TITULO') }}</h1>

        <ErroComTentarDeNovo
          v-if="lista.erro.value && !lista.resumo.value"
          data-relacionamentos="erro"
          @tentar="lista.recarregar"
        />
        <EsqueletoDeLista
          v-else-if="!lista.resumo.value"
          data-relacionamentos="carregando"
        />
        <template v-else>
          <HeroiDaLista
            :resumo="lista.resumo.value"
            @trazer="trazer"
            @ver-grupo="lista.escolherGrupo"
          />
          <VazioComUmBotao
            v-if="contaVazia"
            data-relacionamentos="vazio"
            :frase="t('RELACIONAMENTOS.LISTA.ESTADOS.CONTA_VAZIA')"
            :botao="t('RELACIONAMENTOS.COMUM.TRAZER_MINHA_LISTA')"
            @acao="trazer"
          />
          <template v-else>
            <AbasDaLista :model-value="aba" @update:model-value="trocarAba" />
            <div
              :id="PAINEL_DAS_ABAS"
              role="tabpanel"
              :aria-labelledby="idDaAba(aba)"
              class="flex flex-col gap-5"
            >
              <div class="flex flex-col gap-3">
                <PilulasDeGrupo
                  :grupos="grupos"
                  :model-value="lista.grupo.value"
                  @update:model-value="lista.escolherGrupo"
                />
                <p aria-live="polite" class="m-0 text-sm text-n-slate-11">
                  {{ explicacao }}
                </p>
              </div>
              <BarraDeControles
                :busca="lista.busca.value"
                :ordem="lista.ordem.value"
                :filtros-ativos="lista.filtrosAtivos.value"
                :com-filtros="!ehEmpresas"
                :placeholder="placeholder"
                @update:busca="lista.mudarBusca"
                @update:ordem="lista.mudarOrdem"
                @abrir-filtros="abrirFiltros"
              />
              <ErroComTentarDeNovo
                v-if="lista.erro.value"
                data-relacionamentos="erro"
                @tentar="lista.recarregar"
              />
              <EsqueletoDeLista
                v-else-if="lista.carregando.value"
                data-relacionamentos="carregando"
              />
              <EstadoSemResultado
                v-else-if="!lista.itens.value.length && lista.busca.value"
                :frase="
                  t(
                    `RELACIONAMENTOS.LISTA.ESTADOS.BUSCA_SEM_RESULTADO${ehEmpresas ? '_EMPRESAS' : ''}`,
                    { busca: lista.busca.value }
                  )
                "
                :botao="t('RELACIONAMENTOS.LISTA.ESTADOS.LIMPAR_BUSCA')"
                @acao="lista.mudarBusca('')"
              />
              <EstadoSemResultado
                v-else-if="
                  !lista.itens.value.length && lista.filtrosAtivos.value
                "
                :frase="
                  t('RELACIONAMENTOS.LISTA.ESTADOS.FILTROS_SEM_RESULTADO')
                "
                :botao="t('RELACIONAMENTOS.LISTA.ESTADOS.LIMPAR_FILTROS')"
                @acao="lista.limparFiltros"
              />
              <EstadoSemResultado
                v-else-if="!lista.itens.value.length"
                :frase="
                  t(
                    `RELACIONAMENTOS.LISTA.ESTADOS.GRUPO_VAZIO${ehEmpresas ? '_EMPRESAS' : ''}`
                  )
                "
              />
              <template v-else>
                <MarcarTodas
                  v-if="!ehEmpresas && faltamMarcar"
                  :total="lista.total.value"
                  @marcar-todas="marcarTodas"
                />
                <ListaDeLinhas>
                  <template v-if="ehEmpresas">
                    <LinhaDeEmpresa
                      v-for="empresa in lista.itens.value"
                      :key="empresa.id"
                      :empresa="empresa"
                      @abrir="abrirEmpresa"
                    />
                  </template>
                  <template v-else>
                    <LinhaDePessoa
                      v-for="pessoa in lista.itens.value"
                      :key="pessoa.id"
                      :pessoa="pessoa"
                      :marcada="marcados.ehMarcado(pessoa.id)"
                      @alternar="marcados.alternar"
                      @abrir="abrirPessoa"
                      @conversar="conversar"
                    />
                  </template>
                </ListaDeLinhas>
                <MostrarMais
                  :mostradas="lista.itens.value.length"
                  :total="lista.total.value"
                  :tem-mais="lista.temMais.value"
                  :carregando="lista.carregandoMais.value"
                  @mais="lista.mostrarMais"
                />
              </template>
            </div>
          </template>
        </template>

        <transition
          enter-active-class="transition duration-200 ease-out"
          enter-from-class="translate-y-4 opacity-0"
          leave-active-class="transition duration-150 ease-in"
          leave-to-class="translate-y-4 opacity-0"
        >
          <BarraDeAcaoEmGrupo
            v-if="marcados.quantos.value > 0 && !ehEmpresas"
            class="sticky z-30 mt-auto bottom-4"
            :quantas="marcados.quantos.value"
            @mandar-mensagem="dialogoDeMensagem.abrir()"
            @criar-cards="dialogoDeCards.abrir()"
            @etiqueta="dialogoDeEtiqueta.abrir()"
            @apagar="dialogoDeApagar.abrir()"
            @fechar="marcados.limpar"
          />
        </transition>
      </div>
    </main>

    <GavetaDeFiltros
      :aberta="gavetaAberta"
      :filtros="lista.filtros.value"
      :opcoes="opcoesDeFiltro"
      @fechar="gavetaAberta = false"
      @aplicar="aplicarFiltros"
      @limpar="limparFiltros"
    />
    <DialogoMandarMensagem
      ref="dialogoDeMensagem"
      :pessoas="marcados.pessoas.value"
      @continuar="abrirCampanha"
    />
    <DialogoCriarCards
      ref="dialogoDeCards"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="marcados.limpar"
    />
    <DialogoEtiqueta
      ref="dialogoDeEtiqueta"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="marcados.limpar"
    />
    <DialogoApagar
      ref="dialogoDeApagar"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="marcados.limpar"
    />
  </section>
</template>
