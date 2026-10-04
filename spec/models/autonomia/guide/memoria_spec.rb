require 'rails_helper'

# O que o Guia lembra entre conversas (#933): de quem é, o que entra no prompt
# e o que sai junto quando a conta, a pessoa ou a conversa saem.
RSpec.describe Autonomia::Guide::Memoria do
  let(:conta) { create(:account) }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:ana) { create(:user, account: conta) }

  def anotar(texto, user: nil, autor: user || admin, account: conta, turno: nil)
    described_class.create!(account: account, user: user, texto: texto, autor_id: autor.id, turno: turno)
  end

  describe '.bloco' do
    # AC-M1 — a Ana vê as dela e as da corretora; as do admin, nunca.
    it 'monta o que a pessoa e a corretora ensinaram, sem as de outra pessoa', :aggregate_failures do
      anotar('Fala curto comigo', user: admin)
      dela = anotar('Prefere respostas com lista', user: ana)
      da_corretora = anotar('Funil do Zé = funil Comercial (id 12)')

      bloco = described_class.bloco(conta, ana)

      expect(bloco).to include("##{dela.id} Prefere respostas com lista", "##{da_corretora.id} Funil do Zé")
      expect(bloco).not_to include('Fala curto comigo')
      expect(bloco).to start_with("[#{described_class::CABECALHO}")
      expect(bloco).to include('Sobre a pessoa:', 'Sobre a corretora:')
    end

    it 'fica vazio sem memória e sem pessoa', :aggregate_failures do
      expect(described_class.bloco(conta, ana)).to eq('')

      anotar('Funil do Zé = funil Comercial (id 12)')
      expect(described_class.bloco(conta, nil)).to eq('')
    end

    it 'não mistura contas' do
      outra_conta = create(:account)
      anotar('De outra corretora', account: outra_conta)

      expect(described_class.bloco(conta, ana)).to eq('')
    end

    # AC-M8 — o bloco vai em toda pergunta.
    it 'cabe no orçamento no caso típico: 5 pessoais e 8 da corretora' do
      5.times { |n| anotar("Prefere relatório do mês corrente, sem gráfico, em tópicos curtos #{n}", user: ana) }
      8.times { |n| anotar("Funil do Zé número #{n} = funil Comercial da equipe de autos (id 1#{n})") }

      expect(described_class.bloco(conta, ana).length).to be <= 2_000
    end

    def encher(tamanho)
      described_class::TETO_PESSOAL.times { |n| anotar("#{n} #{'a' * tamanho}"[0, tamanho], user: ana) }
      described_class::TETO_CORRETORA.times { |n| anotar("#{n} #{'b' * tamanho}"[0, tamanho]) }
    end

    it 'cabe no orçamento no teto cheio, com frases longas (150 caracteres)' do
      encher(150)

      expect(described_class.bloco(conta, ana).length).to be <= 6_500
    end

    # Com as 32 no limite de 200 caracteres, só o texto já soma 6.400: o bloco dá
    # cerca de 6,7 mil com os números e os títulos. Fica medido aqui, para o
    # custo do pior caso não crescer calado.
    it 'no pior caso (32 frases de 200 caracteres) fica perto de 6,7 mil' do
      encher(200)

      expect(described_class.bloco(conta, ana).length).to be <= 6_800
    end
  end

  it 'não aceita texto vazio nem acima de 200 caracteres', :aggregate_failures do
    expect(described_class.new(account: conta, autor_id: admin.id, texto: '')).not_to be_valid
    expect(described_class.new(account: conta, autor_id: admin.id, texto: 'x' * 201)).not_to be_valid
    expect(described_class.new(account: conta, autor_id: admin.id, texto: 'x' * 200)).to be_valid
  end

  # AC-M5 — LGPD.
  describe 'o que sai junto' do
    it 'some com a conta, pelo banco' do
      anotar('Funil do Zé = funil Comercial (id 12)')
      anotar('Fala curto comigo', user: ana)

      Account.where(id: conta.id).delete_all

      expect(described_class.where(account_id: conta.id)).to be_empty
    end

    it 'fica quando a conversa onde nasceu é apagada, sem o turno', :aggregate_failures do
      conversa = Autonomia::Guide::Conversa.create!(account: conta, user: ana, titulo: 'teste')
      turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'oi', tela: 'home')
      memoria = anotar('Fala curto comigo', user: ana, turno: turno)

      conversa.destroy!

      expect(memoria.reload.turno_id).to be_nil
      expect(memoria.texto).to eq('Fala curto comigo')
    end

    it 'quem sai da conta leva as pessoais e as conversas; as da corretora que escreveu ficam', :aggregate_failures do
      pessoal = anotar('Fala curto comigo', user: ana)
      da_corretora = anotar('Trabalhamos com Porto', autor: ana)
      do_admin = anotar('Prefere tópicos', user: admin)
      conversa = Autonomia::Guide::Conversa.create!(account: conta, user: ana, titulo: 'teste')
      outra_conta = create(:account)
      create(:account_user, account: outra_conta, user: ana)
      fora = anotar('Na outra conta', user: ana, account: outra_conta)

      conta.account_users.find_by(user: ana).destroy!

      expect(described_class.exists?(pessoal.id)).to be(false)
      expect(Autonomia::Guide::Conversa.exists?(conversa.id)).to be(false)
      expect(da_corretora.reload.autor_id).to eq(ana.id)
      expect(described_class.exists?(do_admin.id)).to be(true)
      expect(described_class.exists?(fora.id)).to be(true)
    end
  end

  it 'mostra no painel de que conversa veio a pessoal e quem escreveu a da corretora', :aggregate_failures do
    conversa = Autonomia::Guide::Conversa.create!(account: conta, user: ana, titulo: 'teste')
    turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'oi', tela: 'home')

    expect(anotar('Fala curto', user: ana, turno: turno).para_tela).to include('aprendida_em_conversa' => conversa.id)
    expect(anotar('Porto', autor: ana).para_tela).to include('autor' => ana.name)
  end
end
