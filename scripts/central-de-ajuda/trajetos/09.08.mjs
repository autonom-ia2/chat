// Roteiro do vídeo de trajeto do artigo 09.08 — "Mesclar e excluir
// contatos". Cobre só a mesclagem: é a parte que mais confunde (a direção
// decide quem sobrevive, sem confirmação nem desfazer, por isso o "Por que
// importa" do artigo é todo sobre esse risco). Excluir um contato é um
// clique simples e autoexplicativo (Excluir contato → Sim, excluir), e não
// coube dentro dos 40s do vídeo somado à mesclagem — o texto do artigo já
// cobre esse passo sozinho.
//
// Rótulos e seletores conferidos ao vivo no painel local (login Rafa Admin,
// conta 9) em 2026-09-23.
//
// Trajeto: Contatos → busca o duplicado → Ver detalhes → aba Mesclar →
// busca o principal → seleciona → Mesclar contatos.

export const id = '09.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const PRINCIPAL_NOME = 'Marcos Tavares';
const PRINCIPAL_EMAIL = 'marcos-tavares@desnorteada.test';
// Duplicado com o mesmo sobrenome e um erro de digitação — cenário comum de
// duplicidade real (a mesma pessoa cadastrada duas vezes).
const DUPLICADO_NOME = 'Marcos Tavarez';
const DUPLICADO_EMAIL = 'marcos-tavarez@desnorteada.test';
// "Marcos Tavares" é criado uma vez e nunca apagado entre gravações
// (find_or_create), então o ID dele no dev local é estável — conferido em
// 2026-09-23.
const PRINCIPAL_ID = 39;

// Roda antes de gravar: recria o contato duplicado deste vídeo do zero a
// cada gravação (a mesclagem o apaga) e garante o principal sem apagá-lo —
// idempotente, mexe só nos contatos que este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})

principal = conta.contacts.find_or_create_by!(email: ${JSON.stringify(PRINCIPAL_EMAIL)}) { |c| c.name = ${JSON.stringify(PRINCIPAL_NOME)} }
principal.update!(name: ${JSON.stringify(PRINCIPAL_NOME)})
raise "PRINCIPAL_ID desatualizado: esperava ${PRINCIPAL_ID}, achou #{principal.id}" unless principal.id == ${PRINCIPAL_ID}

conta.contacts.find_by(email: ${JSON.stringify(DUPLICADO_EMAIL)})&.destroy!
conta.contacts.create!(email: ${JSON.stringify(DUPLICADO_EMAIL)}, name: ${JSON.stringify(DUPLICADO_NOME)})

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Mesclar contatos duplicados',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 900,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra o contato duplicado',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [DUPLICADO_NOME],
    zoom: 1.8,
  },
  {
    legenda: 'Encontrado',
    acao: 'parar',
    alvo: { texto: 'Pesquisar contatos' },
    zoom: 1.6,
    duracaoMs: 600,
  },
  {
    legenda: 'Clique em Ver detalhes',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.6,
    // Navega para a página do contato: o alvo some da tela, e o motor gasta
    // até 3s tentando reachá-lo antes de desistir (comportamento do motor,
    // não mexido aqui).
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Abra a aba Mesclar',
    acao: 'mover e clicar',
    alvo: { texto: 'Mesclar' },
    zoom: 1.8,
  },
  {
    legenda: 'Busque o contato principal',
    acao: 'mover e clicar',
    alvo: { texto: 'Pesquisar contato principal' },
    zoom: 1.8,
  },
  {
    legenda: 'O que sobrevive é o que você busca',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar um contato"]' },
    texto: [PRINCIPAL_NOME],
    zoom: 1.8,
  },
  {
    legenda: 'Selecione o contato certo',
    acao: 'mover e clicar',
    alvo: { texto: `(ID: ${PRINCIPAL_ID}) ${PRINCIPAL_NOME}` },
    zoom: 1.6,
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'O aberto é o que é excluído',
    acao: 'parar',
    alvo: { texto: 'Para ser excluído' },
    zoom: 1.4,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Mesclar contatos',
    acao: 'mover e clicar',
    // Botão real de envio, não o título da seção (os dois têm o mesmo
    // texto "Mesclar contatos") — escopado pela linha de botões
    // Cancelar/Mesclar, não pelo texto.
    alvo: { seletor: '.flex.items-center.justify-between.gap-3 > button:last-child' },
    zoom: 1.6,
    // Sem tela de confirmação: mescla na hora e navega de volta para a
    // lista — mesmo ajuste de pausas da cena "Ver detalhes".
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Duplicado mesclado e removido',
    acao: 'parar',
    alvo: { texto: 'Nenhum contato corresponde à sua pesquisa 🔍' },
    zoom: 1.4,
    duracaoMs: 1200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 900,
  },
];
