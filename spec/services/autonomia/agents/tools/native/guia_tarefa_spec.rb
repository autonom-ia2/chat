require 'rails_helper'

# A ferramenta `planejar_tarefa` (#936): planeja sem executar, devolve a amostra ao modelo e põe
# `tarefa: {id, status}` na resposta do turno, para a tela mostrar o cartão — também ao reabrir.
RSpec.describe Autonomia::Agents::Tools::Native::GuiaTarefa do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:contexto) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }

  before do
    simular_ia_do_cliente!
    contatos_em_maiusculas!(conta, 12)
  end

  def chamar(receita)
    described_class.new(agent: nil, operador: contexto, params: { 'receita_json' => receita.to_json }).call
  end

  it 'está entre as ferramentas do Guia' do
    expect(Autonomia::Guide::Seed::FERRAMENTAS).to include('planejar_tarefa')
    expect(Autonomia::Agents::Tools::Registry.find('planejar_tarefa')).to eq(described_class)
  end

  it 'planeja, avisa que nada mudou e deixa a tarefa no turno', :aggregate_failures do
    saida = chamar(receita_de_nomes)

    tarefa = Autonomia::Guide::Tarefa.last
    expect(saida).to include('NADA foi mudado', '"total":12')
    expect(contexto.tarefa).to eq('id' => tarefa.id, 'status' => 'amostra_pronta')
    expect(contexto.leu?(tarefa.id)).to be(true)
  end

  it 'devolve a recusa ao modelo, em pt-BR' do
    expect(chamar(receita_de_nomes('acao' => 'POST contacts/:id/call'))).to start_with('Não planejei:')
  end

  it 'leva a tarefa para a conversa guardada', :aggregate_failures do
    conversa = Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 'Nomes')
    turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'arruma os nomes', tela: nil)
    contexto_do_turno = Autonomia::Guide::Contexto.new(account: conta, user: admin, turno_id: turno.id)

    described_class.new(agent: nil, operador: contexto_do_turno, params: { 'receita_json' => receita_de_nomes.to_json }).call

    expect(turno.reload.para_tela['tarefa']).to eq('id' => Autonomia::Guide::Tarefa.last.id, 'status' => 'amostra_pronta')
  end

  it 'manda a tarefa na resposta do turno' do
    expect(Autonomia::Guide::Chat::Result.members).to include(:tarefa)
  end
end
