// Roteiro do vídeo de trajeto do artigo 12.01 — "Criar uma regra de
// Automação do zero". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,automation}.json e em
// app/javascript/dashboard/routes/dashboard/settings/automation/{AutomationRuleForm,
// AutomationInstantTrigger,AutomationActions}.vue.
//
// Segurança: a condição usa "Assunto do e-mail = <string impossível>" —
// nenhuma conversa de verdade tem esse assunto, então a regra não dispara
// em nada da conta mesmo ativa. Além disso, depois de gravar e conferir,
// desativei a regra na mão (active: false) — não fica ligada entre uma
// sessão e outra; regravar aqui reativa (o preparar só apaga e a gravação
// recria com active: true, o padrão do formulário).
//
// 1ª tentativa: o clique em "Criar" não fazia nada (sem POST no log do
// Rails). Causa real: Descrição é campo obrigatório
// (app/javascript/dashboard/helper/validations.js:80) e eu não preenchia
// — a validação barrava o submit antes de qualquer rede, em silêncio, sem
// exception pro motor pegar. Corrigido preenchendo Descrição também.
//
// Trajeto: barra lateral → Configurações → Automação → Criar Automação →
// Nome da Regra → Descrição → Evento (Conversa Criada) → Condição (Assunto
// do e-mail contém texto impossível) → Ação (Adicionar uma Etiqueta →
// sinistro) → Criar.

export const id = '12.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_REGRA = 'Etiquetar pedidos de sinistro';

// Idempotente: apaga a regra anterior com esse nome antes de gravar de
// novo. Não mexe em nenhuma outra regra de automação da conta.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.automation_rules.where(name: ${JSON.stringify(NOME_REGRA)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar uma regra de automação',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Abra Configurações no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurações' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Automação',
    acao: 'mover e clicar',
    alvo: { texto: 'Automação' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar Automação',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar Automação' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da regra',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Inserir nome da regra"]' },
    texto: [NOME_REGRA],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a descrição',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Inserir descrição de regra"]' },
    texto: ['Etiqueta pedidos de sinistro ao criar a conversa.'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o evento Conversa Criada',
    acao: 'selecionar',
    alvo: { seletor: 'select' },
    valor: 'Conversa Criada',
    zoom: 1.8,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Abra o campo da condição',
    acao: 'mover e clicar',
    alvo: { texto: 'Status' },
    zoom: 1.8,
    pausaAntesMs: 700,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escolha Assunto do e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Assunto do e-mail' },
    zoom: 1.8,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escreva um valor que não existe',
    acao: 'digitar',
    alvo: { seletor: 'section input[type="text"]' },
    texto: ['pedido-de-sinistro-teste-nina-9x7z'],
    zoom: 1.8,
  },
  {
    legenda: 'Abra o campo da ação',
    acao: 'mover e clicar',
    alvo: { texto: 'Atribuir ao Agente' },
    zoom: 1.8,
    pausaAntesMs: 700,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escolha Adicionar uma Etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar uma Etiqueta' },
    zoom: 1.8,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Abra o campo da etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecione uma opção...' },
    zoom: 1.8,
    pausaAntesMs: 700,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escolha a etiqueta sinistro',
    acao: 'mover e clicar',
    alvo: { texto: 'sinistro' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1200,
  },
];
