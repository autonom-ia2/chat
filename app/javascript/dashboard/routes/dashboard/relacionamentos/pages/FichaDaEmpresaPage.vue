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
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import FieldConfigurator from 'dashboard/components-next/Relationships/FieldConfigurator.vue';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AvisoComDesfazer from '../components/carteira/AvisoComDesfazer.vue';
import DialogoDeConfirmacao from '../components/carteira/DialogoDeConfirmacao.vue';
import AvisoVivo from '../components/ficha/AvisoVivo.vue';
import CabecalhoDaEmpresa from '../components/ficha/CabecalhoDaEmpresa.vue';
import CorpoDaFichaDaEmpresa from '../components/ficha/CorpoDaFichaDaEmpresa.vue';
import DialogoMandarMensagem from '../components/ficha/DialogoMandarMensagem.vue';
import DialogoPorPessoa from '../components/ficha/DialogoPorPessoa.vue';
import GavetaDaEmpresa from '../components/ficha/GavetaDaEmpresa.vue';
import EsqueletoDaFicha from '../components/ficha/EsqueletoDaFicha.vue';
import GavetaDoCard from '../components/ficha/GavetaDoCard.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import { fichaFonte } from '../fonte/fichaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { ABAS } from '../fonte/grupos';
import { camposDaEmpresa } from '../ficha/atributos';
import { useIdioma } from '../ficha/idioma';
import { linhasDaEmpresa } from '../ficha/informacoesDaEmpresa';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { useAvisoVivo } from '../ficha/useAvisoVivo';
import { DA_EMPRESA, useCamposDaConta } from '../ficha/useCamposDaConta';
import { useDesfazerNaFicha } from '../ficha/useDesfazerNaFicha';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../ficha/useEstadoDaFicha';
import { useFichaDaEmpresa } from '../ficha/useFichaDaEmpresa';
import { usePerguntaDaFicha } from '../ficha/usePerguntaDaFicha';
import { usePermissoesDaFicha } from '../ficha/usePermissoesDaFicha';

// #2897 — o bloco Seguros (com a gaveta do seguro) só é baixado na conta que
// tem a carteira.
const SegurosDaFicha = defineAsyncComponent(
  () => import('../components/carteira/SegurosDaFicha.vue')
);
// #3078 — a gaveta do lembrete (a mesma do calendário) só é baixada no clique.
const LembreteGaveta = defineAsyncComponent(
  () =>
    import(
      'dashboard/routes/dashboard/crm/components/lembrete/LembreteGaveta.vue'
    )
);

// #2894 — a ficha da empresa: o mesmo desenho da pessoa, mais simples. Fora da
// demonstração lê e grava no servidor (#2895), e quem só pode ver não tem os
// botões de escrita. A parte que quem está olhando não pode ver some; a que não
// carregou fica, com "Tentar de novo".
// #2897 — na conta que tem a carteira de seguros, os seguros em nome da empresa
// vêm depois de Pessoas.
// #2970 — "Mandar mensagem", o ícone de conversar de cada pessoa e o "Ver
// todas" das conversas ainda só avisam: aparecem só na demonstração.
// #3078 — tudo o que a ficha antiga de Empresas fazia, com as permissões dela:
// a foto, a cidade, "O que a empresa faz" e os campos personalizados com o tipo
// (gaveta "Alterar informações"; "Escolher campos" abre o configurador da
// ficha antiga, área company_details); pôr e tirar pessoa (tirar mostra o
// aviso com "Desfazer"); o histórico de conversas, que abre cada uma; as notas
// das pessoas, para ler; as mídias (chave relationships_company_media), com
// "Ver todas" na tela de mídias; Lembrete; e Apagar, que pergunta antes e
// volta para a aba Empresas. Na demonstração tudo roda na memória
// (demo/ficha.js); só o lembrete avisa.
// #3082 — os campos personalizados da empresa ganharam o bloco "Seus campos",
// do lado, antes de Informações, com "Novo campo" e "Escolher campos da ficha".
const { t } = useI18n();
const route = useRoute();
const idioma = useIdioma();
const { isCloudFeatureEnabled } = useAccount();
const acoes = useAcoesDaFicha();
const permissoes = usePermissoesDaFicha();
const demo = usarDemo(route.query);
const fonte = fichaFonte({ demo });
const comSeguros = useContaDeSeguros(demo);
// Na demonstração tudo aparece, como na lista: é o desenho inteiro da tela.
const podeEditar = computed(() => fonte.usaDemo || permissoes.podeEditar.value);
// CompanyPolicy#destroy?: a mesma regra de apagar contato.
const podeApagar = computed(() => fonte.usaDemo || permissoes.podeApagar.value);
const podeLembrete = computed(
  () => fonte.usaDemo || permissoes.podeCriarLembrete.value
);
// #2898 — "Exportar" no histórico do seguro: quem pode exportar contatos.
const podeExportar = computed(
  () => fonte.usaDemo || permissoes.podeExportar.value
);
// As mídias da empresa: a regra da ficha antiga (useRelationships#mediaEnabled),
// as chaves `companies` e `relationships_company_media`.
const comMidias = computed(
  () =>
    fonte.usaDemo ||
    (isCloudFeatureEnabled(FEATURE_FLAGS.COMPANIES) &&
      isCloudFeatureEnabled(FEATURE_FLAGS.RELATIONSHIPS_COMPANY_MEDIA))
);
// Na demonstração a tela de mídias não teria o que mostrar. Fora dela, quem vê
// a ficha chega na tela de mídias (a mesma regra de leitura no servidor).
const podeVerTodasAsMidias = !fonte.usaDemo;
const id = computed(() => Number(route.params?.companyId));
const ficha = useFichaDaEmpresa(fonte, id, {
  comMidias: () => comMidias.value,
});
const camposDaConta = useCamposDaConta({ de: DA_EMPRESA });
const podeEscolherCampos = computed(
  () => !fonte.usaDemo && camposDaConta.podeEscolher.value
);
const configurador = useTemplateRef('configurador');
const confirmacao = useTemplateRef('confirmacao');
const dialogoDaMensagem = useTemplateRef('dialogoDaMensagem');
const dialogoPorPessoa = useTemplateRef('dialogoPorPessoa');
const agora = Date.now();
const cardAberto = ref(null);
const gavetaAberta = ref(false);
const lembreteAberto = ref(false);
const alertaDoPor = ref('');
const tirandoId = ref(null);
const { aviso, anunciar } = useAvisoVivo();
const desfazer = useDesfazerNaFicha();
const {
  pergunta,
  alerta: alertaDaPergunta,
  perguntar,
  confirmar: confirmarPergunta,
} = usePerguntaDaFicha({
  dialogo: confirmacao,
  motivo: () => ficha.motivo.value,
});

const nome = computed(() => ficha.empresa.value?.name ?? '');
const fe = (chave, valores) =>
  t(`RELACIONAMENTOS_FICHA.EMPRESA.${chave}`, valores);
const campos = computed(() =>
  ficha.empresa.value
    ? camposDaEmpresa({
        definicoes: camposDaConta.definicoes.value,
        escolhidos: camposDaConta.escolhidos.value,
        valores: ficha.empresa.value.custom_attributes ?? {},
      })
    : []
);
const linhas = computed(() =>
  ficha.empresa.value
    ? linhasDaEmpresa(ficha.empresa.value, { idioma: idioma.value, agora })
    : []
);
const abrirSegurado = ({ tipo, id: donoId }) =>
  tipo === 'empresa' ? acoes.abrirEmpresa(donoId) : acoes.abrirPessoa(donoId);

const dizer = texto => {
  useAlert(texto);
  anunciar(texto);
};

const continuarMensagem = () => {
  dialogoDaMensagem.value?.close();
  dizer(fe('MENSAGEM.AVISO'));
};

const fraseDoSalvar = certo => {
  if (certo) return t('RELACIONAMENTOS_FICHA.GAVETA.SALVO');
  if (ficha.salvouEmParte.value)
    return t('RELACIONAMENTOS_FICHA.GAVETA.SALVOU_EM_PARTE');
  return ficha.motivo.value || t('RELACIONAMENTOS_FICHA.GAVETA.ERRO_AO_SALVAR');
};

// Se a empresa ficou gravada e só a foto (ou um campo que sai) falhou, o aviso
// diz isso: "Salvar" de novo repete o que faltou.
const salvar = async pedido => {
  if (ficha.ocupadoEm('salvar')) return;
  const certo = await ficha.salvar(pedido);
  if (certo) gavetaAberta.value = false;
  dizer(fraseDoSalvar(certo));
};

const alterar = () => {
  desfazer.limpar();
  gavetaAberta.value = true;
};

// O que o DELETE companies/:id faz de verdade (Companies::DeleteJob), a perda
// primeiro: os lembretes e arquivos da empresa são apagados; as pessoas saem
// da empresa e continuam na conta, com as conversas; os seguros ficam sem ela.
const avisoDeApagar = () => {
  const pessoas = ficha.empresa.value?.contacts_count ?? 0;
  return [
    fe('APAGAR.LEMBRETES'),
    pessoas > 0 &&
      t(
        'RELACIONAMENTOS_FICHA.EMPRESA.APAGAR.PESSOAS',
        { count: pessoas },
        pessoas
      ),
    comSeguros.value && fe('APAGAR.SEGUROS'),
    fe('APAGAR.NAO_VOLTA'),
  ]
    .filter(Boolean)
    .join(' ');
};

// Depois de apagar não há ficha: volta para a aba Empresas, e o aviso vai junto.
// A empresa com muitas pessoas o servidor apaga em alguns minutos (#3079): o
// aviso diz isso, e a lista a mostra até lá.
const perguntarApagar = () => {
  desfazer.limpar();
  perguntar({
    marca: 'confirmar-apagar-empresa',
    tipo: 'alert',
    titulo: fe('APAGAR.TITULO', { nome: nome.value }),
    aviso: avisoDeApagar(),
    confirmar: fe('APAGAR.CONFIRMAR'),
    erro: fe('APAGAR.ERRO', { nome: nome.value }),
    agir: async () => {
      const qual = nome.value;
      const apagada = await ficha.apagar();
      if (!apagada) return false;
      useAlert(
        fe(apagada.naFila ? 'APAGAR.NA_FILA' : 'APAGAR.APAGADA', { nome: qual })
      );
      acoes.voltarParaLista(ABAS.EMPRESAS);
      return true;
    },
  });
};

const abrirPor = () => {
  desfazer.limpar();
  alertaDoPor.value = '';
  dialogoPorPessoa.value?.abrir();
};

// "Desfazer" devolve a pessoa para onde estava: sem empresa (tira desta) ou
// para a empresa de antes (põe de volta lá).
const porPessoa = async pessoa => {
  alertaDoPor.value = '';
  if (!(await ficha.porPessoa(pessoa.id))) {
    alertaDoPor.value = ficha.motivo.value || fe('POR.ERRO');
    return;
  }
  dialogoPorPessoa.value?.fechar();
  const valores = { nome: pessoa.name, empresa: nome.value };
  if (pessoa.empresa) {
    const de = pessoa.empresa.nome;
    desfazer.mostrar(fe('POR.MUDOU', { ...valores, de }), async () => {
      const certo = await ficha.devolverPessoa(pessoa.id, pessoa.empresa.id);
      return {
        certo,
        frase: fe(certo ? 'POR.MUDOU_DESFEITO' : 'POR.ERRO', {
          ...valores,
          de,
        }),
      };
    });
    return;
  }
  desfazer.mostrar(fe('POR.ENTROU', valores), async () => {
    const certo = await ficha.tirarPessoa(pessoa.id);
    return {
      certo,
      frase: fe(certo ? 'POR.DESFEITO' : 'TIRAR.ERRO', valores),
    };
  });
};

const tirarPessoa = async pessoa => {
  if (tirandoId.value) return;
  desfazer.limpar();
  tirandoId.value = pessoa.id;
  const valores = { nome: pessoa.name, empresa: nome.value };
  const certo = await ficha.tirarPessoa(pessoa.id);
  tirandoId.value = null;
  if (!certo) {
    dizer(ficha.motivo.value || fe('TIRAR.ERRO', valores));
    return;
  }
  desfazer.mostrar(fe('TIRAR.SAIU', valores), async () => {
    const voltou = await ficha.porPessoa(pessoa.id);
    return {
      certo: voltou,
      frase: fe(voltou ? 'TIRAR.VOLTOU' : 'POR.ERRO', valores),
    };
  });
};

// O lembrete aberto pela ficha já vem com o "O que é" e com "Amanhã, 09:00".
const amanha = () => {
  const dia = new Date();
  dia.setDate(dia.getDate() + 1);
  return dia;
};
const diaDoLembrete = ref(amanha());
const lembrete = () => {
  desfazer.limpar();
  if (fonte.usaDemo) {
    acoes.avisar('RELACIONAMENTOS_FICHA.AVISOS.LEMBRETE', nome.value);
    return;
  }
  diaDoLembrete.value = amanha();
  lembreteAberto.value = true;
};

// Só na demonstração (#2970): conversar daqui ainda só avisa.
const avisarConversa = () =>
  acoes.avisar('RELACIONAMENTOS_FICHA.EMPRESA.CONVERSAR', nome.value);

const abrirConversa = conversaId => {
  if (fonte.usaDemo) {
    acoes.avisar('RELACIONAMENTOS.LISTA.LINHA.ABRINDO_CONVERSA', nome.value);
    return;
  }
  acoes.abrirConversa(conversaId);
};

// Na demonstração os cards são inventados: lá abre só o quadro do CRM.
const abrirNoCrm = () => {
  const cardId = fonte.usaDemo ? undefined : cardAberto.value?.id;
  cardAberto.value = null;
  acoes.abrirNoCrm(cardId);
};

onMounted(ficha.carregar);
// Ao sair da ficha o parâmetro some (id NaN): não é pedido, não é "não achei".
watch(id, novo => {
  desfazer.limpar();
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
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10"
        :class="desfazer.texto.value ? 'md:pb-28' : 'md:pb-10'"
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
            :pode-apagar="podeApagar"
            :pode-lembrete="podeLembrete"
            :pode-mandar-mensagem="fonte.usaDemo"
            @mandar-mensagem="dialogoDaMensagem?.open()"
            @lembrete="lembrete"
            @alterar="alterar"
            @apagar="perguntarApagar"
          />

          <!-- O aviso do que acabou de acontecer, como na ficha da pessoa: no
               celular logo abaixo do cabeçalho; no computador preso ao pé da
               tela. Vazio, o espaço entre os blocos não dobra. -->
          <AvisoComDesfazer
            class="md:order-last md:sticky md:z-30 md:bottom-4"
            :class="{ '-mt-6': !desfazer.texto.value }"
            :texto="desfazer.texto.value"
            :pode-desfazer="desfazer.podeDesfazer.value"
            :desfazendo="desfazer.desfazendo.value"
            pode-fechar
            @desfazer="desfazer.desfazer"
            @fechar="desfazer.limpar"
          />

          <CorpoDaFichaDaEmpresa
            :pessoas="ficha.pessoas.value"
            :total-de-pessoas="ficha.empresa.value.contacts_count ?? 0"
            :conversas="ficha.conversas.value"
            :cards="ficha.cards.value"
            :notas="ficha.notas.value"
            :midias="ficha.midias.value"
            :linhas="linhas"
            :campos="campos"
            :agora="agora"
            :falhas="ficha.falhas.value"
            :tirando="tirandoId"
            :pode-editar="podeEditar"
            :pode-escolher-campos="podeEscolherCampos"
            :pode-conversar="fonte.usaDemo"
            :pode-ver-todas="false"
            pode-abrir-conversas
            :com-midias="comMidias"
            :pode-ver-todas-as-midias="podeVerTodasAsMidias"
            @tentar="ficha.relerParte"
            @abrir-pessoa="acoes.abrirPessoa"
            @conversar="avisarConversa"
            @por-pessoa="abrirPor"
            @tirar-pessoa="tirarPessoa"
            @abrir-conversa="abrirConversa"
            @abrir-card="card => (cardAberto = card)"
            @ver-todas-as-midias="acoes.verMidiasDaEmpresa(id)"
            @alterar="alterar"
            @escolher-campos="configurador?.open()"
            @criar-campo="configurador?.open(null, true)"
          >
            <template v-if="comSeguros" #depoisDasPessoas>
              <SegurosDaFicha
                da-empresa
                :dono-id="id"
                :demo="demo"
                :pode-editar="podeEditar"
                :pode-exportar="podeExportar"
                :agora="agora"
                @abrir-segurado="abrirSegurado"
              />
            </template>
          </CorpoDaFichaDaEmpresa>
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
      :salvando="ficha.ocupadoEm('salvar')"
      :definicoes="camposDaConta.definicoes.value"
      :escolhidos="camposDaConta.escolhidos.value"
      @fechar="gavetaAberta = false"
      @salvar="salvar"
    />
    <FieldConfigurator
      v-if="podeEscolherCampos && podeEditar"
      ref="configurador"
      entity="company"
      surface="company_details"
      :show-actions="false"
    />
    <GavetaDoCard
      :card="cardAberto"
      @fechar="cardAberto = null"
      @abrir-no-crm="abrirNoCrm"
    />
    <template v-if="ficha.empresa.value">
      <DialogoDeConfirmacao
        ref="confirmacao"
        :marca="pergunta?.marca ?? 'confirmar'"
        :tipo="pergunta?.tipo ?? 'alert'"
        :titulo="pergunta?.titulo ?? ''"
        :aviso="pergunta?.aviso ?? ''"
        :confirmar="pergunta?.confirmar ?? ''"
        :voltar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
        :ocupado="ficha.algumOcupado.value"
        :alerta="alertaDaPergunta"
        :empilhado="pergunta?.empilhado ?? false"
        aviso-forte
        @confirmar="confirmarPergunta"
      />
      <DialogoPorPessoa
        ref="dialogoPorPessoa"
        :empresa="ficha.empresa.value"
        :buscar="ficha.buscarPessoas"
        :pondo="ficha.ocupadoEm('porPessoa')"
        :alerta="alertaDoPor"
        @por="porPessoa"
      />
      <LembreteGaveta
        v-if="lembreteAberto"
        show
        :empresa="{ id: ficha.empresa.value.id, name: nome }"
        :titulo="t('RELACIONAMENTOS_FICHA.ACOES.LEMBRETE_TITULO', { nome })"
        :dia="diaDoLembrete"
        @close="lembreteAberto = false"
      />
    </template>
  </section>
</template>
