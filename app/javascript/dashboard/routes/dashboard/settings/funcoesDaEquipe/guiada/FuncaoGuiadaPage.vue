<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import ErroAoAbrir from '../components/ErroAoAbrir.vue';
import PaywallDasFuncoes from '../components/PaywallDasFuncoes.vue';
import GavetaDaFuncao from '../pessoas/GavetaDaFuncao.vue';
import { nivelQueFica, perdasDeAcesso } from '../perdaDeAcesso';
import { oferecerMemoria } from './memoriaDaConversa';
import { useEtapasDaGuiada } from './useEtapasDaGuiada';
import { useFuncaoGuiada } from './useFuncaoGuiada';
import AjustesDaFuncao from './AjustesDaFuncao.vue';
import ComoVaiFicar from './ComoVaiFicar.vue';
import ConfiraFuncao from './ConfiraFuncao.vue';
import DialogoDaCasa from './DialogoDaCasa.vue';
import EscolhaDaFuncao from './EscolhaDaFuncao.vue';
import EtapasDaFuncao from './EtapasDaFuncao.vue';
import PerdaDeAcesso from './PerdaDeAcesso.vue';
import PerguntaContatos from './PerguntaContatos.vue';
import PerguntaConversas from './PerguntaConversas.vue';
import PerguntaCuidado from './PerguntaCuidado.vue';
import PerguntaVendas from './PerguntaVendas.vue';
import SucessoDaFuncao from './SucessoDaFuncao.vue';

// Criar, alterar e duplicar uma função numa conversa guiada (#2308, PR 3 do épico #1784): Escolha → Ajustes →
// perguntas → Confira → Sucesso, com "Como vai ficar" ao lado e a guarda "Sair sem salvar?".
const { giver, isAdmin, canManagePeople, reachesRole } = usePeopleAccess();
const agentes = useMapGetter('agents/getAgents');
const conta = useMapGetter('accounts/getAccount');
const accountId = useMapGetter('getCurrentAccountId');
const {
  modo,
  idDaFuncao,
  carregou,
  erroAoAbrir,
  semPlano,
  memoria,
  etapa,
  pronta,
  permissions,
  inicial,
  nome,
  descricao,
  comeco,
  deFora,
  salva,
  salvando,
  erro,
  erroDoNome,
  vezDoErro,
  dicaDoNome,
  mudou,
  nomeDaPronta,
  usarPronta,
  doZero,
  carregar,
  salvar,
  voltarParaLista,
} = useFuncaoGuiada();

const PERGUNTAS = {
  conversas: PerguntaConversas,
  contatos: PerguntaContatos,
  vendas: PerguntaVendas,
  cuidado: PerguntaCuidado,
};
// A função cuja gaveta de pessoas está aberta (Escolha › "Pôr uma pessoa nela" e Sucesso › "Escolher pessoas").
const gaveta = ref(null);
const perda = ref(null);
const guarda = ref(null);
const trocar = ref(null);
let responderGuarda = null;

const podeEscolherPessoas = computed(
  () => canManagePeople.value && (!salva.value || reachesRole(salva.value))
);

const { etapas, passo, voltar, nomeNaFrase, ajustes } = useEtapasDaGuiada({
  modo,
  etapa,
  pronta,
  nome,
  comeco,
  mudou,
  podeEscolherPessoas,
  nomeDaPronta,
  voltarParaLista,
  pedirTroca: () => trocar.value?.abrir(),
});
oferecerMemoria(memoria);

// Cotações: só na conta com Cotação ou quando a função já tem a chave (decisão 13).
const comCotacoes = computed(
  () =>
    conta.value(accountId.value)?.autonomia_insurance_enabled === true ||
    inicial.value.some(chave => chave.startsWith('insurance_'))
);

// Durante o envio ninguém sai: a função seria criada mesmo com "Sair".
onBeforeRouteLeave(() => {
  if (salvando.value) return false;
  if (!mudou.value || salva.value) return true;
  guarda.value?.abrir();
  return new Promise(resolve => {
    responderGuarda = resolve;
  });
});
const sair = decisao => {
  responderGuarda?.(decisao);
  responderGuarda = null;
};

const fecharGaveta = () => {
  gaveta.value = null;
  if (etapa.value === 'sucesso') voltarParaLista();
};

// Perda de acesso (especificação 5.F), só para o administrador: o que quem já tem a função deixa de poder.
const pessoasDaFuncao = computed(() =>
  modo.value === 'alterar'
    ? agentes.value.filter(item => item.custom_role_id === idDaFuncao.value)
    : []
);
const perdas = computed(() => perdasDeAcesso(inicial.value, permissions.value));
const fica = computed(() => nivelQueFica(inicial.value, permissions.value));
const pedirSalvar = () => {
  if (isAdmin.value && pessoasDaFuncao.value.length && perdas.value.length)
    perda.value?.abrir();
  else salvar();
};

// A cada troca de etapa, o foco vai para o título dela: quem usa teclado ou leitor de tela sabe que mudou.
const principal = ref(null);
watch(etapa, async () => {
  await nextTick();
  const titulo = principal.value?.querySelector('h1');
  titulo?.setAttribute('tabindex', '-1');
  titulo?.focus();
});

onMounted(carregar);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div ref="principal" class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-8 px-4 pt-6 mx-auto max-w-6xl pb-56 sm:px-8 sm:pt-8 md:pb-12"
      >
        <EtapasDaFuncao
          :voltar="
            voltar ? $t(`FUNCOES_EQUIPE.GUIADA.VOLTAR.${voltar.texto}`) : ''
          "
          :etapas="etapas"
          :atual="passo"
          :desabilitado="salvando"
          @voltar="voltar?.ir()"
        />

        <PaywallDasFuncoes v-if="semPlano" />

        <ErroAoAbrir v-else-if="erroAoAbrir" @tentar="carregar" />

        <div v-else-if="!carregou" aria-busy="true" class="flex flex-col gap-4">
          <span class="sr-only">{{ $t('FUNCOES_EQUIPE.CARREGANDO') }}</span>
          <div class="w-72 h-10 rounded-xl bg-n-alpha-2 animate-pulse" />
          <div class="h-64 rounded-2xl bg-n-alpha-2 animate-pulse" />
        </div>

        <EscolhaDaFuncao
          v-else-if="etapa === 'escolha'"
          @criar="usarPronta"
          @zero="doZero"
          @por-pessoa="funcao => (gaveta = funcao)"
        />

        <div
          v-else
          class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_27rem]"
        >
          <div class="min-w-0">
            <AjustesDaFuncao
              v-if="etapa === 'ajustes'"
              v-model:permissions="permissions"
              :titulo="ajustes.titulo"
              :dica="ajustes.dica"
              :inicial="inicial"
              :giver="giver"
              :com-cotacoes="comCotacoes"
              @alterar="pergunta => (etapa = pergunta)"
              @continuar="etapa = 'confira'"
            />
            <component
              :is="PERGUNTAS[etapa]"
              v-else-if="PERGUNTAS[etapa]"
              v-model:permissions="permissions"
              :inicial="inicial"
              :giver="giver"
              :nome="nomeNaFrase"
              @pronto="etapa = 'ajustes'"
            />
            <ConfiraFuncao
              v-else-if="etapa === 'confira'"
              v-model:nome="nome"
              v-model:descricao="descricao"
              :modo="modo"
              :permissions="permissions"
              :inicial="inicial"
              :de-fora="deFora"
              :dica-do-nome="dicaDoNome"
              :erro-do-nome="erroDoNome"
              :erro="erro"
              :vez-do-erro="vezDoErro"
              :salvando="salvando"
              :pode-escolher-pessoas="podeEscolherPessoas"
              @salvar="pedirSalvar"
            />
            <SucessoDaFuncao
              v-else
              :nome="salva?.name || nome"
              :pode-escolher-pessoas="podeEscolherPessoas"
              @escolher-pessoas="gaveta = salva"
              @voltar="voltarParaLista"
            />
          </div>
          <ComoVaiFicar
            class="lg:sticky lg:top-6"
            :class="etapa === 'confira' ? 'hidden lg:flex' : ''"
            :nome="nomeNaFrase"
            :permissions="permissions"
            :inicial="inicial"
            :salva="etapa === 'sucesso'"
          />
        </div>
      </div>
    </div>

    <DialogoDaCasa
      ref="guarda"
      tipo="destrutivo"
      icone="i-lucide-door-open"
      :titulo="$t('FUNCOES_EQUIPE.GUARDA.TITULO')"
      :texto="$t('FUNCOES_EQUIPE.GUARDA.TEXTO')"
      :seguro="$t('FUNCOES_EQUIPE.GUARDA.CONTINUAR')"
      :acao="$t('FUNCOES_EQUIPE.GUARDA.SAIR')"
      @seguro="sair(false)"
      @acao="sair(true)"
    />
    <DialogoDaCasa
      ref="trocar"
      tipo="destrutivo"
      icone="i-lucide-door-open"
      :titulo="$t('FUNCOES_EQUIPE.GUIADA.TROCAR.TITULO')"
      :texto="$t('FUNCOES_EQUIPE.GUIADA.TROCAR.TEXTO')"
      :seguro="$t('FUNCOES_EQUIPE.GUIADA.TROCAR.CONTINUAR')"
      :acao="$t('FUNCOES_EQUIPE.GUIADA.TROCAR.TROCAR')"
      @acao="etapa = 'escolha'"
    />
    <PerdaDeAcesso
      ref="perda"
      :nome="comeco.nome"
      :pessoas="pessoasDaFuncao"
      :perdas="perdas"
      :fica="fica"
      @salvar="salvar"
    />
    <GavetaDaFuncao v-if="gaveta" :funcao="gaveta" @fechar="fecharGaveta" />
  </section>
</template>
