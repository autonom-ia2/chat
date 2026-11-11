<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import PilulasDeGrupo from '../comum/PilulasDeGrupo.vue';
import AbasDaLista from '../lista/AbasDaLista.vue';
import DialogoMandarMensagem from '../lista/DialogoMandarMensagem.vue';
import EstadoSemResultado from '../lista/EstadoSemResultado.vue';
import ListaDeLinhas from '../lista/ListaDeLinhas.vue';
import MostrarMais from '../lista/MostrarMais.vue';
import { ABA_SEGUROS, carteiraFonte } from '../../fonte/carteiraFonte';
import {
  GRUPO_SEM_TELEFONE,
  grupoConhecido,
  grupoTemporario,
} from '../../fonte/gruposDeSeguros';
import {
  casoPedido,
  cotacaoDesligada,
  pecaPedida,
} from '../../fonte/modoCarteira';
import { PAINEL_DAS_ABAS, idDaAba } from '../../lista/idsDasAbas';
import { useAcoesEmGrupo } from '../../lista/useAcoesEmGrupo';
import { useRolarPilula } from '../../lista/useRolarPilula';
import { useApoliceNaUrl } from '../../carteira/useApoliceNaUrl';
import { useListaDeSeguros } from '../../carteira/useListaDeSeguros';
import BarraDeSeguros from './BarraDeSeguros.vue';
import ControlesDeSeguros from './ControlesDeSeguros.vue';
import GavetaDeFiltrosDeSeguros from './GavetaDeFiltrosDeSeguros.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import HeroiDeSeguros from './HeroiDeSeguros.vue';
import LinhaDeSeguro from './LinhaDeSeguro.vue';
import GavetaDaRenovacao from './renovacao/GavetaDaRenovacao.vue';
import SegurosDeExemplo from './SegurosDeExemplo.vue';

// #2897 — a aba Seguros de Relacionamentos (`?aba=seguros`): herói com a frase
// do dia, abas, grupos, busca, ordem, "Mais filtros", um seguro por linha, a
// barra de quem está marcado, a gaveta do seguro (`?apolice=<id>`) e a da
// renovação (`?renovacao=<id>`). Fala só com `carteiraFonte`. "Trazer seguros",
// "Resultados" e "Ajustar renovações" levam às telas deles. `?grupo=<id>` abre
// a lista já num grupo (é assim que os resultados mostram quem não renovou). A
// conversa é de outra entrega: por ora, um aviso diz o que vai abrir.
const props = defineProps({
  demo: { type: String, default: null },
});
const emit = defineEmits(['trocarAba']);

const { t } = useI18n();
const tc = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const grupoInicial = grupoConhecido(route.query.grupo);
const temporario = grupoTemporario(grupoInicial)?.id ?? '';
const fonte = carteiraFonte({
  demo: props.demo,
  peca: pecaPedida(route.query),
  caso: casoPedido(route.query),
  cotacaoDesligada: cotacaoDesligada(route.query),
  temporario,
});
const {
  lista,
  marcados,
  grupos,
  explicacao,
  semResultado,
  pessoasMarcadas,
  semSeguros,
  faltamMarcar,
  avisoDaLista,
} = useListaDeSeguros(fonte, { grupoInicial, temporario });
const { apolice, renovacao, abrir, abrirRenovacao, fechar } = useApoliceNaUrl();

const acoesEmGrupo = useAcoesEmGrupo({
  lista,
  marcados,
  aba: ref(ABA_SEGUROS),
  aoFalhar: () => useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO')),
});

const simular = (chave, valores) => useAlert(tc(chave, valores));
const trazer = () => router.push({ name: 'relacionamentos_trazer' });
const verResultados = () => router.push({ name: 'relacionamentos_resultados' });
const ajustar = () => router.push({ name: 'relacionamentos_renovacoes' });
const abrirCampanha = quantas =>
  useAlert(
    t(
      'RELACIONAMENTOS.LISTA.MENSAGEM.ABRINDO_CAMPANHA',
      { count: quantas },
      quantas
    )
  );
const abrirSegurado = ({ tipo, id }) =>
  router.push(
    tipo === 'empresa'
      ? { name: 'relacionamentos_empresa', params: { companyId: id } }
      : { name: 'relacionamentos_pessoa', params: { contactId: id } }
  );

const dialogoDeMensagem = useTemplateRef('dialogoDeMensagem');
const gavetaDeFiltros = ref(false);
const opcoesDeFiltro = ref({ tipos: [], seguradoras: [], cuida: [] });
const abrirFiltros = async () => {
  gavetaDeFiltros.value = true;
  try {
    opcoesDeFiltro.value = await fonte.opcoesDeFiltro();
  } catch {
    useAlert(t('RELACIONAMENTOS.COMUM.ERRO_GENERICO'));
  }
};
const aplicarFiltros = novos => {
  gavetaDeFiltros.value = false;
  lista.mudarFiltros(novos);
};
const limparFiltros = () => {
  gavetaDeFiltros.value = false;
  lista.limparFiltros();
};

const barraVisivel = computed(() => marcados.quantos.value > 0);
const raiz = useTemplateRef('raiz');
useRolarPilula(raiz, lista.grupo);

onMounted(lista.iniciar);
</script>

<template>
  <main ref="raiz" class="flex-1 min-w-0 overflow-y-auto">
    <div
      class="flex flex-col w-full min-w-0 max-w-6xl min-h-full gap-6 px-5 pt-8 mx-auto md:px-8 md:pt-10"
      :class="barraVisivel ? 'pb-48 md:pb-28' : 'pb-24 md:pb-10'"
    >
      <h1 class="sr-only">{{ t('RELACIONAMENTOS_CARTEIRA.TITULO') }}</h1>
      <p role="status" class="sr-only" data-carteira="aviso-da-lista">
        {{ avisoDaLista }}
      </p>

      <EsqueletoDeLista
        v-if="!lista.resumo.value && !lista.erro.value"
        com-topo
        data-carteira="carregando"
      />
      <template v-else>
        <HeroiDeSeguros
          v-if="lista.resumo.value"
          :resumo="lista.resumo.value"
          @trazer="trazer"
          @ver-grupo="lista.escolherGrupo"
        />
        <AbasDaLista
          com-seguros
          :model-value="ABA_SEGUROS"
          @update:model-value="emit('trocarAba', $event)"
        />
        <div
          :id="PAINEL_DAS_ABAS"
          role="tabpanel"
          :aria-labelledby="idDaAba(ABA_SEGUROS)"
          class="flex flex-col min-w-0 gap-5"
        >
          <div v-if="!lista.resumo.value" data-carteira="erro">
            <ErroComTentarDeNovo
              :mensagem="tc('ERRO')"
              @tentar="lista.recarregar"
            />
          </div>
          <SegurosDeExemplo v-else-if="semSeguros" />
          <template v-else>
            <div data-carteira="grupos" class="flex flex-col">
              <PilulasDeGrupo
                :grupos="grupos"
                :model-value="lista.grupo.value"
                @update:model-value="lista.escolherGrupo"
              />
              <p
                aria-live="polite"
                class="m-0 text-sm text-n-slate-11"
                :class="{ 'mt-3': explicacao }"
                data-carteira="explicacao-do-grupo"
              >
                {{ explicacao }}
              </p>
            </div>
            <ControlesDeSeguros
              :busca="lista.busca.value"
              :ordem="lista.ordem.value"
              :filtros-ativos="lista.filtrosAtivos.value"
              @update:busca="lista.mudarBusca"
              @update:ordem="lista.mudarOrdem"
              @abrir-filtros="abrirFiltros"
              @resultados="verResultados"
              @ajustar="ajustar"
            />
            <div v-if="lista.erro.value" data-carteira="erro">
              <ErroComTentarDeNovo
                :mensagem="tc('ERRO')"
                @tentar="lista.recarregar"
              />
            </div>
            <EsqueletoDeLista
              v-else-if="lista.carregando.value"
              data-carteira="carregando"
            />
            <div v-else-if="semResultado" data-carteira="vazio">
              <EstadoSemResultado
                :frase="semResultado.frase"
                :botao="semResultado.botao"
                @acao="semResultado.acao"
              />
            </div>
            <template v-else>
              <div v-if="faltamMarcar">
                <Button
                  link
                  data-carteira="marcar-todos"
                  :is-loading="acoesEmGrupo.marcandoTodas.value"
                  :label="tc('MARCAR_TODOS', { count: lista.total.value })"
                  @click="acoesEmGrupo.marcarTodas"
                />
              </div>
              <ListaDeLinhas>
                <LinhaDeSeguro
                  v-for="seguro in lista.itens.value"
                  :key="seguro.id"
                  :seguro="seguro"
                  :marcado="marcados.ehMarcado(seguro.id)"
                  :diz-sem-telefone="lista.grupo.value === GRUPO_SEM_TELEFONE"
                  @alternar="marcados.alternar"
                  @abrir="abrir($event.id)"
                  @conversar="
                    simular('ABRINDO_CONVERSA', { nome: $event.pessoa.name })
                  "
                />
              </ListaDeLinhas>
              <MostrarMais
                :mostradas="lista.itens.value.length"
                :total="lista.total.value"
                :tem-mais="lista.temMais.value"
                :carregando="lista.carregandoMais.value"
                @mais="lista.mostrarMais"
              />
            </template>
          </template>
        </div>
      </template>

      <transition
        enter-active-class="transition duration-200 ease-out"
        enter-from-class="translate-y-4 opacity-0"
        leave-active-class="transition duration-150 ease-in"
        leave-to-class="translate-y-4 opacity-0"
      >
        <BarraDeSeguros
          v-if="barraVisivel"
          class="sticky z-30 mt-auto bottom-4 ms-20 md:ms-0"
          :quantos="marcados.quantos.value"
          @mandar-mensagem="dialogoDeMensagem.abrir()"
          @fechar="marcados.limpar"
        />
      </transition>
    </div>

    <GavetaDeFiltrosDeSeguros
      :aberta="gavetaDeFiltros"
      :filtros="lista.filtros.value"
      :opcoes="opcoesDeFiltro"
      @fechar="gavetaDeFiltros = false"
      @aplicar="aplicarFiltros"
      @limpar="limparFiltros"
    />
    <DialogoMandarMensagem
      ref="dialogoDeMensagem"
      :pessoas="pessoasMarcadas"
      @continuar="abrirCampanha"
    />
    <GavetaDoSeguro
      :apolice-id="apolice"
      :fonte="fonte"
      @fechar="fechar"
      @mudou="lista.recarregar"
      @abrir-segurado="abrirSegurado"
      @abrir-renovacao="abrirRenovacao"
    />
    <GavetaDaRenovacao
      :seguro-id="renovacao"
      :fonte="fonte"
      @fechar="fechar"
      @mudou="lista.recarregar"
      @abrir-segurado="abrirSegurado"
    />
  </main>
</template>
