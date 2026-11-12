import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { modeloDeRamo } from '../constants/modelosDeRamo';
import { oferecida } from '../vitrine/catalogo';

// #2881 — o agente pronto por ramo de seguro na página "Criar agente" (AgenteCriarPage), fora dela para a página não
// crescer. O ramo entra por `?ramo=<chave>` (`pedido`, lido uma vez pela página) e vale de dois jeitos:
// - ANTES de a conversa existir, a tela fala primeiro: a pergunta do nome da corretora, o exemplo do campo e a
//   conversa de exemplo ao lado são os do cartão do ramo. A conversa só abre no servidor com a primeira resposta.
// - DEPOIS, quem manda é o servidor: o `modelo_pronto` da conversa (store autonomiaBuildThreads) diz se há modelo e
//   traz o nome do ramo, as listas, as ferramentas com a frase "Use quando" e as perguntas de teste. A query já não
//   tem o ramo (só `?agente=`), e conta sem direito ao modelo recebe nulo: a tela segue como a de qualquer agente.
// - RASCUNHO REABERTO (`?agente=`, sem conversa na tela): o mesmo `modelo_pronto` vem no próprio agente, e as
//   mudanças são gravadas por ele. Havendo conversa com modelo, vale a da conversa.
// As listas na tela são sempre as do servidor. Cada mudança (`mudar`) manda a lista inteira nova e a tela só muda com
// a resposta; se o servidor recusar, um aviso curto e a lista fica como ele a tem. Um pedido por lista de cada vez.
// `conversa`: o useConversaDeCriacao da página (quantas respostas a pessoa já deu e se a conversa fechou).
// `agente`: o rascunho da página (computed), ou null enquanto ele não existe.
const NS = 'AGENTS.JORNADA.RAMOS';
const JA_COMECOU = 'agente_ja_comecou';

export function useModeloDeRamo({ pedido, conversa, agente }) {
  const store = useStore();
  const { t } = useI18n();
  const thread = useMapGetter('autonomiaBuildThreads/getThread');
  const daConversa = useMapGetter('autonomiaBuildThreads/getModeloPronto');

  const threadId = computed(() => thread.value?.id || null);
  const modelo = computed(
    () => daConversa.value || agente.value?.modelo_pronto || null
  );
  const ativo = computed(
    () => Boolean(modelo.value) || (!threadId.value && Boolean(pedido))
  );
  const cartao = computed(() =>
    ativo.value ? modeloDeRamo(modelo.value?.chave || pedido) : null
  );
  const textoDoCartao = campo => t(`${NS}.ITENS.${cartao.value.i18n}.${campo}`);
  // O nome do ramo é o do servidor assim que ele chega; antes, o título do cartão.
  const ramo = computed(() => {
    if (modelo.value?.ramo) return modelo.value.ramo;
    return cartao.value ? textoDoCartao('TITULO') : '';
  });

  const falaDeAbertura = computed(() =>
    t('AGENTS.JORNADA.RAMOS.CRIAR.PERGUNTA_EMPRESA', { ramo: ramo.value })
  );
  // A segunda pergunta é a das seguradoras: a sugestão do ramo e "Decido depois" preenchem o campo.
  const ideias = computed(() => {
    if (!modelo.value || conversa.fechada.value) return [];
    if (conversa.respostas.value !== 1) return [];
    return [
      modelo.value.seguradoras_sugeridas,
      t('AGENTS.JORNADA.RAMOS.CRIAR.DECIDO_DEPOIS'),
    ].filter(Boolean);
  });
  const exemploDoCampo = computed(() => {
    if (conversa.respostas.value === 0) {
      return t('AGENTS.JORNADA.RAMOS.CRIAR.EXEMPLO_EMPRESA');
    }
    return conversa.respostas.value === 1
      ? t('AGENTS.JORNADA.RAMOS.CRIAR.EXEMPLO_SEGURADORAS')
      : '';
  });
  // A conversa de exemplo ao lado, enquanto a conversa com o Construtor não fecha: a do cartão do ramo.
  const exemplo = computed(() => {
    if (!cartao.value) return null;
    const hora = cartao.value.horario;
    return [
      { de: 'cliente', texto: textoDoCartao('CLIENTE'), hora },
      { de: 'agente', texto: textoDoCartao('AGENTE'), hora },
    ];
  });

  const lista = campo =>
    computed(() => (modelo.value?.[campo] || []).filter(Boolean));
  const soOferecidas = campo =>
    computed(() =>
      (modelo.value?.[campo] || []).filter(item => oferecida(item.fonte))
    );
  const perguntas = lista('perguntas');
  const documentos = lista('documentos');
  const perguntasDeTeste = lista('teste');
  const ferramentas = soOferecidas('ferramentas');
  const tambem = soOferecidas('tambem');
  const pagas = computed(() => (modelo.value?.premium || []).filter(oferecida));
  // A frase "Use quando" de cada ferramenta do ramo, para o "Começar" mandar junto ao incluir.
  const frases = computed(() =>
    Object.fromEntries(
      [...ferramentas.value, ...tambem.value].map(item => [
        item.fonte,
        item.usar_quando,
      ])
    )
  );

  const gravando = ref({});
  const marcar = (campo, valor) => {
    gravando.value = { ...gravando.value, [campo]: valor };
  };
  const avisoDoErro = erro =>
    erro?.response?.data?.motivo === JA_COMECOU
      ? t('AGENTS.JORNADA.RAMOS.CONFIRA.ERRO_JA_COMECOU')
      : t('AGENTS.JORNADA.RAMOS.CONFIRA.ERRO_AO_MUDAR');

  // Pela conversa quando o modelo é o dela; sem conversa (rascunho reaberto), pelo agente.
  const gravar = listas =>
    daConversa.value
      ? store.dispatch('autonomiaBuildThreads/mudarModeloPronto', {
          threadId: threadId.value,
          listas,
        })
      : store.dispatch('autonomiaAgents/mudarModeloPronto', {
          agentId: agente.value.id,
          listas,
        });

  // `campo`: perguntas, documentos ou ferramentas. `itens`: a lista inteira nova.
  const mudar = async (campo, itens) => {
    if (gravando.value[campo] || !modelo.value) return;
    marcar(campo, true);
    try {
      await gravar({ [campo]: itens });
    } catch (erro) {
      useAlert(avisoDoErro(erro));
    } finally {
      marcar(campo, false);
    }
  };

  return {
    ativo,
    modelo,
    ramo,
    falaDeAbertura,
    ideias,
    exemploDoCampo,
    exemplo,
    perguntas,
    documentos,
    perguntasDeTeste,
    ferramentas,
    tambem,
    pagas,
    frases,
    gravando,
    mudar,
  };
}
