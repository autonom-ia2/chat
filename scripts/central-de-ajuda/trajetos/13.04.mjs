// Roteiro do vídeo de trajeto do artigo 13.04 — "Importar, confirmar e
// desfazer uma base de campanha". Refeito no P2 (o do P1 ficava parado em
// "Enviada" por falta de Sidekiq — nunca mostrava confirmar nem desfazer).
//
// Sem Sidekiq no dev, nenhuma fila termina sozinha: a base enviada AO VIVO
// (cena de upload, com anexarArquivo) fica em "Enviada" para sempre, como
// no P1 — é o comportamento real deste ambiente, não escondemos isso. Para
// mostrar confirmar e desfazer de verdade, o `preparar` cria DUAS outras
// bases chamando os services do próprio produto direto (sem passar pelo
// ActiveJob/Sidekiq):
//   - CampaignImports::Validator  → deixa uma base "Pronta para confirmar"
//   - CampaignImports::Importer   → deixa outra "Concluída" (já com
//     contatos e labels de verdade), pronta para "Desfazer labels"
// Os cliques de Importar e Desfazer labels na gravação são reais: batem no
// controller de verdade (CampaignImportsController#confirm/#undo_labels),
// que muda o status na hora (queued / undoing_labels) ANTES de enfileirar
// o job — por isso a transição aparece no vídeo mesmo sem worker. O vídeo
// para exatamente aí: sem Sidekiq, nenhuma das duas avança further que
// isso, e é esse o ponto real onde o produto pausa neste ambiente.

export const id = '13.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const CSV_LOCAL =
  '/private/tmp/claude-501/-Users-rodrigosilva-dev-projetos-noindex-chat2you/a9e1eafb-5894-4277-af99-55ee38fe4e69/scratchpad/base-campanha-13.04.csv';

const NOME_CAMPANHA_AO_VIVO = 'campanha_renovacao_dezembro';
const NOME_CAMPANHA_PRONTA = 'campanha_fidelizacao_novembro';
const NOME_CAMPANHA_CONCLUIDA = 'campanha_boasvindas_setembro';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

nomes_do_video = ${JSON.stringify([NOME_CAMPANHA_AO_VIVO, NOME_CAMPANHA_PRONTA, NOME_CAMPANHA_CONCLUIDA])}

# Idempotente: apaga só o que este roteiro criou em execuções anteriores
# (bases com esses nomes, os contatos que elas importaram e as labels que
# criaram) — nunca mexe em base, contato ou label de outro vídeo.
conta.campaign_imports.where(campaign_name: nomes_do_video).find_each do |ci|
  ci.campaign_import_rows.where.not(contact_id: nil).find_each do |row|
    Contact.find_by(id: row.contact_id)&.destroy
  end
  ci.campaign_import_labels.find_each { |l| l.label&.destroy }
  ci.destroy
end

def montar_base!(conta, usuaria, nome_campanha, nome_arquivo, csv)
  ci = conta.campaign_imports.create!(
    user: usuaria,
    status: :uploaded,
    mode: "batches",
    campaign_name: nome_campanha,
    batch_count: 1,
    source_filename: nome_arquivo,
    source_content_type: "text/csv",
    source_byte_size: csv.bytesize,
    source_format: "csv",
    options: { "default_country" => "BR", "requested_batch_count" => 1 }
  )
  ci.original_file.attach(io: StringIO.new(csv), filename: nome_arquivo, content_type: "text/csv")
  ci
end

# Base B: fica "Pronta para confirmar" — roda o service de validação de
# verdade (o mesmo que o ValidateJob chamaria), só que direto, sem fila.
csv_pronta = "nome,telefone\\nBeatriz Andrade,11982200101\\nDiego Martins,11982200102\\nLarissa Gomes,11982200103\\n"
ci_pronta = montar_base!(conta, usuaria, ${JSON.stringify(NOME_CAMPANHA_PRONTA)}, "fidelizacao_novembro.csv", csv_pronta)
CampaignImports::Validator.new(ci_pronta).perform
ci_pronta.reload
raise "base pronta ficou em #{ci_pronta.status}, não ready_to_confirm" unless ci_pronta.ready_to_confirm?

# Base C: fica "Concluída" — valida e importa de verdade (mesmo service do
# ImportJob), criando os contatos e aplicando as labels, para o botão
# Desfazer labels ter o que desfazer.
csv_concluida = "nome,telefone\\nIgor Teixeira,11982210201\\nPatricia Nogueira,11982210202\\n"
ci_concluida = montar_base!(conta, usuaria, ${JSON.stringify(NOME_CAMPANHA_CONCLUIDA)}, "boasvindas_setembro.csv", csv_concluida)
CampaignImports::Validator.new(ci_concluida).perform
ci_concluida.reload
raise "base concluída não validou (#{ci_concluida.status})" unless ci_concluida.ready_to_confirm?
CampaignImports::Importer.new(ci_concluida).perform
ci_concluida.reload
raise "base concluída ficou em #{ci_concluida.status}, não completed" unless ci_concluida.completed?

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Importar, confirmar e desfazer uma base',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1200,
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
    legenda: 'Clique em Base Campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Base Campanha' },
    zoom: 1.6,
  },
  {
    legenda: 'Dê um nome para a campanha',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: campanha_junho_whatsapp"]' },
    texto: [NOME_CAMPANHA_AO_VIVO],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o CSV ou XLSX',
    acao: 'anexarArquivo',
    alvo: { texto: 'Escolher arquivo' },
    seletorArquivo: 'input[type="file"]',
    arquivo: CSV_LOCAL,
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Validar base',
    acao: 'mover e clicar',
    alvo: { texto: 'Validar base' },
    zoom: 1.8,
    // O clique fecha o diálogo e navega pro Histórico de bases (rota nova)
    // — espera o nome da campanha recém-criada aparecer lá antes de seguir.
    aguardarTextoDepois: NOME_CAMPANHA_AO_VIVO,
    pausaDepoisMs: 300,
  },
  {
    // Sem worker, a base recém-enviada não sai de "Enviada" — é o ponto
    // real onde ESTA base para (mesma lição do P1). O resto do vídeo usa
    // duas bases que o `preparar` já deixou prontas, pelos services de
    // verdade, para mostrar confirmar e desfazer sem depender de fila.
    legenda: 'Sem worker, essa fica Enviada',
    acao: 'parar',
    alvo: {
      texto: 'Enviada',
      dentro: { texto: NOME_CAMPANHA_AO_VIVO, subindoAte: 'tr' },
    },
    zoom: 1.3,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Importar numa base pronta',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Importar',
      dentro: { texto: NOME_CAMPANHA_PRONTA, subindoAte: 'tr' },
    },
    zoom: 1.8,
    aguardarTextoDepois: 'Na fila',
    pausaDepoisMs: 300,
  },
  {
    legenda: 'A importação entra na fila',
    acao: 'parar',
    alvo: {
      texto: 'Na fila',
      dentro: { texto: NOME_CAMPANHA_PRONTA, subindoAte: 'tr' },
    },
    zoom: 1.4,
    duracaoMs: 900,
  },
  {
    legenda: 'Clique em Desfazer labels numa base concluída',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Desfazer labels',
      dentro: { texto: NOME_CAMPANHA_CONCLUIDA, subindoAte: 'tr' },
    },
    zoom: 1.8,
  },
  {
    legenda: 'Confirme para desfazer',
    acao: 'mover e clicar',
    alvo: { seletor: 'dialog[open] button[type="submit"]' },
    zoom: 1.6,
    aguardarTextoDepois: 'Desfazendo labels',
    pausaDepoisMs: 300,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: {
      texto: 'Desfazendo labels',
      dentro: { texto: NOME_CAMPANHA_CONCLUIDA, subindoAte: 'tr' },
    },
    zoom: 1.4,
    duracaoMs: 1200,
  },
];
