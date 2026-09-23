// Roteiro do vídeo de trajeto do artigo 09.03 — "Criar e editar um
// contato". Rótulos conferidos ao vivo no painel local (login Rafa Admin,
// conta 9) em 2026-09-23.
//
// Trajeto: Contatos → menu de três pontinhos → Adicionar contato → nome e
// e-mail → Salvar contato → busca o contato criado → Ver detalhes → edita a
// cidade → Atualizar contato.

export const id = '09.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME = 'Carla';
const SOBRENOME = 'Mendes';
const EMAIL = 'carla-mendes@desnorteada.test';

// Roda antes de gravar: apaga o contato de teste deste vídeo se uma
// gravação anterior o deixou para trás — idempotente, mexe só no contato
// que este vídeo cria (nunca nos contatos fixos Pedro Alves, Sandra Reis,
// Marcos Lima, Joana Prado, usados por outros vídeos).
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
contato = conta.contacts.find_by(email: ${JSON.stringify(EMAIL)})
contato&.destroy!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar e editar um contato',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 800,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra o menu de três pontinhos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-ellipsis-vertical' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar contato' },
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o primeiro nome',
    acao: 'digitar',
    // Escopado em "dialog[open]": cada card da lista tem um formulário de
    // edição embutido (mesmos placeholders), escondido mas presente no DOM
    // — sem o escopo, o seletor por placeholder pode achar o campo errado
    // (de outro contato) em vez do diálogo "Adicionar contato" aberto.
    alvo: { seletor: 'dialog[open] input[placeholder="Digite o primeiro nome"]' },
    texto: [NOME],
    zoom: 1.8,
  },
  {
    legenda: 'Sobrenome é opcional',
    acao: 'digitar',
    alvo: { seletor: 'dialog[open] input[placeholder="Digite o sobrenome"]' },
    texto: [SOBRENOME],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o endereço de e-mail',
    acao: 'digitar',
    alvo: { seletor: 'dialog[open] input[placeholder="Digite o endereço de e-mail"]' },
    texto: [EMAIL],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar contato' },
    zoom: 1.6,
    // Pausas reduzidas só nesta cena: o clique fecha o diálogo na hora, e
    // depois o motor ainda gasta até 3s tentando reachar o alvo que sumiu
    // antes de desistir (comportamento do motor, não mexido aqui) — sem
    // encurtar as pausas próprias, o vídeo passa dos 40s. As outras cenas
    // mantêm o padrão de 1,2s/0,8s.
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    // Não mira no toast de sucesso: ele esvanece sozinho antes que sobre
    // tempo pra essa cena pegá-lo (ver nota acima). O card na lista com o
    // nome novo é uma confirmação igual de válida e não some da tela.
    legenda: 'Contato criado na lista',
    acao: 'parar',
    alvo: { texto: `${NOME} ${SOBRENOME}` },
    zoom: 1.4,
    duracaoMs: 1000,
  },
  {
    legenda: 'Busque o contato pelo nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [`${NOME} ${SOBRENOME}`],
    zoom: 1.8,
  },
  {
    legenda: 'Contato encontrado',
    acao: 'parar',
    alvo: { texto: 'Pesquisar contatos' },
    zoom: 1.6,
    duracaoMs: 500,
  },
  {
    legenda: 'Clique em Ver detalhes',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.6,
    // Mesmo motivo da cena "Salvar contato": este clique navega para a
    // página do contato, o alvo "Ver detalhes" some, e o motor gasta até 3s
    // tentando reachá-lo antes de desistir.
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Corrija os campos que precisar',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Digite o nome da cidade"]' },
    texto: ['Fortaleza'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar contato' },
    zoom: 1.6,
  },
  {
    legenda: 'Contato atualizado',
    acao: 'parar',
    alvo: { texto: 'Contato atualizado com sucesso' },
    zoom: 1.3,
    duracaoMs: 1000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 800,
  },
];
