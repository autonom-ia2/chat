require 'rails_helper'

# O pedido ao Guia enquanto ele trabalha (#572). O ponto que não pode quebrar é
# o DONO: a resposta foi montada com a permissão de quem perguntou, e pode
# conter o que só ele tem direito de ver.
RSpec.describe Autonomia::Guide::Pedido do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  it 'nasce pendente, e só o dono lê' do
    id = described_class.abrir(account: conta, user: admin)

    expect(described_class.ler(id, account: conta, user: admin)).to eq('status' => 'pending')
  end

  it 'entrega a resposta quando o Guia termina', :aggregate_failures do
    id = described_class.abrir(account: conta, user: admin)

    described_class.concluir(id, { text: 'Você tem 48 conversas abertas.', available: true })
    pedido = described_class.ler(id, account: conta, user: admin)

    expect(pedido['status']).to eq('done')
    expect(pedido['text']).to eq('Você tem 48 conversas abertas.')
    expect(pedido['available']).to be(true)
  end

  it 'marca a falha, para a tela dizer em vez de esperar para sempre' do
    id = described_class.abrir(account: conta, user: admin)

    described_class.falhar(id)

    expect(described_class.ler(id, account: conta, user: admin)['status']).to eq('failed')
  end

  # Outra pessoa da MESMA conta: um agente comum não pode ler a resposta que o
  # administrador recebeu, montada com a permissão do administrador.
  it 'não entrega a resposta a outra pessoa da mesma conta' do
    id = described_class.abrir(account: conta, user: admin)
    described_class.concluir(id, { text: 'dado que só o admin vê' })
    outro, = create_crm_agent(account: conta)

    expect(described_class.ler(id, account: conta, user: outro)).to be_nil
  end

  it 'não entrega a resposta a outra conta' do
    id = described_class.abrir(account: conta, user: admin)
    outra_conta, = create_account_and_user

    expect(described_class.ler(id, account: outra_conta, user: admin)).to be_nil
  end

  # Pedido alheio tem que ser indistinguível de pedido inexistente: dizer
  # "existe, mas não é seu" confirmaria a quem tenta adivinhar que acertou.
  it 'responde igual para pedido que não existe' do
    expect(described_class.ler(SecureRandom.uuid, account: conta, user: admin)).to be_nil
  end

  # O job pode terminar depois de o pedido vencer. Ele não pode ressuscitar a
  # chave — a tela já desistiu dela, e ninguém a apagaria de novo.
  it 'não recria um pedido que já venceu' do
    id = SecureRandom.uuid

    described_class.concluir(id, { text: 'tarde demais' })

    expect(Redis::Alfred.get("#{described_class::PREFIXO}#{id}")).to be_nil
  end

  it 'vence sozinho, sem ninguém precisar apagar' do
    id = described_class.abrir(account: conta, user: admin)

    expect(Redis::Alfred.ttl("#{described_class::PREFIXO}#{id}")).to be_between(1, described_class::VALIDADE.to_i)
  end
end
