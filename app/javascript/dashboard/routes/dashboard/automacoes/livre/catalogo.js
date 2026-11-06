// #2414 F5 — o catálogo de passos que o editor lê (GET automacoes/passos, o
// mesmo arquivo do Guia). Daqui saem os gatilhos, os operadores, os valores que
// a condição lê e cada passo com os campos e a peça da tela de cada campo.
import { ref } from 'vue';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';

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

const DURACAO_PADRAO = { valor: 1, unidade: 'dias' };

// Um passo novo, a partir da entrada do catálogo. A descrição é a frase do
// passo (o esquema pede uma); o parâmetro do caminho que vem do alvo e o padrão
// de cada campo já entram.
export const novoPasso = (entrada, id, t) => {
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
  // G2: a caixa de e-mail a escolher, o assunto e o texto a escrever.
  if (entrada.tipo === 'email')
    return { id, tipo: 'email', caixa_id: null, assunto: [], texto: [] };
  // G3: o retorno nasce para o responsável, daqui a um dia, só como lembrete.
  if (entrada.tipo === 'retorno')
    return { id, tipo: 'retorno', titulo: [], daqui: { ...DURACAO_PADRAO } };
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
  // G15: a agente nasce sem escolha; o "Salvar" do painel espera escolher.
  if (entrada.tipo === 'ia_assumir')
    return { id, tipo: 'ia_assumir', agente_id: null };

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
export const comPermissoes = (dados, podeLer) => {
  if (!dados?.valores) return dados;
  return {
    ...dados,
    valores: dados.valores.map(item =>
      item.permissao && !podeLer(item.permissao)
        ? { ...item, sem_permissao: true }
        : item
    ),
  };
};

// G12: a reunião (`so_nos_gatilhos`) só nos gatilhos de reunião.
export const doAlvoDoGatilho = (dados, tipoDoGatilho) => {
  const alvo = dados?.gatilhos?.find(item => item.tipo === tipoDoGatilho)?.alvo;
  const bases = alvo && dados.alvos?.[alvo];
  if (!bases) return dados;
  return {
    ...dados,
    valores: dados.valores.filter(
      item =>
        (!item.base || bases.includes(item.base)) &&
        (!item.so_nos_gatilhos || item.so_nos_gatilhos.includes(tipoDoGatilho))
    ),
  };
};
