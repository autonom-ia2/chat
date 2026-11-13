// #2414 F5 — o catálogo de passos que o editor lê (GET automacoes/passos, o
// mesmo arquivo do Guia). Daqui saem os gatilhos, os operadores, os valores que
// a condição lê e cada passo com os campos e a peça da tela de cada campo.
import { ref } from 'vue';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { todosOsPassos } from './receita';
import { novoParaCada, valoresDoParaCada } from './paraCada';
import {
  ehPassoNovo,
  novoPassoNovo,
  valoresDaConsulta,
} from './passosNovos/passosNovos';

const catalogo = ref(null);
let carregando = null;

export const carregarCatalogo = () => {
  if (catalogo.value) return Promise.resolve(catalogo.value);
  if (!carregando) {
    carregando = AutomacoesAPI.passos()
      .then(({ data }) => {
        catalogo.value = data;
        return data;
      })
      .finally(() => {
        carregando = null;
      });
  }
  return carregando;
};

export const useCatalogo = () => ({ catalogo, carregarCatalogo });

// A entrada do catálogo que mostra este passo. Sem entrada (passo que só o Guia
// monta, ou ação que saiu do editor), o passo aparece como "Ação avançada".
export const entradaDoPasso = (passo, dados = catalogo.value) => {
  if (!dados || !passo) return null;
  if (passo.tipo !== 'acao')
    return dados.passos.find(item => item.tipo === passo.tipo) || null;
  return (
    dados.passos.find(
      item => item.tipo === 'acao' && item.acao === passo.acao
    ) || null
  );
};

// O corpo guarda o campo de dentro pelo ponto ("custom_attribute_definition.
// attribute_values") e, quando a ação pede, dentro do envelope.
const caminhoNoCorpo = (entrada, nome) => [
  ...(entrada.envelope ? [entrada.envelope] : []),
  ...nome.split('.'),
];

export const lerCampo = (passo, entrada, nome) =>
  caminhoNoCorpo(entrada, nome).reduce(
    (nivel, parte) => (nivel == null ? undefined : nivel[parte]),
    passo.corpo
  );

const gravar = (objeto, [parte, ...resto], valor) => {
  const base = objeto && typeof objeto === 'object' ? objeto : {};
  if (!resto.length) {
    if (valor === undefined || valor === '' || valor === null) {
      const { [parte]: _tirado, ...sobra } = base;
      return sobra;
    }
    return { ...base, [parte]: valor };
  }
  return { ...base, [parte]: gravar(base[parte], resto, valor) };
};

export const gravarCampo = (passo, entrada, nome, valor) => ({
  ...passo,
  corpo: gravar(passo.corpo, caminhoNoCorpo(entrada, nome), valor),
});

export const DURACAO_PADRAO = { valor: 1, unidade: 'dias' };

// Um passo novo, a partir da entrada do catálogo. A descrição é a frase do
// passo (o esquema pede uma); o parâmetro do caminho que vem do alvo e o padrão
// de cada campo já entram.
export const novoPasso = (entrada, id, t) => {
  // Protótipo #2931–#2936: os passos novos nascem prontos (passosNovos.js).
  if (ehPassoNovo(entrada)) return novoPassoNovo(entrada.tipo, id, t);
  if (entrada.tipo === 'esperar')
    return { id, tipo: 'esperar', duracao: { ...DURACAO_PADRAO } };
  if (entrada.tipo === 'esperar_ate')
    return {
      id,
      tipo: 'esperar_ate',
      condicao: null,
      prazo: { ...DURACAO_PADRAO },
    };
  if (entrada.tipo === 'se')
    return { id, tipo: 'se', condicao: null, entao: [] };
  if (entrada.tipo === 'parar') return { id, tipo: 'parar' };
  // O texto nasce vazio: o "Salvar" do painel só libera depois de escrito.
  if (entrada.tipo === 'mensagem') return { id, tipo: 'mensagem', texto: [] };
  if (entrada.tipo === 'avisar')
    return { id, tipo: 'avisar', texto: [], para: { responsavel: true } };
  // G14: nasce no "não receber", que vale em qualquer gatilho.
  if (entrada.tipo === 'campanha')
    return { id, tipo: 'campanha', faz: 'nao_receber' };
  // G21: nasce no "recusar", que vale em qualquer gatilho.
  if (entrada.tipo === 'prospeccao')
    return { id, tipo: 'prospeccao', faz: 'recusar' };
  // G2: a caixa de e-mail a escolher, o assunto e o texto a escrever.
  if (entrada.tipo === 'email')
    return { id, tipo: 'email', caixa_id: null, assunto: [], texto: [] };
  // G18: o "em outro registro" nasce sem ligação e sem passo dentro; a pessoa
  // escolhe onde no painel e põe os passos pelo próprio Confira.
  if (entrada.tipo === 'em_outro_registro')
    return { id, tipo: 'em_outro_registro', registro: {}, passos: [] };
  // G3: o retorno nasce para o responsável, daqui a um dia, só como lembrete.
  if (entrada.tipo === 'retorno')
    return { id, tipo: 'retorno', titulo: [], daqui: { ...DURACAO_PADRAO } };
  // G13: o endereço, a frase, o que mandar e o que guardar, a preencher no painel.
  if (entrada.tipo === 'webhook')
    return {
      id,
      tipo: 'webhook',
      descricao: '',
      url: '',
      corpo: {},
      gravar: [],
    };
  // G4: a etapa do card a escolher no painel.
  if (entrada.tipo === 'card') return { id, tipo: 'card', etapa_id: null };
  // F7: os passos de IA nascem com o que a IA lê por padrão; o decidir com dois
  // caminhos e o extrair com um dado, a preencher no painel.
  const LE = ['mensagens_recentes'];
  const caminhoVazio = () => ({
    nome: '',
    chave: '',
    descricao: '',
    passos: [],
  });
  if (entrada.tipo === 'decidir')
    return {
      id,
      tipo: 'decidir',
      le: LE,
      pergunta: '',
      caminhos: [caminhoVazio(), caminhoVazio()],
    };
  if (entrada.tipo === 'extrair')
    return {
      id,
      tipo: 'extrair',
      le: LE,
      campos: [{ chave: '', descricao: '', destino: '' }],
    };
  if (entrada.tipo === 'escrever')
    return { id, tipo: 'escrever', le: LE, instrucao: '', destino: 'sugestao' };
  if (entrada.tipo === 'resumir')
    return { id, tipo: 'resumir', le: LE, linhas: 3, destino: 'nota' };
  // G24: o "para cada item" nasce com o campo "nome" e a etapa a escolher.
  if (entrada.tipo === 'para_cada') return novoParaCada(id);
  // G15: a agente nasce sem escolha; o "Salvar" do painel espera escolher.
  if (entrada.tipo === 'ia_assumir')
    return { id, tipo: 'ia_assumir', agente_id: null };
  // G52: a lista nasce sem escolha; o "Salvar" do painel espera escolher.
  if (entrada.tipo === 'lista_de_email')
    return { id, tipo: 'lista_de_email', lista_id: null };
  // G66: sem escolha; a conversa vai para quem cuida do card na hora.
  if (entrada.tipo === 'conversa_ao_responsavel')
    return { id, tipo: 'conversa_ao_responsavel' };
  // #2502: nasce entre todos da caixa; o time é escolha opcional.
  if (entrada.tipo === 'rodizio') return { id, tipo: 'rodizio' };

  const caminho = Object.fromEntries(
    Object.entries(entrada.caminho || {})
      .filter(([, origem]) => origem.$valor)
      .map(([nome, origem]) => [nome, { $valor: origem.$valor }])
  );
  const passo = {
    id,
    tipo: 'acao',
    acao: entrada.acao,
    descricao: t(entrada.frase),
    ...(Object.keys(caminho).length || entrada.caminho ? { caminho } : {}),
    corpo: { ...(entrada.fixos || {}) },
  };
  // O padrão que a tela mostra já vai na receita: o que se vê é o que roda.
  return entrada.campos
    .filter(campo => campo.padrao !== undefined)
    .reduce(
      (atual, campo) => gravarCampo(atual, entrada, campo.nome, campo.padrao),
      passo
    );
};

// #2499: só o que o alvo do gatilho alcança (conversa, card, contato). Card num
// gatilho de conversa o salvar recusaria; o editor nem oferece. Sem gatilho
// escolhido, ou valor sem base (a mensagem do gatilho), fica tudo.
// #2597: o valor que pede permissão (`permissao`, como o valor do card, que
// pede `sales_value_view`) fica marcado `sem_permissao` para quem não pode
// lê-lo. A escolha não o oferece; o texto e a condição que já o usam continuam
// mostrando o nome dele, e o salvar recusa até a pessoa tirar.
// #2594: o campo de ação que pede permissão (o valor de venda do card) fica
// marcado `sem_permissao` para quem não pode vê-lo. O "Alterar" não oferece pôr
// um valor nele; o que outra pessoa já pôs aparece travado, sem o valor, com
// "Tirar", porque o salvar recusa (campo_protegido) até ele sair.
const semCamposProtegidos = (passos, podeLer) =>
  passos.map(passo =>
    passo.tipo === 'acao' && passo.campos.some(campo => campo.permissao)
      ? {
          ...passo,
          campos: passo.campos.map(campo =>
            campo.permissao && !podeLer(campo.permissao)
              ? { ...campo, sem_permissao: true }
              : campo
          ),
        }
      : passo
  );

export const comPermissoes = (dados, podeLer) => {
  if (!dados?.valores) return dados;
  return {
    ...dados,
    valores: dados.valores.map(item =>
      item.permissao && !podeLer(item.permissao)
        ? { ...item, sem_permissao: true }
        : item
    ),
    ...(dados.passos
      ? { passos: semCamposProtegidos(dados.passos, podeLer) }
      : {}),
  };
};

// G25: o mesmo vale para a ação que lê o alvo no caminho (`card.id` no fechar
// o card): no gatilho de conversa, o seletor nem a oferece. O card da conversa
// (#2716) é só para ler: para ação, ele não conta como base do alvo.
const basesDaAcao = (alvo, bases) =>
  alvo === 'Conversation' ? bases.filter(base => base !== 'card') : bases;

const caminhoNoAlvo = (passo, bases) =>
  Object.values(passo.caminho || {}).every(
    origem => !origem.$valor || bases.includes(origem.$valor.split('.')[0])
  );

// G12: a reunião (`so_nos_gatilhos`) só nos gatilhos de reunião. G32: o tipo
// do gatilho segue junto, para o "avisar" oferecer quem atende a reunião.
// #2680: com a caixa da conversa nova, o contato alcança a conversa que ela
// abre; e "o cliente respondeu" sai do contato, então vale onde há contato.
// #2716: o card da conversa (gatilho de conversa) só para quem tem a chave de
// funis (`podeLerCard`), a mesma pergunta que o salvar faz.
// G18 (#2671): dentro do "em outro registro", vale o registro em que o ramo roda
// (`alvoDoRamo`), não o alvo do gatilho; lá não há a reunião do gatilho nem a
// conversa nova. `alvo` volta junto, para a peça que precisa saber de onde lê
// (o campo do contato).
const RESPOSTA_DO_CONTATO = 'conversa.cliente_respondeu';
// G65 (#2842): dentro do ramo, também os valores do registro de origem (o alvo
// do gatilho), com o prefixo `origem.`. O servidor marca quais (`na_origem`); a
// permissão (`sem_permissao`) segue a do valor sem o prefixo. Decisão 19: o
// card de uma origem que é conversa só para ler, e só com a chave de funis
// (`semCard`), como fora do ramo.
export const ORIGEM = 'origem.';
const daOrigem = (valores, bases, semCard) =>
  valores
    .filter(
      item =>
        item.na_origem &&
        bases.includes(item.base) &&
        !(semCard && item.base === 'card')
    )
    .map(item => ({
      ...item,
      caminho: `${ORIGEM}${item.caminho}`,
      base: null,
      origem: true,
    }));
export const doAlvoDoGatilho = (
  dados,
  tipoDoGatilho,
  comConversaNova = false,
  podeLerCard = false,
  alvoDoRamo = null
) => {
  const doGatilho = dados?.gatilhos?.find(
    item => item.tipo === tipoDoGatilho
  )?.alvo;
  const alvo = alvoDoRamo || doGatilho;
  const doAlvo = alvo && dados.alvos?.[alvo];
  if (!doAlvo) return dados;
  const bases =
    comConversaNova && !alvoDoRamo
      ? [...new Set([...doAlvo, 'conversa'])]
      : doAlvo;
  const semCard = alvo === 'Conversation' && !podeLerCard;
  const alcanca = item =>
    !(semCard && item.base === 'card') &&
    (!item.base ||
      bases.includes(item.base) ||
      (item.caminho === RESPOSTA_DO_CONTATO && bases.includes('contato')));
  const daReuniao = item =>
    !item.so_nos_gatilhos ||
    (!alvoDoRamo && item.so_nos_gatilhos.includes(tipoDoGatilho));
  return {
    ...dados,
    alvo,
    gatilho: alvoDoRamo ? null : tipoDoGatilho,
    valores: [
      ...dados.valores.filter(item => alcanca(item) && daReuniao(item)),
      ...(alvoDoRamo && dados.alvos?.[doGatilho]
        ? daOrigem(
            dados.valores,
            dados.alvos[doGatilho],
            doGatilho === 'Conversation' && !podeLerCard
          )
        : []),
    ],
    passos: (dados.passos || []).filter(passo =>
      caminhoNoAlvo(passo, basesDaAcao(alvo, bases))
    ),
  };
};

// #2679 — o texto que um "escrever" ou "resumir" da receita produz vira um dado
// que os passos seguintes leem (`ia.<id>`). O rótulo diz qual: a instrução do
// "escrever", ou "Resumo da IA"; dois iguais levam o id junto (comChaveSeRepetido).
// Antes de o passo rodar, o dado está vazio e o passo que o lê pula. O "para cada
// item" (G24) deixa dois: quantos itens e os nomes (`ia.<id>.quantos`, `.nomes`).
const CABE_NO_ROTULO = 40;
const rotuloDoTexto = (passo, t) => {
  if (passo.tipo === 'resumir')
    return t('AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.RESUMIR');
  const letras = Array.from((passo.instrucao || '').trim());
  const curta =
    letras.length > CABE_NO_ROTULO
      ? `${letras.slice(0, CABE_NO_ROTULO).join('').trimEnd()}…`
      : letras.join('');
  return curta
    ? t('AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER', { instrucao: curta })
    : t('AUTOMACAO_LIVRE.IA.TEXTO_DA_IA.ESCREVER_SEM_INSTRUCAO');
};

// G44 (#2756) — o link da agenda de uma página escolhida (`agenda.<id>`), um
// dado por página da conta (useAgendasDaConta), com o rótulo pronto. A escolha
// (`soAsQueMarcam`) só oferece a página que recebe reserva (a regra de
// Crm::BookingV2::InvitePages::SERVES); a frase dos passos mostra o nome de
// qualquer uma. O salvar confere a página e a permissão de novo.
const PAGINA_QUE_MARCA = ['ativa', 'agenda_pausada'];
export const comAgendas = (
  dados,
  paginas,
  t,
  { soAsQueMarcam = false } = {}
) => {
  if (!dados?.valores || !paginas?.length) return dados;
  const agendas = paginas
    .filter(
      pagina => !soAsQueMarcam || PAGINA_QUE_MARCA.includes(pagina.ai_status)
    )
    .map(pagina => ({
      caminho: `agenda.${pagina.id}`,
      chave: String(pagina.id),
      rotulo: t('AUTOMACAO_LIVRE.VALORES.AGENDA_DA_PAGINA', {
        titulo: pagina.title,
      }),
    }));
  return { ...dados, valores: [...dados.valores, ...agendas] };
};

// G49 — o registro que um passo cria (o card do "criar card", o contato de uma
// ação que cria contato) vira um dado dos passos seguintes: `criado.<id>`, o id
// dele. `criado` diz o tipo, para a peça que só aceita contato. A mesma lista
// fechada do servidor (RegistroCriado).
const ACOES_QUE_CRIAM = {
  'POST contacts': 'Contact',
  'POST crm/cards/:card_id/contact': 'Contact',
};
export const tipoCriado = passo => {
  if (passo?.tipo === 'card') return 'Crm::Card';
  return (passo?.tipo === 'acao' && ACOES_QUE_CRIAM[passo.acao]) || null;
};
const ROTULO_DO_CRIADO = { Contact: 'CONTATO', 'Crm::Card': 'CARD' };

// `achatar`: como a lista vira os passos de onde vêm os textos; o "Alterar"
// passa a lista já pronta da execução do passo (passosDaExecucao, G18). Junto
// com os textos da IA vêm os registros criados (G49): os dois ficam na execução.
export const comTextosDaIa = (dados, passos, t, achatar = todosOsPassos) => {
  if (!dados?.valores) return dados;
  const lista = achatar(passos);
  const textos = lista.flatMap(passo => {
    if (passo.tipo === 'para_cada') return valoresDoParaCada(passo, t);
    if (passo.tipo === 'consultar') return valoresDaConsulta(passo);
    if (!['escrever', 'resumir'].includes(passo.tipo)) return [];
    return [
      {
        caminho: `ia.${passo.id}`,
        chave: passo.id,
        rotulo: rotuloDoTexto(passo, t),
      },
    ];
  });
  const criados = lista
    .filter(passo => tipoCriado(passo))
    .map(passo => ({
      caminho: `criado.${passo.id}`,
      chave: passo.id,
      criado: tipoCriado(passo),
      rotulo: t(
        `AUTOMACAO_LIVRE.CRIADO.${ROTULO_DO_CRIADO[tipoCriado(passo)]}`
      ),
    }));
  return { ...dados, valores: [...dados.valores, ...textos, ...criados] };
};
