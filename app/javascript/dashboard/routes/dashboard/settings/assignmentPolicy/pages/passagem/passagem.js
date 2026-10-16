// #1385 — regras puras da tela de passagem: o que cada regra quer dizer em frase e o que acontece com a
// cliente de exemplo. Sem Vue aqui, para o teste ler direto.

export const ETAPA_IGUAL = 'igual';
export const ETAPA_DESLIGADA = 'desligada';
export const ETAPA_PROPRIA = 'propria';

// #1593: o agente de IA escolhido em "A mesma pessoa" vem como "ia:<id>"; a pessoa, com o id do usuário.
export const PREFIXO_IA = 'ia:';
export const ehAgente = valor => String(valor || '').startsWith(PREFIXO_IA);

// #1593: agente de IA parado (ou que não aparece mais na lista, como sem a Fase 2) é como pessoa fora: a conversa vai
// para alguém da equipe. -> { nome } desse agente, ou null quando a regra não aponta agente ou ele pode receber.
export const agenteQueNaoRecebe = (regra, todas) => {
  if (regra.pool_type !== 'user' || !ehAgente(regra.pool_id)) return null;
  const agente = (todas || []).find(item => item.id === regra.pool_id);
  return !agente || agente.parado ? { nome: agente?.name || '' } : null;
};

// A regra que vale de verdade na prévia: com o agente parado, a de alguém da equipe.
export const regraQueVale = (regra, todas) =>
  agenteQueNaoRecebe(regra, todas)
    ? { ...regra, pool_type: 'inbox', pool_id: null }
    : regra;

export const ESPERAS_EM_MINUTOS = [5, 10, 15, 30, 60];

export const minutosDe = regra =>
  Math.max(1, Math.round(Number(regra.pickup_threshold_seconds) / 60) || 1);

export const primeiroNome = nome => String(nome || '').split(' ')[0];

export const nomeDe = (pessoas, id) =>
  pessoas.find(pessoa => pessoa.id === id)?.name || '';

// Falta escolher alguém onde a regra pede uma pessoa?
export const faltaQuemRecebe = regra =>
  regra.pool_type === 'user' && !regra.pool_id;

export const faltaParaQuem = regra =>
  regra.handoff_mode === 'r3_invite' &&
  regra.escalation_action === 'escalate' &&
  !regra.escalation_user_id;

export const faltaPessoa = regra =>
  regra.enabled && (faltaQuemRecebe(regra) || faltaParaQuem(regra));

export const etapaLigada = (etapa, regraDoFunil) => {
  if (etapa.modo === ETAPA_IGUAL) return regraDoFunil.enabled;
  return etapa.modo === ETAPA_PROPRIA;
};

// A regra que vale numa etapa: a do funil, a própria, ou nenhuma.
export const regraDaEtapa = (etapa, regraDoFunil) => {
  if (etapa.modo === ETAPA_PROPRIA) return { ...etapa.regra, enabled: true };
  if (etapa.modo === ETAPA_DESLIGADA)
    return { ...regraDoFunil, enabled: false };
  return regraDoFunil;
};

// Quem aparece recebendo na prévia: a pessoa escolhida, ou alguém da equipe que não tenha o nome da
// cliente de exemplo nem seja a pessoa do "passar para outra" (para a prévia não dizer "passou do Bruno para o Bruno").
export const quemRecebeNoExemplo = ({
  regra,
  equipe,
  todas,
  cliente,
  evitar = '',
}) => {
  if (regra.pool_type === 'user') {
    return primeiroNome(
      nomeDe(todas, regra.pool_id) || nomeDe(equipe, regra.pool_id)
    );
  }
  const nomes = equipe.map(pessoa => primeiroNome(pessoa.name));
  return nomes.find(nome => nome !== cliente && nome !== evitar) || '';
};

// A ordem do rodízio no exemplo: até três pessoas da equipe.
export const filaDoExemplo = (equipe, cliente) =>
  equipe
    .filter(pessoa => primeiroNome(pessoa.name) !== cliente)
    .slice(0, 3)
    .map(pessoa => primeiroNome(pessoa.name));

// A conversa pode cair com quem está fora? Só com "prefer_online" desligado (regra da tela antiga): no modo "na hora",
// e no convite que passa para outra pessoa, o sistema atribui a quem está fora e o atendimento automático para
// (HandoffExecutor#assign! e HandoffEscalationJob chamam bot_handoff!). A tela nova não oferece esse jeito; quando ele
// vem salvo, avisa e oferece corrigir.
export const podeFicarSemResposta = regra =>
  regra.enabled &&
  !regra.prefer_online &&
  (regra.handoff_mode === 'r2_direct' ||
    regra.escalation_action === 'escalate');

const evento = (chave, tom, campos = {}) => ({
  tipo: 'evento',
  chave,
  tom,
  ...campos,
});
const SEM_RESPOSTA = nome => [
  evento('ROBO_PARA', 'ambar'),
  { tipo: 'cliente', chave: 'CLIENTE_DUVIDA' },
  evento('SEM_RESPOSTA', 'ambar', { nome }),
];
const ENQUANTO_ISSO = [
  { tipo: 'cliente', chave: 'CLIENTE_DUVIDA' },
  { tipo: 'robo', chave: 'ROBO_RESPONDE' },
];
const ROBO_AVISA = { tipo: 'robo', chave: 'ROBO_AVISA' };

// Os dois dias da prévia: sábado com a equipe toda fora, terça com a equipe online.
export const CENARIO_FORA = 'fora';
export const CENARIO_ONLINE = 'online';

// Convite com todos fora: o convite sai mesmo assim (HandoffMemberSelector prefere quem está online, mas não exige) e
// a assistente segue, porque convite nunca cala o atendimento automático. O convite vence em 24 horas
// (Config::HANDOFF_INVITE_TTL_SECONDS, HandoffExpiryJob): depois disso ninguém mais é avisado nem recebe. "Passar para
// outra pessoa" só atribui quando ela está online (HandoffEscalationJob#escalation_target_ready?). O desfecho mostrado
// acontece dentro das 24 horas.
const conviteComTodosFora = (regra, recebe, outra) => {
  const minutos = minutosDe(regra);
  const comeco = [ROBO_AVISA, evento('CONVITE_FORA', 'azul', { nome: recebe })];
  const vence = evento('CONVITE_VENCE', 'prazo');
  const tarde = { tipo: 'dia', chave: 'SABADO_TARDE' };
  if (regra.escalation_action !== 'escalate') {
    return [
      ...comeco,
      ...ENQUANTO_ISSO,
      evento('ESPERA_AVISA', 'azul', { minutos, nome: recebe }),
      vence,
      tarde,
      evento('ACEITOU', 'azul', { nome: recebe }),
      evento('ASSUMIU', 'verde', { nome: recebe }),
    ];
  }
  if (!regra.prefer_online) {
    return [
      ...comeco,
      evento('ESPERA_PASSA_FORA', 'ambar', {
        minutos,
        nome: outra,
        convidada: recebe,
      }),
      ...SEM_RESPOSTA(outra),
    ];
  }
  return [
    ...comeco,
    ...ENQUANTO_ISSO,
    evento(outra ? 'ESPERA_PASSA_SEGURA' : 'ESPERA_PASSA_SEGURA_SEM', 'azul', {
      minutos,
      nome: outra,
      convidada: recebe,
    }),
    vence,
    tarde,
    evento('ENTREGUE_OUTRA', 'azul', { nome: outra }),
    evento('ASSUMIU', 'verde', { nome: outra }),
  ];
};

// Na hora com todos fora: a conversa espera com a assistente (HandoffExecutor#hold_online) e vai para quem ficar online
// primeiro (HandoffDrainJob, a cada 2 minutos). Essa espera não vence. Com a regra antiga, vai para quem está fora e a
// assistente para (HandoffExecutor#assign! chama bot_handoff!).
const naHoraComTodosFora = (regra, recebe) => {
  if (!regra.prefer_online) {
    return [
      evento('FOI_PARA_QUEM_ESTA_FORA', 'ambar', { nome: recebe }),
      ...SEM_RESPOSTA(recebe),
    ];
  }
  return [
    ROBO_AVISA,
    evento('NINGUEM_ONLINE', 'verde'),
    ...ENQUANTO_ISSO,
    { tipo: 'dia', chave: 'SEGUNDA' },
    evento('ENTREGUE', 'azul', { nome: recebe }),
    evento('ASSUMIU', 'verde', { nome: recebe }),
  ];
};

// Terça, com a equipe online: na hora, a conversa vai para quem está online e a assistente para; com convite, a pessoa
// é avisada, a assistente segue e para quando ela aceita. A regra antiga não olha quem está online.
const comEquipeOnline = (regra, recebe) => {
  if (regra.handoff_mode === 'r3_invite') {
    return [
      ROBO_AVISA,
      evento(
        regra.prefer_online ? 'CONVITE_ONLINE' : 'CONVITE_ENVIADO',
        'azul',
        { nome: recebe }
      ),
      ...ENQUANTO_ISSO,
      evento('ACEITOU_LOGO', 'azul', { nome: recebe }),
      evento('ASSUMIU', 'verde', { nome: recebe }),
    ];
  }
  if (!regra.prefer_online) {
    return [evento('VAI_ONLINE_OU_NAO', 'ambar', { nome: recebe })];
  }
  return [
    { tipo: 'robo', chave: 'ROBO_CHAMA' },
    evento('ENTREGUE_NA_HORA', 'azul', { nome: recebe }),
    evento('ASSUMIU', 'verde', { nome: recebe }),
  ];
};

// A conversa da cliente de exemplo, no dia escolhido. Cada passo é uma chave de texto (CRM_KANBAN.PASSAGEM.CENA.*) e o
// que preencher nela. Sem caixa ou com a assistente do funil desligada, mostra o que acontece de verdade: nenhuma
// conversa chega, ou ninguém chama a equipe.
export const cenaDaPrevia = ({
  regra,
  recebe,
  outra,
  iaLigada = true,
  semCaixa = false,
  cenario = CENARIO_FORA,
}) => {
  if (semCaixa) return [evento('SEM_CAIXA', 'ambar')];
  const online = cenario === CENARIO_ONLINE;
  const comeco = [
    { tipo: 'dia', chave: online ? 'TERCA' : 'SABADO' },
    { tipo: 'cliente', chave: 'CLIENTE_PEDE' },
  ];
  if (!iaLigada) {
    return [
      ...comeco,
      evento('FUNIL_DESLIGADO', 'cinza'),
      evento('FICA_NA_CAIXA', 'ambar'),
    ];
  }
  if (!regra.enabled) {
    return [
      ...comeco,
      evento('NAO_CHAMA', 'cinza'),
      { tipo: 'robo', chave: 'ROBO_SEGUE' },
    ];
  }
  // #1593: agente de IA não fica fora nem recebe convite: assume na hora, qualquer dia.
  if (ehAgente(regra.pool_id) && regra.pool_type === 'user') {
    return [...comeco, evento('IA_ASSUME', 'verde', { nome: recebe })];
  }
  if (online) return [...comeco, ...comEquipeOnline(regra, recebe)];
  const resto =
    regra.handoff_mode === 'r3_invite'
      ? conviteComTodosFora(regra, recebe, outra)
      : naHoraComTodosFora(regra, recebe);
  return [...comeco, ...resto];
};

// Quem recebe quando parte da equipe está fora: o fato que a prévia de "Quem recebe" mostra. O seletor prefere quem
// está online (HandoffMemberSelector#preferred_pool); a regra antiga não olha isso.
export const quemComParteFora = ({ regra, fila, pessoa }) => {
  const convite = regra.handoff_mode === 'r3_invite';
  if (regra.pool_type === 'user') {
    if (!pessoa) return { chave: 'FALTA' };
    // #1593: agente de IA não fica fora; assume na hora.
    if (ehAgente(regra.pool_id)) return { chave: 'IA', nome: pessoa };
    if (convite) return { chave: 'PESSOA_CONVITE', nome: pessoa };
    return {
      chave: regra.prefer_online ? 'PESSOA_ESPERA' : 'PESSOA_FORA',
      nome: pessoa,
    };
  }
  if (!regra.prefer_online) return { chave: 'EQUIPE_ANTIGA' };
  if (fila.length < 2) return { chave: 'EQUIPE_UMA', nome: fila[0] || '' };
  return {
    chave: convite ? 'EQUIPE_VAI_CONVITE' : 'EQUIPE_VAI',
    fora: fila[0],
    online: fila[1],
  };
};

// Etapas agrupadas pelo que acontece nelas, para a frase do resumo.
export const etapasPorModo = (etapas, regraDoFunil) => ({
  ligadas: etapas.filter(etapa => etapaLigada(etapa, regraDoFunil)),
  proprias: etapas.filter(etapa => etapa.modo === ETAPA_PROPRIA),
  semPassagem: etapas.filter(etapa => !etapaLigada(etapa, regraDoFunil)),
});

// O idioma do painel vem como "pt_BR"; o Intl só aceita "pt-BR".
export const juntarNomes = (nomes, idioma = 'pt-BR') =>
  new Intl.ListFormat(String(idioma).replaceAll('_', '-'), {
    style: 'long',
    type: 'conjunction',
  }).format(nomes);

// O jeito de uma etapa "do meu jeito", em poucas palavras. O tempo de espera e o "e se ninguém aceitar" ficam na tela
// da etapa.
export const jeitoDaRegra = (regra, pessoas) => {
  const convite = regra.handoff_mode === 'r3_invite';
  if (regra.pool_type === 'user') {
    return {
      chave: convite ? 'CONVITE_PESSOA' : 'NA_HORA_PESSOA',
      nome: nomeDe(pessoas, regra.pool_id),
    };
  }
  return { chave: convite ? 'CONVITE_EQUIPE' : 'NA_HORA_EQUIPE' };
};

// A mesma coisa, já traduzida (recebe o `t` do vue-i18n): CURTO para o quadro, numa linha; FRASE para o cartão.
export const textoDoJeito = (t, regra, pessoas, forma = 'CURTO') => {
  const jeito = jeitoDaRegra(regra, pessoas);
  const nome = jeito.nome || t('CRM_KANBAN.PASSAGEM.JEITO.PESSOA_ESCOLHIDA');
  return t(`CRM_KANBAN.PASSAGEM.JEITO.${forma}.${jeito.chave}`, {
    nome: forma === 'CURTO' ? primeiroNome(nome) : nome,
  });
};

// Até duas etapas do seu jeito, cada uma ganha a sua frase no resumo e na prévia; com mais, uma frase só com os nomes,
// para o texto não virar um parágrafo.
export const MAX_PROPRIAS_UMA_A_UMA = 2;

// O modo de uma etapa como o servidor manda (Crm::Ai::SettingsPresenter): sem regra própria, segue o funil.
export const modoDaEtapa = etapa => {
  if (etapa.handoff_custom !== true) return ETAPA_IGUAL;
  return etapa.handoff?.enabled === true ? ETAPA_PROPRIA : ETAPA_DESLIGADA;
};

const jeitoDoFluxo = fluxo => (fluxo === 'r3_invite' ? 'convite' : 'na_hora');

// Para a lista de funis: o que vale hoje, contando as etapas. Funil desligado com uma etapa do seu jeito chama a
// equipe nessa etapa, então não é "desligada". Com a assistente do funil desligada, ninguém é chamado. O jeito
// (na hora ou com convite) só aparece quando é o mesmo em todas as etapas que chamam a equipe.
export const situacaoDoFunil = ajustes => {
  if (ajustes?.enabled === false) {
    return { estado: 'desligada', semAssistente: true };
  }
  const regra = { enabled: ajustes?.handoff?.enabled === true };
  const fluxoDoFunil = ajustes?.handoff?.handoff_mode;
  const etapas = (ajustes?.stages || []).map(etapa => ({
    modo: modoDaEtapa(etapa),
    fluxo: etapa.handoff?.handoff_mode,
  }));
  const ligadas = etapas.filter(etapa => etapaLigada(etapa, regra));
  if (!ligadas.length && !(regra.enabled && !etapas.length)) {
    return { estado: 'desligada' };
  }
  const fluxos = new Set(
    ligadas.length
      ? ligadas.map(etapa =>
          etapa.modo === ETAPA_PROPRIA ? etapa.fluxo : fluxoDoFunil
        )
      : [fluxoDoFunil]
  );
  const jeito = fluxos.size === 1 ? jeitoDoFluxo([...fluxos][0]) : null;
  if (ligadas.length < etapas.length) {
    return {
      estado: 'parte',
      ligadas: ligadas.length,
      total: etapas.length,
      jeito,
    };
  }
  return { estado: 'ligada', jeito, total: etapas.length };
};

// A frase do cartão da lista: a chave (em CRM_KANBAN.PASSAGEM.LISTA.ESTADO) e o que entra nela. O jeito vai como
// chave também, para a página traduzir. Sem situação (o servidor não respondeu para esse funil), diz isso.
export const fraseDaSituacao = situacao => {
  if (!situacao) return { chave: 'SEM_SITUACAO' };
  if (situacao.estado === 'desligada') {
    return { chave: situacao.semAssistente ? 'SEM_ASSISTENTE' : 'DESLIGADA' };
  }
  const jeito =
    situacao.jeito === 'convite' ? 'JEITO_CONVITE' : 'JEITO_NA_HORA';
  if (situacao.estado === 'parte') {
    return {
      chave: situacao.jeito ? 'PARTE' : 'PARTE_MISTO',
      jeito,
      n: situacao.ligadas,
      total: situacao.total,
    };
  }
  if (!situacao.total) return { chave: 'LIGADA_SEM_ETAPAS', jeito };
  return { chave: situacao.jeito ? 'LIGADA' : 'LIGADA_MISTO', jeito };
};
