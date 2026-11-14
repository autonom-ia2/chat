<script setup>
import {
  computed,
  defineAsyncComponent,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import AbasDaLista from '../components/lista/AbasDaLista.vue';
import BarraDeAcaoEmGrupo from '../components/lista/BarraDeAcaoEmGrupo.vue';
import BarraDeControles from '../components/lista/BarraDeControles.vue';
import DialogoApagar from '../components/lista/DialogoApagar.vue';
import DialogoCriarCards from '../components/lista/DialogoCriarCards.vue';
import DialogoEtiqueta from '../components/lista/DialogoEtiqueta.vue';
import DialogoMandarMensagem from '../components/lista/DialogoMandarMensagem.vue';
import EstadoSemAcesso from '../components/lista/EstadoSemAcesso.vue';
import EstadoSemResultado from '../components/lista/EstadoSemResultado.vue';
import LinhasDeExemplo from '../components/lista/LinhasDeExemplo.vue';
import GavetaDeFiltros from '../components/lista/GavetaDeFiltros.vue';
import HeroiDaLista from '../components/lista/HeroiDaLista.vue';
import LinhaDeEmpresa from '../components/lista/LinhaDeEmpresa.vue';
import LinhaDePessoa from '../components/lista/LinhaDePessoa.vue';
import ListaDeLinhas from '../components/lista/ListaDeLinhas.vue';
import MarcarTodas from '../components/lista/MarcarTodas.vue';
import MostrarMais from '../components/lista/MostrarMais.vue';
import { acoesDaListaFonte } from '../fonte/acoesDaListaFonte';
import { ABAS, GRUPO_PADRAO, gruposDaAba } from '../fonte/grupos';
import { ABA_SEGUROS } from '../fonte/gruposDeSeguros';
import { listaFonte } from '../fonte/listaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { chaveDoSeloDaPessoa } from '../carteira/tomDoSelo';
import { useCarteiraNaLista } from '../carteira/useCarteiraNaLista';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { ehSemAcesso } from '../lista/falhas';
import { PAINEL_DAS_ABAS, idDaAba } from '../lista/idsDasAbas';
import { rotaDoTrazer, temOndeTrazer } from '../lista/rotaDoTrazer';
import { contaDaMensagem } from '../lista/quemFicaDeFora';
import { useRolarPilula } from '../lista/useRolarPilula';
import { useAcoesEmGrupo } from '../lista/useAcoesEmGrupo';
import { usePermissoesDaLista } from '../lista/usePermissoesDaLista';
import { useLista } from '../lista/useLista';
import { useMarcados } from '../lista/useMarcados';

// #2897 — a aba Seguros só é baixada quando abre: quem não tem a carteira (ou
// não abre a aba) não carrega a tela dela.
const ListaDeSeguros = defineAsyncComponent(
  () => import('../components/carteira/ListaDeSeguros.vue')
);
// O selo de seguro da linha da pessoa, idem: só é baixado quando há uma pessoa
// com seguro na tela, o que só acontece na conta que tem a carteira.
const SeloDoSeguro = defineAsyncComponent(
  () => import('../components/carteira/SeloDoSeguro.vue')
);

// #2894 — a lista de Relacionamentos: herói com a frase do dia, abas
// Pessoas · Empresas (na URL, `?aba=empresas`), grupos, busca, ordem, "Mais
// filtros", a lista com ações em grupo e os estados (vazio, carregando, erro,
// sem acesso).
// Fala só com `listaFonte` e `acoesDaListaFonte`; em `?demo=` tudo é inventado
// e as escritas só simulam. Fora da demonstração a lista lê do servidor e as
// ações em grupo escrevem nele.
// #2897 — a conta que tem a carteira de seguros ganha a aba Seguros
// (`?aba=seguros`), que é outra peça (components/carteira/ListaDeSeguros.vue):
// enquanto ela está aberta, a lista de pessoas não carrega. Nessa conta a lista
// de pessoas também ganha o selo do seguro ao lado do nome, o grupo "Só tem um
// seguro" e a busca pelo número da apólice (carteira/useCarteiraNaLista.js).
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const demo = usarDemo(route.query);
const acoes = acoesDaListaFonte({ demo });

// Empresas é de quem tem a chave `companies` na conta (sem ela o servidor
// responde 403): a aba some e `?aba=empresas` abre Pessoas. A demonstração
// inventa as empresas e mostra sempre.
const { isCloudFeatureEnabled } = useAccount();
const temEmpresas = computed(
  () => Boolean(demo) || isCloudFeatureEnabled(FEATURE_FLAGS.COMPANIES)
);

// A aba vem da URL, mas só enquanto a rota ainda é a da lista: ao sair para uma
// ficha a query perde o `aba` e, sem isto, a lista dispararia uma carga à toa.
const ROTA_DA_LISTA = 'relationships_home';
const abaPedida = () =>
  temEmpresas.value && route.query.aba === ABAS.EMPRESAS
    ? ABAS.EMPRESAS
    : ABAS.PESSOAS;
let abaDaUrl = abaPedida();
const aba = computed(() => {
  if (route.name && route.name !== ROTA_DA_LISTA) return abaDaUrl;
  abaDaUrl = abaPedida();
  return abaDaUrl;
});
const ehEmpresas = computed(() => aba.value === ABAS.EMPRESAS);

// A aba Seguros é de quem tem a carteira (o servidor diz no payload da conta);
// sem ela a aba some e `?aba=seguros` abre Pessoas. Como a aba de cima, só
// acompanha o endereço enquanto a rota é a da lista.
const temSeguros = useContaDeSeguros(demo);
const segurosPedidos = () =>
  temSeguros.value && route.query.aba === ABA_SEGUROS;
let segurosNaUrl = segurosPedidos();
const naAbaDeSeguros = computed(() => {
  if (route.name && route.name !== ROTA_DA_LISTA) return segurosNaUrl;
  segurosNaUrl = segurosPedidos();
  return segurosNaUrl;
});
// As abas aparecem quando há mais de uma.
const temAbas = computed(() => temEmpresas.value || temSeguros.value);

// "Criar cards", "Etiqueta" e "Apagar" são de quem pode (usePermissoesDaLista);
// a demonstração só simula e mostra as três sempre.
const permissoes = usePermissoesDaLista();
const podeCriarCards = computed(
  () => Boolean(demo) || permissoes.podeCriarCards.value
);
const podeEtiquetar = computed(
  () => Boolean(demo) || permissoes.podeEtiquetar.value
);
const podeApagar = computed(() => Boolean(demo) || permissoes.podeApagar.value);
// #2970 — "Conversar" da linha e "Mandar mensagem" da barra ainda só simulam:
// aparecem só na demonstração. Fora dela, quem não pode nenhuma das três ações
// de verdade não tem o que fazer com gente marcada, e a lista não oferece a
// caixa de marcar (sem ela não há "Marcar todas" nem barra).
const naDemonstracao = Boolean(demo);
const podeMarcar = computed(
  () => podeCriarCards.value || podeEtiquetar.value || podeApagar.value
);
// "Trazer minha lista" é de quem pode importar contatos, e só aparece onde há
// para onde levar (#2947).
const podeTrazer = computed(
  () => temOndeTrazer(demo) && (Boolean(demo) || permissoes.podeTrazer.value)
);

const marcados = useMarcados();
// Na conta com a carteira, cada página de pessoas que chega pede os selos de
// seguro daquelas pessoas; nas outras, a fonte passa como é. Se os selos não
// chegam, a tela avisa acima das linhas: pessoa sem selo se lê como "não tem
// seguro", e aqui isso não se sabe.
const carteira = useCarteiraNaLista({ demo, ligada: temSeguros });
const lista = useLista({
  fonte: carteira.comSelos(listaFonte({ demo, comSeguros: temSeguros })),
  aba,
  aoMudarConsulta: marcados.limpar,
});
// O resumo dos seguros da pessoa da linha (nulo para quem não tem seguro) e o
// texto do selo dela: "Seguro vencido", "Seguro em renovação", "Seguro
// renovado", "Seguro ativo" ou "Seguro cancelado" (os cinco selos da carteira).
const seguroDe = ({ id }) => carteira.daPessoa(id);
// O selo que a tela não conhece vira só "Seguro" (carteira/tomDoSelo.js).
const rotuloDoSeguro = ({ selo }) => t(chaveDoSeloDaPessoa(selo));

// Trocar de aba fecha a gaveta do seguro que estiver aberta (`?apolice=`).
const DA_ABA = ['aba', 'apolice'];
const trocarAba = nova => {
  const resto = Object.fromEntries(
    Object.entries(route.query).filter(([chave]) => !DA_ABA.includes(chave))
  );
  return router.push({
    query: nova === ABAS.PESSOAS ? resto : { ...resto, aba: nova },
  });
};

// O herói acompanha a aba: o grupo para onde o botão leva é sempre da aba que
// está aberta.
const verGrupo = id => lista.escolherGrupo(id);

// Os grupos da aba; a conta com a carteira tem um a mais em Pessoas.
const gruposDaLista = computed(() =>
  gruposDaAba(aba.value, { comSeguros: temSeguros.value })
);
const grupos = computed(() =>
  gruposDaLista.value.map(({ id, nome }) => ({
    id,
    nome: t(nome),
    total: lista.contagens.value[id],
  }))
);
// "Todos" e "Todas" não dizem nada além do nome: sem explicação. A linha mantém
// a altura (`min-h-5`) para a tela não pular ao trocar de grupo.
const explicacao = computed(() => {
  if (lista.grupo.value === GRUPO_PADRAO[aba.value]) return '';
  const atual = gruposDaLista.value.find(g => g.id === lista.grupo.value);
  return atual ? t(atual.explicacao) : '';
});
const contaDeMarcados = computed(() => contaDaMensagem(marcados.pessoas.value));

const contaVazia = computed(() => lista.resumo.value?.total === 0);
// Na conta com a carteira a busca de pessoas também acha pelo número da
// apólice, e o campo diz isso.
const placeholder = computed(() => {
  if (temSeguros.value && !ehEmpresas.value) {
    return t('RELACIONAMENTOS_CARTEIRA.PESSOAS.BUSCA');
  }
  return t(
    `RELACIONAMENTOS.LISTA.BUSCA.PLACEHOLDER_${ehEmpresas.value ? 'EMPRESAS' : 'PESSOAS'}`
  );
});
const placeholderCurto = computed(() =>
  t(
    `RELACIONAMENTOS.LISTA.BUSCA.PLACEHOLDER_CURTO_${ehEmpresas.value ? 'EMPRESAS' : 'PESSOAS'}`
  )
);
const faltamMarcar = computed(
  () => marcados.quantos.value > 0 && marcados.quantos.value < lista.total.value
);

// A lista sem ninguém: a frase (e a saída, quando há) depende do que a pessoa
// pediu. Nasce sempre da mesma conta, para a tela e o aviso falado coincidirem.
const semResultado = computed(() => {
  if (lista.itens.value.length) return null;
  const sufixo = ehEmpresas.value ? '_EMPRESAS' : '';
  const estados = 'RELACIONAMENTOS.LISTA.ESTADOS';
  if (lista.busca.value) {
    return {
      frase: t(`${estados}.BUSCA_SEM_RESULTADO${sufixo}`, {
        busca: lista.busca.value,
      }),
      botao: t(`${estados}.LIMPAR_BUSCA`),
      acao: () => lista.mudarBusca(''),
    };
  }
  if (lista.filtrosAtivos.value) {
    return {
      frase: t(`${estados}.FILTROS_SEM_RESULTADO`),
      botao: t(`${estados}.LIMPAR_FILTROS`),
      acao: lista.limparFiltros,
    };
  }
  return { frase: t(`${estados}.GRUPO_VAZIO${sufixo}`), botao: '', acao: null };
});
// Quem não pode ver lê só isto, sem "tentar de novo" e sem busca, grupos ou
// filtros agindo sobre nada.
const fraseSemAcesso = computed(() =>
  ehEmpresas.value
    ? t('RELACIONAMENTOS.LISTA.ESTADOS.SEM_ACESSO_EMPRESAS')
    : t('RELACIONAMENTOS.LISTA.ESTADOS.SEM_ACESSO')
);
// Região viva única e permanente: o leitor de tela só anuncia o que muda dentro
// de uma região que já estava na página, não a que nasce junto com o texto.
const avisoDaLista = computed(() =>
  !lista.erro.value && !lista.carregando.value && semResultado.value
    ? semResultado.value.frase
    : ''
);

const trazer = () => router.push({ name: rotaDoTrazer(demo) });
// O quadro do CRM, a mesma rota do item do menu (Sidebar.vue).
const abrirCrm = () => router.push({ name: 'crm_kanban_index' });
const abrirPessoa = ({ id }) =>
  router.push({ name: 'relacionamentos_pessoa', params: { contactId: id } });
const abrirEmpresa = ({ id }) =>
  router.push({ name: 'relacionamentos_empresa', params: { companyId: id } });
// Simulado: a conversa e a campanha reais ainda não recebem a pessoa de fora.
// Só a demonstração chega aqui (#2970).
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

const acoesEmGrupo = useAcoesEmGrupo({
  lista,
  marcados,
  aba,
  aoFalhar: () => useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO')),
});

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
  } catch (falha) {
    useAlert(
      ehSemAcesso(falha)
        ? fraseSemAcesso.value
        : t('RELACIONAMENTOS.COMUM.ERRO_GENERICO')
    );
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

// Com gente marcada a barra de ação fica colada no rodapé: a lista ganha folga
// do tamanho dela, e abaixo de `md` a barra deixa livre o canto do botão ☰.
const barraVisivel = computed(
  () => marcados.quantos.value > 0 && !ehEmpresas.value
);

const raiz = useTemplateRef('raiz');
useRolarPilula(raiz, lista.grupo);

// Na aba Seguros quem carrega é a peça dela. Ao voltar, a lista se atualiza.
onMounted(() => {
  if (!naAbaDeSeguros.value) lista.iniciar();
});
watch(naAbaDeSeguros, estaNela => {
  if (!estaNela) lista.recarregar();
});
</script>

<template>
  <section
    ref="raiz"
    class="flex flex-col flex-1 w-full h-full min-w-0 bg-n-surface-1"
    data-relacionamentos="lista"
  >
    <ListaDeSeguros
      v-if="naAbaDeSeguros"
      :demo="demo"
      :com-empresas="temEmpresas"
      @trocar-aba="trocarAba"
    />
    <main v-else class="flex-1 min-w-0 overflow-y-auto">
      <div
        class="flex flex-col w-full min-w-0 max-w-6xl min-h-full gap-6 px-5 pt-8 mx-auto md:px-8 md:pt-10"
        :class="barraVisivel ? 'pb-48 md:pb-28' : 'pb-24 md:pb-10'"
      >
        <h1 class="sr-only">{{ t('RELACIONAMENTOS.LISTA.TITULO') }}</h1>
        <p role="status" class="sr-only" data-relacionamentos="aviso-da-lista">
          {{ avisoDaLista }}
        </p>

        <EstadoSemAcesso
          v-if="lista.semAcesso.value && !lista.resumo.value"
          :frase="fraseSemAcesso"
        />
        <ErroComTentarDeNovo
          v-else-if="lista.erro.value && !lista.resumo.value"
          :mensagem="t('RELACIONAMENTOS.LISTA.ERRO_DA_TELA')"
          data-relacionamentos="erro"
          @tentar="lista.recarregar"
        />
        <EsqueletoDeLista
          v-else-if="!lista.resumo.value"
          com-topo
          data-relacionamentos="carregando"
        />
        <template v-else>
          <HeroiDaLista
            :data-relacionamentos="contaVazia ? 'vazio' : undefined"
            :resumo="lista.resumo.value"
            :aba="aba"
            :pode-trazer="podeTrazer"
            @trazer="trazer"
            @ver-grupo="verGrupo"
          />
          <LinhasDeExemplo v-if="contaVazia" />
          <template v-else>
            <AbasDaLista
              v-if="temAbas"
              :com-empresas="temEmpresas"
              :com-seguros="temSeguros"
              :model-value="aba"
              @update:model-value="trocarAba"
            />
            <div
              :id="PAINEL_DAS_ABAS"
              :role="temAbas ? 'tabpanel' : undefined"
              :aria-labelledby="temAbas ? idDaAba(aba) : undefined"
              class="flex flex-col min-w-0 gap-5"
            >
              <div v-if="!lista.semAcesso.value" class="flex flex-col">
                <PilulasDeGrupo
                  :grupos="grupos"
                  :model-value="lista.grupo.value"
                  @update:model-value="lista.escolherGrupo"
                />
                <p
                  aria-live="polite"
                  class="m-0 text-sm text-n-slate-11"
                  :class="{ 'mt-3': explicacao }"
                  data-relacionamentos="explicacao-do-grupo"
                >
                  {{ explicacao }}
                </p>
              </div>
              <BarraDeControles
                v-if="!lista.semAcesso.value"
                :busca="lista.busca.value"
                :ordem="lista.ordem.value"
                :filtros-ativos="lista.filtrosAtivos.value"
                :com-filtros="!ehEmpresas"
                :placeholder="placeholder"
                :placeholder-curto="placeholderCurto"
                @update:busca="lista.mudarBusca"
                @update:ordem="lista.mudarOrdem"
                @abrir-filtros="abrirFiltros"
              />
              <EstadoSemAcesso
                v-if="lista.semAcesso.value"
                :frase="fraseSemAcesso"
              />
              <ErroComTentarDeNovo
                v-else-if="lista.erro.value"
                :mensagem="t('RELACIONAMENTOS.LISTA.ERRO_DA_TELA')"
                data-relacionamentos="erro"
                @tentar="lista.recarregar"
              />
              <EsqueletoDeLista
                v-else-if="lista.carregando.value"
                data-relacionamentos="carregando"
              />
              <EstadoSemResultado
                v-else-if="semResultado"
                :frase="semResultado.frase"
                :botao="semResultado.botao"
                @acao="semResultado.acao"
              />
              <template v-else>
                <Banner
                  v-if="temSeguros && !ehEmpresas && carteira.falhou.value"
                  color="amber"
                  role="alert"
                  data-carteira="aviso-dos-selos"
                >
                  <div class="flex flex-wrap items-center gap-3">
                    <span class="text-sm">
                      {{ t('RELACIONAMENTOS_CARTEIRA.PESSOAS.SELOS_FALHARAM') }}
                    </span>
                    <Button
                      slate
                      faded
                      size="lg"
                      data-carteira="tentar-os-selos"
                      :is-loading="carteira.tentando.value"
                      :label="t('RELACIONAMENTOS.COMUM.TENTAR_DE_NOVO')"
                      @click="carteira.tentarDeNovo"
                    />
                  </div>
                </Banner>
                <MarcarTodas
                  v-if="!ehEmpresas && faltamMarcar"
                  :total="lista.total.value"
                  :carregando="acoesEmGrupo.marcandoTodas.value"
                  @marcar-todas="acoesEmGrupo.marcarTodas"
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
                      :pode-marcar="podeMarcar"
                      :pode-conversar="naDemonstracao"
                      @alternar="marcados.alternar"
                      @abrir="abrirPessoa"
                      @conversar="conversar"
                    >
                      <template v-if="seguroDe(pessoa)" #selos>
                        <SeloDoSeguro
                          :seguro="seguroDe(pessoa)"
                          :rotulo="rotuloDoSeguro(seguroDe(pessoa))"
                        />
                      </template>
                    </LinhaDePessoa>
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
            v-if="barraVisivel"
            class="sticky z-30 mt-auto bottom-4 ms-20 md:ms-0"
            :quantas="marcados.quantos.value"
            :conta="contaDeMarcados"
            :pode-mandar-mensagem="naDemonstracao"
            :pode-criar-cards="podeCriarCards"
            :pode-etiquetar="podeEtiquetar"
            :pode-apagar="podeApagar"
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
    <!-- #2970: sem "Mandar mensagem" fora da demonstração, nada abre isto. -->
    <DialogoMandarMensagem
      v-if="naDemonstracao"
      ref="dialogoDeMensagem"
      :pessoas="marcados.pessoas.value"
      @continuar="abrirCampanha"
    />
    <DialogoCriarCards
      ref="dialogoDeCards"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="acoesEmGrupo.depoisDeAgir"
      @abrir-crm="abrirCrm"
    />
    <DialogoEtiqueta
      ref="dialogoDeEtiqueta"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="acoesEmGrupo.depoisDeAgir"
    />
    <DialogoApagar
      ref="dialogoDeApagar"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      @concluido="acoesEmGrupo.depoisDeAgir"
    />
  </section>
</template>
