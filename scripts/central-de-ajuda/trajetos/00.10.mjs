// Roteiro do vídeo de trajeto do artigo 00.10 — "Passo 9 — Ajustar a conta ao
// seu jeito". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/labelsMgmt.json.
//
// Trajeto: Configurações → Etiquetas → Adicionar etiqueta → nome → Criar.
// O artigo também aceita "ou resposta pronta", mas só um caminho fecha o
// passo — a etiqueta é o mais rápido de mostrar em vídeo.

export const id = '00.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Remove a etiqueta de exemplo de uma gravação anterior, para o nome poder
// ser criado de novo sem esbarrar na unicidade por conta.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.labels.where(title: "renovacao-anual").destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ajustar a conta ao seu jeito',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Configurações → Etiquetas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/labels/list`,
    aguardarTexto: 'Adicionar etiqueta',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique em Adicionar etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar etiqueta' },
    aguardarTextoDepois: 'Nome da Etiqueta',
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o nome',
    acao: 'digitar',
    alvo: { seletor: '[data-testid="label-title"]' },
    texto: ['renovacao-anual'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha uma cor',
    acao: 'parar',
    alvo: { texto: 'Cor' },
    zoom: 1.5,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Criar',
    acao: 'mover e clicar',
    alvo: { seletor: '[data-testid="label-submit"]' },
    aguardarTextoDepois: 'adicionada com sucesso',
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
