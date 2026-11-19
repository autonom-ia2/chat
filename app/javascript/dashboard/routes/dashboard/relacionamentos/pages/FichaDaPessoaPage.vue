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
import { useMapGetter } from 'dashboard/composables/store';
import { isVoiceCallEnabled } from 'dashboard/helper/inbox';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AvisoComDesfazer from '../components/carteira/AvisoComDesfazer.vue';
import ConversaNova from '../components/carteira/ConversaNova.vue';
import DialogoDeConfirmacao from '../components/carteira/DialogoDeConfirmacao.vue';
import AvisoVivo from '../components/ficha/AvisoVivo.vue';
import CabecalhoDaPessoa from '../components/ficha/CabecalhoDaPessoa.vue';
import CorpoDaFichaDaPessoa from '../components/ficha/CorpoDaFichaDaPessoa.vue';
import DialogoEtiquetasDaPessoa from '../components/ficha/DialogoEtiquetasDaPessoa.vue';
import DialogoJuntar from '../components/ficha/DialogoJuntar.vue';
import EsqueletoDaFicha from '../components/ficha/EsqueletoDaFicha.vue';
import FaixaBloqueada from '../components/ficha/FaixaBloqueada.vue';
import FaixaNaoQuer from '../components/ficha/FaixaNaoQuer.vue';
import GavetaDeInformacoes from '../components/ficha/GavetaDeInformacoes.vue';
import GavetaDoCard from '../components/ficha/GavetaDoCard.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import { fichaFonte } from '../fonte/fichaFonte';
import { usarDemo } from '../fonte/modoDemo';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { useConversarComPessoa } from '../carteira/useConversarComPessoa';
import { linhasDaPessoa, redesPreenchidas } from '../ficha/informacoes';
import { useAcoesDaFicha } from '../ficha/useAcoesDaFicha';
import { useAvisoVivo } from '../ficha/useAvisoVivo';
import { useDesfazerNaFicha } from '../ficha/useDesfazerNaFicha';
import {
  ESTADOS_DA_FICHA as ESTADOS,
  idValido,
} from '../ficha/useEstadoDaFicha';
import { useFichaDaPessoa } from '../ficha/useFichaDaPessoa';
import { usePerguntaDaFicha } from '../ficha/usePerguntaDaFicha';
import { usePermissoesDaFicha } from '../ficha/usePermissoesDaFicha';

// #2897 — o bloco Seguros (com a gaveta do seguro) só é baixado na conta que
// tem a carteira.
const SegurosDaFicha = defineAsyncComponent(
  () => import('../components/carteira/SegurosDaFicha.vue')
);
// #3071 — a gaveta do lembrete (a mesma do calendário) só é baixada no clique.
const LembreteGaveta = defineAsyncComponent(
  () =>
    import(
      'dashboard/routes/dashboard/crm/components/lembrete/LembreteGaveta.vue'
    )
);

// #2894 — a ficha da pessoa: primeiro "quem é e o que tem comigo". Editar é um
// passo a mais, de propósito (a gaveta "Alterar informações"). Em 390 px a ordem é
// cabeçalho, faixa, Conversas, Cards, Informações, Notas, Arquivos, De onde veio
// (o DOM segue essa ordem; ver `CorpoDaFichaDaPessoa`). Fora da demonstração lê e
// grava no servidor (#2895), e quem só pode ver não tem os botões de escrita.
// #2897 — na conta que tem a carteira de seguros, o bloco Seguros vem antes de
// Conversas.
// #3071 — todas as ações da ficha antiga, de verdade e com as permissões dela:
// Conversar (com quem nunca conversou abre a "Nova conversa" já com a pessoa),
// Ligar, Lembrete, pôr e tirar etiqueta, apagar nota, "Ver todas" as
// conversas, e no "⋯" Não quer receber mensagens, Juntar, Bloquear ou
// Desbloquear e Apagar. O que apaga ou restringe pergunta antes e diz o que vai
// acontecer; o que dá para voltar atrás (bloquear, "não quer mensagens",
// etiquetas) mostra o aviso com "Desfazer". Depois de apagar, a ficha volta
// para a lista; depois de juntar, fica na mesma pessoa, já com o que veio da
// outra. Na demonstração tudo isso roda na memória (demo/ficha.js); só a
// conversa e o lembrete avisam, porque as pessoas são inventadas.
const { t } = useI18n();
const route = useRoute();
const acoes = useAcoesDaFicha();
const permissoes = usePermissoesDaFicha();
const demo = usarDemo(route.query);
const fonte = fichaFonte({ demo });
const comSeguros = useContaDeSeguros(demo);
// Na demonstração tudo aparece, como na lista: é o desenho inteiro da tela.
const podeEditar = computed(() => fonte.usaDemo || permissoes.podeEditar.value);
const podeApagar = computed(() => fonte.usaDemo || permissoes.podeApagar.value);
const podeLembrete = computed(
  () => fonte.usaDemo || permissoes.podeCriarLembrete.value
);
// #2898 — "Exportar" no histórico do seguro: quem pode exportar contatos.
const podeExportar = computed(
  () => fonte.usaDemo || permissoes.podeExportar.value
);
const podeCriarCards = computed(
  () => fonte.usaDemo || permissoes.podeCriarCards.value
);
const id = computed(() => Number(route.params?.contactId));
const ficha = useFichaDaPessoa(fonte, id);
const agora = Date.now();

const gavetaAberta = ref(false);
const cardAberto = ref(null);
const lembreteAberto = ref(false);
const corpo = ref(null);
const { aviso, anunciar } = useAvisoVivo();
const desfazer = useDesfazerNaFicha();
const confirmacao = useTemplateRef('confirmacao');
const dialogoJuntar = useTemplateRef('dialogoJuntar');
const dialogoEtiquetas = useTemplateRef('dialogoEtiquetas');
const conversaNova = useTemplateRef('conversaNova');
const alertaDoJuntar = ref('');
const alertaDasEtiquetas = ref('');
const {
  pergunta,
  alerta: alertaDaPergunta,
  perguntar,
  confirmar: confirmarPergunta,
} = usePerguntaDaFicha({
  dialogo: confirmacao,
  motivo: () => ficha.motivo.value,
});

const nome = computed(() => ficha.pessoa.value?.name ?? '');
const primeiroNome = computed(() => nome.value.trim().split(' ')[0]);
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
const ft = (chave, valores) => t(`RELACIONAMENTOS_FICHA.${chave}`, valores);

// #3071 — "Ligar": a conta tem caixa com voz e a pessoa tem telefone (a regra
// do VoiceCallButton, que liga de verdade). Na demonstração não há chamada.
const caixas = useMapGetter('inboxes/getInboxes');
const podeLigar = computed(
  () =>
    !fonte.usaDemo &&
    Boolean(ficha.pessoa.value?.phone_number) &&
    (caixas.value ?? []).some(isVoiceCallEnabled)
);

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

// O "desfazer" de cada ação: { certo, frase }.
const desfeito = async (acao, certo, erro) => {
  const deuCerto = await acao();
  return {
    certo: deuCerto,
    frase: ft(deuCerto ? certo : erro, { nome: nome.value }),
  };
};

const desbloquear = async () => {
  desfazer.limpar();
  resultado(
    await ficha.desbloquear(),
    'RELACIONAMENTOS_FICHA.BLOQUEIO.DESBLOQUEADA',
    'RELACIONAMENTOS_FICHA.BLOQUEIO.ERRO_DESBLOQUEAR',
    { nome: nome.value }
  );
};

const perguntarBloquear = () =>
  perguntar({
    marca: 'confirmar-bloquear',
    tipo: 'alert',
    titulo: ft('BLOQUEIO.TITULO', { nome: nome.value }),
    aviso: ft('BLOQUEIO.AVISO', { nome: primeiroNome.value }),
    confirmar: ft('BLOQUEIO.CONFIRMAR'),
    erro: ft('BLOQUEIO.ERRO_BLOQUEAR'),
    agir: async () => {
      if (!(await ficha.bloquear())) return false;
      desfazer.mostrar(ft('BLOQUEIO.BLOQUEADA', { nome: nome.value }), () =>
        desfeito(
          ficha.desbloquear,
          'BLOQUEIO.DESBLOQUEADA',
          'BLOQUEIO.ERRO_DESBLOQUEAR'
        )
      );
      return true;
    },
  });

const perguntarNaoQuer = () =>
  perguntar({
    marca: 'confirmar-nao-quer',
    tipo: 'edit',
    titulo: ft('NAO_QUER.TITULO', { nome: nome.value }),
    aviso: ft('NAO_QUER.AVISO', { nome: primeiroNome.value }),
    confirmar: ft('NAO_QUER.CONFIRMAR'),
    erro: ft('NAO_QUER.ERRO'),
    agir: async () => {
      if (!(await ficha.marcarNaoQuer())) return false;
      desfazer.mostrar(ft('NAO_QUER.MARCADO', { nome: nome.value }), () =>
        desfeito(ficha.liberar, 'FAIXA.LIBERADO', 'FAIXA.ERRO')
      );
      return true;
    },
  });

// Depois de apagar não há ficha: volta para a lista, e o aviso vai junto.
const perguntarApagar = () =>
  perguntar({
    marca: 'confirmar-apagar',
    tipo: 'alert',
    titulo: ft('APAGAR.TITULO', { nome: nome.value }),
    aviso: ft('APAGAR.AVISO', { nome: nome.value }),
    confirmar: ft('APAGAR.CONFIRMAR', { nome: primeiroNome.value }),
    erro: ft('APAGAR.ERRO', { nome: nome.value }),
    agir: async () => {
      const quem = nome.value;
      if (!(await ficha.apagar())) return false;
      useAlert(ft('APAGAR.APAGADA', { nome: quem }));
      acoes.voltarParaLista();
      return true;
    },
  });

// O texto da nota no aviso, curto: é para a pessoa reconhecer qual é.
const TAMANHO_DO_TRECHO = 80;
const trechoDa = texto =>
  texto.length > TAMANHO_DO_TRECHO
    ? `${texto.slice(0, TAMANHO_DO_TRECHO)}…`
    : texto;

const perguntarApagarNota = nota => {
  desfazer.limpar();
  perguntar({
    marca: 'confirmar-apagar-nota',
    tipo: 'alert',
    titulo: ft('NOTAS.APAGAR_TITULO'),
    aviso: ft('NOTAS.APAGAR_AVISO', {
      texto: trechoDa(nota.texto),
      nome: nome.value,
    }),
    confirmar: ft('NOTAS.APAGAR_CONFIRMAR'),
    erro: ft('NOTAS.ERRO_APAGAR'),
    agir: async () => {
      if (!(await ficha.apagarNota(nota.id))) return false;
      resultado(true, 'RELACIONAMENTOS_FICHA.NOTAS.APAGADA');
      return true;
    },
  });
};

const abrirJuntar = () => {
  alertaDoJuntar.value = '';
  dialogoJuntar.value?.abrir();
};

const juntar = async outra => {
  alertaDoJuntar.value = '';
  const fica = nome.value;
  if (!(await ficha.juntar(outra.id))) {
    alertaDoJuntar.value = ficha.motivo.value || ft('JUNTAR.ERRO');
    return;
  }
  dialogoJuntar.value?.fechar();
  resultado(true, 'RELACIONAMENTOS_FICHA.JUNTAR.JUNTADAS', '', {
    sai: outra.name,
    fica,
  });
};

const abrirEtiquetas = () => {
  desfazer.limpar();
  alertaDasEtiquetas.value = '';
  dialogoEtiquetas.value?.abrir();
};

const salvarEtiquetas = async etiquetas => {
  const antes = [...(ficha.pessoa.value?.labels ?? [])];
  alertaDasEtiquetas.value = '';
  if (!(await ficha.trocarEtiquetas(etiquetas))) {
    alertaDasEtiquetas.value = ft('ETIQUETAS.ERRO');
    return;
  }
  dialogoEtiquetas.value?.fechar();
  desfazer.mostrar(ft('ETIQUETAS.SALVAS', { nome: nome.value }), () =>
    desfeito(
      () => ficha.trocarEtiquetas(antes),
      'ETIQUETAS.VOLTARAM',
      'ETIQUETAS.ERRO'
    )
  );
};

const ESCOLHAS_DO_MAIS = {
  alterar: () => {
    gavetaAberta.value = true;
  },
  desmarcar: desmarcarCliente,
  naoQuer: perguntarNaoQuer,
  juntar: abrirJuntar,
  bloquear: perguntarBloquear,
  desbloquear,
  apagar: perguntarApagar,
};

const escolherNoMais = escolha => {
  desfazer.limpar();
  ESCOLHAS_DO_MAIS[escolha]?.();
};

// "Conversar" aparece sempre: abre a conversa mais recente e, com quem nunca
// conversou, a "Nova conversa" já com a pessoa (o mesmo caminho da carteira,
// #3060). Na demonstração as conversas são inventadas: o clique só avisa.
const conversarCom = useConversarComPessoa({
  demo: fonte.usaDemo,
  abrirConversaNova: async pessoaId =>
    Boolean(await conversaNova.value?.abrir(pessoaId)),
});
const conversar = () => conversarCom({ id: id.value, name: nome.value });

const abrirConversa = conversaId => {
  if (fonte.usaDemo) {
    useAlert(
      t('RELACIONAMENTOS.LISTA.LINHA.ABRINDO_CONVERSA', { nome: nome.value })
    );
    return;
  }
  acoes.abrirConversa(conversaId);
};

const lembrete = () => {
  desfazer.limpar();
  if (fonte.usaDemo) avisar('LEMBRETE');
  else lembreteAberto.value = true;
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
            :pode-apagar="podeApagar"
            :pode-criar-cards="podeCriarCards"
            :pode-lembrete="podeLembrete"
            :pode-ligar="podeLigar"
            @conversar="conversar"
            @novo-card="novoCard"
            @lembrete="lembrete"
            @mais-acao="escolherNoMais"
            @marcar-cliente="marcarCliente"
            @abrir-empresa="acoes.abrirEmpresa"
            @etiquetas="abrirEtiquetas"
          />

          <FaixaBloqueada
            v-if="ficha.pessoa.value.blocked"
            :pessoa="ficha.pessoa.value"
            :desbloqueando="ficha.ocupado.value === 'desbloquear'"
            :pode-desbloquear="podeEditar"
            @desbloquear="desbloquear"
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
            pode-abrir-conversas
            @tentar="ficha.relerParte"
            @abrir-conversa="abrirConversa"
            @apagar-nota="perguntarApagarNota"
            @abrir-card="card => (cardAberto = card)"
            @guardar-nota="guardarNota"
            @alterar="gavetaAberta = true"
          >
            <template v-if="comSeguros" #antes>
              <SegurosDaFicha
                :dono-id="id"
                :demo="demo"
                :nome="nome"
                :pode-editar="podeEditar"
                :pode-exportar="podeExportar"
                :agora="agora"
                @abrir-segurado="abrirSegurado"
              />
            </template>
          </CorpoDaFichaDaPessoa>
        </div>
        <AvisoComDesfazer
          class="sticky z-30 bottom-4 ms-20 md:ms-0"
          :texto="desfazer.texto.value"
          :pode-desfazer="desfazer.podeDesfazer.value"
          :desfazendo="desfazer.desfazendo.value"
          @desfazer="desfazer.desfazer"
        />
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
    <template v-if="ficha.pessoa.value">
      <DialogoDeConfirmacao
        ref="confirmacao"
        :marca="pergunta?.marca ?? 'confirmar'"
        :tipo="pergunta?.tipo ?? 'alert'"
        :titulo="pergunta?.titulo ?? ''"
        :aviso="pergunta?.aviso ?? ''"
        :confirmar="pergunta?.confirmar ?? ''"
        :voltar="t('RELACIONAMENTOS.COMUM.CANCELAR')"
        :ocupado="Boolean(ficha.ocupado.value)"
        :alerta="alertaDaPergunta"
        aviso-forte
        @confirmar="confirmarPergunta"
      />
      <DialogoJuntar
        ref="dialogoJuntar"
        :pessoa="ficha.pessoa.value"
        :buscar="termo => fonte.buscarPessoas(termo, id)"
        :juntando="ficha.ocupado.value === 'juntar'"
        :alerta="alertaDoJuntar"
        @juntar="juntar"
      />
      <DialogoEtiquetasDaPessoa
        ref="dialogoEtiquetas"
        :pessoa="ficha.pessoa.value"
        :carregar="fonte.etiquetasDaConta"
        :salvando="ficha.ocupado.value === 'etiquetas'"
        :alerta="alertaDasEtiquetas"
        @salvar="salvarEtiquetas"
      />
      <LembreteGaveta
        v-if="lembreteAberto"
        show
        :contato="{ id: ficha.pessoa.value.id, name: nome }"
        @close="lembreteAberto = false"
      />
    </template>
    <ConversaNova ref="conversaNova" />
  </section>
</template>
