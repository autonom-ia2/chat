require 'rails_helper'

RSpec.describe Autonomia::Automacao::Valores do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria', custom_attributes: { 'apolice.numero' => '991' }) }
  let(:conversa) { create(:conversation, account: account, contact: contato, custom_attributes: { 'origem' => 'anuncio' }) }
  let(:valores) { described_class.new(alvo: conversa, quem: nil) }

  it 'lê campos da conversa e do contato' do
    expect(valores.ler('conversa.id')).to eq(conversa.display_id)
    expect(valores.ler('mensagem.tipo')).to be_nil
    expect(valores.ler('conversa.caixa_id')).to eq(conversa.inbox_id)
    expect(valores.ler('contato.nome')).to eq('Maria')
  end

  it 'lê a mensagem do gatilho: recebida, enviada ou nota', :aggregate_failures do
    tipo = lambda do |message_type, privada = false|
      mensagem = build(:message, conversation: conversa, account: account, message_type: message_type, private: privada)
      described_class.new(alvo: conversa, mensagem: mensagem, quem: nil).ler('mensagem.tipo')
    end

    expect([tipo.call(:incoming), tipo.call(:outgoing), tipo.call(:outgoing, true)]).to eq(%w[recebida enviada nota])
  end

  # #2496: o salvar recusa o que não está em FECHADOS; se a lista e o que a mensagem devolve divergirem, a condição
  # certa seria recusada, ou a errada passaria e nunca casaria.
  it 'tem como opções da mensagem exatamente o que a mensagem pode valer', :aggregate_failures do
    lido = lambda do |caminho, message_type, privada|
      mensagem = build(:message, conversation: conversa, account: account, message_type: message_type, private: privada)
      described_class.new(alvo: conversa, mensagem: mensagem, quem: nil).ler(caminho)
    end
    formas = [[:incoming, false], [:outgoing, false], [:outgoing, true], [:template, false]]

    # `mensagem.primeira` e `conversa.iniciada_por` dependem das mensagens gravadas: primeira_mensagem_spec. A resposta
    # durante a espera (G11): resposta_spec. `card.tem_reuniao_marcada` (G32): g32_reuniao_spec.
    # `contato.tem_reuniao_marcada` (#2710): reuniao_lembrete_e_contato_spec. A situação do envio (#2680): envio_spec.
    # Quem cuidava antes está ausente (G9): gatilho_troca_de_responsavel_spec.
    de_fora = %w[conversa.iniciada_por card.tem_reuniao_marcada contato.tem_reuniao_marcada envio.situacao
                 gatilho.responsavel_anterior_ausente]
    expect(described_class::FECHADOS.keys)
      .to match_array(described_class::MENSAGEM.keys + described_class::RESPOSTA.keys + de_fora + Autonomia::Automacao::Ausencia::FECHADOS.keys)
    described_class::FECHADOS.slice('mensagem.tipo', 'mensagem.privada').each do |caminho, fechado|
      expect(formas.map { |forma| lido.call(caminho, *forma) }.uniq).to match_array(fechado['opcoes'])
    end
  end

  it 'lê atributo personalizado pela chave, mesmo com ponto' do
    expect(valores.ler('conversa.atributos.origem')).to eq('anuncio')
    expect(valores.ler('contato.atributos.apolice.numero')).to eq('991')
    expect(valores.ler('contato.atributos.ausente')).to be_nil
  end

  it 'só aceita caminho da lista' do
    expect(described_class.caminho_valido?('contato.atributos.placa')).to be(true)
    expect(described_class.caminho_valido?('contato.atributos.')).to be(false)
    expect(described_class.caminho_valido?('contato.senha')).to be(false)
    expect { valores.ler('contato.senha') }.to raise_error(ArgumentError)
  end

  describe 'alvo card e contato (#2499)' do
    # O valor da venda pede quem vê valores de venda (#2597): o administrador vê.
    let(:funil_admin) { create(:user, account: account, role: :administrator) }
    let(:funil) { create_crm_pipeline(account: account, user: funil_admin) }
    let(:card) do
      novo_card(primary_conversation: conversa, title: 'Seguro auto', value_cents: 180_050, custom_attributes: { 'vencimento' => '2026-12-01' })
    end

    def novo_card(**atributos)
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Pedido', currency: 'BRL', contact: contato, **atributos)
    end

    it 'lê o card e, pelas pontes, a conversa principal e o contato', :aggregate_failures do
      valores = described_class.new(alvo: card, quem: funil_admin)

      expect(valores.ler('card.titulo')).to eq('Seguro auto')
      expect(valores.ler('card.valor')).to eq(BigDecimal('1800.50'))
      expect(valores.ler('card.etapa_id')).to eq(card.stage_id)
      expect(valores.ler('card.atributos.vencimento')).to eq('2026-12-01')
      expect(valores.ler('conversa.id')).to eq(conversa.display_id)
      expect(valores.ler('contato.nome')).to eq('Maria')
    end

    # Decisão do #2499 (PR2a): o card sem valor lê zero, não vazio, como no quadro (value_cents é obrigatório, padrão 0).
    # "Valor maior que 0" separa o card com valor; "está vazio" nunca casa no card.
    it 'o card sem valor lê zero' do
      expect(described_class.new(alvo: novo_card, quem: funil_admin).ler('card.valor')).to eq(0)
    end

    it 'lê vazio quando a ponte falta: card sem conversa, contato sem card' do
      sem_conversa = novo_card(primary_conversation: nil)

      expect(described_class.new(alvo: sem_conversa, quem: nil).ler('conversa.status')).to be_nil
      expect(described_class.new(alvo: contato, quem: nil).ler('card.titulo')).to be_nil
      expect(described_class.new(alvo: contato, quem: nil).ler('contato.atributos.apolice.numero')).to eq('991')
    end

    it 'diz o que cada alvo alcança' do
      expect(described_class.no_alvo?('card.valor', 'Conversation')).to be(false)
      expect(described_class.no_alvo?('contato.nome', 'Crm::Card')).to be(true)
      expect(described_class.no_alvo?('conversa.status', 'Contact')).to be(false)
      expect(described_class.no_alvo?('mensagem.tipo', 'Conversation')).to be(true)
    end
  end

  # G23 (#2737): o "ausente até" de quem cuida, na conta da execução. Passou a data, volta a ser presente.
  describe 'responsável ausente' do
    let(:agente) { create(:user, account: account, role: :agent) }

    def ausente!(ate) = agente.account_users.find_by(account: account).update!(ausente_ate: ate)

    it 'na conversa: verdadeiro enquanto o ausente até não passou', :aggregate_failures do
      expect(valores.ler('conversa.responsavel_ausente')).to be(false)

      conversa.update!(assignee: agente)
      ausente!(3.days.from_now)
      expect(described_class.new(alvo: conversa.reload, quem: nil).ler('conversa.responsavel_ausente')).to be(true)

      ausente!(1.minute.ago)
      expect(described_class.new(alvo: conversa.reload, quem: nil).ler('conversa.responsavel_ausente')).to be(false)
    end

    it 'só lê a ausência na conta da execução' do
      outra = create(:account)
      create(:account_user, account: outra, user: agente, ausente_ate: 3.days.from_now)
      conversa.update!(assignee: agente)

      expect(described_class.new(alvo: conversa.reload, quem: nil).ler('conversa.responsavel_ausente')).to be(false)
    end
  end
end
