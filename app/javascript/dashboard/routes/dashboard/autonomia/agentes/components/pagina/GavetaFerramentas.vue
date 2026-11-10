<script setup>
import { computed, nextTick, onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AgenteBotao from '../AgenteBotao.vue';
import AgenteConfirmacao from '../AgenteConfirmacao.vue';
import AgenteErro from '../AgenteErro.vue';
import AgenteGaveta from '../AgenteGaveta.vue';
import DialogoAcao from './DialogoAcao.vue';
import FerramentaDetalhe from './ferramentas/FerramentaDetalhe.vue';
import FerramentaPassos from './ferramentas/FerramentaPassos.vue';
import FerramentaTeste from './ferramentas/FerramentaTeste.vue';
import FerramentasLista from './ferramentas/FerramentasLista.vue';
import { useFerramentasDoAgente } from '../../composables/useFerramentasDoAgente';
import { useVitrine } from '../../vitrine/useVitrine';
import { chaveDoTexto, ferramentaPorId } from '../../vitrine/catalogo';

// #1301 (Fase 2, protótipo ferramentas.html) — gaveta de Ferramentas, só SuperAdmin (a página só
// a oferece a ele e o ToolsController recusa os outros com 403). Uma gaveta, várias vistas: lista
// (F01), assistente de 4 passos (F03–F06), teste (F07), ferramenta (F09) e sem permissão (F12).
// Cada vista põe os próprios botões no rodapé (Teleport para o rodapé da gaveta). Ligar sempre
// passa por uma chamada de teste; desligar e excluir pedem confirmação no diálogo do módulo.
// O painel antigo (PanelTools) continua para as contas sem a jornada nova.
// #2858 F2 — com a vitrine (`vitrine`), as prontas do agente aparecem na lista (liga/desliga e "Tirar") e "Adicionar
// ferramenta" leva à vitrine já com este agente (`verVitrine`). O cadastro manual só existe para quem pode usá-lo
// (`cadastroManual`): sem ele, a API das ferramentas feitas à mão nem é chamada (ela responderia 401). `comecarNova`
// abre direto o cadastro novo ("Criar a minha (avançado)" da vitrine).
const props = defineProps({
  agente: { type: Object, required: true },
  nome: { type: String, default: '' },
  cadastroManual: { type: Boolean, default: true },
  vitrine: { type: Boolean, default: false },
  comecarNova: { type: Boolean, default: false },
});

const emit = defineEmits(['fechar', 'verVitrine']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const { t } = useI18n();

const api = useFerramentasDoAgente(Number(props.agente.id));
const estadoDaVitrine = useVitrine();
const NS_VITRINE = 'AGENTS.VITRINE';
const nomeDaPronta = item =>
  item ? t(`${NS_VITRINE}.FERRAMENTAS.${chaveDoTexto(item.fonte)}.NOME`) : '';
// Só as fontes que esta tela conhece (o catálogo): uma fonte que a tela ainda não tem não aparece com a chave crua.
const prontas = computed(() =>
  props.vitrine
    ? estadoDaVitrine
        .doAgente(props.agente.id)
        .filter(item => ferramentaPorId(item.fonte))
        .map(item => ({
          ...item,
          nome: nomeDaPronta(item),
          frase:
            item.usar_quando ||
            t(`${NS_VITRINE}.FERRAMENTAS.${chaveDoTexto(item.fonte)}.FAZ`),
          icone: ferramentaPorId(item.fonte).icone,
        }))
    : []
);
const ferramentasManuais = computed(() =>
  props.cadastroManual ? api.ferramentas.value : []
);
const carregandoLista = computed(
  () =>
    (props.cadastroManual && api.carregando.value) ||
    (props.vitrine && estadoDaVitrine.carregando.value)
);
const erroNaLista = computed(
  () =>
    (props.cadastroManual && api.erroAoCarregar.value) ||
    (props.vitrine && Boolean(estadoDaVitrine.erro.value))
);
const semPermissao = computed(
  () => props.cadastroManual && api.semPermissao.value
);
const carregar = () => {
  if (props.cadastroManual) api.carregar();
  if (props.vitrine) estadoDaVitrine.carregar();
};
const nomeDoAgente = computed(() => props.nome || props.agente.name || '');
const rodape = `ferramentas-rodape-${useId()}`;

const conteudo = ref(null);
let contador = 0;
const vista = ref(
  props.comecarNova && props.cadastroManual
    ? { tipo: 'passos', modo: 'novo', passo: 1, chave: 0 }
    : { tipo: 'lista', chave: 0 }
);
const ir = async (nova, foco = null) => {
  contador += 1;
  vista.value = { ...nova, chave: contador };
  await nextTick();
  const alvo = foco && document.getElementById(foco);
  (alvo || conteudo.value)?.focus();
};

const passos = ref(null);
const dialogoSair = ref(null);
const dialogoDesligar = ref(null);
const dialogoExcluir = ref(null);
const dialogoTirar = ref(null);
const alvo = ref(null);
const prontaAlvo = ref(null);
const saida = ref(null);
const anuncio = ref('');

const ferramenta = computed(() =>
  api.ferramentas.value.find(f => f.id === vista.value.id)
);

const titulo = computed(() => {
  const { tipo, modo } = vista.value;
  const nomeDaFerramenta = ferramenta.value?.name || '';
  if (semPermissao.value || tipo === 'lista') return t(`${NS}.TITULO`);
  if (tipo === 'passos' && modo === 'novo') return t(`${NS}.TITULO_NOVA`);
  if (tipo === 'passos') {
    return t(`${NS}.TITULO_ALTERAR`, { ferramenta: nomeDaFerramenta });
  }
  if (tipo === 'teste') {
    return t(`${NS}.TITULO_TESTAR`, { ferramenta: nomeDaFerramenta });
  }
  return nomeDaFerramenta;
});

const temRodape = computed(() => {
  if (semPermissao.value) return false;
  if (vista.value.tipo !== 'lista') return true;
  return (
    !carregandoLista.value &&
    !erroNaLista.value &&
    (ferramentasManuais.value.length > 0 || prontas.value.length > 0)
  );
});

// Sair com algo digitado no assistente pede confirmação ("Sair sem salvar?").
const liberado = acao => {
  if (vista.value.tipo !== 'passos' || !passos.value?.sujo) return true;
  saida.value = acao;
  dialogoSair.value?.abrir();
  return false;
};
const podeFechar = () => liberado('fechar');
const aoFechar = () => {
  if (liberado('fechar')) emit('fechar');
};
const sairDosPassos = () => {
  const { id, de } = vista.value;
  ir({ tipo: de === 'teste' ? 'teste' : 'detalhe', id });
};
const confirmarSaida = () => {
  const acao = saida.value;
  dialogoSair.value?.fechar();
  if (acao === 'fechar') emit('fechar');
  else if (acao === 'voltar') sairDosPassos();
  else ir({ tipo: 'lista' }, 'ferramentas-adicionar');
};

const anunciar = texto => {
  anuncio.value = '';
  nextTick(() => {
    anuncio.value = texto;
  });
};

const abrir = item => ir({ tipo: 'detalhe', id: item.id });
const criarAMinha = () => ir({ tipo: 'passos', modo: 'novo', passo: 1 });
const adicionar = () => {
  if (props.vitrine) emit('verVitrine');
  else criarAMinha();
};

// As prontas ligam e desligam na hora (não há teste a fazer: a fonte é da plataforma). Tirar pede confirmação com o
// nome da ferramenta.
// Um pedido por pronta de cada vez: o segundo clique, antes da resposta, mandaria o mesmo valor de novo.
const prontasOcupadas = new Set();
const alternarPronta = async (item, ligar) => {
  if (prontasOcupadas.has(item.id)) return;
  prontasOcupadas.add(item.id);
  try {
    await estadoDaVitrine.mudarLigada(item.id, ligar);
  } catch (falha) {
    useAlert(t(`${NS_VITRINE}.MOTIVOS.${falha.motivo || 'GERAL'}`));
  } finally {
    prontasOcupadas.delete(item.id);
  }
};
const pedirTirar = async item => {
  prontaAlvo.value = item;
  // O título leva o nome: abre depois que ele chegou ao diálogo.
  await nextTick();
  dialogoTirar.value?.abrir();
};
const tirarPronta = async () => {
  const item = prontaAlvo.value;
  await estadoDaVitrine.tirar(item.id);
  useAlert(
    t(`${NS_VITRINE}.PRONTAS.TIRADA`, {
      ferramenta: item.nome,
      agente: nomeDoAgente.value,
    })
  );
};
const cancelarNovo = () => {
  if (liberado('lista')) ir({ tipo: 'lista' }, 'ferramentas-adicionar');
};

// Ligar sempre passa pelo teste; desligar pede confirmação.
const alternar = (item, ligar) => {
  if (ligar) {
    ir({ tipo: 'teste', id: item.id, precisaTestar: true });
    return;
  }
  alvo.value = item;
  dialogoDesligar.value?.abrir();
};

const desligar = async () => {
  const item = alvo.value;
  await api.mudarLigada(item.id, false);
  useAlert(t(`${NS}.DESLIGAR.PRONTO`, { ferramenta: item.name }));
};

const pedirExcluir = item => {
  alvo.value = item;
  dialogoExcluir.value?.abrir();
};

const excluir = async () => {
  const item = alvo.value;
  await api.excluir(item.id);
  useAlert(t(`${NS}.EXCLUIR.PRONTO`, { ferramenta: item.name }));
};
// Depois que o diálogo fecha (o foco volta a quem abriu, que já não existe): a lista.
const aoExcluir = () => ir({ tipo: 'lista' }, 'ferramentas-adicionar');

const aoSalvar = ({ ferramenta: salva, desligou }) => {
  const { modo, de } = vista.value;
  if (modo === 'novo' || desligou) {
    ir({ tipo: 'teste', id: salva.id, precisaTestar: desligou });
  } else if (de === 'teste') {
    ir({ tipo: 'teste', id: salva.id });
  } else {
    ir({ tipo: 'detalhe', id: salva.id, salvo: true });
  }
};

// Voltar com mudança na edição pergunta, como o fechar.
const voltarDosPassos = () => {
  if (liberado('voltar')) sairDosPassos();
};

const alterar = (passo, de) =>
  ir({ tipo: 'passos', modo: 'edicao', passo, id: vista.value.id, de });

const ligar = id => api.mudarLigada(id, true);

const aoLigar = salva => {
  useAlert(t(`${NS}.TESTE.LIGADA_AVISO`, { nome: nomeDoAgente.value }));
  ir({ tipo: 'lista' }, `ferramenta-interruptor-${salva.id}`);
};

const agoraNao = () => {
  useAlert(t(`${NS}.TESTE.AGORA_NAO_AVISO`));
  ir({ tipo: 'lista' }, 'ferramentas-adicionar');
};

onMounted(carregar);
</script>

<template>
  <AgenteGaveta :titulo="titulo" :pode-fechar="podeFechar" @fechar="aoFechar">
    <div class="relative">
      <p role="status" class="sr-only">{{ anuncio }}</p>
    </div>
    <div
      :key="vista.chave"
      ref="conteudo"
      tabindex="-1"
      class="flex flex-col outline-none"
    >
      <div v-if="semPermissao" data-sem-permissao class="flex flex-col gap-4">
        <AgenteErro
          v-if="api.perdeuPermissao.value"
          :titulo="t(`${NS}.SEM_PERMISSAO.MUDOU`)"
          :garantia="t(`${NS}.SEM_PERMISSAO.MUDOU_GARANTIA`)"
        />
        <div
          class="flex flex-col items-center gap-3 px-4 py-8 text-center rounded-2xl bg-n-alpha-1"
        >
          <span
            aria-hidden="true"
            class="i-lucide-lock size-8 text-n-slate-11"
          />
          <p class="m-0 text-sm text-n-slate-12">
            {{ t(`${NS}.SEM_PERMISSAO.TEXTO`) }}
          </p>
          <AgenteBotao
            tamanho="lg"
            icone="i-lucide-arrow-left"
            @click="emit('fechar')"
          >
            {{ t(`${NS}.SEM_PERMISSAO.VOLTAR`) }}
          </AgenteBotao>
        </div>
      </div>
      <FerramentasLista
        v-else-if="vista.tipo === 'lista'"
        :nome="nomeDoAgente"
        :ferramentas="ferramentasManuais"
        :carregando="carregandoLista"
        :erro="erroNaLista"
        :rodape="rodape"
        :vitrine="vitrine"
        :prontas="prontas"
        :cadastro-manual="cadastroManual"
        @abrir="abrir"
        @alternar="alternar"
        @adicionar="adicionar"
        @criar="criarAMinha"
        @alternar-pronta="alternarPronta"
        @tirar-pronta="pedirTirar"
        @tentar="carregar"
      />
      <FerramentaPassos
        v-else-if="vista.tipo === 'passos'"
        ref="passos"
        :modo="vista.modo"
        :passo-inicial="vista.passo"
        :ferramenta="ferramenta"
        :rodape="rodape"
        :criar="api.criar"
        :alterar="api.alterar"
        @salva="aoSalvar"
        @voltar="voltarDosPassos"
        @cancelar="cancelarNovo"
        @anunciar="anunciar"
      />
      <FerramentaTeste
        v-else-if="vista.tipo === 'teste' && ferramenta"
        :ferramenta="ferramenta"
        :precisa-testar="Boolean(vista.precisaTestar)"
        :rodape="rodape"
        :testar="api.testar"
        :ligar="ligar"
        @ligada="aoLigar"
        @agora-nao="agoraNao"
        @corrigir="alterar($event, 'teste')"
        @voltar="ir({ tipo: 'detalhe', id: vista.id })"
      />
      <FerramentaDetalhe
        v-else-if="vista.tipo === 'detalhe' && ferramenta"
        :ferramenta="ferramenta"
        :nome="nomeDoAgente"
        :salvo="Boolean(vista.salvo)"
        :rodape="rodape"
        @alternar="alternar"
        @alterar="alterar($event, 'detalhe')"
        @testar="ir({ tipo: 'teste', id: vista.id })"
        @excluir="pedirExcluir"
      />
    </div>

    <template v-if="temRodape" #rodape>
      <div
        :id="rodape"
        class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end"
      />
    </template>

    <AgenteConfirmacao
      ref="dialogoSair"
      :titulo="t(`${NS}.PASSOS.SAIR.TITULO`)"
      :texto="t(`${NS}.PASSOS.SAIR.TEXTO`)"
      :confirmar="t(`${NS}.PASSOS.SAIR.SAIR`)"
      :cancelar="t(`${NS}.PASSOS.SAIR.CONTINUAR`)"
      @confirmar="confirmarSaida"
      @fechada="saida = null"
    />
    <DialogoAcao
      ref="dialogoDesligar"
      variante="aviso"
      :titulo="t(`${NS}.DESLIGAR.TITULO`, { ferramenta: alvo?.name || '' })"
      :texto="t(`${NS}.DESLIGAR.TEXTO`, { nome: nomeDoAgente })"
      :confirmar="t(`${NS}.DESLIGAR.CONFIRMAR`)"
      :rotulo-carregando="t(`${NS}.DESLIGAR.CARREGANDO`)"
      :erro-titulo="t(`${NS}.DESLIGAR.ERRO`)"
      :erro-garantia="t(`${NS}.DESLIGAR.ERRO_GARANTIA`)"
      :executar="desligar"
    />
    <DialogoAcao
      ref="dialogoTirar"
      variante="perigo"
      :titulo="
        t(`${NS_VITRINE}.PRONTAS.CONFIRMA_TITULO`, {
          ferramenta: prontaAlvo?.nome || '',
        })
      "
      :texto="
        t(`${NS_VITRINE}.PRONTAS.CONFIRMA_TEXTO`, { agente: nomeDoAgente })
      "
      :confirmar="t(`${NS_VITRINE}.PRONTAS.CONFIRMA_SIM`)"
      :cancelar="t(`${NS_VITRINE}.PRONTAS.CONFIRMA_NAO`)"
      :rotulo-carregando="t(`${NS_VITRINE}.PRONTAS.TIRANDO`)"
      :erro-titulo="t(`${NS_VITRINE}.PRONTAS.ERRO`)"
      :erro-garantia="t(`${NS_VITRINE}.PRONTAS.ERRO_GARANTIA`)"
      :executar="tirarPronta"
      @confirmado="ir({ tipo: 'lista' }, 'ferramentas-adicionar')"
    />
    <DialogoAcao
      ref="dialogoExcluir"
      variante="perigo"
      :titulo="t(`${NS}.EXCLUIR.TITULO`, { ferramenta: alvo?.name || '' })"
      :texto="t(`${NS}.EXCLUIR.TEXTO`)"
      :extra="alvo?.enabled ? t(`${NS}.EXCLUIR.DICA`) : ''"
      :confirmar="t(`${NS}.EXCLUIR.CONFIRMAR`)"
      :rotulo-carregando="t(`${NS}.EXCLUIR.CARREGANDO`)"
      :erro-titulo="t(`${NS}.EXCLUIR.ERRO`)"
      :erro-garantia="t(`${NS}.EXCLUIR.ERRO_GARANTIA`)"
      :executar="excluir"
      @confirmado="aoExcluir"
    />
  </AgenteGaveta>
</template>
