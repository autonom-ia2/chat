// Roteiro do vídeo de trajeto do artigo 05.05 — "Atribuir e ver conversas
// por time". A seção "Times" da barra lateral só aparece para quem é membro
// de pelo menos um time (regra do próprio artigo) — o preparar garante que
// Lia Admin seja membro do time "vendas" (idempotente, só adiciona).
//
// O campo "Time atribuído" (dentro de Ações da conversa) usa o mesmo
// componente MultiselectDropdown do campo "Agente atribuído" logo acima,
// os dois mostram o texto genérico "Nenhum" quando vazios — não dá para
// mirar por texto (ambíguo) nem por posição (cada um fica dentro do seu
// próprio wrapper, sem índice comum). O vídeo por isso mostra o campo
// (cumpre "clique no campo Time atribuído e veja a lista") sem completar a
// escolha, e cobre a parte de "ver conversas por time" clicando de verdade
// no time na barra lateral, que tem um seletor estável (rota do time).
//
// Trajeto: tela de Conversas → aba Todos → abre um card qualquer →
// Contatos → Ações da conversa (mostra Time atribuído) → clique no time
// "vendas" na barra lateral.

export const id = '05.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
time = conta.teams.find_by!(name: "vendas")
time.team_members.find_or_create_by!(user_id: usuaria.id)
puts "preparo-ok time-id=#{time.id}"
`);
}

export const cenas = [
  {
    legenda: 'Atribuir e ver conversas por time',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra uma conversa qualquer',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-user-bold' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Ações da conversa',
    acao: 'mover e clicar',
    alvo: { texto: 'Ações da conversa' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja o campo Time atribuído',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique num time para ver',
    acao: 'mover e clicar',
    alvo: { seletor: 'a[href="/app/accounts/9/team/1"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja as conversas atribuídas ao time',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
