require 'rails_helper'

# G16 do fechamento do #2414: a ação grava um valor calculado na hora, pela porta da frente. Passo 3 do exemplo 5
# ("revisão: hoje + 6 meses") e passo 3 do exemplo 11 ("indicado por {nome}"); o vazio pula, e o valor que não cabe no
# campo (fora da lista) pula sem gravar.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }

  before do
    ligar_motor(account)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'revisao',
                                         attribute_display_type: :date)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'nivel',
                                         attribute_display_type: :text)
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'indicado_por',
                                         attribute_display_type: :text)
  end

  after { Current.reset }

  def rodar(*passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, passos), conversa) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def revisao_passo(origem = 'hoje')
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Marcar a revisão',
      'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
      'corpo' => { 'merge' => true,
                   'custom_attributes' => { 'revisao' => { '$data' => { 'de' => origem, 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } } } } }
  end

  def indicacao_passo
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH contacts/:id', 'descricao' => 'Anotar quem indicou',
      'caminho' => { 'id' => { '$valor' => 'contato.id' } },
      'corpo' => { 'custom_attributes' => { 'indicado_por' => { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] } } } }
  end

  it 'exemplo 5: grava "hoje + 6 meses" no atributo de data, com o "hoje" da execução no fuso da conta', :aggregate_failures do
    travel_to(Time.utc(2026, 11, 5, 1, 30)) do # 22h30 do dia 4 em São Paulo
      execucao = rodar(revisao_passo).reload

      expect([execucao.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
      expect(conversa.reload.custom_attributes['revisao']).to eq('2027-05-04')
    end
  end

  it 'exemplo 11: grava "indicado por {nome}" no atributo do contato, sem apagar os outros' do
    contato.update!(custom_attributes: { 'placa' => 'ABC1D23' })

    rodar(indicacao_passo)

    expect(contato.reload.custom_attributes).to eq('placa' => 'ABC1D23', 'indicado_por' => 'indicado por Maria')
  end

  it 'valor vazio pula a ação, sem gravar o texto pela metade', :aggregate_failures do
    contato.update!(name: '')

    execucao = rodar(indicacao_passo)

    expect(registros(execucao)).to eq([%w[p1 pulado faltou_valor]])
    expect(contato.reload.custom_attributes).not_to have_key('indicado_por')
  end

  it 'data lida que não é data: pula com o motivo, sem gravar', :aggregate_failures do
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'entrega',
                                         attribute_display_type: :date)
    conversa.update!(custom_attributes: { 'entrega' => 'semana que vem' })

    execucao = rodar(revisao_passo({ '$valor' => 'conversa.atributos.entrega' }))

    expect(registros(execucao)).to eq([%w[p1 pulado data_invalida]])
    expect(conversa.reload.custom_attributes).not_to have_key('revisao')
  end

  describe 'no card (exemplo 5 inteiro: card ganho, revisão no atributo de data do card)' do
    around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

    let(:funil) { create_crm_pipeline(account: account, user: admin) }
    let(:card) do
      account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Revisão', currency: 'BRL', primary_conversation: conversa,
                                contact: contato, custom_attributes: { 'placa' => 'ABC1D23' })
    end
    let(:revisao_no_card) do
      { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Marcar a revisão',
        'caminho' => { 'id' => { '$valor' => 'card.id' } },
        'corpo' => { 'card' => { 'custom_attributes' => { 'revisao' => seis_meses } } } }
    end
    let(:seis_meses) { { '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } } }

    before do
      account.enable_features!('automacao_gatilhos')
      create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'revisao',
                                           attribute_display_type: :date)
    end

    it 'grava "hoje + 6 meses" no card, sem apagar os outros atributos dele', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [revisao_no_card], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })

      travel_to(Time.utc(2026, 11, 5, 1, 30)) do
        execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, card) }.reload
        expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      end
      expect(card.reload.custom_attributes).to eq('placa' => 'ABC1D23', 'revisao' => '2027-05-04')
    end

    it 'valor de outro tipo num campo de data do card: pula, e a data do card fica como estava', :aggregate_failures do
      card.update!(expected_close_at: Time.zone.parse('2026-12-01'))
      titulo_na_data = revisao_no_card.merge('corpo' => { 'card' => { 'expected_close_at' => { '$valor' => 'card.titulo' } } })
      definicao = automacao_ligada(account, admin, [titulo_na_data], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })

      execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, card) }

      expect(registros(execucao)).to eq([%w[p1 pulado valor_fora_do_formato]])
      expect(card.reload.expected_close_at.to_date).to eq(Date.new(2026, 12, 1))
    end
  end

  describe 'valor de lista (enum) lido do alvo' do
    let(:prioridade) { prioridade_passo('p1', { '$valor' => 'conversa.atributos.nivel' }) }

    it 'fora das opções na hora de executar: pula com o motivo e nunca grava o valor inválido', :aggregate_failures do
      conversa.update!(custom_attributes: { 'nivel' => 'altissima' })

      execucao = rodar(prioridade).reload

      expect(registros(execucao)).to eq([%w[p1 pulado valor_fora_do_formato]])
      expect(Autonomia::Automacao::Registro.find_by(execucao: execucao).dados['problemas'].join).to include('altissima')
      expect(conversa.reload.priority).to be_nil
    end

    it 'dentro das opções: grava' do
      conversa.update!(custom_attributes: { 'nivel' => 'high' })

      rodar(prioridade)

      expect(conversa.reload.priority).to eq('high')
    end
  end
end
