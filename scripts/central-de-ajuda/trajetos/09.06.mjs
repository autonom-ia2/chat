// Roteiro do vídeo de trajeto do artigo 09.06 — "Preencher atributos
// personalizados na ficha do contato". Rótulos e seletores conferidos ao
// vivo no painel local (login Rafa Admin, conta 9) em 2026-09-23.
//
// Trajeto: Contatos → busca o contato → Ver detalhes (aba Atributos já
// vem ativa) → clique no campo → digita o valor → confirma.

export const id = '09.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const CONTATO_NOME = 'Renata Cardoso';
const CONTATO_EMAIL = 'renata-cardoso@desnorteada.test';
const ATRIBUTO_CHAVE = 'plano';
const ATRIBUTO_NOME = 'Plano';
const VALOR = 'Seguro Auto Completo';

// Roda antes de gravar: garante o atributo personalizado "Plano" na conta
// (não apaga — é uma definição de conta, não um dado de teste isolado) e
// zera o valor no contato deste vídeo, para a cena de preencher partir de
// um campo vazio, de forma idempotente.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.custom_attribute_definitions.find_or_create_by!(attribute_key: ${JSON.stringify(ATRIBUTO_CHAVE)}, attribute_model: "contact_attribute") do |a|
  a.attribute_display_name = ${JSON.stringify(ATRIBUTO_NOME)}
  a.attribute_display_type = "text"
end
contato = conta.contacts.find_or_create_by!(email: ${JSON.stringify(CONTATO_EMAIL)}) { |c| c.name = ${JSON.stringify(CONTATO_NOME)} }
contato.update!(name: ${JSON.stringify(CONTATO_NOME)}, custom_attributes: {})
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Preencher atributos do contato',
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
    legenda: 'Abra o contato',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [CONTATO_NOME],
    zoom: 1.8,
  },
  {
    legenda: 'Encontrado',
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
    // Navega para a página do contato — mesmo ajuste de pausas usado nos
    // outros vídeos de Contatos (o alvo some da tela após o clique).
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Vá até a aba Atributos',
    acao: 'parar',
    alvo: { texto: ATRIBUTO_NOME },
    zoom: 1.6,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique no campo do atributo',
    acao: 'mover e clicar',
    alvo: { texto: 'Inserir valor' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o valor',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Inserir valor"]' },
    texto: [VALOR],
    zoom: 1.8,
  },
  {
    legenda: 'Confirme para salvar',
    acao: 'mover e clicar',
    // O ícone de confirmar (✓) também existe, escondido, em outro lugar da
    // página — escopado a "dentro de um botão" para não achar o errado.
    alvo: { seletor: 'button .i-lucide-check' },
    zoom: 1.8,
  },
  {
    legenda: 'Atributo preenchido',
    acao: 'parar',
    alvo: { texto: VALOR },
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
