require 'rails_helper'

# #3246b: a varredura reserva as propostas que ainda esperam pagamento e enfileira uma conferência por proposta. Cada
# exemplo cobre um modo de falha: conferir fora da janela, conferir a cada rodada, conferir o que já foi pago, enviado ou
# cancelado, duas varreduras reservarem a mesma linha, e um `gerada_em` malformado derrubar a varredura inteira.
RSpec.describe Autonomia::Agents::Contratados::VarreduraDoPagamentoJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:agora) { Time.utc(2026, 11, 26, 15, 0, 0) }

  before { travel_to agora }

  def cotacao(gerada_em: agora - 1.hour, criada_em: agora - 1.hour, **extra)
    proposta = { 'codigo_do_plano' => 'P1', 'codigo_carrinho' => 987_654, 'link' => 'https://pagamento.exemplo.test/',
                 'gerada_em' => gerada_em.is_a?(String) ? gerada_em : gerada_em.iso8601 }.merge(extra.transform_keys(&:to_s))
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: bia, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: proposta, created_at: criada_em)
  end

  def conferencias
    enqueued_jobs.select { |job| job[:job] == Autonomia::Agents::Contratados::ConferirPagamentoJob }.map { |job| job[:args] }
  end

  def varrer = described_class.new.perform

  it 'enfileira a conferência com o id e o gerada_em em segundos, e grava conferido_em' do
    alvo = cotacao

    varrer

    expect(conferencias).to eq([[alvo.id, (agora - 1.hour).to_i]])
    expect(alvo.reload.proposta['conferido_em']).to eq(agora.iso8601)
  end

  it 'a janela do gerada_em: de 5 min a 24 h 10 min atrás' do
    dentro = [cotacao(gerada_em: agora - 5.minutes), cotacao(gerada_em: agora - 24.hours - 9.minutes)]
    cotacao(gerada_em: agora - 4.minutes)
    cotacao(gerada_em: agora - 24.hours - 11.minutes, criada_em: agora - 25.hours)

    varrer

    expect(conferencias.map(&:first)).to match_array(dentro.map(&:id))
  end

  it 'cotação criada há mais de 2 dias fica de fora' do
    cotacao(criada_em: agora - 3.days)

    varrer

    expect(conferencias).to be_empty
  end

  it 'espaçamento: a rodada seguinte (5 min) não confere de novo; depois de 9 min 30 s, confere' do
    alvo = cotacao

    varrer
    travel_to agora + 5.minutes
    varrer
    expect(conferencias.size).to eq(1)

    travel_to agora + 10.minutes
    varrer
    expect(conferencias.size).to eq(2)
    expect(alvo.reload.proposta['conferido_em']).to eq((agora + 10.minutes).iso8601)
  end

  it 'pago, voucher enviado, cancelado e proposta sem carrinho ficam de fora' do
    cotacao(pago_em: '2026-11-26T11:00:00')
    cotacao(voucher_enviado_em: (agora - 1.minute).iso8601)
    cotacao(situacao: 'cancelado')
    cotacao(codigo_carrinho: nil)
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: bia, id_cotacao: 'c-2',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: nil)

    varrer

    expect(conferencias).to be_empty
  end

  it 'gerada_em malformada não derruba a varredura: a linha fica de fora e as outras seguem' do
    cotacao(gerada_em: 'ontem à tarde')
    cotacao(gerada_em: '2026-13-45T99:00:00Z')
    boa = cotacao

    expect { varrer }.not_to raise_error
    expect(conferencias).to eq([[boa.id, (agora - 1.hour).to_i]])
  end

  # Duas varreduras ao mesmo tempo: a segunda roda com a reserva da primeira já gravada (o UPDATE confere o espaçamento
  # de novo), e não pega a mesma linha.
  it 'o espaçamento conferido no UPDATE barra a segunda reserva da linha recém-reservada' do
    alvo = cotacao
    primeira = described_class.new
    segunda = described_class.new
    ids = primeira.send(:candidatas, agora)

    expect(segunda.send(:reservar, ids, agora).map(&:first)).to eq([alvo.id])
    expect(primeira.send(:reservar, ids, agora)).to be_empty
  end

  it 'o lote tem teto' do
    stub_const("#{described_class}::LOTE", 2)
    3.times { cotacao }

    varrer

    expect(conferencias.size).to eq(2)
  end
end
