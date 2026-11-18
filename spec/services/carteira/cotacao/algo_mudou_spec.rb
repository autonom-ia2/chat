require 'rails_helper'

# E8 (#2901): o "Algo mudou?". O "não saiu" cobre só o envio: a mensagem que saiu e só não teve a espera agendada não
# vira "não saiu" nem aviso à equipe; fica no log técnico, sem dado do cliente. Tudo fictício; a Meta é dublê.
RSpec.describe Carteira::Cotacao::AlgoMudou do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { por_em_renovacao(seguro, ajustes) }

  def perguntar
    described_class.new(seguro.reload, ajustes.reload).call
  end

  def avisos
    Crm::FollowUp.where(account_id: account.id).map { |tarefa| tarefa.metadata['motivo'] }
  end

  it 'saiu e só a espera não foi agendada: não vira "não saiu", a equipe não é avisada e o log não leva dado do cliente' do
    aprovar_modelos(caixa, 'renovacao_algo_mudou')
    allow(Carteira::Cotacao::SemRespostaJob).to receive(:set).and_raise(StandardError, 'fila fora do ar')
    allow(Rails.logger).to receive(:error)

    perguntar

    expect(algo_mudou_de(seguro)).to be_present
    expect(tipos_da_historia(seguro)).not_to include('algo_mudou_nao_saiu')
    expect(avisos).not_to include('algo_mudou_nao_saiu')
    expect(Rails.logger).to have_received(:error).with("[carteira][cotacao] espera do algo mudou nao agendada apolice=#{seguro.id} StandardError")
  end

  it 'saiu: agenda a espera dos dias sem resposta' do
    aprovar_modelos(caixa, 'renovacao_algo_mudou')

    expect { perguntar }.to have_enqueued_job(Carteira::Cotacao::SemRespostaJob).with(seguro.id, seguro.fim_vigencia.iso8601)
  end

  it 'não saiu: fica na história com o motivo, avisa a equipe e não agenda a espera' do
    expect { perguntar }.not_to have_enqueued_job(Carteira::Cotacao::SemRespostaJob)

    expect(seguro.eventos.find_by(tipo: 'algo_mudou_nao_saiu').valores).to include('motivo' => 'sem_modelo')
    expect(avisos).to include('algo_mudou_nao_saiu')
  end
end
