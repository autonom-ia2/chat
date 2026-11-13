<script setup>
import { computed, defineAsyncComponent, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AvisoVivo from '../components/ficha/AvisoVivo.vue';
import CabecalhoDaEmpresa from '../components/ficha/CabecalhoDaEmpresa.vue';
import DialogoMandarMensagem from '../components/ficha/DialogoMandarMensagem.vue';
import GavetaDaEmpresa from '../components/ficha/GavetaDaEmpresa.vue';
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
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { ABAS } from '../fonte/grupos';
import { FALHA_DA_PARTE } from '../ficha/falhas';
import { linhasDaEmpresa } from '../ficha/informacoes';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { useAvisoVivo } from '../ficha/useAvisoVivo';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../ficha/useEstadoDaFicha';
import { useFichaDaEmpresa } from '../ficha/useFichaDaEmpresa';
import { usePermissoesDaFicha } from '../ficha/usePermissoesDaFicha';

// #2897 — o bloco Seguros (com a gaveta do seguro) só é baixado na conta que
// tem a carteira.
const SegurosDaFicha = defineAsyncComponent(
  () => import('../components/carteira/SegurosDaFicha.vue')
);

// #2894 — a ficha da empresa: o mesmo desenho da pessoa, mais simples. Cabeçalho,
// as pessoas dela, as conversas, os cards e as informações. A ação principal é
// "Mandar mensagem" (sempre abre o diálogo que diz quem recebe e quem fica de
// fora; continuar ainda só avisa); "Alterar" abre a gaveta. Fora da demonstração
// lê e grava no servidor (#2895), e quem só pode ver não tem "Alterar". A parte
// que quem está olhando não pode ver some; a que não carregou fica, com "Tentar
// de novo".
// #2897 — na conta que tem a carteira de seguros, os seguros em nome da empresa
// vêm depois de Pessoas.
// #2970 — "Mandar mensagem", o ícone de conversar de cada pessoa e o "Ver
// todas" das conversas ainda só avisam: aparecem só na demonstração, até serem
// de verdade.
const { t } = useI18n();
const route = useRoute();
const acoes = useAcoesDaFicha();
const permissoes = usePermissoesDaFicha();
const demo = usarDemo(route.query);
const fonte = fichaFonte({ demo });
const comSeguros = useContaDeSeguros(demo);
// Na demonstração tudo aparece, como na lista: é o desenho inteiro da tela.
const podeEditar = computed(() => fonte.usaDemo || permissoes.podeEditar.value);
const id = computed(() => Number(route.params?.companyId));
const ficha = useFichaDaEmpresa(fonte, id);
const agora = Date.now();
const cardAberto = ref(null);
const gavetaAberta = ref(false);
const dialogoDaMensagem = ref(null);
const { aviso, anunciar } = useAvisoVivo();

const nome = computed(() => ficha.empresa.value?.name ?? '');
const linhas = computed(() =>
  ficha.empresa.value ? linhasDaEmpresa(ficha.empresa.value) : []
);
const avisar = chave =>
  acoes.avisar(`RELACIONAMENTOS_FICHA.EMPRESA.${chave}`, nome.value);
const abrirSegurado = ({ tipo, id: donoId }) =>
  tipo === 'empresa' ? acoes.abrirEmpresa(donoId) : acoes.abrirPessoa(donoId);

const resultado = (deuCerto, certo, erro) => {
  const texto = t(deuCerto ? certo : erro);
  useAlert(texto);
  anunciar(texto);
};

const continuarMensagem = () => {
  dialogoDaMensagem.value?.close();
  const texto = t('RELACIONAMENTOS_FICHA.EMPRESA.MENSAGEM.AVISO');
  useAlert(texto);
  anunciar(texto);
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

const podeVer = parte =>
  ficha.falhas.value[parte] !== FALHA_DA_PARTE.SEM_ACESSO;
const falhou = parte => ficha.falhas.value[parte] === FALHA_DA_PARTE.ERRO;

// Na demonstração os cards são inventados: lá abre só o quadro do CRM.
const abrirNoCrm = () => {
  const cardId = fonte.usaDemo ? undefined : cardAberto.value?.id;
  cardAberto.value = null;
  acoes.abrirNoCrm(cardId);
};

onMounted(ficha.carregar);
// Ao sair da ficha o parâmetro some (id NaN): não é pedido, não é "não achei".
watch(id, novo => {
  if (idValido(novo)) ficha.carregar();
});
watch(
  ficha.estado,
  estado =>
    anunciar(
      estado === ESTADOS.CARREGANDO ? t('RELACIONAMENTOS.COMUM.CARREGANDO') : ''
    ),
  { immediate: true }
);
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 bg-n-surface-1"
    data-relacionamentos="empresa"
  >
    <AvisoVivo :texto="aviso" />
    <main class="flex-1 min-w-0 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
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
          v-else-if="ficha.estado.value === ESTADOS.SEM_ACESSO"
          data-relacionamentos="sem-acesso"
        >
          <VazioComUmBotao
            :frase="t('RELACIONAMENTOS_FICHA.ESTADOS.SEM_ACESSO')"
            :botao="t('RELACIONAMENTOS_FICHA.ESTADOS.VOLTAR_PARA_LISTA')"
            @acao="acoes.voltarParaLista()"
          />
        </div>

        <div
          v-else
          data-relacionamentos="ficha-empresa"
          class="flex flex-col min-w-0 gap-6"
        >
          <CabecalhoDaEmpresa
            :empresa="ficha.empresa.value"
            :pode-editar="podeEditar"
            :pode-mandar-mensagem="fonte.usaDemo"
            @mandar-mensagem="dialogoDaMensagem?.open()"
            @alterar="gavetaAberta = true"
          />
          <div
            class="flex flex-col min-w-0 gap-6 lg:grid lg:grid-cols-3 lg:items-start"
          >
            <div class="flex flex-col min-w-0 gap-6 lg:col-span-2">
              <SecaoPessoasDaEmpresa
                v-if="podeVer('pessoas')"
                :pessoas="ficha.pessoas.value"
                :total="ficha.empresa.value.contacts_count ?? 0"
                :falhou="falhou('pessoas')"
                :pode-conversar="fonte.usaDemo"
                @tentar="ficha.relerParte('pessoas')"
                @abrir="acoes.abrirPessoa"
                @conversar="
                  pessoa =>
                    acoes.avisar(
                      'RELACIONAMENTOS_FICHA.AVISOS.CONVERSAR',
                      pessoa.name
                    )
                "
              />
              <SegurosDaFicha
                v-if="comSeguros"
                da-empresa
                :dono-id="id"
                :demo="demo"
                :pode-editar="podeEditar"
                :agora="agora"
                @abrir-segurado="abrirSegurado"
              />
              <SecaoConversas
                v-if="podeVer('conversas')"
                :conversas="ficha.conversas.value"
                :agora="agora"
                :falhou="falhou('conversas')"
                :pode-ver-todas="fonte.usaDemo"
                @tentar="ficha.relerParte('conversas')"
                @ver-todas="avisar('VER_TODAS')"
              />
              <SecaoCards
                v-if="podeVer('cards')"
                :cards="ficha.cards.value"
                :falhou="falhou('cards')"
                @tentar="ficha.relerParte('cards')"
                @abrir="card => (cardAberto = card)"
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

    <!-- #2970: sem "Mandar mensagem" fora da demonstração, nada abre isto. -->
    <DialogoMandarMensagem
      v-if="fonte.usaDemo && ficha.empresa.value"
      ref="dialogoDaMensagem"
      :pessoas="ficha.pessoas.value"
      @continuar="continuarMensagem"
    />
    <GavetaDaEmpresa
      :aberta="gavetaAberta"
      :empresa="ficha.empresa.value"
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
