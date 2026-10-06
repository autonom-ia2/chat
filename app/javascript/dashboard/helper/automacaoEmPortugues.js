import {
  AUTOMATIONS,
  AUTOMATION_ACTION_TYPES,
  AUTOMATION_RULE_EVENTS,
} from 'dashboard/routes/dashboard/settings/automation/constants';

// #859 — uma automação escrita como frase, para quem nunca viu o formulário:
// "Quando chega uma mensagem, se Caixa de Entrada é Comercial → Adicionar uma
// Etiqueta: sinistro". Função pura: recebe a regra como a API devolve, o `t` do
// i18n e os nomes que a tela já carregou (caixas, agentes, times, funis, etapas,
// Decisores).
//
// Os rótulos de condição e de ação são os MESMOS do modo manual
// (settings/automation/constants.js): a pessoa reconhece a frase quando abre a
// regra no formulário antigo.

const MINUTOS_POR_HORA = 60;
const MAX_TEXTO_DE_MENSAGEM = 80;
const SEM_VALOR = ['is_present', 'is_not_present'];
const MUDOU_DE_VALOR = 'attribute_changed';

const NOME_DA_CONDICAO = Object.fromEntries(
  Object.values(AUTOMATIONS)
    .flatMap(evento => evento.conditions)
    .reverse()
    .map(condicao => [condicao.key, condicao.name])
);

const ROTULO_DA_ACAO = Object.fromEntries(
  AUTOMATION_ACTION_TYPES.map(acao => [acao.key, acao.label])
);

const EVENTOS = AUTOMATION_RULE_EVENTS.map(evento => evento.key);

// Onde procurar o nome de cada id. A chave é o campo da regra; o valor, a lista
// de nomes que a tela passou.
const LISTA_DE_NOMES = {
  inbox_id: 'inboxes',
  assignee_id: 'agentes',
  team_id: 'times',
  crm_pipeline_id: 'funis',
  crm_stage_id: 'etapas',
};

// As variáveis de nome que o Chatwoot troca na hora do envio. Na tela, viram
// algo que a pessoa entende ("[nome do cliente]") ou um nome de exemplo.
const VARIAVEIS_DE_NOME = [
  '{{contact.name}}',
  '{{ contact.name }}',
  '{{contact.first_name}}',
  '{{ contact.first_name }}',
];

export const trocarNome = (texto, nome) =>
  VARIAVEIS_DE_NOME.reduce(
    (resultado, variavel) => resultado.split(variavel).join(nome),
    String(texto ?? '')
  );

const cortar = texto => {
  const limpo = String(texto ?? '').trim();
  return limpo.length > MAX_TEXTO_DE_MENSAGEM
    ? `${limpo.slice(0, MAX_TEXTO_DE_MENSAGEM)}…`
    : limpo;
};

// O formulário antigo às vezes guarda o valor como { id, name }.
const valorCru = valor =>
  valor && typeof valor === 'object' ? (valor.id ?? valor.name) : valor;

const nomeDe = (lista, id, t) => {
  const nome = lista?.[String(id)];
  return nome || t('AUTOMACOES.NUMERO', { id });
};

const traduzirValor = (chave, valor, { t, nomes }) => {
  if (valor && typeof valor === 'object' && valor.name) return valor.name;
  const cru = valorCru(valor);
  if (LISTA_DE_NOMES[chave])
    return nomeDe(nomes[LISTA_DE_NOMES[chave]], cru, t);

  const texto = String(cru ?? '');
  const maiusculo = texto.toUpperCase();
  if (chave === 'message_type')
    return t(`AUTOMATION.MESSAGE_TYPES.${maiusculo}`);
  if (chave === 'priority') return t(`AUTOMATION.PRIORITY_TYPES.${maiusculo}`);
  if (chave === 'crm_card_status')
    return t(`AUTOMATION.CRM_CARD_STATUS.${maiusculo}`);
  if (chave === 'status') return t(`AUTOMACOES.STATUS.${maiusculo}`);
  if (chave === 'private_note')
    return texto === 'true' ? t('AUTOMACOES.SIM') : t('AUTOMACOES.NAO');
  return texto;
};

const listaDeValores = (chave, valores, contexto) =>
  (Array.isArray(valores) ? valores : [valores])
    .filter(valor => valor !== null && valor !== undefined && valor !== '')
    .map(valor => traduzirValor(chave, valor, contexto))
    .join(` ${contexto.t('AUTOMACOES.OU')} `);

export const nomeDoAtributo = (chave, t) =>
  NOME_DA_CONDICAO[chave]
    ? t(`AUTOMATION.ATTRIBUTES.${NOME_DA_CONDICAO[chave]}`)
    : chave;

const descreverCondicao = (condicao, contexto) => {
  const { t } = contexto;
  const chave = condicao.attribute_key;
  const atributo = nomeDoAtributo(chave, t);
  const operador = condicao.filter_operator;

  if (operador === MUDOU_DE_VALOR) {
    return t('AUTOMACOES.MUDOU', {
      atributo,
      de: listaDeValores(chave, condicao.values?.from, contexto),
      para: listaDeValores(chave, condicao.values?.to, contexto),
    });
  }

  const verbo = t(`AUTOMACOES.OPERADOR.${operador}`);
  if (SEM_VALOR.includes(operador)) return `${atributo} ${verbo}`;
  return `${atributo} ${verbo} ${listaDeValores(chave, condicao.values, contexto)}`;
};

const descreverQuando = (regra, t) => {
  const evento = EVENTOS.includes(regra.event_name)
    ? regra.event_name.toUpperCase()
    : 'DESCONHECIDO';
  const quando = t(`AUTOMACOES.QUANDO.${evento}`);
  const minutos = Number(regra.execution_delay);
  if (!minutos) return quando;

  const espera =
    minutos % MINUTOS_POR_HORA === 0
      ? t('AUTOMACOES.ESPERA_HORAS', { n: minutos / MINUTOS_POR_HORA })
      : t('AUTOMACOES.ESPERA_MINUTOS', { n: minutos });
  return `${quando} ${espera}`;
};

const ESPECIAIS_DO_AGENTE = {
  nil: 'AUTOMATION.NONE_OPTION',
  last_responding_agent: 'AUTOMATION.LAST_RESPONDING_AGENT',
};

const agenteDaAcao = (id, { t, nomes }) =>
  ESPECIAIS_DO_AGENTE[id]
    ? t(ESPECIAIS_DO_AGENTE[id])
    : nomeDe(nomes.agentes, id, t);

// O complemento de cada ação: para quem, qual etiqueta, qual texto.
const COMPLEMENTO = {
  assign_agent: (params, contexto) => agenteDaAcao(params[0], contexto),
  crm_assign_card_owner: (params, contexto) =>
    agenteDaAcao(params[0], contexto),
  assign_team: (params, { t, nomes }) => nomeDe(nomes.times, params[0], t),
  add_label: params => params.join(', '),
  remove_label: params => params.join(', '),
  send_message: (params, { t }) =>
    `“${cortar(trocarNome(params[0], t('AUTOMACOES.VARIAVEL_NOME')))}”`,
  add_private_note: params => `“${cortar(params[0])}”`,
  crm_create_card: (params, { t, nomes }) => nomeDe(nomes.etapas, params[0], t),
  crm_move_card_stage: (params, { t, nomes }) =>
    nomeDe(nomes.etapas, params[0], t),
  change_priority: (params, { t }) =>
    t(`AUTOMATION.PRIORITY_TYPES.${String(params[0]).toUpperCase()}`),
  send_email_to_team: (params, { t, nomes }) =>
    (params[0]?.team_ids || [])
      .map(id => nomeDe(nomes.times, id, t))
      .join(', '),
};

// #858 — o passo do Decisor não existe no formulário antigo (não está em
// AUTOMATION_ACTION_TYPES): "Pergunta ao Decisor É lead?: segue se a resposta
// for “sim” (Pede cotação)". Sem o nome carregado, sai "#12".
const PASSO_DO_DECISOR = 'perguntar_ao_decisor';

const descreverPassoDoDecisor = ([decisorId, chave], { t, nomes }) => {
  const decisor = nomes.decisores?.[String(decisorId)];
  const resposta = (decisor?.respostas || []).find(
    item => String(item.chave) === String(chave)
  );
  const descricao = resposta?.descricao
    ? ` (${cortar(resposta.descricao)})`
    : '';
  return t('AUTOMACOES.DECISOR.PASSO', {
    decisor: decisor?.nome || t('AUTOMACOES.DECISOR.NUMERO', { id: decisorId }),
    resposta: `“${chave}”${descricao}`,
  });
};

const descreverAcao = (acao, contexto) => {
  const { t } = contexto;
  const params = Array.isArray(acao.action_params)
    ? acao.action_params.map(valorCru)
    : [acao.action_params];
  if (acao.action_name === PASSO_DO_DECISOR)
    return descreverPassoDoDecisor(params, contexto);

  const rotulo = ROTULO_DA_ACAO[acao.action_name];
  if (!rotulo) return t('AUTOMACOES.ACAO_DESCONHECIDA');

  const nome = t(`AUTOMATION.ACTIONS.${rotulo}`);
  const complemento = COMPLEMENTO[acao.action_name]?.(params, contexto);
  return complemento ? `${nome}: ${complemento}` : nome;
};

// O nome que a tela mostra para cada passo, sem o complemento (o ensaio só sabe
// o nome da ação).
export const nomeDaAcao = (actionName, t) => {
  if (actionName === PASSO_DO_DECISOR)
    return t('AUTOMACOES.DECISOR.NOME_DO_PASSO');
  return ROTULO_DA_ACAO[actionName]
    ? t(`AUTOMATION.ACTIONS.${ROTULO_DA_ACAO[actionName]}`)
    : t('AUTOMACOES.ACAO_DESCONHECIDA');
};

const juntarCondicoes = se =>
  se
    .map((item, indice) =>
      indice === 0 ? item.texto : `${se[indice - 1].liga} ${item.texto}`
    )
    .join(' ');

export const descreverAutomacao = (regra, { t, nomes = {} }) => {
  const contexto = { t, nomes };
  const quando = descreverQuando(regra, t);
  const se = (regra.conditions || []).map(condicao => ({
    texto: descreverCondicao(condicao, contexto),
    liga:
      String(condicao.query_operator || '').toUpperCase() === 'OR'
        ? t('AUTOMACOES.LIGA.OR')
        : t('AUTOMACOES.LIGA.AND'),
  }));
  const entao = (regra.actions || []).map(acao =>
    descreverAcao(acao, contexto)
  );
  const acoes = entao.join('; ');
  const frase = se.length
    ? t('AUTOMACOES.FRASE', {
        quando,
        condicoes: juntarCondicoes(se),
        acoes,
      })
    : t('AUTOMACOES.FRASE_SEM_CONDICAO', { quando, acoes });

  return { quando, se, entao, frase };
};

// As ações do Guia que criam ou mudam uma automação: o cartão de confirmação
// mostra a prévia dela em vez dos dados crus.
const ACOES_DE_AUTOMACAO = [
  'POST automation_rules',
  'PATCH automation_rules/:id',
  'PUT automation_rules/:id',
];
export const ehAcaoDeAutomacao = nome => ACOES_DE_AUTOMACAO.includes(nome);
