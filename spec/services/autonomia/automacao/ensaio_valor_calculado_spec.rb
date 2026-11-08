require 'rails_helper'

# G16 do #2414 no ensaio: a ação com valor calculado mostra o valor que daria agora (a data com o "hoje" de agora, no
# fuso da conta), sem gravar nada; pula como o motor pularia.
RSpec.describe Autonomia::Automacao::Ensaio, :automacao_motor do
  let(:account) { create(:account, custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let!(:conversa) { create(:conversation, account: account, contact: contato, status: :resolved) }

  before do
    ligar_motor(account)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'revisao',
                                         attribute_display_type: :date)
  end

  def acao(custom_attributes)
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
      'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'merge' => true, 'custom_attributes' => custom_attributes } }
  end

  def passo_ensaiado(passo)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
    described_class.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos].first
  end

  it 'mostra a data que daria agora e o texto com os dados da conversa, sem gravar', :aggregate_failures do
    revisao = { '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } }
    nota = { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] }

    passo = travel_to(Time.utc(2026, 11, 5, 1, 30)) { passo_ensaiado(acao('revisao' => revisao, 'nota' => nota)) }

    expect(passo).to eq(id: 'p1', tipo: 'acao', faria: 'acao',
                        dados: { calculados: [{ campo: 'revisao', valor: '2027-05-04' }, { campo: 'nota', valor: 'indicado por Maria' }] })
    expect(conversa.reload.custom_attributes).to eq({})
  end

  it 'valor vazio: diria que pula, como o motor' do
    contato.update!(name: '')

    expect(passo_ensaiado(acao('nota' => { '$valor' => 'contato.nome' }))[:faria]).to eq('faltou_valor')
  end

  it 'valor fora das opções do campo: diria que pula' do
    conversa.update!(custom_attributes: { 'nivel' => 'altissima' })
    prioridade = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/toggle_priority', 'descricao' => 'Prioridade',
                   'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'priority' => { '$valor' => 'conversa.atributos.nivel' } } }

    expect(passo_ensaiado(prioridade)[:faria]).to eq('valor_fora_do_formato')
  end

  it 'valor vazio no caminho da ação: diria que pula, como o motor, também com corpo literal' do
    sem_time = acao('origem' => 'site').merge('caminho' => { 'id' => { '$valor' => 'conversa.time_id' } })

    expect(passo_ensaiado(sem_time)[:faria]).to eq('faltou_valor')
  end

  it 'a ação de corpo literal continua só mostrada' do
    expect(passo_ensaiado(acao('origem' => 'site'))).to eq(id: 'p1', tipo: 'acao', faria: 'acao', dados: {})
  end
end
