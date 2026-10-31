// #2414 F0 — o "servidor" do protótipo: guarda o estado na memória da aba,
// com a mesma forma que o endpoint vai ter (automação + versão ativa +
// execuções + registros). Recarregar a página volta ao começo.
import { computed, ref } from 'vue';
import {
  AUTOMACOES_INICIAIS,
  CARTOES,
  EXECUCOES_INICIAIS,
  REGISTROS_INICIAIS,
  VERSOES_INICIAIS,
} from './dados';
import { copiar } from './receita';

const estadoInicial = () => ({
  automacoes: copiar(AUTOMACOES_INICIAIS),
  versoes: copiar(VERSOES_INICIAIS),
  execucoes: copiar(EXECUCOES_INICIAIS),
  registros: copiar(REGISTROS_INICIAIS),
  proximoId: 100,
});

const estado = ref(estadoInicial());

const GATILHOS_DO_FUNIL = [
  'cartao_entrou',
  'cartao_parado',
  'campo_data',
  'cartao_criado_formulario',
];

const versaoAtivaDe = (versoes, automacaoId) =>
  versoes
    .filter(versao => versao.automacaoId === automacaoId)
    .reduce(
      (maior, versao) =>
        !maior || versao.numero > maior.numero ? versao : maior,
      null
    );

const trocarAutomacao = (id, mudanca) => {
  estado.value = {
    ...estado.value,
    automacoes: estado.value.automacoes.map(item =>
      item.id === id ? { ...item, ...mudanca } : item
    ),
  };
};

export function useAutomacoesLivre() {
  const automacoes = computed(() =>
    estado.value.automacoes.map(automacao => ({
      ...automacao,
      versao: versaoAtivaDe(estado.value.versoes, automacao.id),
    }))
  );

  const buscar = id =>
    automacoes.value.find(automacao => automacao.id === Number(id)) || null;

  const alternar = (id, ativa) => trocarAutomacao(id, { ativa });

  // Salvar sempre cria a próxima versão. `quemEstaNoMeio`: 'terminam' (seguem
  // na versão antiga, o padrão) ou 'param' (as execuções são encerradas).
  const salvarVersao = (id, receita, { quemEstaNoMeio = 'terminam' } = {}) => {
    const atual = versaoAtivaDe(estado.value.versoes, id);
    const nova = {
      id: estado.value.proximoId,
      automacaoId: id,
      numero: (atual?.numero || 0) + 1,
      autor: 'Você',
      receita: copiar(receita),
    };
    estado.value = {
      ...estado.value,
      proximoId: estado.value.proximoId + 1,
      versoes: [...estado.value.versoes, nova],
      execucoes:
        quemEstaNoMeio === 'param'
          ? estado.value.execucoes.filter(exec => exec.automacaoId !== id)
          : estado.value.execucoes,
    };
    if (quemEstaNoMeio === 'param') trocarAutomacao(id, { noMeio: 0 });
    return nova;
  };

  const criar = ({ nome, receita, ativa = false, extra = {} }) => {
    const id = estado.value.proximoId;
    const automacao = {
      id,
      nome,
      ativa,
      origem: GATILHOS_DO_FUNIL.includes(receita.gatilho?.tipo)
        ? 'funil'
        : 'conversa',
      jeitoAntigo: false,
      criadaPor: 'manual',
      pacote: null,
      ligadaPor: ativa ? 'Você' : null,
      estatisticas: { semana: 0, pararam: 0 },
      noMeio: 0,
      ...extra,
    };
    estado.value = {
      ...estado.value,
      proximoId: id + 1,
      automacoes: [automacao, ...estado.value.automacoes],
    };
    salvarVersao(id, receita);
    return id;
  };

  // "Trazer para o novo": cria a automação nova com a mesma receita, desligada,
  // e desliga a antiga (nunca apaga; ADR D12).
  const trazerParaONovo = id => {
    const antiga = buscar(id);
    if (!antiga) return null;
    trocarAutomacao(id, { ativa: false });
    return criar({
      nome: antiga.nome,
      receita: antiga.versao.receita,
      extra: { origem: antiga.origem, trazidaDe: id, exemplo: id },
    });
  };

  const execucoesDoCartao = cartaoId =>
    estado.value.execucoes
      .filter(exec => exec.cartaoId === Number(cartaoId))
      .map(exec => ({ ...exec, automacao: buscar(exec.automacaoId) }));

  const registrosDe = ({ automacaoId, cartaoId } = {}) =>
    estado.value.registros.filter(
      registro =>
        (automacaoId === undefined || registro.automacaoId === automacaoId) &&
        (cartaoId === undefined || registro.cartaoId === Number(cartaoId))
    );

  const pararParaCartao = execucaoId => {
    const execucao = estado.value.execucoes.find(
      exec => exec.id === execucaoId
    );
    if (!execucao) return;
    const registro = {
      id: estado.value.proximoId,
      automacaoId: execucao.automacaoId,
      cartaoId: execucao.cartaoId,
      alvo: CARTOES.find(cartao => cartao.id === execucao.cartaoId)?.nome || '',
      em: new Date().toISOString(),
      resultado: 'parou',
      chave: 'PAROU_POR_PESSOA',
      params: { pessoa: 'Você' },
    };
    estado.value = {
      ...estado.value,
      proximoId: estado.value.proximoId + 1,
      execucoes: estado.value.execucoes.filter(exec => exec.id !== execucaoId),
      registros: [registro, ...estado.value.registros],
    };
  };

  const reiniciar = () => {
    estado.value = estadoInicial();
  };

  return {
    automacoes,
    buscar,
    alternar,
    salvarVersao,
    criar,
    trazerParaONovo,
    execucoesDoCartao,
    registrosDe,
    pararParaCartao,
    reiniciar,
  };
}
