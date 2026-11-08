require 'rails_helper'

# G19 do fechamento do #2414 (#2636): a automação deixa uma nota no contato, pela mesma porta da tela de notas. Passo do
# exemplo 5 ("anotar a próxima revisão no contato") e do exemplo 19 ("anotar que o número parou de receber"). A nota sai
# no nome de quem ligou; mudar e apagar nota ficam fora da lista.
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

  it 'mudar e apagar nota não viram passo: a receita recusa ao salvar' do
    acoes = ['PATCH contacts/:contact_id/notes/:id', 'PUT contacts/:contact_id/notes/:id', 'DELETE contacts/:contact_id/notes/:id']
    passos = acoes.map.with_index do |acao, indice|
      { 'id' => "x#{indice}", 'tipo' => 'acao', 'acao' => acao, 'descricao' => 'Mexer na nota',
        'caminho' => { 'contact_id' => { '$valor' => 'contato.id' }, 'id' => 1 }, 'corpo' => { 'content' => 'outra' } }
    end
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }

    problemas = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

    esperados = acoes.map.with_index { |acao, indice| I18n.t('autonomia.automacao.receita.acao_fora', passo: "x#{indice}", acao: acao) }
    expect(problemas).to include(*esperados)
  end

  it 'versão salva fora do editor com "mudar nota": o motor recusa ao rodar e a nota fica como estava', :aggregate_failures do
    nota = contato.notes.create!(content: 'Original', user: admin)
    automacao = automacao_ligada(account, admin, [nota_passo('Nova')])
    antiga = automacao.versao_ativa.receita.deep_dup
    antiga['passos'][0].merge!('acao' => 'PATCH contacts/:contact_id/notes/:id',
                               'caminho' => { 'contact_id' => { '$valor' => 'contato.id' }, 'id' => nota.id })
    # Montada fora do editor: a validação de hoje não a deixaria salvar, e a versão é só leitura.
    Autonomia::Automacao::Versao.where(id: automacao.versao_ativa_id).update_all(receita: antiga) # rubocop:disable Rails/SkipsModelValidations

    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }

    expect(registros(execucao)).to eq([%w[p1 falhou acao_recusada]])
    expect(nota.reload.content).to eq('Original')
  end
end
