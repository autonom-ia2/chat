require 'rails_helper'

# A conversa com o Guia (#861): de quem é, o que sai junto quando ela sai e o
# histórico que o Guia lê.
RSpec.describe Autonomia::Guide::Conversa do
  let(:conta) { create(:account) }
  let(:pessoa) { create(:user, account: conta) }
  let(:outra) { create(:user, account: conta) }

  def conversa_com(*idas_e_voltas, user: pessoa)
    conversa = Autonomia::Guide::Conversa.create!(account: conta, user: user, titulo: 'teste')
    idas_e_voltas.each do |pergunta, resposta|
      turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: pergunta, tela: 'home')
      turno.update!(resposta: resposta, status: resposta ? 'done' : 'failed')
    end
    conversa
  end

  it 'é só de quem perguntou' do
    minha = conversa_com(%W[oi ol\u00E1])
    conversa_com(%W[oi ol\u00E1], user: outra)

    expect(described_class.de(conta, pessoa)).to eq([minha])
  end

  it 'leva os turnos junto quando é apagada, pelo banco' do
    conversa = conversa_com(%W[oi ol\u00E1])

    described_class.where(id: conversa.id).delete_all

    expect(Autonomia::Guide::Turno.where(conversation_id: conversa.id)).to be_empty
  end

  it 'monta o histórico das idas e voltas, sem a resposta que não veio' do
    conversa = conversa_com(['quantos funis?', 'São 3.'], ['e quais?', nil], ['tenta de novo', 'Vendas, Pós e Renovação.'])

    expect(conversa.historico.map { |m| [m[:role], m[:content]] }).to eq(
      [['user', 'quantos funis?'], ['assistant', 'São 3.'], ['user', 'e quais?'], ['user', 'tenta de novo'],
       ['assistant', 'Vendas, Pós e Renovação.']]
    )
  end

  it 'fica com as últimas mensagens quando a conversa é longa' do
    conversa = conversa_com(*(1..15).map { |n| ["pergunta #{n}", "resposta #{n}"] })

    historico = conversa.historico
    expect(historico.size).to eq(Autonomia::Guide::Chat::MAX_HISTORY)
    expect(historico.last[:content]).to eq('resposta 15')
  end

  it 'usa a primeira pergunta, cortada, como título' do
    expect(described_class.titulo_para("  como   faço\n#{'x' * 200}")).to have_attributes(size: 120)
  end

  describe Autonomia::Guide::Turno do
    let(:conversa) { conversa_com }
    let(:turno) { described_class.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'oi', tela: 'home') }

    it 'grava o desfecho do pedido', :aggregate_failures do
      described_class.concluir(turno.pedido_id, { text: 'Pronto.', available: true, navigations: [{ route_name: 'home' }],
                                                  artigos: [], acao: { nome: 'DELETE inboxes/1' } }, { 'rodadas' => 2 })

      turno.reload
      expect(turno.status).to eq('done')
      expect(turno.resposta).to eq('Pronto.')
      expect(turno.navegacoes).to eq([{ 'route_name' => 'home' }])
      expect(turno.acao).to eq('nome' => 'DELETE inboxes/1')
      expect(turno.diagnostico).to eq('rodadas' => 2)
    end

    it 'marca retido quando o Guia não devolveu resposta' do
      described_class.concluir(turno.pedido_id, { available: true, retido: true }, {})

      expect(turno.reload.status).to eq('retido')
    end

    # O desfazer vale 5 dias; a conversa, 30. Depois da execução vencer, a tela
    # ainda mostra o que o Guia fez, sem o botão.
    it 'mostra o que o Guia fez mesmo depois de a execução vencer' do
      turno.update!(passos: [{ 'frase' => 'Criei a etiqueta.', 'ok' => true }])

      expect(turno.para_tela['execucao']).to eq('passos' => [{ 'frase' => 'Criei a etiqueta.', 'ok' => true }], 'vencida' => true)
    end
  end
end
