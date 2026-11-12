require 'rails_helper'

# G19 do fechamento do #2414 (#2636): a automação deixa uma nota no contato, pela mesma porta da tela de notas. Passo do
# exemplo 5 ("anotar a próxima revisão no contato") e do exemplo 19 ("anotar que o número parou de receber"). A nota sai
# no nome de quem ligou. Mudar e apagar nota entram pela D1 do #2660 (escolha do Rodrigo).
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }

  before { ligar_motor(account) }

  after { Current.reset }

  def rodar(*passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def nota_passo(content)
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST contacts/:contact_id/notes', 'descricao' => 'Anotar no contato',
      'caminho' => { 'contact_id' => { '$valor' => 'contato.id' } }, 'corpo' => { 'content' => content } }
  end

  it 'exemplo 19: deixa a nota no contato do alvo, no nome de quem ligou, com o valor lido na hora', :aggregate_failures do
    execucao = rodar(nota_passo({ '$texto' => ['O número de ', { '$valor' => 'contato.nome' }, ' parou de receber.'] })).reload

    expect([execucao.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
    expect(contato.notes.pluck(:content, :user_id)).to eq([['O número de Maria parou de receber.', admin.id]])
  end

  it 'a nota é do contato, não vira mensagem nem nota na conversa' do
    rodar(nota_passo('Próxima revisão em maio.'))

    expect([contato.notes.count, conversa.messages.count]).to eq([1, 0])
  end

  it 'valor vazio pula, sem nota pela metade', :aggregate_failures do
    contato.update!(name: '')

    execucao = rodar(nota_passo({ '$texto' => ['Ligar para ', { '$valor' => 'contato.nome' }] }))

    expect(registros(execucao)).to eq([%w[p1 pulado faltou_valor]])
    expect(contato.notes.count).to eq(0)
  end

  # #2660 D1: mudar e apagar nota entram, pela mesma porta da tela; o desfazer do Guia alcança os dois.
  it 'mudar e apagar nota viram passo: a receita aceita ao salvar' do
    pedidos = [['PATCH contacts/:contact_id/notes/:id', { 'content' => 'outra' }], ['PUT contacts/:contact_id/notes/:id', { 'content' => 'outra' }],
               ['DELETE contacts/:contact_id/notes/:id', nil]]
    passos = pedidos.map.with_index do |(acao, corpo), indice|
      { 'id' => "x#{indice}", 'tipo' => 'acao', 'acao' => acao, 'descricao' => 'Mexer na nota',
        'caminho' => { 'contact_id' => { '$valor' => 'contato.id' }, 'id' => 1 }, 'corpo' => corpo }.compact
    end
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }

    problemas = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

    recusas = passos.map { |passo| I18n.t('autonomia.automacao.receita.acao_fora', passo: passo['id'], acao: passo['acao']) }
    expect(problemas & recusas).to be_empty
  end

  it 'muda a nota, que passa a ser de quem ligou, e depois apaga', :aggregate_failures do
    nota = contato.notes.create!(content: 'Original', user: create(:user, account: account))
    caminho = { 'contact_id' => { '$valor' => 'contato.id' }, 'id' => nota.id }
    mudar = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH contacts/:contact_id/notes/:id', 'descricao' => 'Corrigir a nota',
              'caminho' => caminho, 'corpo' => { 'content' => 'Corrigida' } }
    apagar = { 'id' => 'p2', 'tipo' => 'acao', 'acao' => 'DELETE contacts/:contact_id/notes/:id', 'descricao' => 'Apagar a nota',
               'caminho' => caminho }

    expect(registros(rodar(mudar))).to eq([['p1', 'ok', nil]])
    expect([nota.reload.content, nota.user_id]).to eq(['Corrigida', admin.id])
    expect(registros(rodar(apagar))).to eq([['p2', 'ok', nil]])
    expect(contato.notes.exists?(nota.id)).to be(false)
  end
end
