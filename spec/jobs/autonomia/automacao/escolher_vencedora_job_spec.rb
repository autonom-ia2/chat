require 'rails_helper'

# #3099: o cron escolhe a versão que fica nos passos com duas versões da Automação livre. O passo que saiu da receita
# não é escolhido, e um teste com problema não segura os outros.
RSpec.describe Autonomia::Automacao::EscolherVencedoraJob, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:regra) { { 'criterio' => 'respostas', 'divisao' => 50, 'espera' => 4 } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    stub_const('Autonomia::Automacao::DuasVersoes::MINIMO_POR_VERSAO', 2)
  end

  def com_versoes(id) = mensagem_passo(id, 'Oi').merge('versoes' => regra.merge('texto' => ['Olá'], 'modelo' => nil))

  def automacao_com(*passos)
    automacao = create(:autonomia_automacao, account: account)
    travel_to(1.day.ago) do
      automacao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: admin)
    end
    automacao
  end

  def envios(automacao, passo)
    [1, 1, 2, 2].each do |versao|
      contato = create(:contact, account: account)
      Autonomia::Automacao::VersaoEnvio.create!(account: account, automacao: automacao, passo: passo, alvo_type: 'Contact',
                                                alvo_id: contato.id, contact: contato, versao: versao, created_at: 10.hours.ago)
    end
  end

  def linha(automacao, passo) = Autonomia::Automacao::VersaoVencedora.find_by!(automacao_id: automacao.id, passo: passo)

  it 'depois da espera, poucas respostas: fica a versão 1 (empate)' do
    automacao = automacao_com(com_versoes('p1'))
    envios(automacao, 'p1')

    described_class.perform_now

    expect(linha(automacao, 'p1')).to have_attributes(vencedora: 1, escolhida_por: 'empate')
  end

  it 'não escolhe no passo que saiu da receita' do
    automacao = automacao_com(com_versoes('p1'))
    envios(automacao, 'p1')
    automacao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [mensagem_passo('p2', 'Oi')] },
                             autor: admin)

    described_class.perform_now

    expect(linha(automacao, 'p1').vencedora).to be_nil
  end

  it 'um teste que quebra vai ao log e não segura os outros', :aggregate_failures do
    quebra = automacao_com(com_versoes('p1'))
    envios(quebra, 'p1')
    segue = automacao_com(com_versoes('p1'))
    envios(segue, 'p1')
    allow(Autonomia::Automacao::DuasVersoes).to receive(:passo_ativo).and_call_original
    allow(Autonomia::Automacao::DuasVersoes).to receive(:passo_ativo).with(have_attributes(id: quebra.id), 'p1').and_raise('falhou')
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(linha(segue, 'p1').vencedora).to eq(1)
    expect(Rails.logger).to have_received(:error).with(a_string_including('EscolherVencedoraJob', 'RuntimeError'))
  end
end
