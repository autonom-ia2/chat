import { ref } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { useTextos } from '../guiada/useTextos';
import { useSemFuncao } from '../useSemFuncao';
import { explicar401ComQuemMonta } from '../salvarFuncao';

// O "Salvar" da gaveta de pessoas (#2308, especificação 5.D). Manda só custom_role_id (null para sem função): reenviar
// o nome lido da lista desfaria uma troca de nome feita em paralelo. Depois, recarrega as pessoas e confere nelas que
// cada uma ficou na função pedida; o 200 sozinho não prova (sem custom_roles na conta, o servidor ignora a função).
// Os nomes saem da lista no momento do pedido: quem some na recarga ainda tem nome na frase (rodada 7).
//
// Desfechos por pessoa (revisão do #2308, rodadas 7 a 9; GavetaDaFuncao.spec.js cobre cada linha e as misturas):
// | desfecho                                           | frase                                     | pendente? |
// | 200 e a recarga mostra a função pedida             | SALVA, só quando nem todos gravaram       | não       |
// | 200 e a recarga mostra outra                       | NAO_MUDOU                                 | fica      |
// | 401 com a sessão vencida                           | nenhuma: o app vai para o login           | fica tudo |
// | 401 e a conferência da sessão cai (rede)           | ERRO_PARCIAL + TENTE                      | fica      |
// | 401 e quem monta perdeu Pessoas                    | SEM_ACESSO + CONTINUA (só leitura)        | nada fica |
// | a função da gaveta foi apagada (na recarga)        | CONTINUA (só leitura, SO_LEITURA_APAGADA) | nada fica |
// | a função da gaveta saiu do alcance (na recarga)    | CONTINUA (só leitura, SO_LEITURA_ABOVE)   | nada fica |
// | a recarga mostra a pessoa travada (qualquer acima) | TRAVADA.<trava>                           | não       |
// | a pessoa já estava travada antes do pedido         | TRAVADA.<trava>, sem mandar o pedido      | não       |
// | a pessoa saiu da lista visível (já tem função)     | SAIU_DA_LISTA                             | não       |
// | 401 com Pessoas, sem trava (ou com código)         | FORA_DO_ALCANCE (recarrega as funções)    | fica      |
// | 401 e o destino escolhido saiu do alcance          | FORA_DO_ALCANCE (recarrega as funções)    | não       |
// | destino (ou "Sem função") já fora do alcance antes | FORA_DO_ALCANCE, sem mandar o pedido      | não       |
// | 4xx e a função escolhida sumiu                     | FUNCAO_SUMIU (recarrega as funções)       | não       |
// | 4xx com pessoa e função ainda lá                   | NAO_MUDOU (recarrega as funções)          | fica      |
// | 429 (muitos pedidos seguidos)                      | ERRO_PARCIAL + ESPERE                     | fica      |
// | rede (sem status, ou 5xx)                          | ERRO_PARCIAL + TENTE                      | fica      |
// | erro inesperado (algo lança no meio do salvar)     | NAO_CONFIRMOU, uma frase só               | fica tudo |
// | a pessoa some na recarga (qualquer acima)          | SAIU_DA_CONTA                             | não       |
// Travada e fora da lista valem depois de qualquer resposta (até 200 sem gravar, 429 ou rede): mandar de novo
// não mudaria nada, e a linha dela já não tem Desfazer (rodada 9). "Lista visível" é a da gaveta: a de quem está
// sem função perde quem ganhou função em paralelo; a de uma função mostra todo mundo.
// "Só leitura" é a gaveta inteira: sem Pessoas, ou a função dela, lida da lista pelo id, sumiu ou saiu do alcance
// (`somenteLeitura`). Aí quem não gravou ouve CONTINUA e nada fica pendente (rodada 8). FUNCAO_SUMIU ("Escolha outra")
// só sai para um destino escolhido na linha: o "Pôr como" da gaveta leva à função dela, e ela sumida é só leitura.
// Fecha com "salvas" só quando todos gravaram. Senão fica aberta, com "foi salva" numa linha neutra (`aviso.salva`) e
// cada problema no seu parágrafo vermelho (`aviso.problemas`); sem nada pendente, o botão de baixo vira "Fechar"
// (GavetaDaFuncao) e o X fecha direto. `salvando` sempre volta a false, até quando algo lança no meio.
const NAO_AUTORIZADO = 401;
const MUITOS_PEDIDOS = 429;
const ERRO_DO_PEDIDO = { de: 400, ate: 500 };
const SEM_AVISO = Object.freeze({ salva: '', problemas: [] });

const tipoDaFalha = status => {
  if (status === NAO_AUTORIZADO) return 'recusado';
  if (status === MUITOS_PEDIDOS) return 'limitado';
  if (status >= ERRO_DO_PEDIDO.de && status < ERRO_DO_PEDIDO.ate)
    return 'invalido';
  return 'caido';
};

export function useSalvarGaveta(
  mudancas,
  { travaDe, naLista, somenteLeitura }
) {
  const store = useStore();
  const { t, lista } = useTextos();
  const agentes = useMapGetter('agents/getAgents');
  const funcoes = useMapGetter('customRole/getCustomRoles');
  const { canManagePeople, reachesRole } = usePeopleAccess();
  const { semFuncaoTravado } = useSemFuncao();
  const salvando = ref(false);
  const aviso = ref(SEM_AVISO);

  const agenteDe = id => agentes.value.find(item => item.id === id);
  const funcaoDe = id => agenteDe(id)?.custom_role_id ?? null;
  const acharFuncao = id => funcoes.value.find(funcao => funcao.id === id);
  // Sem função segue a régua de dar uma função (#2317): só com as chaves do "Sem função" ao alcance. Uma função fora
  // da lista, o servidor decide.
  const alcanca = ([, destino]) => {
    if (destino === null) return !semFuncaoTravado.value;
    const funcao = acharFuncao(destino);
    return !funcao || reachesRole(funcao);
  };

  const enviar = pedidos =>
    Promise.allSettled(
      pedidos.map(([id, destino]) =>
        store.dispatch('agents/update', { id, custom_role_id: destino })
      )
    );

  // A trava da pessoa como a lista a mostra agora; quem não está mais na conta não tem trava (sai como SAIU_DA_CONTA).
  const travaAgora = id => {
    const agente = agenteDe(id);
    return agente ? travaDe(agente) : '';
  };

  // Cada pedido com o que o servidor respondeu: gravado, recusado (401), limitado (429), invalido (outro 4xx) ou
  // caido (o resto). Os barrados nem foram: o destino já estava fora do alcance; os travados antes, também não.
  const separar = (pedidos, { barrados, travadosAntes }, resultados) => {
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
      limitados: de('limitado'),
      invalidos: de('invalido'),
      caidos: de('caido'),
      barrados,
      travadosAntes,
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

  const GRUPOS_VAZIOS = {
    travados: [],
    foraDaLista: [],
    funcaoSumiu: [],
    foraDoAlcance: [],
    caidos: [],
    limitados: [],
    semEfeito: [],
    continuam: [],
    semAcesso: false,
  };

  // Os pedidos que a recarga mostra travados, com a trava junto ([pedido, trava]), para uma frase por trava.
  const travadosEm = grupo =>
    grupo
      .map(pedido => [pedido, travaAgora(pedido[0])])
      .filter(([, trava]) => trava);

  // Depois da recarga: em que grupo cada pedido fica. Quem saiu da conta vem antes de qualquer outro motivo; depois,
  // quem ficou travado e quem saiu da lista da gaveta, seja qual for a resposta. Com a gaveta só leitura, quem não
  // gravou só "continua como era".
  const classificar = (pedidos, separados, { motivo, semAcesso }) => {
    const naConta = ([id]) => Boolean(agenteDe(id));
    const sairam = pedidos.filter(pedido => !naConta(pedido));
    const salvos = separados.gravados.filter(
      ([id, destino]) => naConta([id]) && funcaoDe(id) === destino
    );
    const restantes = pedidos.filter(p => naConta(p) && !salvos.includes(p));
    if (semAcesso || somenteLeitura.value)
      return {
        ...GRUPOS_VAZIOS,
        salvos,
        sairam,
        continuam: restantes,
        semAcesso,
      };
    const travados = travadosEm(restantes);
    const travou = pedido => travados.some(([travado]) => travado === pedido);
    const foraDaLista = restantes.filter(
      pedido => !travou(pedido) && !naLista(agenteDe(pedido[0]))
    );
    const livres = grupo =>
      grupo.filter(
        p => restantes.includes(p) && !travou(p) && !foraDaLista.includes(p)
      );
    const rede = motivo === 'REDE';
    const recusadosAqui = livres(separados.recusados);
    const invalidosAqui = livres(separados.invalidos);
    const funcaoSumiu = invalidosAqui.filter(
      ([, destino]) => destino !== null && !acharFuncao(destino)
    );
    return {
      ...GRUPOS_VAZIOS,
      salvos,
      sairam,
      travados,
      foraDaLista,
      funcaoSumiu,
      foraDoAlcance: [
        ...(rede ? [] : recusadosAqui),
        ...livres(separados.barrados),
      ],
      caidos: [...livres(separados.caidos), ...(rede ? recusadosAqui : [])],
      limitados: livres(separados.limitados),
      semEfeito: [
        ...livres(separados.gravados),
        ...invalidosAqui.filter(pedido => !funcaoSumiu.includes(pedido)),
        ...livres(separados.travadosAntes),
      ],
    };
  };

  // O que continua pendente: fora do alcance só enquanto o destino ainda está ao alcance (senão, "Salvar" mandaria de
  // novo o que o servidor recusa).
  const pendentesDe = grupos => [
    ...grupos.foraDoAlcance.filter(alcanca),
    ...grupos.caidos,
    ...grupos.limitados,
    ...grupos.semEfeito,
  ];

  const fraseDe = (chave, grupo, nomeNoPedido, extra = {}) =>
    grupo.length
      ? t(
          `FUNCOES_EQUIPE.GAVETA.${chave}`,
          { nomes: lista(grupo.map(([id]) => nomeNoPedido.get(id))), ...extra },
          grupo.length
        )
      : '';

  // "Foi salva" à parte (linha neutra), só quando nem todos gravaram (com todos, a gaveta fecha dizendo "salvas").
  // Os problemas, um por parágrafo; os travados, um por trava.
  const avisoDe = (grupos, nomeNoPedido, todosSalvos) => {
    const frase = (chave, grupo, extra) =>
      fraseDe(chave, grupo, nomeNoPedido, extra);
    const travas = [...new Set(grupos.travados.map(([, trava]) => trava))];
    const naTrava = trava =>
      grupos.travados
        .filter(([, dela]) => dela === trava)
        .map(([pedido]) => pedido);
    const tente = { motivo: t('FUNCOES_EQUIPE.GAVETA.TENTE') };
    const espere = { motivo: t('FUNCOES_EQUIPE.GAVETA.ESPERE') };
    const problemas = [
      grupos.semAcesso && t('FUNCOES_EQUIPE.GAVETA.SEM_ACESSO'),
      ...travas.map(trava => frase(`TRAVADA.${trava}`, naTrava(trava))),
      frase('SAIU_DA_CONTA', grupos.sairam),
      frase('SAIU_DA_LISTA', grupos.foraDaLista),
      frase('FUNCAO_SUMIU', grupos.funcaoSumiu),
      frase('FORA_DO_ALCANCE', grupos.foraDoAlcance),
      frase('ERRO_PARCIAL', grupos.caidos, tente),
      frase('ERRO_PARCIAL', grupos.limitados, espere),
      frase('NAO_MUDOU', grupos.semEfeito),
      frase('CONTINUA', grupos.continuam),
    ].filter(Boolean);
    return {
      salva: todosSalvos ? '' : frase('SALVA', grupos.salvos),
      problemas,
    };
  };

  // Os pedidos e os nomes de agora, sem mandar o que o servidor recusaria: a pessoa que uma recarga já travou e o
  // destino que já não se alcança.
  const montarPedidos = () => {
    const pedidos = [...mudancas.value];
    const nomeNoPedido = new Map(
      pedidos.map(([id]) => [id, agenteDe(id)?.name ?? ''])
    );
    const travadosAntes = pedidos.filter(([id]) => travaAgora(id));
    return {
      pedidos,
      nomeNoPedido,
      travadosAntes,
      barrados: pedidos.filter(p => !travadosAntes.includes(p) && !alcanca(p)),
    };
  };

  // Devolve true só quando tudo o que estava pendente gravou; false deixa a gaveta aberta (com a frase, ou indo para
  // o login). Se algo lança no meio, tudo segue pendente e a gaveta diz que não deu para confirmar o que gravou (o
  // servidor pode ter gravado; quase sempre é defeito, não rede), e o erro sobe para o Vue registrar.
  const salvar = async () => {
    if (salvando.value) return false;
    salvando.value = true;
    aviso.value = SEM_AVISO;
    const { pedidos, nomeNoPedido, ...foraDoEnvio } = montarPedidos();
    try {
      const { barrados, travadosAntes } = foraDoEnvio;
      const enviados = pedidos.filter(
        p => !barrados.includes(p) && !travadosAntes.includes(p)
      );
      const separados = separar(enviados, foraDoEnvio, await enviar(enviados));
      const { recusados, invalidos, codigo } = separados;
      const sessao = await conferirSessao(recusados, codigo);
      if (sessao.vencida) return false;
      await recarregar(
        [recusados, invalidos, barrados, travadosAntes].some(
          grupo => grupo.length
        )
      );
      const grupos = classificar(pedidos, separados, sessao);
      const todosSalvos = grupos.salvos.length === pedidos.length;
      mudancas.value = new Map(pendentesDe(grupos));
      aviso.value = avisoDe(grupos, nomeNoPedido, todosSalvos);
      return todosSalvos;
    } catch (falha) {
      aviso.value = {
        salva: '',
        problemas: [t('FUNCOES_EQUIPE.GAVETA.NAO_CONFIRMOU')],
      };
      throw falha;
    } finally {
      salvando.value = false;
    }
  };

  const limparAviso = () => {
    aviso.value = SEM_AVISO;
  };

  return { salvando, aviso, salvar, limparAviso };
}
