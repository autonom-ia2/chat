<script setup>
import { computed, defineAsyncComponent, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AvisoVivo from '../components/ficha/AvisoVivo.vue';
import CabecalhoDaPessoa from '../components/ficha/CabecalhoDaPessoa.vue';
import CorpoDaFichaDaPessoa from '../components/ficha/CorpoDaFichaDaPessoa.vue';
import EsqueletoDaFicha from '../components/ficha/EsqueletoDaFicha.vue';
import FaixaNaoQuer from '../components/ficha/FaixaNaoQuer.vue';
import GavetaDeInformacoes from '../components/ficha/GavetaDeInformacoes.vue';
import GavetaDoCard from '../components/ficha/GavetaDoCard.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import { fichaFonte } from '../fonte/fichaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { linhasDaPessoa, redesPreenchidas } from '../ficha/informacoes';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { useAvisoVivo } from '../ficha/useAvisoVivo';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../ficha/useEstadoDaFicha';
import { useFichaDaPessoa } from '../ficha/useFichaDaPessoa';
import { usePermissoesDaFicha } from '../ficha/usePermissoesDaFicha';

// #2897 — o bloco Seguros (com a gaveta do seguro) só é baixado na conta que
// tem a carteira.
const SegurosDaFicha = defineAsyncComponent(
  () => import('../components/carteira/SegurosDaFicha.vue')
);

// #2894 — a ficha da pessoa: primeiro "quem é e o que tem comigo". Editar é um
// passo a mais, de propósito (a gaveta "Alterar informações"). Em 390 px a ordem é
// cabeçalho, faixa, Conversas, Cards, Informações, Notas, Arquivos, De onde veio
// (o DOM segue essa ordem; ver `CorpoDaFichaDaPessoa`). Fora da demonstração lê e
// grava no servidor (#2895), e quem só pode ver não tem os botões de escrita.
// #2897 — na conta que tem a carteira de seguros, o bloco Seguros vem antes de
// Conversas.
const { t } = useI18n();
const route = useRoute();
const acoes = useAcoesDaFicha();
const permissoes = usePermissoesDaFicha();
const demo = usarDemo(route.query);
const fonte = fichaFonte({ demo });
const comSeguros = useContaDeSeguros(demo);
// Na demonstração tudo aparece, como na lista: é o desenho inteiro da tela.
const podeEditar = computed(() => fonte.usaDemo || permissoes.podeEditar.value);
const podeCriarCards = computed(
  () => fonte.usaDemo || permissoes.podeCriarCards.value
);
const id = computed(() => Number(route.params?.contactId));
const ficha = useFichaDaPessoa(fonte, id);
const agora = Date.now();

const gavetaAberta = ref(false);
const cardAberto = ref(null);
const corpo = ref(null);
const { aviso, anunciar } = useAvisoVivo();

const nome = computed(() => ficha.pessoa.value?.name ?? '');
const linhas = computed(() =>
  ficha.pessoa.value ? linhasDaPessoa(ficha.pessoa.value) : []
);
const redes = computed(() =>
  ficha.pessoa.value ? redesPreenchidas(ficha.pessoa.value) : []
);
const avisar = chave =>
  acoes.avisar(`RELACIONAMENTOS_FICHA.AVISOS.${chave}`, nome.value);
const abrirSegurado = ({ tipo, id: donoId }) =>
  tipo === 'empresa' ? acoes.abrirEmpresa(donoId) : acoes.abrirPessoa(donoId);

const resultado = (deuCerto, certo, erro, valores) => {
  const texto = t(deuCerto ? certo : erro, valores);
  useAlert(texto);
  anunciar(texto);
};

const marcarCliente = async () =>
  resultado(
    await ficha.marcarCliente(),
    'RELACIONAMENTOS_FICHA.CABECALHO.CLIENTE_MARCADO',
    'RELACIONAMENTOS_FICHA.CABECALHO.ERRO_MARCAR',
    { nome: nome.value }
  );

// Sem pergunta antes: volta com um clique em "Marcar como cliente".
const desmarcarCliente = async () =>
  resultado(
    await ficha.desmarcarCliente(),
    'RELACIONAMENTOS_FICHA.CABECALHO.CLIENTE_DESMARCADO',
    'RELACIONAMENTOS_FICHA.CABECALHO.ERRO_DESMARCAR',
    { nome: nome.value }
  );

// Quem liberou fica só no log do servidor; gravar isso é da fatia B do #2895.
const liberar = async () =>
  resultado(
    await ficha.liberar(),
    'RELACIONAMENTOS_FICHA.FAIXA.LIBERADO',
    'RELACIONAMENTOS_FICHA.FAIXA.ERRO',
    { nome: nome.value }
  );

const guardarNota = async texto => {
  const certo = await ficha.guardarNota(texto);
  if (certo) corpo.value?.limpar();
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

// "Alterar informações" abre a gaveta e "Não é mais cliente" desmarca na hora;
// as outras escolhas só avisam, por ora.
const escolherNoMais = escolha => {
  if (escolha === 'alterar') gavetaAberta.value = true;
  else if (escolha === 'desmarcar') desmarcarCliente();
  else avisar(AVISO_DO_MAIS[escolha]);
};

// As saídas que têm rota real. Na demonstração as pessoas, as conversas e os
// cards são inventados: lá o clique só avisa (ou abre o quadro do CRM, sem card).
// "Conversar" abre a conversa mais recente; com quem nunca conversou ainda só
// avisa (começar conversa nova não é só uma rota).
const conversar = () => {
  const [maisRecente] = ficha.conversas.value;
  if (fonte.usaDemo || !maisRecente) avisar('CONVERSAR');
  else acoes.abrirConversa(maisRecente.id);
};

const novoCard = () => {
  if (fonte.usaDemo) avisar('NOVO_CARD');
  else acoes.novoCardNoCrm(id.value);
};

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
    data-relacionamentos="pessoa"
  >
    <AvisoVivo :texto="aviso" />
    <main class="flex-1 min-w-0 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
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
          data-relacionamentos="ficha-pessoa"
          class="flex flex-col min-w-0 gap-6"
        >
          <CabecalhoDaPessoa
            :pessoa="ficha.pessoa.value"
            :marcando-cliente="ficha.ocupado.value === 'marcarCliente'"
            :pode-editar="podeEditar"
            :pode-criar-cards="podeCriarCards"
            @conversar="conversar"
            @novo-card="novoCard"
            @lembrete="avisar('LEMBRETE')"
            @mais-acao="escolherNoMais"
            @marcar-cliente="marcarCliente"
            @abrir-empresa="acoes.abrirEmpresa"
          />

          <FaixaNaoQuer
            v-if="ficha.pessoa.value.opted_out_at"
            :pessoa="ficha.pessoa.value"
            :liberando="ficha.ocupado.value === 'liberar'"
            :agora="agora"
            :pode-liberar="podeEditar"
            @liberar="liberar"
          />

          <CorpoDaFichaDaPessoa
            ref="corpo"
            :conversas="ficha.conversas.value"
            :cards="ficha.cards.value"
            :notas="ficha.notas.value"
            :arquivos="ficha.arquivos.value"
            :origem="ficha.origem.value"
            :linhas="linhas"
            :redes="redes"
            :agora="agora"
            :guardando-nota="ficha.ocupado.value === 'guardarNota'"
            :falhas="ficha.falhas.value"
            :pode-editar="podeEditar"
            @tentar="ficha.relerParte"
            @ver-todas="avisar('VER_TODAS')"
            @abrir-card="card => (cardAberto = card)"
            @guardar-nota="guardarNota"
            @alterar="gavetaAberta = true"
          >
            <template v-if="comSeguros" #antes>
              <SegurosDaFicha
                :dono-id="id"
                :demo="demo"
                :pode-editar="podeEditar"
                :agora="agora"
                @abrir-segurado="abrirSegurado"
              />
            </template>
          </CorpoDaFichaDaPessoa>
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
