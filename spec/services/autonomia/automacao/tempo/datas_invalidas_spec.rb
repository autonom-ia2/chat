require 'rails_helper'

# #2556: o gatilho de data (Tempo::Data) deixa de fora o contato ou card cujo campo tem a data em outro formato. A
# varredura grava, uma vez por dia, quantos ficaram de fora e de qual campo, para o editor avisar o dono; nunca o valor,
# que é dado do cliente. Sem nenhum inválido, o aviso some.
RSpec.describe Autonomia::Automacao::Tempo::DatasInvalidas, :automacao_motor do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:passo) { { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } } }
  let(:gatilho) { { 'tipo' => 'contato.data', 'campo' => 'aniversario', 'dias' => 0, 'quando' => 'depois', 'hora' => 9 } }
  let(:definicao) { automacao_ligada(account, admin, [passo], gatilho: gatilho) }
  let(:valor_do_cliente) { '31/12/1990' }
  let!(:fora) { create(:contact, account: account, custom_attributes: { 'aniversario' => valor_do_cliente }) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    create(:custom_attribute_definition, account: account, attribute_key: 'aniversario', attribute_display_name: 'Aniversário',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'date')
    create(:contact, account: account, custom_attributes: { 'aniversario' => '1990-12-31' })
    create(:contact, account: account)
  end

  def varrer(agora: Time.current)
    Autonomia::Automacao::Tempo::Data.new(definicao: definicao, gatilho: definicao.versao_ativa.receita['gatilho'], agora: agora)
                                     .cada { |_alvo, _marca| nil }
  end

  def gravado = Redis::Alfred.get(described_class.chave(definicao.id))

  it 'grava quantos ficaram de fora e o campo pelo nome da tela, sem o valor do cliente', :aggregate_failures do
    varrer

    expect(described_class.para_tela(definicao)).to eq(quantos: 1, alvo: 'contato', campo: 'Aniversário')
    expect(JSON.parse(gravado)).to eq('quantos' => 1, 'tipo' => 'contato.data', 'campo' => 'aniversario',
                                      'dia' => Time.current.to_date.iso8601)
    expect(gravado).not_to include(valor_do_cliente)
    expect(Redis::Alfred.ttl(described_class.chave(definicao.id))).to be_between(1, described_class::VALIDADE.to_i)
  end

  it 'escreve no log só a contagem, sem o valor do cliente', :aggregate_failures do
    allow(Rails.logger).to receive(:warn)

    varrer

    expect(Rails.logger).to have_received(:warn).with(
      "[automacao][tempo] datas_invalidas conta=#{account.id} automacao=#{definicao.id} quantos=1"
    )
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including(valor_do_cliente))
  end

  it 'some na contagem do dia seguinte quando ninguém mais tem a data errada', :aggregate_failures do
    varrer
    fora.update!(custom_attributes: { 'aniversario' => '1990-12-31' })

    varrer(agora: 1.day.from_now)

    expect(gravado).to be_nil
    expect(described_class.para_tela(definicao)).to be_nil
  end

  it 'conta uma vez por dia: a segunda varredura do dia não refaz a contagem' do
    varrer
    fora.update!(custom_attributes: { 'aniversario' => '1990-12-31' })

    varrer

    expect(described_class.para_tela(definicao)).to include(quantos: 1)
  end

  it 'não avisa quando o gatilho de agora usa outro campo' do
    create(:custom_attribute_definition, account: account, attribute_key: 'vencimento', attribute_display_name: 'Vencimento',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'date')
    varrer

    definicao.salvar_versao!(receita: { 'gatilho' => gatilho.merge('campo' => 'vencimento'), 'passos' => [passo] }, autor: admin)

    expect(described_class.para_tela(definicao.reload)).to be_nil
  end

  it 'no gatilho do card, diz card e o nome do campo do card' do
    create(:custom_attribute_definition, account: account, attribute_key: 'renovacao', attribute_display_name: 'Renovação',
                                         attribute_model: 'card_attribute', attribute_display_type: 'date')
    do_card = automacao_ligada(account, admin, [passo], gatilho: gatilho.merge('tipo' => 'card.data', 'campo' => 'renovacao'))

    described_class.gravar(do_card, quantos: 12, tipo: 'card.data', campo: 'renovacao', dia: Time.current.to_date)

    expect(described_class.para_tela(do_card)).to eq(quantos: 12, alvo: 'card', campo: 'Renovação')
  end
end
