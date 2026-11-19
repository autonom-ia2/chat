<script setup>
import {
  computed,
  defineAsyncComponent,
  onMounted,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { declararContexto } from 'dashboard/composables/useContextoDaTela';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import PilulasDeGrupo from '../components/comum/PilulasDeGrupo.vue';
import AbasDaLista from '../components/lista/AbasDaLista.vue';
import AcoesDaAba from '../components/lista/AcoesDaAba.vue';
import BarraDeAcaoEmGrupo from '../components/lista/BarraDeAcaoEmGrupo.vue';
import BarraDeControles from '../components/lista/BarraDeControles.vue';
import DialogoApagar from '../components/lista/DialogoApagar.vue';
import DialogoCriarCards from '../components/lista/DialogoCriarCards.vue';
import DialogoEtiqueta from '../components/lista/DialogoEtiqueta.vue';
import DialogoMandarMensagem from '../components/lista/DialogoMandarMensagem.vue';
import DialogoPlanilha from '../components/lista/DialogoPlanilha.vue';
import GavetaDeInformacoes from '../components/ficha/GavetaDeInformacoes.vue';
import AvisoComDesfazer from '../components/carteira/AvisoComDesfazer.vue';
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
import NovaEmpresaNaLista from '../components/lista/NovaEmpresaNaLista.vue';
import { acoesDaListaFonte } from '../fonte/acoesDaListaFonte';
import { ABAS, GRUPO_PADRAO, gruposDaAba } from '../fonte/grupos';
import { ABA_SEGUROS } from '../fonte/gruposDeSeguros';
import { listaFonte } from '../fonte/listaFonte';
import { diasParaTerminar } from '../fonte/selosDoSeguro';
import { usarDemo } from '../fonte/modoDemo';
import { chaveDoSeloDaPessoa } from '../carteira/tomDoSelo';
import { useCarteiraNaLista } from '../carteira/useCarteiraNaLista';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { useGavetaDeFiltros } from '../lista/useGavetaDeFiltros';
import { PAINEL_DAS_ABAS, idDaAba } from '../lista/idsDasAbas';
import { contaDaMensagem } from '../lista/quemFicaDeFora';
import { useRolarPilula } from '../lista/useRolarPilula';
import { useAcoesEmGrupo } from '../lista/useAcoesEmGrupo';
import { usePermissoesDaLista } from '../lista/usePermissoesDaLista';
import { useLista } from '../lista/useLista';
import { useMarcados } from '../lista/useMarcados';
import { CAMPOS_DE_ORDEM_DAS_EMPRESAS, gruposDeOrdem } from '../lista/ordens';
import { useOrdemGuardada } from '../lista/useOrdemGuardada';
import { usePessoaNaGaveta } from '../lista/usePessoaNaGaveta';
import { useCamposDaConta } from '../ficha/useCamposDaConta';
import { useDevolverEtiquetas } from '../lista/useDevolverEtiquetas';

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
// #3062 — paridade com a lista de contatos de hoje, na aba Pessoas: "Nova
// pessoa" e "Baixar planilha" ao lado das abas, "Etiquetas" (colocar e tirar
// várias) na barra de ação em grupo, as sete ordens guardadas por pessoa da
// equipe, o grupo "No site agora", o lápis de editar na linha e as pessoas
// marcadas indo para o Guia (#934). No celular, "Nova pessoa" fica à vista
// acima das abas e "Baixar planilha" vira a última linha da lista; o lápis
// some (tocar na linha abre a ficha).
// #3078 — a aba Empresas com o que a lista antiga de Empresas tinha: "Nova
// empresa", as cinco ordens guardadas dela, "Mais filtros" (cidade e quando
// chegou), a foto e a cidade na linha, e marcar empresas para apagar (a única
// ação em grupo de empresa; "Marcar todas" fica só em Pessoas).
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
// #3062 — "Nova pessoa" e o lápis da linha: quem edita contato; "Baixar
// planilha": quem exporta contato. As regras da lista de contatos de hoje.
const podeEditar = computed(() => Boolean(demo) || permissoes.podeEditar.value);
const podeBaixar = computed(
  () => Boolean(demo) || permissoes.podeExportar.value
);
// #2970 — "Conversar" da linha e "Mandar mensagem" da barra ainda só simulam:
// aparecem só na demonstração. Fora dela, quem não pode nenhuma das três ações
// de verdade não tem o que fazer com gente marcada, e a lista não oferece a
// caixa de marcar (sem ela não há "Marcar todas" nem barra).
const naDemonstracao = Boolean(demo);
const podeMarcar = computed(
  () => podeCriarCards.value || podeEtiquetar.value || podeApagar.value
);
// Empresa marcada só serve para apagar.
const podeMarcarEmpresas = podeApagar;
// #2896 — "Trazer minha lista" só aparece para quem pode importar contato.
const podeTrazer = computed(() => Boolean(demo) || permissoes.podeTrazer.value);

const marcados = useMarcados();
// #934 — as pessoas marcadas vão ao Guia ("põe a etiqueta nesses"), como na
// lista de contatos de hoje; na aba Empresas, as empresas marcadas.
declararContexto({
  selecionados: () => ({
    recurso: ehEmpresas.value ? 'companies' : 'contacts',
    ids: marcados.pessoas.value.map(({ id }) => id),
  }),
});
const ordemGuardada = useOrdemGuardada({ demo });
// Na conta com a carteira, cada página de pessoas que chega pede os selos de
// seguro daquelas pessoas; nas outras, a fonte passa como é. Se os selos não
// chegam, a tela avisa acima das linhas: pessoa sem selo se lê como "não tem
// seguro", e aqui isso não se sabe.
const carteira = useCarteiraNaLista({ demo, ligada: temSeguros });
const lista = useLista({
  fonte: carteira.comSelos(listaFonte({ demo, comSeguros: temSeguros })),
  aba,
  aoMudarConsulta: marcados.limpar,
  ordemPadrao: ordemGuardada.ordemDaAba,
});
const mudarOrdem = nova => {
  ordemGuardada.guardar(nova, aba.value);
  return lista.mudarOrdem(nova);
};
const ordensDaAba = computed(() =>
  ehEmpresas.value
    ? gruposDeOrdem(t, CAMPOS_DE_ORDEM_DAS_EMPRESAS)
    : gruposDeOrdem(t)
);
// O resumo dos seguros da pessoa da linha (nulo para quem não tem seguro) e o
// texto do selo dela: "Seguro vencido", "Seguro em renovação", "Seguro
// renovado", "Seguro ativo" ou "Seguro cancelado" (os cinco selos da carteira).
const seguroDe = ({ id }) => carteira.daPessoa(id);
// O selo que a tela não conhece vira só "Seguro", e o ativo que termina em até
// 30 dias diz "Seguro vence logo" (carteira/tomDoSelo.js).
const rotuloDoSeguro = seguro =>
  t(chaveDoSeloDaPessoa(seguro.selo, diasParaTerminar(seguro)));

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

// "Clientes · busca “ana” · 2 filtros": a lista que a planilha leva.
const PLANILHA = 'RELACIONAMENTOS.LISTA.PLANILHA';
const listaDaPlanilha = computed(() => {
  const atual = grupos.value.find(({ id }) => id === lista.grupo.value);
  const filtros = lista.filtrosAtivos.value;
  return [
    atual?.nome,
    lista.busca.value && t(`${PLANILHA}.BUSCA`, { busca: lista.busca.value }),
    filtros && t(`${PLANILHA}.FILTROS`, { count: filtros }, filtros),
  ]
    .filter(Boolean)
    .join(' · ');
});
const consultaDaTela = () => ({
  aba: aba.value,
  grupo: lista.grupo.value,
  busca: lista.busca.value,
  ordem: lista.ordem.value,
  filtros: lista.filtros.value,
});

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
// Tirar etiquetas: o aviso com "Desfazer" fica no lugar da barra até a próxima
// ação (marcar alguém de novo o tira).
const devolucao = useDevolverEtiquetas({
  acoes,
  t,
  aoDevolver: () => lista.atualizar(),
});
watch(marcados.quantos, quantas => {
  if (quantas) devolucao.limpar();
});

// Região viva única e permanente: o leitor de tela só anuncia o que muda dentro
// de uma região que já estava na página, não a que nasce junto com o texto.
// O aviso de "Tirar etiquetas" (com "Desfazer") também é lido por aqui: a
// faixa dele nasce junto com o texto.
const avisoDaLista = computed(() => {
  if (devolucao.texto.value) return devolucao.texto.value;
  return !lista.erro.value && !lista.carregando.value && semResultado.value
    ? semResultado.value.frase
    : '';
});

// #3057 — a aba de onde a pessoa saiu vai junto (`?aba=`): a volta de "Como
// trazer" leva de novo a ela (VoltarDoTrazer).
const abaDeOrigem = () => {
  if (naAbaDeSeguros.value) return ABA_SEGUROS;
  return ehEmpresas.value ? ABAS.EMPRESAS : null;
};
const trazer = () => {
  const origem = abaDeOrigem();
  router.push(
    origem
      ? { name: 'relacionamentos_trazer', query: { aba: origem } }
      : { name: 'relacionamentos_trazer' }
  );
};
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
const dialogoDaPlanilha = useTemplateRef('dialogoDaPlanilha');

// "Nova pessoa" e o lápis da linha: a gaveta "Alterar informações" da ficha.
// Depois de criar, abre a ficha nova (o próximo passo de quem acabou de
// cadastrar); depois de editar, a lista se atualiza sem sair do lugar.
// #3075 — com a empresa cadastrada (`temEmpresas`) e os campos personalizados
// da conta. A lista não lê o configurador de campos (seria uma leitura a mais
// ao abrir a lista): os campos vêm na ordem da conta.
const camposDaConta = useCamposDaConta({ comConfiguracao: false });
const gaveta = usePessoaNaGaveta({
  acoes,
  aoCriar: criada => {
    useAlert(
      t('RELACIONAMENTOS.LISTA.NOVA_PESSOA.CRIADA', { nome: criada.name })
    );
    abrirPessoa(criada);
  },
  aoSalvar: dados => {
    useAlert(t('RELACIONAMENTOS.LISTA.EDITAR.SALVO', { nome: dados.name }));
    lista.atualizar();
  },
  // #3075 — `parcial`: a pessoa ficou gravada e só a foto (ou um campo que
  // sai) falhou. A lista já a mostra; "Salvar" de novo repete só o que faltou.
  aoFalhar: (nova, { parcial = false } = {}) => {
    if (parcial) {
      useAlert(t('RELACIONAMENTOS_FICHA.GAVETA.SALVOU_EM_PARTE'));
      lista.atualizar();
      return;
    }
    useAlert(
      t(
        nova
          ? 'RELACIONAMENTOS.LISTA.NOVA_PESSOA.ERRO'
          : 'RELACIONAMENTOS_FICHA.GAVETA.ERRO_AO_SALVAR'
      )
    );
  },
});
// As ações ao lado das abas só existem para quem pode e com a lista à vista:
// sem acesso não há o que criar nem baixar; sem ninguém, não há o que baixar.
// "Baixar planilha" é só de Pessoas (a lista antiga de Empresas não tinha);
// criar existe nas duas (#3078: "Nova empresa").
const criarNaAba = computed(() => !lista.semAcesso.value && podeEditar.value);
const novaEmpresa = useTemplateRef('novaEmpresa');
const criar = () =>
  ehEmpresas.value ? novaEmpresa.value?.abrir() : gaveta.abrirNova();
const baixarNaAba = computed(
  () =>
    !ehEmpresas.value &&
    !lista.semAcesso.value &&
    !contaVazia.value &&
    podeBaixar.value
);
// #3057 — as abas sublinhadas: a linha fina embaixo delas atravessa a linha
// inteira, por baixo das ações também.
const abasAVista = computed(() => temAbas.value && !contaVazia.value);
const temLinhaDasAbas = computed(
  () => abasAVista.value || criarNaAba.value || baixarNaAba.value
);

const tituloDaGaveta = computed(() =>
  gaveta.ehNova.value
    ? t('RELACIONAMENTOS.LISTA.NOVA_PESSOA.TITULO')
    : t('RELACIONAMENTOS.LISTA.LINHA.EDITAR', {
        nome: gaveta.pessoa.value?.name ?? '',
      })
);
const salvarDaGaveta = computed(() =>
  gaveta.ehNova.value ? t('RELACIONAMENTOS.LISTA.NOVA_PESSOA.SALVAR') : ''
);

const maisFiltros = useGavetaDeFiltros({
  lista,
  lerOpcoes: () => listaFonte({ demo }).opcoesDeFiltro(),
  fraseSemAcesso: () => fraseSemAcesso.value,
  erroGenerico: () => t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'),
});

// Com gente marcada a barra de ação fica colada no rodapé: a lista ganha folga
// do tamanho dela, e abaixo de `md` a barra deixa livre o canto do botão ☰.
const barraVisivel = computed(() => marcados.quantos.value > 0);

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
      :pode-trazer="podeTrazer"
      @trocar-aba="trocarAba"
      @trazer="trazer"
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
          <!-- No celular as ações sobem para cima das abas, e as abas levam a
          própria linha: com três abas e "Nova pessoa" lado a lado não cabe. -->
          <div
            v-if="temLinhaDasAbas"
            data-relacionamentos="linha-das-abas"
            class="flex flex-wrap items-center justify-between gap-3 sm:flex-nowrap"
            :class="{ 'sm:border-b sm:border-n-weak': abasAVista }"
          >
            <AbasDaLista
              v-if="abasAVista"
              class="w-full min-w-0 sm:w-auto sm:-mb-px"
              :com-empresas="temEmpresas"
              :com-seguros="temSeguros"
              :model-value="aba"
              @update:model-value="trocarAba"
            />
            <AcoesDaAba
              v-if="criarNaAba || baixarNaAba"
              class="order-first ms-auto shrink-0 sm:order-none"
              :pode-criar="criarNaAba"
              :pode-baixar="baixarNaAba"
              :de-empresas="ehEmpresas"
              @criar="criar"
              @baixar="dialogoDaPlanilha.abrir()"
            />
          </div>
          <LinhasDeExemplo v-if="contaVazia" />
          <template v-else>
            <div
              :id="PAINEL_DAS_ABAS"
              :role="temAbas ? 'tabpanel' : undefined"
              :aria-labelledby="temAbas ? idDaAba(aba) : undefined"
              class="flex flex-col min-w-0 gap-5"
            >
              <div v-if="!lista.semAcesso.value" class="flex flex-col">
                <PilulasDeGrupo
                  sem-vazios
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
                :grupos-de-ordem="ordensDaAba"
                :filtros-ativos="lista.filtrosAtivos.value"
                :placeholder="placeholder"
                :placeholder-curto="placeholderCurto"
                @update:busca="lista.mudarBusca"
                @update:ordem="mudarOrdem"
                @abrir-filtros="maisFiltros.abrir"
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
                      :marcada="marcados.ehMarcado(empresa.id)"
                      :pode-marcar="podeMarcarEmpresas"
                      @alternar="marcados.alternar"
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
                      :pode-editar="podeEditar"
                      @alternar="marcados.alternar"
                      @abrir="abrirPessoa"
                      @conversar="conversar"
                      @editar="gaveta.abrirEdicao"
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
                <Button
                  v-if="baixarNaAba"
                  slate
                  faded
                  icon="i-lucide-download"
                  class="w-full min-h-11 sm:hidden"
                  data-relacionamentos="baixar-no-fim"
                  aria-haspopup="dialog"
                  :label="t('RELACIONAMENTOS.LISTA.TOPO.BAIXAR_NO_FIM')"
                  @click="dialogoDaPlanilha.abrir()"
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
            :conta="ehEmpresas ? null : contaDeMarcados"
            :pode-mandar-mensagem="naDemonstracao && !ehEmpresas"
            :pode-criar-cards="podeCriarCards && !ehEmpresas"
            :pode-etiquetar="podeEtiquetar && !ehEmpresas"
            :pode-apagar="podeApagar"
            @mandar-mensagem="dialogoDeMensagem.abrir()"
            @criar-cards="dialogoDeCards.abrir()"
            @etiqueta="dialogoDeEtiqueta.abrir()"
            @apagar="dialogoDeApagar.abrir()"
            @fechar="marcados.limpar"
          />
        </transition>
        <AvisoComDesfazer
          v-if="devolucao.texto.value"
          class="sticky z-30 bottom-4 ms-20 md:ms-0"
          :texto="devolucao.texto.value"
          :pode-desfazer="devolucao.podeDesfazer.value"
          :desfazendo="devolucao.desfazendo.value"
          @desfazer="devolucao.desfazer"
        />
      </div>
    </main>

    <GavetaDeFiltros
      :aberta="maisFiltros.aberta.value"
      :de-empresas="ehEmpresas"
      :filtros="lista.filtros.value"
      :opcoes="maisFiltros.opcoes.value"
      @fechar="maisFiltros.aberta.value = false"
      @aplicar="maisFiltros.aplicar"
      @limpar="maisFiltros.limpar"
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
      @tirou="devolucao.mostrar"
    />
    <DialogoApagar
      ref="dialogoDeApagar"
      :pessoas="marcados.pessoas.value"
      :acoes="acoes"
      :de-empresas="ehEmpresas"
      @concluido="acoesEmGrupo.depoisDeAgir"
    />
    <DialogoPlanilha
      v-if="podeBaixar"
      ref="dialogoDaPlanilha"
      :quantas="lista.total.value"
      :lista="listaDaPlanilha"
      :acoes="acoes"
      :consulta="consultaDaTela"
    />
    <GavetaDeInformacoes
      v-if="podeEditar"
      :aberta="gaveta.aberta.value"
      :pessoa="gaveta.pessoa.value"
      :salvando="gaveta.salvando.value"
      :titulo="tituloDaGaveta"
      :rotulo-salvar="salvarDaGaveta"
      :erros-do-servidor="gaveta.errosDoServidor.value"
      :empresa-cadastrada="gaveta.empresaCadastrada.value"
      :com-empresas="temEmpresas"
      :buscar-empresas="acoes.buscarEmpresas"
      :definicoes="camposDaConta.definicoes.value"
      marca="gaveta-da-pessoa"
      @fechar="gaveta.fechar"
      @salvar="gaveta.salvar"
    />
    <NovaEmpresaNaLista
      v-if="podeEditar && temEmpresas"
      ref="novaEmpresa"
      :acoes="acoes"
      @criada="abrirEmpresa"
    />
  </section>
</template>
