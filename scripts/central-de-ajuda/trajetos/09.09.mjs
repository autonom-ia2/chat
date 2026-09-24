// Roteiro do vídeo de trajeto do artigo 09.09 — "Empresas: cadastro,
// edição e vínculo com contatos". Rótulos conferidos no código (i18n
// pt_BR/companies.json e componentes em
// app/javascript/dashboard/components-next/Companies/) em 2026-09-24.
//
// Trajeto: barra lateral → Empresas → menu de três pontinhos → Adicionar
// empresa → nome e domínio → Adicionar empresa (salvar) → ficha da empresa
// → aba Contatos → Adicionar contato → busca → Vincular contato.
//
// Achado de produto (não corrigido aqui, só registrado): o item do menu
// "Adicionar empresa" (COMPANIES.ACTIONS.CREATE) e o botão de salvar do
// diálogo (COMPANIES.CREATE.ACTIONS.SAVE) usam o MESMO texto — "Adicionar
// empresa" aparece duas vezes na tela em momentos diferentes.

export const id = '09.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3007';

const NOME_EMPRESA = 'Distribuidora Nordeste Ltda';
const DOMINIO_EMPRESA = 'distribuidoranordeste.test';
const NOME_CONTATO = 'Fernanda Castro';
const EMAIL_CONTATO = 'fernanda.castro@desnorteada.test';

// Roda antes de gravar (idempotente): apaga a empresa que este vídeo cria
// se uma gravação anterior a deixou para trás, e garante que o contato de
// exemplo exista, sem empresa vinculada (senão o combobox de busca não o
// mostra como candidato — CompanyContactsSidebar.vue filtra quem já está
// vinculado à empresa atual). Não mexe em nenhum outro contato ou empresa
// da conta 9.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
empresa = conta.companies.find_by(name: ${JSON.stringify(NOME_EMPRESA)})
empresa&.destroy!
contato = conta.contacts.find_or_initialize_by(email: ${JSON.stringify(EMAIL_CONTATO)})
contato.name = ${JSON.stringify(NOME_CONTATO)}
contato.company_id = nil
contato.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Cadastrar empresa e vincular contato',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 700,
  },
  {
    legenda: 'Abra Empresas',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Companies"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra o menu de três pontinhos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-ellipsis-vertical' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar empresa',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar empresa' },
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o nome da empresa',
    acao: 'digitar',
    alvo: { seletor: 'dialog[open] input[placeholder="Nome"]' },
    texto: [NOME_EMPRESA],
    zoom: 1.8,
  },
  {
    legenda: 'Domínio é opcional',
    acao: 'digitar',
    alvo: { seletor: 'dialog[open] input[placeholder="Domínio"]' },
    texto: [DOMINIO_EMPRESA],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar empresa',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar empresa' },
    zoom: 1.6,
    // O clique salva e navega para a ficha da empresa — mesmo ajuste de
    // pausas usado no 09.03 para "Ver detalhes" (o alvo some da tela antes
    // do motor desistir de tentar reachá-lo).
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Empresa criada',
    acao: 'parar',
    alvo: { texto: NOME_EMPRESA },
    zoom: 1.4,
    duracaoMs: 600,
  },
  {
    legenda: 'Abra a aba Contatos',
    acao: 'mover e clicar',
    // 3º botão do TabBar da barra lateral da ficha (Histórico, Notas,
    // Contatos, nessa ordem) — o rótulo muda com a contagem ("Contatos
    // (0)"), por isso a posição é mais estável que o texto aqui.
    alvo: { seletor: '.bg-n-alpha-black2 button:nth-of-type(3)' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar contato',
    acao: 'mover e clicar',
    // Escopado pela classe utilitária que só o combobox de vínculo tem
    // (o rótulo "Adicionar contato" também aparece, idêntico, no texto de
    // apoio acima do campo — por texto ficaria ambíguo).
    alvo: { seletor: 'div[class*="div>button]:bg-n-alpha-black2"] button' },
    zoom: 1.8,
  },
  {
    legenda: 'Pesquise o contato pelo nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar contatos..."]' },
    texto: [NOME_CONTATO],
    zoom: 1.8,
  },
  {
    legenda: 'Selecione o contato encontrado',
    acao: 'mover e clicar',
    alvo: { seletor: 'li[role="option"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Confirme em Vincular contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Vincular contato' },
    zoom: 1.6,
  },
  {
    // Não mira no toast (esvanece rápido): o e-mail do contato aparece
    // sozinho na lista de vinculados só depois que o vínculo é salvo, e
    // fica na tela — confirmação melhor que o toast.
    legenda: 'Contato vinculado à empresa',
    acao: 'parar',
    alvo: { texto: EMAIL_CONTATO },
    zoom: 1.4,
    duracaoMs: 600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 700,
  },
];
