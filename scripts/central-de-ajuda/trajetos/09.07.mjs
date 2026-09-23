// Roteiro do vídeo de trajeto do artigo 09.07 — "Ações em massa,
// importar/exportar CSV e Base Campanha". Cobre só a primeira seção do
// "Como faz" (ações em massa: marcar contatos e aplicar etiqueta) — as
// seções de Importar contatos e Base Campanha exigem subir um arquivo
// CSV/XLSX, ação que o motor de gravação não tem (ver relatório).
//
// Trajeto: Contatos → busca pelos dois contatos de teste → marca os dois →
// Atribuir rótulo → escolhe uma etiqueta já existente na conta → confirma.

export const id = '09.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

// Casal fictício, mesmo sobrenome — dá um termo de busca comum e plausível
// (duas apólices da mesma família) para marcar os dois de uma vez.
const CONTATO_1 = 'Fábio Nogueira';
const CONTATO_2 = 'Patrícia Nogueira';
const EMAIL_1 = 'fabio-nogueira@desnorteada.test';
const EMAIL_2 = 'patricia-nogueira@desnorteada.test';

// Roda antes de gravar: garante os dois contatos de teste deste vídeo, sem
// etiqueta (para a cena de "aplicar etiqueta" partir de um estado limpo e
// idempotente). Não mexe em nenhum outro contato da conta — "vip" é uma
// etiqueta já existente na conta, só usada como exemplo aqui, nunca
// removida de quem já a tinha.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
[[${JSON.stringify(CONTATO_1)}, ${JSON.stringify(EMAIL_1)}],
 [${JSON.stringify(CONTATO_2)}, ${JSON.stringify(EMAIL_2)}]].each do |nome, email|
  contato = conta.contacts.find_or_create_by!(email: email) { |c| c.name = nome }
  contato.update!(name: nome)
  contato.label_list = []
  contato.save!
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ações em massa nos contatos',
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
    legenda: 'Busque os contatos que precisar',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: ['Nogueira'],
    zoom: 1.8,
  },
  {
    legenda: 'Marque os contatos que quer mudar',
    acao: 'mover e clicar',
    // Passar o mouse sobre o avatar revela a caixa de marcação — por isso o
    // alvo são as iniciais do avatar (sempre presentes), não a caixa em si
    // (que só existe no DOM depois do hover).
    alvo: { texto: 'FN' },
    zoom: 1.8,
  },
  {
    legenda: 'Marque quantos precisar',
    acao: 'mover e clicar',
    alvo: { texto: 'PN' },
    zoom: 1.8,
  },
  {
    legenda: 'Use a barra para aplicar etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Atribuir rótulo' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'vip' },
    zoom: 1.8,
  },
  {
    legenda: 'Confirme para aplicar aos selecionados',
    acao: 'mover e clicar',
    alvo: { texto: 'Atribuir etiquetas selecionadas' },
    zoom: 1.6,
    // O clique fecha o menu suspenso e limpa a seleção na hora — mesmo
    // ajuste de pausas do 09.03/09.02 para não passar dos 40s.
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1000,
  },
];
