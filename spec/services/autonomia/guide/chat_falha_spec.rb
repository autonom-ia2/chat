require 'rails_helper'

# Conserto pós-deploy do #3144: o Guia que caiu depois de mexer na conta devolvia "fora do ar" sem dizer o que fez.
# A tela não mostrava o "O que eu fiz" e oferecia "Tentar de novo" — que faria tudo outra vez.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:chat) { described_class.new(account: conta, user: admin, message: 'cria o contato Ana') }

  def ja_fez(passos)
    execucao = Autonomia::Guide::Execucao.abrir(account: conta, user: admin)
    passos.each { |acao| execucao.registrar_passo(acao: acao, frase: "fiz #{acao}", feito: true) }
    chat.send(:contexto).instance_variable_set(:@execucao, execucao)
    execucao
  end

  before { allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_raise(StandardError, 'caiu') }

  it 'caiu depois de mexer na conta: o fora do ar leva o que o Guia fez', :aggregate_failures do
    execucao = ja_fez(%w[criar_contato])

    resultado = chat.perform

    expect(resultado.available).to be(false)
    expect(resultado.execucao).to include('id' => execucao.id)
    expect(resultado.execucao['passos'].pluck('acao')).to eq(%w[criar_contato])
  end

  it 'caiu sem ter feito nada: o fora do ar vem sem execução' do
    ja_fez([])

    expect(chat.perform.execucao).to be_nil
  end
end
