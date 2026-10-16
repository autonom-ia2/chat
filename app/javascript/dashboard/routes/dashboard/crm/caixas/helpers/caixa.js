// #1149 — regras da tela Caixas no CRM, sem Vue: o que cada pessoa vê, o que o
// sistema faz sozinho e o que muda ao salvar. A tela só mostra.

import { chaveDoModo, iaSalva } from './modoDoAssunto';

export const CORES_DE_FUNIL = [
  'bg-n-blue-9',
  'bg-n-teal-9',
  'bg-n-amber-9',
  'bg-n-iris-9',
  'bg-n-ruby-9',
];

export const corDoFunil = (funis, funilId) => {
  const indice = funis.findIndex(funil => funil.id === funilId);
  return CORES_DE_FUNIL[Math.max(indice, 0) % CORES_DE_FUNIL.length];
};

export const funisDaCaixa = (caixa, funis) =>
  funis.filter(funil => caixa.pipeline_ids.includes(funil.id));

// A mesma conta da tela (CaixaPage): só os funis que existem na lista.
export const umFunilSo = (caixa, funis) =>
  funisDaCaixa(caixa, funis).length === 1;

export const modoDaCaixa = caixa => {
  if (caixa.pipeline_ids.length === 1) {
    return caixa.auto_create_card ? 'chegou' : 'off';
  }
  return caixa.subject_ai_mode;
};

// "Todos os funis" vira a lista explícita dos funis da caixa: na tela, cada
// funil é um botão, e marcar todos volta a ser "Todos os funis" ao salvar.
export const paraFormulario = caixa => ({
  ...JSON.parse(JSON.stringify(caixa)),
  modo: modoDaCaixa(caixa),
  people: caixa.people.map(pessoa => ({
    ...pessoa,
    pipeline_ids: pessoa.all_pipelines
      ? [...caixa.pipeline_ids]
      : pessoa.pipeline_ids.filter(id => caixa.pipeline_ids.includes(id)),
  })),
});

export const agentes = caixa =>
  caixa.people.filter(pessoa => !pessoa.administrator);

// O que vai para o servidor: ele decide, pela quantidade de funis, se o card
// nasce na chegada, pela IA de assunto ou à mão, e quem fica sem linha de
// acesso (quem cuida de tudo). Administrador não vai: vê tudo sempre.
export const paraSalvar = form => ({
  pipeline_ids: form.pipeline_ids,
  default_stage_id:
    form.pipeline_ids.length === 1 ? form.default_stage_id : null,
  modo: form.pipeline_ids.length ? form.modo : 'off',
  ...(form.legado ? { legado: form.legado } : {}),
  people: agentes(form).map(pessoa => ({
    id: pessoa.id,
    triage: pessoa.triage,
    only_own: pessoa.only_own,
    pipeline_ids: pessoa.pipeline_ids.filter(id =>
      form.pipeline_ids.includes(id)
    ),
  })),
});

// R7: com mais de um funil, alguém precisa ver as conversas ainda sem assunto.
export const faltaTriagem = caixa =>
  caixa.pipeline_ids.length > 1 &&
  agentes(caixa).length > 0 &&
  !agentes(caixa).some(pessoa => pessoa.triage);

// R6: a caixa ainda está em "Agente vê apenas atribuídos". A conversão para
// "Só as que atende" é oferecida, nunca feita sozinha.
export const legadoPendente = caixa =>
  caixa.crm_enabled && caixa.visibility_mode === 'assigned_only';

// Na tela: a caixa é antiga e ninguém escolheu ainda entre manter e mudar.
export const faltaEscolherLegado = form => legadoPendente(form) && !form.legado;

export const cuidaDoFunil = (pessoa, funilId) =>
  pessoa.administrator || pessoa.pipeline_ids.includes(funilId);

export const quemCuida = (caixa, funilId) =>
  agentes(caixa).filter(pessoa => cuidaDoFunil(pessoa, funilId));

export const quemFazTriagem = caixa =>
  agentes(caixa).filter(pessoa => pessoa.triage);

// tipo 'disjunction' junta com "ou" ("Bruno ou Diego").
export const juntar = (nomes, locale, tipo = 'conjunction') => {
  if (!nomes.length) return '';
  try {
    return new Intl.ListFormat(locale.replace('_', '-'), {
      style: 'long',
      type: tipo,
    }).format(nomes);
  } catch {
    return nomes.join(', ');
  }
};

export const primeiroNome = pessoa => pessoa.name.split(' ')[0];

// #1570 — o robô que atende primeiro é de outro sistema (n8n, Zapier...): na
// tela é "agente externo", nunca a porta dos Agentes de IA.
export const roboExterno = robo => robo?.tipo_do_principal === 'externo';

// #1570 — quem aparece como porta (agente de IA que atende primeiro): a porta
// dos Agentes ou, sem ela, o robô da caixa, desde que não seja externo.
export const portaOuRobo = (porta, robo) =>
  porta || (roboExterno(robo) ? null : robo);

// O que muda em relação ao que está salvo, em frases curtas para a etapa
// Confira. Cada item: { chave, valores } para o i18n. `semAssunto` é o nome
// das conversas ainda sem assunto na língua da tela.
// Com um funil só, não existe "sem assunto" separado: quem cuida do funil
// cuida também das conversas que ainda não viraram card.
export const assuntosDe = (pessoa, funis, semAssunto) => [
  ...(pessoa.triage && funis.length > 1 ? [semAssunto] : []),
  ...funis
    .filter(funil => pessoa.pipeline_ids.includes(funil.id))
    .map(funil => funil.name),
];

const diferenca = (primeira, segunda) =>
  primeira.filter(item => !segunda.includes(item));

export const mudancas = (
  antes,
  depois,
  funis,
  { semAssunto, locale, iaDeAssunto = false }
) => {
  const nomeDoFunil = id => funis.find(funil => funil.id === id)?.name || '';
  const marcados = funisDaCaixa(depois, funis);
  const lista = [];

  diferenca(depois.pipeline_ids, antes.pipeline_ids).forEach(id =>
    lista.push({ chave: 'FUNIL_ENTRA', valores: { funil: nomeDoFunil(id) } })
  );
  diferenca(antes.pipeline_ids, depois.pipeline_ids).forEach(id =>
    lista.push({ chave: 'FUNIL_SAI', valores: { funil: nomeDoFunil(id) } })
  );

  // R6: a caixa em "vê apenas atribuídos" equivale, hoje, a "Só as que
  // atende" para cada agente; é contra isso que se mede o que muda.
  const hoje = legadoPendente(antes)
    ? antes.people.map(item => ({ ...item, only_own: !item.administrator }))
    : antes.people;

  agentes(depois).forEach(pessoa => {
    const anterior = hoje.find(item => item.id === pessoa.id);
    if (!anterior) return;
    const nome = primeiroNome(pessoa);
    const agora = assuntosDe(pessoa, marcados, semAssunto);
    const eram = assuntosDe(anterior, marcados, semAssunto);
    const ganhou = diferenca(agora, eram);
    const perdeu = diferenca(eram, agora);
    if (ganhou.length) {
      lista.push({
        chave: 'PESSOA_GANHA',
        valores: { nome, assuntos: juntar(ganhou, locale) },
      });
    }
    if (perdeu.length) {
      lista.push({
        chave: 'PESSOA_PERDE',
        valores: { nome, assuntos: juntar(perdeu, locale) },
      });
    }
    if (anterior.only_own !== pessoa.only_own) {
      lista.push({
        chave: pessoa.only_own ? 'PESSOA_SO_SUAS' : 'PESSOA_TODAS',
        valores: { nome },
      });
    }
  });

  // #1676: compara o que o sistema faz (a chave do texto), não o valor gravado.
  // Com a IA de assunto em 1 funil, 'off' de 1 funil cria um card por pedido
  // (AUTO_UM), diferente de 'off' de vários (à mão). Antes de salvar vale a IA
  // de assunto gravada na caixa; depois, a flag da conta.
  const modoAntes = chaveDoModo(
    antes.modo,
    umFunilSo(antes, funis),
    iaSalva(antes)
  );
  const modoDepois = chaveDoModo(
    depois.modo,
    umFunilSo(depois, funis),
    iaDeAssunto
  );
  if (modoAntes !== modoDepois) {
    lista.push({ chave: 'MODO', valores: { modo: depois.modo } });
  }
  return lista;
};
