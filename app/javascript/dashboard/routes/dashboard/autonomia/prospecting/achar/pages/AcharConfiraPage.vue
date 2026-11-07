<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AcharGruposDaLista from '../components/AcharGruposDaLista.vue';
import AcharConfiraCabecalho from '../components/AcharConfiraCabecalho.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharProgresso from '../components/AcharProgresso.vue';
import AcharListaComMapa from '../components/AcharListaComMapa.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import AcharEmpresaGaveta from '../components/AcharEmpresaGaveta.vue';
import AcharFolhaEnvio from '../components/AcharFolhaEnvio.vue';
import AcharComQuemFica from '../components/AcharComQuemFica.vue';
import AcharParaOndePainel from '../components/AcharParaOndePainel.vue';
import AcharPronto from '../components/AcharPronto.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { useListaDaBusca } from '../composables/useListaDaBusca';
import { useFolhaDaLista, folhaNova } from '../composables/useFolhaDaLista';
import { useGavetaDaLista } from '../composables/useGavetaDaLista';
import { ROTAS } from '../utils/acharRotas';
import {
  ESTADOS_LEITURA,
  SOBRE_A_LISTA,
  comoMandada,
  ehEstadoDaLista,
  empresaPadraoDaGaveta,
  grupoAbre,
  grupoEmFoco,
  naoVao,
  textosDoPronto,
} from '../utils/acharConfiraEstados';
import { escolherDestino, lerUltimoDestino } from '../utils/destinoPronto';

// #2692 — T1, a lista que se completa ao vivo (v4), com a gaveta da empresa
// (T1d), a folha "O que fazer com as {n}?" (F1) e o pronto (T2/T3) por cima.
// A pessoa só tira quem não quer ("Vai / Não vai") e continua. Quem só vê (ou
// não tem destino) vê a mesma lista em leitura, sem interruptor nem rodapé.
const { t } = useI18n();
const {
  route,
  router,
  demo,
  fonte,
  permissoes,
  ajustes,
  carregarAjustes,
  irPara,
  mudarEstado,
  contaId,
  usuarioId,
} = useAcharTela();

const NS = 'PROSPECTING_ACHAR.CONFIRA';
// Na demo, "buscando" e "Mandando…" ficam um tempo na tela antes de andar.
const ESPERA_DA_DEMO = 9000;
const ENVIO_PARADO_EM = 9;
const MIN_PARA_NOME = 20;

const carregando = ref(true);
const erro = ref(false);
const busca = ref(null);
const aviso = ref(null);

const gaveta = ref(null);
const folha = ref(null);
const pronto = ref(null);
const subpainel = ref(null);
const funis = ref([]);
const pessoas = ref([]);
const destino = ref(null);
const pessoaId = ref('voce');
const nomeLista = ref('');
const enviandoUma = ref(false);
const destacada = ref(null);
// Último estado da lista na demo: fechar o que está por cima volta a ele.
const estadoDaLista = ref(null);

const estado = computed(() => demo.value || '');
const leitura = computed(
  () =>
    ESTADOS_LEITURA.includes(estado.value) ||
    !permissoes.value.buscar ||
    (!permissoes.value.funil && !permissoes.value.lista)
);
const pesquisaLigada = computed(
  () => estado.value !== 'confira-pesquisa-desligada'
);
const whatsappLigado = computed(
  () => estado.value !== 'confira-sem-whatsapp-conta'
);

const {
  empresas,
  naoVai,
  soWhatsapp,
  procuraNome,
  elegiveis,
  visiveis,
  grupos,
  deFora,
  primeiro,
  primeiroId,
  escolhidas,
  progresso,
  alternar,
  tirarPouca: tirarPoucaDaLista,
  aplicar,
  trocar,
  pararRelogio,
} = useListaDaBusca({
  chaveDaSelecao: () =>
    `prospeccao-achar:selecao:${contaId.value}:${route.params.searchId}`,
  guardaSelecao: () => !demo.value,
});

const pessoaNome = computed(() => {
  if (pessoaId.value === 'voce') return t('PROSPECTING_ACHAR.COMUM.VOCE');
  return (
    pessoas.value.find(pessoa => pessoa.id === pessoaId.value)?.nome ||
    t('PROSPECTING_ACHAR.COMUM.VOCE')
  );
});
const podeTrocarPessoa = computed(() => permissoes.value.trocarDono);
const empresaDaGaveta = computed(() =>
  gaveta.value
    ? empresas.value.find(empresa => empresa.id === gaveta.value.id)
    : null
);
const naoVaoDaBusca = computed(() => {
  const mandadas = elegiveis.value.filter(empresa => empresa.mandada).length;
  const tiradas = elegiveis.value.length - escolhidas.value.length - mandadas;
  return naoVao(empresas.value, tiradas, mandadas);
});
const entramLista = computed(
  () => escolhidas.value.filter(empresa => empresa.temContato).length
);
const semContatoLista = computed(
  () => escolhidas.value.length - entramLista.value
);
// Que grupos abrem: pelo estado da lista por baixo da gaveta ou da folha.
const grupoComecaFechado = chave =>
  !grupoAbre(estadoDaLista.value || estado.value, chave);
const oQueNaFrase = computed(() => busca.value?.oQue.toLowerCase() || '');
let relogioDaDemo = null;
const pararRelogioDaDemo = () => {
  if (relogioDaDemo) clearTimeout(relogioDaDemo);
  relogioDaDemo = null;
};
const andarDepois = proximo => {
  pararRelogioDaDemo();
  relogioDaDemo = setTimeout(() => mudarEstado(proximo), ESPERA_DA_DEMO);
};

const tirarPouca = () => {
  const { n, desfazer } = tirarPoucaDaLista();
  aviso.value = { texto: t(`${NS}.TIROU`, { n }), desfazer };
};

const aplicarLista = dados => {
  busca.value = dados.busca;
  aplicar({
    dados,
    todasFora: estado.value === 'confira-todas-fora',
    soComWhatsapp: estado.value === 'confira-so-whatsapp',
  });
  nomeLista.value = t('PROSPECTING_ACHAR.FOLHA.NOME_LISTA', {
    oQue: dados.busca.oQue,
    lugar: dados.busca.lugar.split(',')[0],
    data: new Date().toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    }),
  });
};

const carregarLista = async () => {
  pararRelogio();
  carregando.value = true;
  erro.value = false;
  try {
    const dados = await fonte.value.busca(route.params.searchId);
    aplicarLista(dados);
    if (ehEstadoDaLista(estado.value)) estadoDaLista.value = estado.value;
    if (estado.value === 'buscando') {
      andarDepois('chegando');
      return;
    }
  } catch (falha) {
    // O título continua quando a busca é conhecida (rodada 2).
    if (falha?.busca) busca.value = falha.busca;
    erro.value = true;
  }
  carregando.value = false;
};

const carregarDestino = async () => {
  try {
    const [lista, gente] = await Promise.all([
      fonte.value.funis(),
      fonte.value.pessoas(),
    ]);
    funis.value = lista;
    pessoas.value = gente;
    destino.value = escolherDestino({
      funis: lista,
      ultimo: demo.value
        ? null
        : lerUltimoDestino(contaId.value, usuarioId.value),
      padrao: ajustes.value?.padrao || null,
    });
  } catch {
    funis.value = [];
  }
};

const {
  enviar,
  abrirFolha,
  escolherDestinoDaFolha,
  mandarDaFolha,
  guardarDaFolha,
  abrirSubpainel,
  fecharSubpainel,
  salvarPessoa,
  salvarDestino,
} = useFolhaDaLista({
  demo,
  estado,
  fonte,
  mudarEstado,
  contaId,
  usuarioId,
  escolhidas,
  destino,
  pessoaId,
  nomeLista,
  folha,
  pronto,
  subpainel,
});

// --- O que vai por cima da lista, pelo estado da demonstração.
const aplicarSobre = () => {
  const sobre = SOBRE_A_LISTA[estado.value] || {};
  const mandada = Number(route.query.mandada);
  if (mandada) trocar(mandada, item => comoMandada(item, pessoaNome.value));
  if (sobre.pessoa) pessoaId.value = sobre.pessoa;
  subpainel.value = sobre.subpainel || null;
  pararRelogioDaDemo();
  gaveta.value = null;
  folha.value = null;
  pronto.value = null;
  if (sobre.gaveta) {
    const pedida = Number(route.query.empresa);
    const empresa =
      empresas.value.find(item => item.id === pedida) ||
      empresaPadraoDaGaveta(sobre.empresa, {
        deFora: deFora.value,
        elegiveis: elegiveis.value,
      });
    gaveta.value = empresa ? { id: empresa.id, passo: sobre.gaveta } : null;
  }
  if ('folha' in sobre) {
    folha.value = folhaNova(sobre.folha, Boolean(sobre.mostrarFora));
    if (sobre.enviar) enviar();
    if (sobre.enviandoParado) {
      folha.value = {
        ...folha.value,
        enviando: {
          feitas: Math.min(ENVIO_PARADO_EM, escolhidas.value.length),
          total: escolhidas.value.length,
        },
      };
      andarDepois('pronto');
    }
  }
  if (sobre.pronto === 'funil') {
    const n = sobre.uma ? 1 : escolhidas.value.length - (sobre.jaEstavam || 0);
    pronto.value = {
      tipo: 'funil',
      n,
      jaEstavam: sobre.jaEstavam || 0,
      nome: escolhidas.value[0]?.nome,
    };
  }
  if (sobre.pronto === 'lista') {
    pronto.value = { tipo: 'lista', n: entramLista.value };
  }
};

// --- Ações da página.
const abrirEmpresa = empresa => {
  destacada.value = empresa.id;
  if (demo.value) {
    mudarEstado(leitura.value ? 'gaveta-leitura' : 'gaveta', {
      empresa: empresa.id,
    });
    return;
  }
  gaveta.value = { id: empresa.id, passo: 'ver' };
};
const voltarParaAListaDaDemo = () =>
  mudarEstado(
    estadoDaLista.value || (leitura.value ? 'leitura' : 'confira-tirou')
  );
const fecharGaveta = () => {
  if (demo.value) voltarParaAListaDaDemo();
  else gaveta.value = null;
};
const { mudarPasso, mandarUma, marcarFora, chamar, verNoFunil } =
  useGavetaDaLista({
    demo,
    route,
    router,
    fonte,
    mudarEstado,
    gaveta,
    empresaDaGaveta,
    destino,
    enviandoUma,
    aviso,
    trocar,
    fecharGaveta,
  });

const voltarParaLista = () => {
  if (demo.value) voltarParaAListaDaDemo();
  else pronto.value = null;
};
const escreverMensagem = () =>
  router.push({
    name: 'campaigns_journey_new',
    params: { accountId: route.params.accountId },
  });
const mudarPedido = () => irPara(ROTAS.PORTA, { estado: 'porta' });
const voltarParaBuscas = () =>
  irPara(ROTAS.BUSCAS, { estado: 'buscas-so-ver' });
const tentarDeNovo = () =>
  demo.value ? mudarEstado('confira') : carregarLista();
const buscarDeNovo = () =>
  demo.value ? mudarEstado('buscando') : carregarLista();
const procurarDeNovo = () => {
  aviso.value = { texto: t('PROSPECTING_ACHAR.GAVETA.PROCURANDO_DE_NOVO') };
  fecharGaveta();
};

const textosPronto = computed(() =>
  textosDoPronto(t, {
    pronto: pronto.value,
    destino: destino.value,
    pessoa: pessoaNome.value,
    nomeLista: nomeLista.value,
  })
);

const iniciar = async () => {
  await carregarAjustes();
  await Promise.all([carregarLista(), carregarDestino()]);
  aplicarSobre();
};

onMounted(iniciar);
onBeforeUnmount(pararRelogioDaDemo);
watch(estado, async (novo, antigo) => {
  if (novo === antigo) return;
  if (ehEstadoDaLista(novo) && novo !== estadoDaLista.value) {
    await carregarLista();
  }
  aplicarSobre();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-4xl gap-6 px-4 pt-6 mx-auto min-h-full md:px-8 md:pt-10"
        :class="[
          pronto || (!leitura && elegiveis.length) ? 'pb-0' : 'md:pb-10',
          { 'xl:max-w-6xl': !pronto },
        ]"
      >
        <template v-if="pronto">
          <AcharPronto
            :titulo="textosPronto.titulo"
            :detalhes="textosPronto.detalhes"
            :link="$t('PROSPECTING_ACHAR.PRONTO.VOLTAR_LISTA')"
            class="w-full"
            @link="voltarParaLista"
          />
          <AcharRodape
            :rotulo="
              pronto.tipo === 'lista'
                ? $t('PROSPECTING_ACHAR.PRONTO.LISTA.ESCREVER')
                : $t('PROSPECTING_ACHAR.COMUM.VER_NO_FUNIL')
            "
            @principal="
              pronto.tipo === 'lista' ? escreverMensagem() : verNoFunil()
            "
          />
        </template>

        <template v-else>
          <AcharConfiraCabecalho
            :busca="busca"
            :carregando="carregando"
            :leitura="leitura"
            :achadas="empresas.length"
            :vao="escolhidas.length"
            :conferindo="Boolean(progresso)"
            @mudar-pedido="mudarPedido"
          />

          <div v-if="carregando" class="flex flex-col gap-3" aria-busy="true">
            <div
              v-for="indice in 3"
              :key="indice"
              class="h-28 rounded-2xl bg-n-slate-3 animate-pulse"
            />
          </div>

          <template v-else>
            <AcharEstado
              v-if="erro"
              tom="erro"
              :texto="$t(`${NS}.ERRO`)"
              :botao="$t('PROSPECTING_ACHAR.COMUM.TENTAR_DE_NOVO')"
              :link="busca ? $t(`${NS}.MUDAR_PEDIDO`) : ''"
              @acao="tentarDeNovo"
              @link="mudarPedido"
            />
            <AcharEstado
              v-if="busca?.googleParou"
              faixa
              tom="aviso"
              :texto="$t(`${NS}.GOOGLE_PAROU`)"
              :botao="$t(`${NS}.BUSCAR_DE_NOVO`)"
              @acao="buscarDeNovo"
            />
            <AcharEstado
              v-if="aviso"
              faixa
              tom="feito"
              :texto="aviso.texto"
              :botao="
                aviso.desfazer ? $t('PROSPECTING_ACHAR.COMUM.DESFAZER') : ''
              "
              @acao="aviso.desfazer(), (aviso = null)"
            />

            <AcharProgresso v-if="progresso" :progresso="progresso" />

            <AcharEstado
              v-if="!erro && !empresas.length && leitura"
              :texto="$t(`${NS}.LEITURA.VAZIA`)"
              :botao="$t(`${NS}.LEITURA.VOLTAR`)"
              @acao="voltarParaBuscas"
            />
            <AcharEstado
              v-else-if="!erro && !empresas.length && busca"
              :texto="
                $t(`${NS}.VAZIA`, { oQue: oQueNaFrase, lugar: busca.lugar })
              "
              :botao="$t(`${NS}.VAZIA_LONGE`)"
              :link="$t(`${NS}.MUDAR_PEDIDO`)"
              @acao="buscarDeNovo"
              @link="mudarPedido"
            />

            <template v-else-if="empresas.length">
              <AcharListaComMapa
                v-model:so-whatsapp="soWhatsapp"
                v-model:procura-nome="procuraNome"
                v-model:destacada="destacada"
                :com-whatsapp="whatsappLigado"
                :com-nome="elegiveis.length >= MIN_PARA_NOME"
                :empresas="empresas"
                :primeiro-id="primeiroId"
                :nao-vai="naoVai"
              >
                <AcharEstado
                  v-if="!visiveis.length && soWhatsapp"
                  :texto="$t(`${NS}.CORTE_VAZIO`)"
                  :botao="$t(`${NS}.MOSTRAR_TODAS`)"
                  @acao="soWhatsapp = false"
                />
                <AcharEstado
                  v-else-if="!visiveis.length && elegiveis.length"
                  :texto="$t(`${NS}.NOME_VAZIO`)"
                  :botao="$t(`${NS}.LIMPAR`)"
                  @acao="procuraNome = ''"
                />

                <AcharGruposDaLista
                  :primeiro="primeiro"
                  :grupos="grupos"
                  :de-fora="deFora"
                  :nao-vai="naoVai"
                  :leitura="leitura"
                  :pesquisa-ligada="pesquisaLigada"
                  :whatsapp-ligado="whatsappLigado"
                  :comeca-fechado="grupoComecaFechado"
                  :rolar-ate="grupoEmFoco(estadoDaLista || estado)"
                  :destacada="destacada"
                  @abrir="abrirEmpresa"
                  @alternar="alternar"
                  @tirar="tirarPouca"
                />
              </AcharListaComMapa>

              <AcharRodape
                v-if="!leitura && elegiveis.length"
                :rotulo="
                  progresso
                    ? $t(`${NS}.CONTINUAR_CONFERINDO`)
                    : $t(`${NS}.CONTINUAR`, { n: escolhidas.length })
                "
                :dica="escolhidas.length ? '' : $t(`${NS}.TODAS_FORA`)"
                :desabilitado="!escolhidas.length"
                icone="i-lucide-arrow-right"
                @principal="abrirFolha"
              />
            </template>
          </template>
        </template>
        <AcharFaixaDoMenu v-if="!pronto && (leitura || !elegiveis.length)" />
      </div>
    </main>

    <AcharEmpresaGaveta
      v-if="empresaDaGaveta && !subpainel"
      :empresa="empresaDaGaveta"
      :primeiro="empresaDaGaveta.id === primeiroId"
      :leitura="leitura"
      :pode-funil="permissoes.funil"
      :passo="gaveta.passo"
      :destino="destino"
      :pessoa="pessoaNome"
      :pode-trocar-pessoa="podeTrocarPessoa"
      :enviando="enviandoUma"
      @close="fecharGaveta"
      @passo="mudarPasso"
      @mandar="mandarUma"
      @nao-serve="marcarFora('descartar', $event)"
      @nao-quer="marcarFora('naoQuer')"
      @chamar="chamar"
      @ver-no-funil="verNoFunil"
      @alterar-destino="abrirSubpainel('destino')"
      @alterar-pessoa="abrirSubpainel('pessoa')"
      @procurar-de-novo="procurarDeNovo"
    />

    <AcharFolhaEnvio
      v-if="folha && !subpainel"
      v-model:nome-lista="nomeLista"
      v-model:mostrar-fora="folha.mostrarFora"
      :n="escolhidas.length"
      :pode-funil="permissoes.funil"
      :pode-lista="permissoes.lista"
      :escolha="folha.escolha"
      :destino="destino"
      :pessoa="pessoaNome"
      :pode-trocar-pessoa="podeTrocarPessoa"
      :nao-vao="naoVaoDaBusca"
      :sem-contato-lista="semContatoLista"
      :entram-lista="entramLista"
      :enviando="folha.enviando"
      :guardando="folha.guardando"
      :erro="folha.erro"
      @escolher="escolherDestinoDaFolha"
      @alterar-destino="abrirSubpainel('destino')"
      @alterar-pessoa="abrirSubpainel('pessoa')"
      @mandar="mandarDaFolha"
      @guardar="guardarDaFolha"
      @close="demo ? voltarParaAListaDaDemo() : (folha = null)"
    />

    <AcharComQuemFica
      v-if="subpainel === 'pessoa'"
      :pessoas="pessoas"
      :escolhida="pessoaId"
      @salvar="salvarPessoa"
      @close="fecharSubpainel"
    />
    <AcharParaOndePainel
      v-if="subpainel === 'destino'"
      :funis="funis"
      :destino="destino"
      voltar
      @salvar="salvarDestino"
      @close="fecharSubpainel"
    />
  </section>
</template>
