// Roteiro do vídeo de trajeto do artigo 09.04 — "Etiquetas, bloqueio e
// notas do contato".
//
// Usa um contato próprio ("Eduardo Martins"), compartilhado com o 09.05
// (mesma pessoa, abas diferentes) — o `preparar` de cada vídeo só mexe no
// que é dele: este reseta etiquetas/bloqueio/notas (estado limpo pra
// mostrar os três "adicionar" ao vivo); o do 09.05 cuida de histórico e
// mídia, sem tocar aqui.

export const id = '09.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CONTATO = 'Eduardo Martins';
const TELEFONE_CONTATO = '+5511982250701';
const NOME_ETIQUETA = 'vip';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
contato = conta.contacts.find_or_initialize_by(phone_number: ${JSON.stringify(TELEFONE_CONTATO)})
contato.name = ${JSON.stringify(NOME_CONTATO)}
contato.blocked = false
contato.save!

# Idempotente: volta ao estado limpo (sem etiqueta, sem nota) — não mexe
# nas conversas/mídia que o 09.05 cria para este mesmo contato.
contato.label_list = []
contato.save!
Note.where(contact_id: contato.id, account_id: conta.id).delete_all

raise "etiqueta #{${JSON.stringify(NOME_ETIQUETA)}} não existe" unless conta.labels.exists?(title: ${JSON.stringify(NOME_ETIQUETA)})

puts "preparo-ok id=#{contato.id}"
`);
}

export const cenas = [
  {
    legenda: 'Etiquetas, bloqueio e notas do contato',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Busque o contato',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [NOME_CONTATO],
    zoom: 1.8,
  },
  {
    legenda: 'Abra o contato',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CONTATO },
    zoom: 1.6,
  },
  {
    legenda: 'Veja os detalhes',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique no ícone de adicionar etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'etiqueta' },
    zoom: 2,
  },
  {
    legenda: 'Escolha entre as etiquetas já existentes',
    acao: 'mover e clicar',
    alvo: { texto: NOME_ETIQUETA },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Bloquear contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Bloquear contato' },
    zoom: 1.6,
    aguardarTextoDepois: 'Desbloquear contato',
  },
  {
    legenda: 'O efeito é imediato',
    acao: 'parar',
    alvo: { texto: 'Desbloquear contato' },
    zoom: 1.5,
    duracaoMs: 1000,
  },
  {
    legenda: 'Abra a aba Notas',
    acao: 'mover e clicar',
    alvo: { texto: 'Notas' },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva a nota',
    acao: 'digitar',
    alvo: { seletor: '.ProseMirror' },
    texto: ['Cliente indicado por parceiro. Confirmar dados antes de cotar.'],
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar nota',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar nota' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1200,
  },
];
