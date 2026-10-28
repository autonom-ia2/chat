import { ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { useTextos } from '../guiada/useTextos';
import { explicar401ComQuemMonta } from '../salvarFuncao';

// O "Salvar" da gaveta de pessoas (#2308, especificação 5.D). Manda só custom_role_id (null para sem função): reenviar
// o nome lido da lista desfaria uma troca de nome feita em paralelo. Depois, recarrega as pessoas e confere nelas que
// cada uma ficou na função pedida; o 200 sozinho não prova (sem custom_roles na conta, o servidor ignora a função).
// Os nomes saem da lista no momento do pedido: quem some na recarga ainda tem nome na frase (rodada 7).
//
// Desfechos por pessoa (revisão do #2308, rodada 7; GavetaDaFuncao.spec.js cobre cada linha e as misturas):
// | desfecho                                   | frase                                   | pendente? |
// | 200 e a recarga mostra a função pedida     | SALVA, só quando nem todos gravaram     | não       |
// | 200 e a recarga mostra outra               | NAO_MUDOU                               | fica      |
// | 401 com a sessão vencida                   | nenhuma: o app vai para o login         | fica tudo |
// | 401 e a conferência da sessão cai (rede)   | ERRO_PARCIAL + TENTE                    | fica      |
// | 401 e quem monta perdeu Pessoas            | SEM_ACESSO (gaveta só leitura)          | nada fica |
// | 401 e a recarga mostra a pessoa travada    | TRAVADA.<trava>                         | não       |
// | 401 com Pessoas, sem trava (ou com código) | FORA_DO_ALCANCE (recarrega as funções)  | fica      |
// | 4xx e a função escolhida sumiu             | FUNCAO_SUMIU (recarrega as funções)     | não       |
// | 4xx com pessoa e função ainda lá           | NAO_MUDOU (recarrega as funções)        | fica      |
// | rede (sem status, ou 5xx)                  | ERRO_PARCIAL + TENTE                    | fica      |
// | a pessoa some na recarga (qualquer acima)  | SAIU_DA_CONTA                           | não       |
// Fecha com "salvas" só quando todos gravaram. Senão fica aberta, com "foi salva" antes do problema quando alguém
// gravou; sem nada pendente, o botão de baixo vira "Fechar" (GavetaDaFuncao) e o X fecha direto. `salvando` sempre
// volta a false, até quando algo lança no meio.
const NAO_AUTORIZADO = 401;
const ERRO_DO_PEDIDO = { de: 400, ate: 500 };

const tipoDaFalha = status => {
  if (status === NAO_AUTORIZADO) return 'recusado';
  if (status >= ERRO_DO_PEDIDO.de && status < ERRO_DO_PEDIDO.ate)
    return 'invalido';
  return 'caido';
};

export function useSalvarGaveta(mudancas, travaDe) {
  const store = useStore();
  const { t, lista } = useTextos();
  const agentes = useMapGetter('agents/getAgents');
  const funcoes = useMapGetter('customRole/getCustomRoles');
  const { canManagePeople } = usePeopleAccess();
  const salvando = ref(false);
  const erro = ref('');

  const agenteDe = id => agentes.value.find(item => item.id === id);
  const funcaoDe = id => agenteDe(id)?.custom_role_id ?? null;
  const existeFuncao = id => funcoes.value.some(funcao => funcao.id === id);

  const enviar = pedidos =>
    Promise.allSettled(
      pedidos.map(([id, destino]) =>
        store.dispatch('agents/update', { id, custom_role_id: destino })
      )
    );

  // Cada pedido com o que o servidor respondeu: gravado, recusado (401), invalido (outro 4xx) ou caido (o resto).
  const separar = (pedidos, resultados) => {
    const tipos = resultados.map(resultado =>
      resultado.status === 'fulfilled'
        ? 'gravado'
        : tipoDaFalha(resultado.reason?.status)
    );
    const de = tipo => pedidos.filter((_, i) => tipos[i] === tipo);
    const recusa = resultados.find((_, i) => tipos[i] === 'recusado');
    return {
      gravados: de('gravado'),
      recusados: de('recusado'),
      invalidos: de('invalido'),
      caidos: de('caido'),
      codigo: recusa?.reason?.code,
    };
  };

  // Sem código, o 401 pode ser de quem perdeu Pessoas: quem monta vem da própria conferência da sessão, e entra na
  // store pela mesma ação do validityCheck (avisa o widget e a análise também; rodada 6).
  const perdeuPessoas = async (motivo, quemMonta) => {
    if (motivo !== 'SEM_ACESSO') return false;
    if (quemMonta) await store.dispatch('setCurrentUser', quemMonta);
    return !canManagePeople.value;
  };

  const conferirSessao = async (recusados, codigo) => {
    if (!recusados.length) return { motivo: '', semAcesso: false };
    const { erro: motivo, quemMonta } = await explicar401ComQuemMonta(codigo);
    if (motivo === null) return { vencida: true };
    return { motivo, semAcesso: await perdeuPessoas(motivo, quemMonta) };
  };

  const recarregar = precisaDasFuncoes =>
    Promise.all([
      store.dispatch('agents/get'),
      ...(precisaDasFuncoes
        ? [store.dispatch('customRole/getCustomRole')]
        : []),
    ]);

  // Depois da recarga: em que grupo cada pedido fica. Quem saiu da conta vem antes de qualquer outro motivo; quem
  // ficou travado leva a trava junto ([pedido, trava]), para uma frase por trava.
  const classificar = (separados, { motivo, semAcesso }) => {
    const { gravados, recusados, invalidos, caidos } = separados;
    const naConta = ([id]) => Boolean(agenteDe(id));
    const ficam = grupo => grupo.filter(naConta);
    const sairam = [...gravados, ...recusados, ...invalidos, ...caidos].filter(
      pedido => !naConta(pedido)
    );
    const ficaram = ficam(gravados);
    const salvos = ficaram.filter(([id, destino]) => funcaoDe(id) === destino);
    const vazio = { travados: [], funcaoSumiu: [], foraDoAlcance: [] };
    if (semAcesso)
      return { ...vazio, salvos, sairam, caidos: [], semEfeito: [], semAcesso };
    const rede = motivo === 'REDE';
    const recusadosAqui = ficam(recusados);
    const travados = rede
      ? []
      : recusadosAqui
          .map(pedido => [pedido, travaDe(agenteDe(pedido[0]))])
          .filter(([, trava]) => trava);
    const travou = pedido => travados.some(([travado]) => travado === pedido);
    const invalidosAqui = ficam(invalidos);
    const funcaoSumiu = invalidosAqui.filter(
      ([, destino]) => destino !== null && !existeFuncao(destino)
    );
    return {
      salvos,
      sairam,
      travados,
      funcaoSumiu,
      foraDoAlcance: rede ? [] : recusadosAqui.filter(p => !travou(p)),
      caidos: [...ficam(caidos), ...(rede ? recusadosAqui : [])],
      semEfeito: [
        ...ficaram.filter(pedido => !salvos.includes(pedido)),
        ...invalidosAqui.filter(pedido => !funcaoSumiu.includes(pedido)),
      ],
      semAcesso: false,
    };
  };

  // Uma frase por grupo, com os nomes guardados no pedido; os travados, uma por trava. "Foi salva" só quando nem
  // todos gravaram (com todos, a gaveta fecha dizendo "salvas").
  const frasesDe = (grupos, nomeNoPedido, todosSalvos) => {
    const frase = (chave, grupo, extra = {}) =>
      grupo.length
        ? t(
            `FUNCOES_EQUIPE.GAVETA.${chave}`,
            {
              nomes: lista(grupo.map(([id]) => nomeNoPedido.get(id))),
              ...extra,
            },
            grupo.length
          )
        : '';
    const travas = [...new Set(grupos.travados.map(([, trava]) => trava))];
    const naTrava = trava =>
      grupos.travados
        .filter(([, dela]) => dela === trava)
        .map(([pedido]) => pedido);
    return [
      !todosSalvos && frase('SALVA', grupos.salvos),
      grupos.semAcesso && t('FUNCOES_EQUIPE.GAVETA.SEM_ACESSO'),
      ...travas.map(trava => frase(`TRAVADA.${trava}`, naTrava(trava))),
      frase('SAIU_DA_CONTA', grupos.sairam),
      frase('FUNCAO_SUMIU', grupos.funcaoSumiu),
      frase('FORA_DO_ALCANCE', grupos.foraDoAlcance),
      frase('ERRO_PARCIAL', grupos.caidos, {
        motivo: t('FUNCOES_EQUIPE.GAVETA.TENTE'),
      }),
      frase('NAO_MUDOU', grupos.semEfeito),
    ]
      .filter(Boolean)
      .join(' ');
  };

  // Devolve true só quando tudo o que estava pendente gravou; false deixa a gaveta aberta (com a frase, ou indo para
  // o login).
  const salvar = async () => {
    if (salvando.value) return false;
    salvando.value = true;
    erro.value = '';
    try {
      const pedidos = [...mudancas.value];
      const nomeNoPedido = new Map(
        pedidos.map(([id]) => [id, agenteDe(id)?.name ?? ''])
      );
      const separados = separar(pedidos, await enviar(pedidos));
      const sessao = await conferirSessao(
        separados.recusados,
        separados.codigo
      );
      if (sessao.vencida) return false;
      await recarregar(
        separados.recusados.length > 0 || separados.invalidos.length > 0
      );
      const grupos = classificar(separados, sessao);
      const todosSalvos = grupos.salvos.length === pedidos.length;
      mudancas.value = new Map([
        ...grupos.foraDoAlcance,
        ...grupos.caidos,
        ...grupos.semEfeito,
      ]);
      erro.value = frasesDe(grupos, nomeNoPedido, todosSalvos);
      return todosSalvos;
    } finally {
      salvando.value = false;
    }
  };

  return { salvando, erro, salvar };
}
