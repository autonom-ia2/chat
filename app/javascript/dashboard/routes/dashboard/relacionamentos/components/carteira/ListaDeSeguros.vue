<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import PilulasDeGrupo from '../comum/PilulasDeGrupo.vue';
import AbasDaLista from '../lista/AbasDaLista.vue';
import EstadoSemAcesso from '../lista/EstadoSemAcesso.vue';
import EstadoSemResultado from '../lista/EstadoSemResultado.vue';
import ListaDeLinhas from '../lista/ListaDeLinhas.vue';
import MostrarMais from '../lista/MostrarMais.vue';
import { ABA_SEGUROS, carteiraFonte } from '../../fonte/carteiraFonte';
import { GRUPO_SEM_TELEFONE } from '../../fonte/gruposDeSeguros';
import { pecaPedida } from '../../fonte/modoCarteira';
import { usePermissoesDaFicha } from '../../ficha/usePermissoesDaFicha';
import { PAINEL_DAS_ABAS, idDaAba } from '../../lista/idsDasAbas';
import { useRolarPilula } from '../../lista/useRolarPilula';
import { useApoliceNaUrl } from '../../carteira/useApoliceNaUrl';
import { useListaDeSeguros } from '../../carteira/useListaDeSeguros';
import ControlesDeSeguros from './ControlesDeSeguros.vue';
import GavetaDeFiltrosDeSeguros from './GavetaDeFiltrosDeSeguros.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import HeroiDeSeguros from './HeroiDeSeguros.vue';
import LinhaDeSeguro from './LinhaDeSeguro.vue';
import SegurosDeExemplo from './SegurosDeExemplo.vue';

// #2897 — a aba Seguros de Relacionamentos (`?aba=seguros`): herói com a frase
// do dia, abas, grupos por vencimento, busca, ordem, "Mais filtros", um seguro
// por linha e a gaveta do seguro (`?apolice=<id>`). Fala só com
// `carteiraFonte`: fora da demonstração lê do servidor e grava nele. Quem não
// pode ver os contatos lê só que não tem acesso. Quando a gaveta muda um
// seguro, a lista relê o que está à vista sem voltar ao começo.
const props = defineProps({
  demo: { type: String, default: null },
  // A conta tem a aba Empresas? (as abas mostram só as que existem)
  comEmpresas: { type: Boolean, default: false },
  // Quem pode trazer lista vê o botão de trazer seguros no herói (a regra é a
  // do botão "Trazer minha lista" da lista de pessoas; quem decide é a página).
  podeTrazer: { type: Boolean, default: false },
});
const emit = defineEmits(['trocarAba', 'trazer']);

const { t } = useI18n();
const ca = chave => t(`RELACIONAMENTOS_CARTEIRA.LISTA.${chave}`);
const route = useRoute();
const router = useRouter();
const fonte = carteiraFonte({
  demo: props.demo,
  peca: pecaPedida(route.query),
});
// Na demonstração tudo aparece, como na lista e na ficha.
const permissoes = usePermissoesDaFicha();
const podeEditar = computed(() => fonte.usaDemo || permissoes.podeEditar.value);
const {
  lista,
  grupos,
  explicacao,
  vencidos,
  topoPronto,
  semResultado,
  semSeguros,
  avisoDaLista,
} = useListaDeSeguros(fonte);
const { apolice, abrir, fechar } = useApoliceNaUrl();

const abrirSegurado = ({ tipo, id }) =>
  router.push(
    tipo === 'empresa'
      ? { name: 'relacionamentos_empresa', params: { companyId: id } }
      : { name: 'relacionamentos_pessoa', params: { contactId: id } }
  );

const gavetaDeFiltros = ref(false);
const opcoesDeFiltro = ref({ tipos: [], seguradoras: [] });
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

const raiz = useTemplateRef('raiz');
useRolarPilula(raiz, lista.grupo);

onMounted(lista.iniciar);
</script>

<template>
  <main ref="raiz" class="flex-1 min-w-0 overflow-y-auto">
    <div
      class="flex flex-col w-full min-w-0 max-w-6xl min-h-full gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
    >
      <h1 class="sr-only">{{ t('RELACIONAMENTOS_CARTEIRA.TITULO') }}</h1>
      <p role="status" class="sr-only" data-carteira="aviso-da-lista">
        {{ avisoDaLista }}
      </p>

      <EsqueletoDeLista
        v-if="!topoPronto && !lista.erro.value"
        com-topo
        data-carteira="carregando"
      />
      <template v-else>
        <HeroiDeSeguros
          v-if="lista.resumo.value"
          :resumo="lista.resumo.value"
          :vencidos="vencidos"
          :pode-trazer="podeTrazer"
          @ver-grupo="lista.escolherGrupo"
          @trazer="emit('trazer')"
        />
        <AbasDaLista
          com-seguros
          :com-empresas="comEmpresas"
          :model-value="ABA_SEGUROS"
          @update:model-value="emit('trocarAba', $event)"
        />
        <div
          :id="PAINEL_DAS_ABAS"
          role="tabpanel"
          :aria-labelledby="idDaAba(ABA_SEGUROS)"
          class="flex flex-col min-w-0 gap-5"
        >
          <EstadoSemAcesso
            v-if="lista.semAcesso.value"
            :frase="ca('SEM_ACESSO')"
          />
          <div v-else-if="!lista.resumo.value" data-carteira="erro">
            <ErroComTentarDeNovo
              :mensagem="ca('ERRO')"
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
            />
            <div v-if="lista.erro.value" data-carteira="erro">
              <ErroComTentarDeNovo
                :mensagem="ca('ERRO')"
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
              <ListaDeLinhas>
                <LinhaDeSeguro
                  v-for="seguro in lista.itens.value"
                  :key="seguro.id"
                  :seguro="seguro"
                  :diz-sem-telefone="lista.grupo.value === GRUPO_SEM_TELEFONE"
                  @abrir="abrir($event.id)"
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
    </div>

    <GavetaDeFiltrosDeSeguros
      :aberta="gavetaDeFiltros"
      :filtros="lista.filtros.value"
      :opcoes="opcoesDeFiltro"
      @fechar="gavetaDeFiltros = false"
      @aplicar="aplicarFiltros"
      @limpar="limparFiltros"
    />
    <GavetaDoSeguro
      :apolice-id="apolice"
      :fonte="fonte"
      :pode-editar="podeEditar"
      @fechar="fechar"
      @mudou="lista.atualizar"
      @abrir-segurado="abrirSegurado"
    />
  </main>
</template>
