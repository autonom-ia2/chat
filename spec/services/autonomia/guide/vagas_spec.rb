require 'rails_helper'

# As vagas dos trabalhos longos do Guia: a revisão de conversas (#3158, B8b) não toma a vaga da tarefa de escrita.
RSpec.describe Autonomia::Guide::Vagas do
  let(:account) { create(:account) }
  let(:trabalho) { Struct.new(:id, :account_id) }

  before do
    Redis::Alfred.delete(Autonomia::Guide::Tarefas::Semaforo::RODANDO)
    Redis::Alfred.delete("#{Autonomia::Guide::Revisoes::Semaforo::PREFIXO}:rodando")
  end

  after do
    Autonomia::Guide::Tarefas::Semaforo.sair(trabalho.new(1, account.id))
    Autonomia::Guide::Revisoes::Semaforo.sair(trabalho.new(1, account.id))
  end

  it 'deixa uma tarefa e uma revisão da mesma conta andarem juntas', :aggregate_failures do
    expect(Autonomia::Guide::Tarefas::Semaforo.entrar(trabalho.new(1, account.id))).to be(true)
    expect(Autonomia::Guide::Revisoes::Semaforo.entrar(trabalho.new(1, account.id))).to be(true)
  end

  it 'deixa só uma revisão por conta' do
    Autonomia::Guide::Revisoes::Semaforo.entrar(trabalho.new(1, account.id))

    expect(Autonomia::Guide::Revisoes::Semaforo.entrar(trabalho.new(2, account.id))).to be(false)
  end
end
