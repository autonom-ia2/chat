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

  # Entrega 2 — a pessoa escreve enquanto o Guia ainda trabalha.
  describe '.acrescentar' do
    def acrescentar(id, mensagem, user: admin)
      nova = SecureRandom.uuid
      [described_class.acrescentar(id, account: conta, user: user, nova: nova, mensagem: mensagem), nova]
    end

    it 'põe a mensagem na fila do pedido em curso, na ordem em que chegou, e abre o pedido dela', :aggregate_failures do
      id = described_class.abrir(account: conta, user: admin)

      aceita, primeira = acrescentar(id, 'pensei melhor')
      _, segunda = acrescentar(id, 'pare')

      expect(aceita).to be(true)
      expect(described_class.ler(primeira, account: conta, user: admin)).to eq('status' => 'pending')
      expect(described_class.retirar_juntas(id)).to eq([{ 'id' => primeira, 'texto' => 'pensei melhor' },
                                                        { 'id' => segunda, 'texto' => 'pare' }])
      expect(described_class.retirar_juntas(id)).to eq([])
    end

    it 'recusa quando o pedido já terminou: a mensagem vira pergunta comum', :aggregate_failures do
      id = described_class.abrir(account: conta, user: admin)
      described_class.concluir(id, { text: 'pronto' })

      aceita, nova = acrescentar(id, 'e mais isso')

      expect(aceita).to be(false)
      expect(described_class.ler(nova, account: conta, user: admin)).to be_nil
      expect(described_class.retirar_juntas(id)).to eq([])
    end

    # Outra pessoa não consegue enfiar mensagem no trabalho que roda com a permissão do dono.
    it 'recusa a mensagem de outra pessoa da mesma conta', :aggregate_failures do
      id = described_class.abrir(account: conta, user: admin)
      outro, = create_crm_agent(account: conta)

      aceita, = acrescentar(id, 'apaga tudo', user: outro)

      expect(aceita).to be(false)
      expect(described_class.retirar_juntas(id)).to eq([])
    end
  end

  describe '.ler_juntas' do
    it 'o que o Guia lê passa para as lidas, e o fim do turno as retira na ordem', :aggregate_failures do
      id = described_class.abrir(account: conta, user: admin)
      %w[pensei pare].each do |texto|
        described_class.acrescentar(id, account: conta, user: admin, nova: SecureRandom.uuid, mensagem: texto)
      end

      expect(described_class.ler_juntas(id).pluck('texto')).to eq(%w[pensei pare])
      expect(described_class.retirar_juntas(id)).to eq([])
      expect(described_class.retirar_lidas(id).pluck('texto')).to eq(%w[pensei pare])
      expect(described_class.retirar_lidas(id)).to eq([])
    end

    it 'roda o bloco só quando a mensagem entrou' do
      id = described_class.abrir(account: conta, user: admin)
      described_class.concluir(id, { text: 'pronto' })
      rodou = false

      described_class.acrescentar(id, account: conta, user: admin, nova: SecureRandom.uuid, mensagem: 'oi') { rodou = true }

      expect(rodou).to be(false)
    end
  end

  describe '.anotar_etapa' do
    it 'mostra o que o Guia está fazendo só enquanto ele trabalha', :aggregate_failures do
      id = described_class.abrir(account: conta, user: admin)

      described_class.anotar_etapa(id, 'ler_da_conta')
      expect(described_class.ler(id, account: conta, user: admin)['etapa']).to eq('ler_da_conta')

      described_class.concluir(id, { text: 'pronto' })
      expect(described_class.ler(id, account: conta, user: admin)).not_to have_key('etapa')
    end

    it 'não anota sem pedido (bateria e specs)' do
      expect { described_class.anotar_etapa(nil, 'ler_da_conta') }.not_to raise_error
    end
  end

  it 'a falha leva a pergunta seguinte, quando a pessoa escreveu de novo' do
    id = described_class.abrir(account: conta, user: admin)

    described_class.falhar(id, { 'seguinte' => 'p2', 'tardias' => ['p2'] })

    expect(described_class.ler(id, account: conta, user: admin))
      .to eq('status' => 'failed', 'seguinte' => 'p2', 'tardias' => ['p2'])
  end
end
