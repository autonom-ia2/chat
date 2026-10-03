require 'rails_helper'

# A consulta do time a um relato sobre o Guia (#861), pelo rails runner.
RSpec.describe Autonomia::Guide::Investigacao do
  let(:conta) { create(:account) }
  let(:diagnostico) do
    { 'modelo' => 'gpt-5.6-sol', 'rodadas' => 2, 'custo_usd' => 0.0123, 'tokens' => { 'in' => 900, 'cached' => 0, 'out' => 80 },
      'chamadas' => [{ 'ferramenta' => 'ler_da_conta', 'args' => { 'recurso' => 'inboxes' }, 'ms' => 420, 'saida_chars' => 3100 }],
      'fluxos' => [{ 'id' => 12, 'titulo' => 'Caixas de entrada' }], 'confianca' => 0.71, 'grounded' => true }
  end
  let(:pessoa) { create(:user, account: conta) }
  let(:conversa) { Autonomia::Guide::Conversa.create!(account: conta, user: pessoa, titulo: 'caixas') }

  def turno(pergunta, resposta, diagnostico = {})
    registro = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: pergunta, tela: 'home')
    registro.update!(resposta: resposta, status: 'done', diagnostico: diagnostico)
    registro
  end

  it 'mostra a linha do tempo de um pedido', :aggregate_failures do
    alvo = turno('quantas caixas eu tenho?', 'Você tem 3 caixas.', diagnostico)

    texto = described_class.new(pedido_id: alvo.pedido_id).relatorio

    expect(texto).to include(alvo.pedido_id, 'quantas caixas eu tenho?', 'ler_da_conta', '{"recurso":"inboxes"}',
                             '#12 Caixas de entrada', 'US$ 0.0123', 'Você tem 3 caixas.')
  end

  it 'filtra pela conta e pela pessoa, no período', :aggregate_failures do
    turno('quantas caixas?', 'Três.')
    de_outra = Autonomia::Guide::Conversa.create!(account: create(:account), user: pessoa, titulo: 'x')
    Autonomia::Guide::Turno.abrir(conversa: de_outra, pedido_id: SecureRandom.uuid, pergunta: 'de outra conta', tela: nil)

    texto = described_class.new(account_id: conta.id, user_id: pessoa.id, desde: 1.day.ago).relatorio

    expect(texto).to include('quantas caixas?')
    expect(texto).not_to include('de outra conta')
  end

  it 'diz quando não acha nada' do
    expect(described_class.new(pedido_id: SecureRandom.uuid).relatorio).to eq('Nenhum pedido encontrado com esses filtros.')
  end

  it 'transforma a conversa do pedido num esqueleto de cenário da bateria', :aggregate_failures do
    turno('quantas caixas eu tenho?', 'Três.', diagnostico)
    alvo = turno('apaga a do instagram', 'Apaguei.')

    esqueleto = described_class.new(pedido_id: alvo.pedido_id).cenario

    expect(esqueleto).to include('r0 = perguntar("quantas caixas eu tenho?")',
                                 'r1 = perguntar("apaga a do instagram", historico: turno("quantas caixas eu tenho?", r0))',
                                 '#   inboxes', '# TODO: o estado final esperado', 'troque à mão')
  end
end
