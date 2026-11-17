require 'rails_helper'

# E8 (#2901): cotar a renovação. Só cota com tudo o que a regra da Cotação pede, depois da conferência gratuita, e uma
# vez só; o que impede não cota, fica na história com o motivo (e os nomes dos campos que faltam) e avisa a equipe.
# ZERO chamada real: o portal é o conector falso, e a ferramenta de cotação é dublê onde o caminho chegaria a cotar.
RSpec.describe Carteira::Cotacao::Cotar do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa) }
  let(:quote) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:completa) do
    Carteira::Cotacao::Entrada::Resultado.new(produto: 'auto', faltam: [],
                                              params: { 'produto' => 'auto', 'item' => 'renovação carro', 'cpf' => '52998224725',
                                                        'nome' => 'Marina Exemplo', 'vehicle' => { 'plate' => 'ABC1D23' } })
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'corretora@exemplo.test', password: 'senha-exemplo')
    conexao.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    agente_de_cotacao(account)
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, ajustes)
    Carteira::Cotacao::ComecarJob.perform_now(seguro.id, seguro.fim_vigencia.iso8601)
  end

  def cotar(tentativa: 1)
    described_class.new(seguro.reload, ajustes.reload, tentativa: tentativa).call
  end

  def execucoes
    Autonomia::Agents::ToolRun.where(account_id: account.id, slug: quote.slug)
  end

  def nao_saiu
    seguro.eventos.where(tipo: 'proposta_nao_saiu').order(:id).last&.valores
  end

  # Com a carteira de hoje (sem bônus, nascimento, sexo, CEP nem placa), a renovação quase sempre para aqui.
  it 'faltou dado: não cota, guarda só os nomes dos campos que faltam e avisa a equipe com eles' do
    allow_any_instance_of(quote).to receive(:start).and_raise('não deveria cotar') # rubocop:disable RSpec/AnyInstance

    cotar

    expect(nao_saiu).to include('motivo' => 'faltou_dado')
    expect(nao_saiu['faltam']).to include('quotation.bonusClass', 'insured.document', 'insured.birthDate', 'insured.gender',
                                          'address.zipCode', 'vehicle.plate')
    expect(execucoes).to be_empty
    expect(tipos_da_historia(seguro)).not_to include('proposta_pedida')
    tarefa = Crm::FollowUp.where(account_id: account.id).find { |item| item.metadata['motivo'] == 'faltou_dado' }
    expect(tarefa.metadata['faltam']).to include('quotation.bonusClass')
    expect(tarefa.title).to include('classe de bônus')
  end

  it 'o código da seguradora anterior só pela lista da conexão: o nome que bate com um da lista não falta' do
    cotar

    expect(nao_saiu['faltam']).not_to include('quotation.previousInsurerCode')
  end

  it 'a seguradora que não bate com a lista falta (nada de chute)' do
    seguro.update!(seguradora: 'Seguradora Exemplo', seguradora_chave: Carteira::Chave.seguradora('Seguradora Exemplo'))

    cotar

    expect(nao_saiu['faltam']).to include('quotation.previousInsurerCode')
  end

  describe 'com a entrada completa' do
    before { allow_any_instance_of(Carteira::Cotacao::Entrada).to receive(:call).and_return(completa) } # rubocop:disable RSpec/AnyInstance

    it 'sem resposta em 3 dias: cota na conversa do contato com o Agente de Cotação, uma vez só, e acompanha' do
      allow_any_instance_of(quote).to receive_messages(precheck: nil, pedido: 'pedido-exemplo') # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(quote).to receive(:start).and_return('quote_id' => 'cotacao-exemplo') # rubocop:disable RSpec/AnyInstance

      expect { Carteira::Cotacao::SemRespostaJob.perform_now(seguro.id, seguro.fim_vigencia.iso8601) }
        .to have_enqueued_job(Carteira::Cotacao::AcompanharJob)
      cotar

      run = execucoes.sole
      expect(run).to have_attributes(status: 'running', notify_customer: false, expires_at: nil,
                                     autonomia_agent_id: Carteira::Cotacao.agente(account).id)
      expect(run.conversation).to have_attributes(contact_id: marina.id, inbox_id: caixa.id)
      expect(run.handle).to include('quote_id' => 'cotacao-exemplo')
      expect(seguro.eventos.where(tipo: 'proposta_pedida').count).to eq(1)
    end

    it 'conferência sem resposta: não cota, guarda o motivo e tenta de novo depois' do
      allow_any_instance_of(quote).to receive_messages(precheck: nil, pedido: nil) # rubocop:disable RSpec/AnyInstance

      expect { cotar }.to have_enqueued_job(Carteira::Cotacao::CotarJob).with(seguro.id, seguro.fim_vigencia.iso8601, 2)
      expect(nao_saiu).to include('motivo' => 'conferencia_caiu')
      expect(execucoes).to be_empty
      expect(Crm::FollowUp.where(account_id: account.id).map { |item| item.metadata['motivo'] }).not_to include('conferencia_caiu')
    end

    it 'na terceira tentativa sem conferência, não agenda outra e avisa a equipe' do
      allow_any_instance_of(quote).to receive_messages(precheck: nil, pedido: nil) # rubocop:disable RSpec/AnyInstance

      expect { cotar(tentativa: 3) }.not_to have_enqueued_job(Carteira::Cotacao::CotarJob)
      expect(Crm::FollowUp.where(account_id: account.id).map { |item| item.metadata['motivo'] }).to include('conferencia_caiu')
    end

    it 'a conferência diz que falta algo: não cota e lista o que falta' do
      conferencia = Autonomia::Agents::Tools::Native::Conferencia.new(texto: 'Falta.', faltando: ['insured.birthDate'], motivo: 'faltam_dados')
      allow_any_instance_of(quote).to receive(:precheck).and_return(conferencia) # rubocop:disable RSpec/AnyInstance

      cotar

      expect(nao_saiu).to include('motivo' => 'faltou_dado', 'faltam' => ['insured.birthDate'])
      expect(execucoes).to be_empty
    end

    it 'sem o modelo da proposta aprovado na caixa: não paga a cotação de uma proposta que não sairia' do
      aprovar_modelos(caixa, 'renovacao_algo_mudou')
      allow_any_instance_of(quote).to receive(:precheck).and_raise('não deveria conferir') # rubocop:disable RSpec/AnyInstance

      cotar

      expect(nao_saiu).to include('motivo' => 'envio', 'detalhe' => 'sem_modelo')
      expect(execucoes).to be_empty
    end
  end

  # A conferência de verdade da ferramenta: só o conferente (`quote/validate`) e a busca paga do segurado são do conector
  # falso; o resto que a ferramenta olha antes (ramo, formulário, consulta da placa) fica de fora.
  describe 'pela conferência da própria ferramenta' do
    let(:conector) { Autonomia::Insurance::Connector::Mock }
    let(:conferente_fora) { Autonomia::Insurance::Connector::Error.new(:timeout, 'conferente fora') }
    let(:entrada_completa) do
      segurado = { 'document' => '52998224725', 'name' => 'Marina Exemplo', 'birthDate' => '1990-01-01', 'gender' => 'F' }
      Carteira::Cotacao::Entrada::Resultado.new(produto: 'auto', faltam: [],
                                                params: { 'produto' => 'auto', 'item' => 'renovação carro', 'insured' => segurado,
                                                          'address' => { 'zipCode' => '01001000' },
                                                          'vehicle' => { 'plate' => 'ABC1D23' } })
    end

    # rubocop:disable RSpec/AnyInstance
    before do
      allow_any_instance_of(Carteira::Cotacao::Entrada).to receive(:call).and_return(entrada_completa)
      allow_any_instance_of(quote).to receive_messages(conferencia_sem_especialista: nil, recusa_de_entrada: nil,
                                                       recusa_do_envio: nil, problemas_locais: [])
      allow_any_instance_of(quote).to receive(:com_veiculo) { |_ferramenta, dados| dados }
    end

    it 'cota pela mesma conferência: o envio não chama o conferente de novo, e o que cairia ali não deixa sair sem conferir' do
      chamadas = 0
      allow_any_instance_of(conector).to receive(:quote_validate) do
        chamadas += 1
        raise conferente_fora if chamadas > 1

        { 'valido' => true, 'problemas' => [], 'entrada' => { 'insured' => { 'document' => '52998224725' } } }
      end
      allow_any_instance_of(quote).to receive(:submeter).and_return('quote_id' => 'cotacao-exemplo')

      cotar

      expect(chamadas).to eq(1)
      expect(execucoes.sole.handle).to include('quote_id' => 'cotacao-exemplo')
    end

    it 'o conferente fora: a cotação paga não sai' do
      allow_any_instance_of(conector).to receive(:quote_validate).and_raise(conferente_fora)
      expect_any_instance_of(quote).not_to receive(:submeter)

      cotar

      expect(nao_saiu).to include('motivo' => 'conferencia_caiu')
      expect(execucoes).to be_empty
    end

    it 'a busca paga do segurado nunca roda, nem nas três tentativas com o conferente fora' do
      allow_any_instance_of(conector).to receive(:quote_validate).and_raise(conferente_fora)
      expect_any_instance_of(conector).not_to receive(:quote_enrich)

      (1..3).each { |tentativa| cotar(tentativa: tentativa) }

      expect(seguro.eventos.where(tipo: 'proposta_nao_saiu').count).to eq(3)
      expect(execucoes).to be_empty
    end
    # rubocop:enable RSpec/AnyInstance
  end

  it 'sem o Agente de Cotação: não cota e avisa' do
    Autonomia::Agents::Agent.where(account_id: account.id).delete_all

    cotar

    expect(nao_saiu).to include('motivo' => 'sem_agente')
  end
end
