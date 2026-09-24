// Roteiro do vídeo de trajeto do artigo 03.03 — "Auditoria: quem convidou
// quem e quem mudou o quê". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/auditLogs.json.
//
// A Auditoria só tem conteúdo real quando algo aconteceu de verdade (gem
// `audited`, model Enterprise::AuditLog) — sem Sidekiq no dev e sem poder
// chamar nada de fora, o jeito idempotente de garantir a lista cheia é
// gerar os dois eventos pelo `preparar`, com o model direto, dentro de
// `Enterprise::AuditLog.as_user(admin)` (mesmo helper que o controller usa
// em produção) para o autor ficar correto:
//   1. cria o AccountUser na primeira vez (dispara o evento "convidou ...
//      como agent" — fica pra sempre no histórico, não precisa recriar);
//   2. alterna o papel dele (agent → administrator → agent de volta) a
//      cada rodada, com o ATOR sendo a admin logada e o AFETADO sendo o
//      convidado — isso é o que o front chama de evento "OTHER" (admin
//      muda o papel de outra pessoa), o segundo tipo de frase que o
//      artigo descreve. Assim toda rodada deixa um evento OTHER fresco,
//      sem duplicar o convite.
// "Marcos Andrade" é reaproveitado entre gravações (find_or_initialize_by
// e-mail), nome fictício de agente, não de teste. O `preparar` NUNCA chama
// `User#destroy`: neste banco de dev, `User has_many :autonomia_user_links,
// dependent: :destroy` aponta pra uma tabela que não existe
// (`autonomia_user_links` — migração pendente, achado de ambiente, não
// deste vídeo), e destruir qualquer usuário estoura com "relation
// autonomia_user_links does not exist".
//
// Sob carga (três servidores + vários agentes mexendo na conta 9 ao mesmo
// tempo), criar o vínculo com find_or_initialize_by + save! correu risco
// real de `ActiveRecord::RecordNotUnique` (reproduzido nos
// testes deste roteiro: o mesmo par account_id/user_id foi inserido por
// fora, entre o find e o save, em pelo menos uma rodada) — por isso o
// bloco abaixo tem `rescue` e recupera o registro já existente em vez de
// falhar.
//
// Trajeto: Configurações → Auditoria → lista → busca por nome → filtro
// "Agentes" (grupo "Agentes e times").
//
// Achado de produto (não corrigido aqui): a busca da Auditoria
// (`Enterprise::AuditLog.search_by_user`, `enterprise/app/models/
// enterprise/audit_log.rb`) filtra pelo nome/e-mail de quem FEZ a ação
// (`audits.username`/`users.name` do autor), não da pessoa afetada. Buscar
// "Marcos Andrade" (o convidado) não acha os dois eventos que ele
// protagoniza — só buscar pela admin que agiu ("Lia Admin") acha. O
// vídeo busca pelo nome da admin (o comportamento real), não do
// convidado, pra não gravar uma busca que dá "0 resultados" sem motivo
// aparente.

export const id = '03.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3005';

const EMAIL_CONVIDADO = 'marcos.andrade@desnorteada.test';
const NOME_CONVIDADO = 'Marcos Andrade';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
admin = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "admin não encontrada" unless admin

email = ${JSON.stringify(EMAIL_CONVIDADO)}

Enterprise::AuditLog.as_user(admin) do
  convidado = User.find_or_initialize_by(email: email)
  convidado.name = ${JSON.stringify(NOME_CONVIDADO)}
  if convidado.new_record?
    convidado.password = "Corretora#Desnorteada2026"
    convidado.skip_confirmation!
  end
  convidado.save!

  au = nil
  begin
    au = AccountUser.find_or_initialize_by(account_id: account.id, user_id: convidado.id)
    novo = au.new_record?
    au.inviter_id = admin.id
    au.role = "agent"
    au.save! if novo
  rescue ActiveRecord::RecordNotUnique
    au = AccountUser.find_by!(account_id: account.id, user_id: convidado.id)
  end

  # Alterna o papel pra deixar um evento "OTHER" fresco a cada rodada, sem
  # recriar o vínculo (que já dispararia de novo o evento de convite).
  au.update!(role: "administrator")
  au.update!(role: "agent")
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ver quem convidou e quem mudou',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Configurações, Auditoria',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/audit-logs/list`,
    aguardarTexto: NOME_CONVIDADO,
    zoom: 1.2,
    duracaoMs: 1200,
  },
  {
    legenda: 'Veja a lista de eventos recentes',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Busque por nome ou e-mail',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar por nome ou e-mail"]' },
    texto: [login.usuarioNome],
    zoom: 1.8,
  },
  {
    legenda: 'Veja os eventos filtrados',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra o filtro de eventos',
    acao: 'mover e clicar',
    alvo: { texto: 'Todos os eventos' },
    // O título da seção some no innerText: o CSS (`uppercase`) transforma
    // "Agentes e times" em "AGENTES E TIMES" na leitura de tela do motor,
    // que usa innerText (respeita text-transform), não textContent — por
    // isso a espera usa um item de LISTA (não afetado por uppercase) que só
    // existe dentro do dropdown já aberto.
    aguardarTextoDepois: 'Membros do time',
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o filtro Agentes',
    acao: 'mover e clicar',
    // "Agentes" sozinho também é o nome do item do menu lateral — sem
    // `dentro`, o motor podia clicar nesse em vez do item do dropdown.
    // `dentro.subindoAte: 'div'` restringe a busca à seção "Agentes e
    // times" do próprio dropdown (o match por texto aqui usa textContent,
    // não innerText, então o `uppercase` do CSS não atrapalha).
    alvo: {
      texto: 'Agentes',
      dentro: { texto: 'Agentes e times', subindoAte: 'div' },
    },
    aguardarTextoDepois: NOME_CONVIDADO,
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2600,
  },
];
