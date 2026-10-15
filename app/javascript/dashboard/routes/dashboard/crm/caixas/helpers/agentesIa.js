import { juntar, paraFormulario, paraSalvar } from './caixa';

// #1447 — os agentes de IA da caixa, sem Vue. A porta atende primeiro todas as
// conversas; cada agente de área cuida de alguns funis. Um funil tem um agente
// de área só por caixa: marcar num agente tira do outro.
//
// A parte dos agentes só aparece com a Fase 2 dos Agentes ligada na conta
// (`autonomia_agents_fase2` do payload da conta, a mesma fonte da tela dos
// Agentes, #1570). Com ela, o servidor manda `caixa.ai_agents`:
// { porta, pode_mudar, areas: [{ id, name, pipeline_ids, parado,
// ultima_caixa }], disponiveis: [{ id, name, parado }] }. No formulário, áreas
// e disponíveis viram uma lista só (`agentes`): `na_caixa` diz quem já é área
// aqui e `sai` marca quem vai ser tirado ao salvar.

export const temAgentesIa = (caixa, fase2) =>
  fase2 === true && Boolean(caixa.ai_agents);

export const portaDa = caixa => caixa.ai_agents?.porta || null;

// Na lista e no cartão (dado do servidor): só as áreas.
export const areasDa = caixa => caixa.ai_agents?.areas || [];

export const agentesParaFormulario = aiAgents =>
  aiAgents
    ? {
        porta: aiAgents.porta,
        pode_mudar: aiAgents.pode_mudar,
        // #1648 — agente de outro sistema que atende primeiro ({ id, name } ou null); a
        // tela só mostra com a aba "Agente de IA" por caixa ligada na conta.
        externo: aiAgents.externo || null,
        agentes: [
          ...aiAgents.areas.map(agente => ({
            ...agente,
            pipeline_ids: [...agente.pipeline_ids],
            na_caixa: true,
            sai: false,
          })),
          ...aiAgents.disponiveis.map(agente => ({
            ...agente,
            pipeline_ids: [],
            ultima_caixa: false,
            na_caixa: false,
            sai: false,
          })),
        ],
      }
    : null;

// Os funis do agente que ainda estão marcados na caixa (etapa 1).
export const funisNaCaixa = (agente, pipelineIds) =>
  agente.pipeline_ids.filter(id => pipelineIds.includes(id));

// No formulário: quem entra (agente de fora com algum funil da caixa) e quem
// fica (área que não foi tirada, ou quem entra).
export const entraNaCaixa = (agente, pipelineIds) =>
  !agente.na_caixa && funisNaCaixa(agente, pipelineIds).length > 0;

export const ficaNaCaixa = (agente, pipelineIds) =>
  agente.na_caixa ? !agente.sai : entraNaCaixa(agente, pipelineIds);

export const agentesDoFormulario = form => form.ai_agents?.agentes || [];

// A parte dos agentes aparece na etapa 2: com a Fase 2 e alguém para mostrar.
export const temAgentesNaTela = aiAgents =>
  Boolean(aiAgents) && (Boolean(aiAgents.porta) || aiAgents.agentes.length > 0);

export const funisDoAgente = (agente, funis) =>
  funis.filter(funil => agente.pipeline_ids.includes(funil.id));

export const donoDoFunil = (agentes, funilId) =>
  agentes.find(agente => agente.pipeline_ids.includes(funilId)) || null;

const comFunis = (agente, pipelineIds) => ({
  ...agente,
  pipeline_ids: pipelineIds,
});

// Liga ou desliga o funil no agente. Ao ligar, quem tinha o funil perde e
// volta em `tirouDe`, para a tela avisar e oferecer desfazer.
export const alternarFunilDoAgente = (agentes, agenteId, funilId) => {
  const agente = agentes.find(item => item.id === agenteId);
  if (agente.pipeline_ids.includes(funilId)) {
    return {
      agentes: agentes.map(item =>
        item.id === agenteId
          ? comFunis(
              item,
              item.pipeline_ids.filter(id => id !== funilId)
            )
          : item
      ),
      tirouDe: null,
    };
  }
  const anterior = donoDoFunil(agentes, funilId);
  return {
    agentes: agentes.map(item => {
      if (item.id === agenteId) {
        return comFunis(item, [...item.pipeline_ids, funilId]);
      }
      if (anterior && item.id === anterior.id) {
        return comFunis(
          item,
          item.pipeline_ids.filter(id => id !== funilId)
        );
      }
      return item;
    }),
    tirouDe: anterior,
  };
};

// Tirar da caixa solta os funis do agente (voltam para a porta) e guarda os
// que ele tinha; desfazer devolve os que nenhum outro agente pegou.
export const tirarDaCaixa = (agentes, agenteId) =>
  agentes.map(item =>
    item.id === agenteId
      ? { ...item, sai: true, funis_antes: item.pipeline_ids, pipeline_ids: [] }
      : item
  );

export const voltarParaCaixa = (agentes, agenteId) =>
  agentes.map(item => {
    if (item.id !== agenteId) return item;
    const livres = (item.funis_antes || []).filter(
      id => !donoDoFunil(agentes, id)
    );
    return { ...item, sai: false, pipeline_ids: livres };
  });

// Os funis da caixa que nenhum agente de área pegou: neles, a porta continua.
export const funisSemAgente = (agentes, funis) =>
  funis.filter(funil => !donoDoFunil(agentes, funil.id));

export const nomesDosFunis = (funis, locale) =>
  juntar(
    funis.map(funil => funil.name),
    locale
  );

const quemFica = form =>
  agentesDoFormulario(form)
    .filter(agente => ficaNaCaixa(agente, form.pipeline_ids))
    .map(agente => ({
      id: agente.id,
      pipeline_ids: funisNaCaixa(agente, form.pipeline_ids),
    }));

// O que vai no PUT: a lista inteira dos agentes de área que ficam na caixa,
// só quando ela mudou em relação ao que está salvo. Sem `ai_agents` (Fase 2
// desligada) ou sem permissão, nada vai.
export const agentesParaSalvar = (form, original) => {
  if (!form.ai_agents?.pode_mudar) return {};
  const lista = quemFica(form);
  const igual =
    original &&
    JSON.stringify(lista) ===
      JSON.stringify(
        quemFica({ ...original, pipeline_ids: form.pipeline_ids })
      );
  return igual ? {} : { ai_agents: lista };
};

const mudancasDeUmAgente = (anterior, agente, marcados, frase) => {
  const ids = marcados.map(funil => funil.id);
  if (agente.na_caixa && agente.sai) {
    return [
      {
        chave: agente.ultima_caixa ? 'AGENTE_PARA' : 'AGENTE_SAI',
        valores: { nome: agente.name },
      },
    ];
  }
  const lista = [];
  if (entraNaCaixa(agente, ids)) {
    lista.push({
      chave: agente.parado ? 'AGENTE_ENTRA_E_LIGA' : 'AGENTE_ENTRA',
      valores: { nome: agente.name },
    });
  }
  const agora = funisDoAgente(agente, marcados);
  const eram = anterior ? funisDoAgente(anterior, marcados) : [];
  const ganhou = agora.filter(
    funil => !eram.some(item => item.id === funil.id)
  );
  const perdeu = eram.filter(
    funil => !agora.some(item => item.id === funil.id)
  );
  if (ganhou.length) {
    lista.push({
      chave: 'PESSOA_GANHA',
      valores: { nome: agente.name, assuntos: frase(ganhou) },
    });
  }
  if (perdeu.length) {
    lista.push({
      chave: 'PESSOA_PERDE',
      valores: { nome: agente.name, assuntos: frase(perdeu) },
    });
  }
  return lista;
};

// Frases do "O que muda ao salvar", no mesmo formato de `mudancas`.
export const mudancasDosAgentes = (antes, depois, funis, locale) => {
  const frase = lista =>
    juntar(
      lista.map(funil => funil.name),
      locale
    );
  const marcados = funis.filter(funil =>
    depois.pipeline_ids.includes(funil.id)
  );
  return agentesDoFormulario(depois).flatMap(agente =>
    mudancasDeUmAgente(
      agentesDoFormulario(antes).find(item => item.id === agente.id),
      agente,
      marcados,
      frase
    )
  );
};

// O formulário e o PUT da caixa com os agentes de IA (#1447).
export const formularioDaCaixa = (caixa, fase2) => ({
  ...paraFormulario(caixa),
  ai_agents: temAgentesIa(caixa, fase2)
    ? agentesParaFormulario(caixa.ai_agents)
    : null,
});

export const salvarDaCaixa = (form, original) => ({
  ...paraSalvar(form),
  ...agentesParaSalvar(form, original),
});

// #1447/#1433 — recusas do servidor ao gravar os agentes de IA da caixa. `ehDosAgentes`: a etapa que resolve é a dos
// agentes. `alerta`: a chave do texto próprio do motivo (em CRM_CAIXAS.EDITOR), ou null para o texto geral.
const ALERTA_DO_ERRO = {
  'crm.caixas.agente_nao_liga': 'AGENTE_NAO_LIGA',
  // #1570 — rascunho tem frase própria.
  'crm.caixas.agente_rascunho': 'AGENTE_RASCUNHO',
  'crm.caixas.principal_parado': 'PRINCIPAL_PARADO',
  'crm.caixas.robo_externo': 'AGENTE_EXTERNO',
};
const ERROS_DOS_AGENTES = [
  ...Object.keys(ALERTA_DO_ERRO),
  'crm.caixas.agente_invalido',
  'crm.caixas.agentes_desligados',
  'crm.caixas.agentes_sem_permissao',
  'crm.caixas.funil_com_dois_agentes',
];

export const erroDosAgentes = codigo => ({
  ehDosAgentes: ERROS_DOS_AGENTES.includes(codigo),
  alerta: ALERTA_DO_ERRO[codigo] || null,
});
