require 'rails_helper'

# E8 (#2901): a cotação da renovação fechou. A melhor oferta (menor prêmio total) vira `proposta_pronta`, o PDF entra
# como anexo de nota privada na conversa, e a proposta só sai sozinha no modo `sozinho`: no `pessoa`, nada sai antes do
# clique. O card mostra a variação contra o ano passado. Tudo fictício; o download do PDF e a subida à Meta são dublês.
RSpec.describe Carteira::Cotacao::Pronta do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) do
    criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', valor_centavos: 200_000, fim_vigencia: 30.days.from_now.to_date)
  end
  let(:agente) { agente_de_cotacao(account) }
  let(:conversa) { Carteira::Cotacao::Envio.new(seguro.reload, ajustes).conversa }
  let(:ofertas) do
    { 'A1' => { 'nome' => 'Seguradora A', 'desfecho' => 'com_preco', 'premio' => { 'amount' => 2300.0, 'basis' => 'total' } },
      'B2' => { 'nome' => 'Seguradora B', 'desfecho' => 'com_preco', 'premio' => { 'amount' => 2100.5, 'basis' => 'total' } },
      'C3' => { 'nome' => 'Seguradora C', 'desfecho' => 'com_preco', 'premio' => { 'amount' => 150.0, 'basis' => 'monthly' } },
      'D4' => { 'nome' => 'Seguradora D', 'desfecho' => 'sem_proposta' } }
  end
  let(:arquivo) { { 'arquivo' => { 'url' => 'https://exemplo.test/comparativo.pdf', 'nome' => 'Comparativo de seguro, auto.pdf' } } }
  let(:pdf) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'Proposta de renovação.pdf',
                                           content_type: 'application/pdf')
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    allow_any_instance_of(Autonomia::Agents::Tools::EntregaDeArquivo).to receive(:gravar).and_return(pdf) # rubocop:disable RSpec/AnyInstance
    allow(Whatsapp::Templates::HeaderMedia).to receive(:dispatch_file)
      .and_return('media_url' => 'https://exemplo.test/proposta.pdf', 'media_name' => 'Proposta de renovação.pdf')
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
  end

  def ajustes(quem_envia: 'pessoa', quem_cota: 'robo')
    @ajustes ||= cotacao_ligada(account, user: admin, caixa: caixa, quem_envia: quem_envia, quem_cota: quem_cota).tap do |config|
      por_em_renovacao(seguro, config)
    end
  end

  def fechar(resultado: ofertas, entregas: [arquivo])
    handle = { 'quote_id' => 'cotacao-exemplo', 'resultado_por_seguradora' => resultado }
    run = Autonomia::Agents::ToolRun.create!(account: account, agent: agente, conversation_id: conversa.id, slug: 'cotar_seguro',
                                             status: 'running', execution_key: SecureRandom.uuid, handle: handle, arguments: {})
    described_class.new(seguro.reload, run, Autonomia::Agents::Tools::Progress.done(deliveries: entregas, handle: handle)).call
    run.reload
  end

  def proposta_enviada
    Message.where(account_id: account.id).find { |m| Carteira::Cotacao.marca_de(m)['etapa'] == 'proposta' }
  end

  it 'guarda a melhor oferta (o menor prêmio total) e o PDF como anexo de nota privada, e fecha a execução' do
    ajustes
    run = fechar

    pronta = seguro.eventos.find_by(tipo: 'proposta_pronta').valores
    expect(pronta).to include('premio_centavos' => 210_050, 'seguradora' => 'Seguradora B')
    nota = Message.find(pronta['nota'])
    expect(nota).to have_attributes(private: true, conversation_id: conversa.id)
    expect(nota.attachments.sole.file.blob).to eq(pdf)
    expect(run.status).to eq('done')
  end

  %w[robo lia].each do |quem_cota|
    it "#{quem_cota} × pessoa: nada sai antes do clique" do
      ajustes(quem_envia: 'pessoa', quem_cota: quem_cota)
      fechar

      expect(proposta_enviada).to be_nil
      expect(tipos_da_historia(seguro)).not_to include('proposta_enviada', 'proposta_enviada_sozinha')
    end

    it "#{quem_cota} × sozinho: a proposta sai sem clique, com o PDF no topo, pela caixa escolhida" do
      ajustes(quem_envia: 'sozinho', quem_cota: quem_cota)
      fechar

      expect(proposta_enviada).to have_attributes(inbox_id: caixa.id, sender_id: nil, private: false)
      expect(seguro.eventos.find_by(tipo: 'proposta_enviada_sozinha').valores['mensagem_id']).to eq(proposta_enviada.id)
      expect(Whatsapp::Templates::HeaderMedia).to have_received(:dispatch_file).with(pdf, caixa)
    end
  end

  it 'sem preço nenhum: proposta_nao_saiu sem_preco e aviso, sem nota' do
    ajustes
    fechar(resultado: { 'D4' => ofertas['D4'] }, entregas: [])

    expect(seguro.eventos.find_by(tipo: 'proposta_nao_saiu').valores).to include('motivo' => 'sem_preco')
    expect(tipos_da_historia(seguro)).not_to include('proposta_pronta')
  end

  it 'com preço e sem PDF: proposta_nao_saiu sem_pdf' do
    ajustes
    fechar(entregas: [])

    expect(seguro.eventos.find_by(tipo: 'proposta_nao_saiu').valores).to include('motivo' => 'sem_pdf')
  end

  describe 'no card do seguro (Carteira::Apresentacao)' do
    it 'a proposta contra o valor do ano passado: a variação em %, e pode enviar' do
      ajustes
      fechar

      cotacao = Carteira::Apresentacao.new(account).de(seguro.reload)[:cotacao]
      expect(cotacao).to include(etapa: 'proposta_pronta', premioCentavos: 210_050, seguradora: 'Seguradora B', variacaoPercentual: 5.0,
                                 podeEnviar: true, enviadaEm: nil)
    end

    it 'sem valor anterior, sem variação' do
      ajustes
      seguro.update!(valor_centavos: nil)
      fechar

      expect(Carteira::Apresentacao.new(account).de(seguro.reload)[:cotacao][:variacaoPercentual]).to be_nil
    end

    it 'sem a chave da cotação, o seguro vem no formato da E5 (sem a chave cotacao)' do
      ajustes
      Carteira::Cotacao::Liberada.desligar!(account)

      expect(Carteira::Apresentacao.new(account).de(seguro.reload)).not_to have_key(:cotacao)
    end
  end
end
