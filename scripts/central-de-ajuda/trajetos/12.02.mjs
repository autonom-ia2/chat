// Roteiro do vídeo de trajeto do artigo 12.02 — "Criar e editar uma Macro".
// Cria de verdade a macro "Repassar para o time de sinistros" (privada, só
// da Lia) com a ação Adicionar uma Etiqueta → sinistro. O preparar apaga
// essa macro antes de cada gravação, pelo nome — idempotente, não mexe em
// nenhuma outra macro da conta (nem na "Marcar como sinistro" do vídeo
// 08.10, nome diferente de propósito).
//
// Seletores conferidos no código-fonte (MacroProperties.vue, MacroNode.vue
// + AutomationActionInput.vue, reaproveitado de automação):
// - Nome da macro: `input[placeholder="Digite um nome para sua macro"]`.
// - Visibilidade: botões "Publico"/"Privada".
// - Ação padrão de uma macro nova: "Atribuir um Time" (MacroEditor.vue,
//   action_name: 'assign_team') — clicar abre a lista de ações.
// - Etiqueta: campo de valor com placeholder "Selecione uma opção..."
//   (COMBOBOX.PLACEHOLDER, componente MultiSelect compartilhado).
// - Botão salvar: "Salvar macro" (HEADER_BTN_TXT_SAVE).
//
// Trajeto: Configurações → Macros → Criar → nome → Privada → ação
// Adicionar uma Etiqueta → sinistro → Salvar macro.

export const id = '12.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_MACRO = 'Repassar para o time de sinistros';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.macros.where(name: ${JSON.stringify(NOME_MACRO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar e editar uma Macro',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações, Macros',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/macros/new`,
    aguardarTexto: 'Nome da macro',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Dê um nome à macro',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Digite um nome para sua macro"]' },
    texto: [NOME_MACRO],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a Visibilidade da Macro',
    acao: 'mover e clicar',
    alvo: { texto: 'Privada' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra a primeira ação',
    acao: 'mover e clicar',
    alvo: { texto: 'Atribuir um Time' },
    zoom: 1.6,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escolha Adicionar uma Etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar uma Etiqueta' },
    zoom: 1.6,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Abra o campo da etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecione uma opção...' },
    zoom: 1.6,
    pausaAntesMs: 700,
    pausaDepoisMs: 500,
  },
  {
    legenda: 'Escolha a etiqueta sinistro',
    acao: 'mover e clicar',
    alvo: { texto: 'sinistro' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar macro',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar macro' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
