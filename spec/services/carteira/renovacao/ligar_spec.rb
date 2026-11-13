require 'rails_helper'

# E5 (#2898) — a apólice nova se liga à anterior pelo segurado, pelo ramo, pelo item e pela vigência, nunca pela
# seguradora nem pelo número (a renovação pode ir para outra seguradora). A tabela de casos do aceite está aqui, caso a
# caso: cada linha diz o que muda em relação ao caso base e se liga. Tudo fictício.
RSpec.describe Carteira::Renovacao::Ligar do
  # Meio-dia em São Paulo: para a conta, hoje é 12/11/2026.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:caio) { create(:contact, account: account, name: 'Caio Exemplo', phone_number: '+5511900000024') }
  let(:fim) { hoje + 20 }
  # O caso base: o seguro auto da Marina, do Carro Exemplo, que termina em 20 dias.
  let(:da_anterior) do
    { seguradora: 'Seguradora Exemplo', numero: 'EX-000001', tipo: 'auto', bem: 'Carro Exemplo 2022', inicio_vigencia: fim - 365,
      fim_vigencia: fim }
  end
  # A apólice que chega: de outra seguradora, com outro número, começando no dia em que a anterior termina.
  let(:da_nova) do
    { seguradora: 'Outra Seguradora Exemplo', numero: 'OS-777001', tipo: 'auto', bem: 'Carro Exemplo 2022', inicio_vigencia: fim,
      fim_vigencia: fim + 365 }
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { travel_to(agora) }

  def anterior(pessoa = marina, **campos)
    criar_apolice(pessoa, **da_anterior, **campos)
  end

  def nova(pessoa = marina, **campos)
    criar_apolice(pessoa, **da_nova, **campos)
  end

  def ligar(apolice, quem: admin)
    described_class.new(apolice, user: quem).sozinha
  end

  describe 'a tabela de casos: liga sozinha?' do
    it 'o caso base liga: mesma pessoa, mesmo ramo, mesmo item, a nova começa quando a anterior termina' do
      antiga = anterior
      chegou = nova

      expect(ligar(chegou)).to eq(antiga)
      expect(chegou.reload.apolice_anterior_id).to eq(antiga.id)
    end

    # [o que muda na anterior, o que muda na nova, liga?]
    {
      'outra seguradora e outro número (o caso base)' => [{}, {}, true],
      'a mesma seguradora e o mesmo número, no termo seguinte' => [{}, { seguradora: 'Seguradora Exemplo', numero: 'EX-000001' }, true],
      'o item escrito de outro jeito (caixa, acento, pontuação)' => [{ bem: 'Carro Exemplo 2022' }, { bem: 'CARRO  exemplo-2022' }, true],
      'a nova sem dizer o item' => [{}, { bem: nil }, true],
      'a anterior sem dizer o item' => [{ bem: nil }, {}, true],
      'outro item' => [{}, { bem: 'Carro Exemplo 2024' }, false],
      'outro ramo' => [{}, { tipo: 'residencial' }, false],
      'ramo que ninguém sabe qual é, nos dois' => [{ tipo: 'outro' }, { tipo: 'outro' }, false],
      'a nova começa 30 dias depois do fim' => [{}, { inicio_vigencia: Date.new(2027, 1, 1), fim_vigencia: Date.new(2028, 1, 1) }, true],
      'a nova começa 31 dias depois do fim' => [{}, { inicio_vigencia: Date.new(2027, 1, 2), fim_vigencia: Date.new(2028, 1, 2) }, false],
      'a nova começa 30 dias antes do fim (renovação adiantada)' => [{}, { inicio_vigencia: Date.new(2026, 11, 2) }, true],
      'a nova começa 31 dias antes do fim' => [{}, { inicio_vigencia: Date.new(2026, 11, 1) }, false],
      'a nova sem começo de vigência' => [{}, { inicio_vigencia: nil }, false],
      'a nova termina no mesmo dia da anterior' => [{}, { inicio_vigencia: Date.new(2026, 11, 20), fim_vigencia: Date.new(2026, 12, 2) }, false],
      'a anterior cancelada' => [{ cancelado_em: Time.utc(2026, 11, 1) }, {}, false],
      'a anterior já como "não renovou"' => [{ nao_renovou_em: Time.utc(2026, 11, 1) }, {}, false],
      'a anterior já como "renovou", ainda sem a apólice nova' => [{ renovado_em: Time.utc(2026, 11, 1) }, {}, true],
      'a nova já cancelada' => [{}, { cancelado_em: Time.utc(2026, 11, 1) }, false]
    }.each do |caso, (na_anterior, na_nova, liga)|
      it "#{caso}: #{liga ? 'liga' : 'não liga'}" do
        antiga = anterior(**na_anterior)
        chegou = nova(**na_nova)

        expect(ligar(chegou)).to eq(liga ? antiga : nil)
        expect(chegou.reload.apolice_anterior_id).to eq(liga ? antiga.id : nil)
      end
    end

    it 'outra pessoa não liga' do
      anterior
      chegou = nova(caio)

      expect([ligar(chegou), chegou.reload.apolice_anterior_id]).to eq([nil, nil])
    end

    it 'a mesma pessoa, mas o segurado de uma é a empresa e o da outra não: não liga' do
      account.enable_features!('companies')
      empresa = create(:company, account: account, name: 'Empresa Exemplo')
      anterior
      chegou = nova(company: empresa)

      expect([ligar(chegou), chegou.reload.apolice_anterior_id]).to eq([nil, nil])
    end

    it 'a mesma pessoa e a mesma empresa segurada: liga' do
      account.enable_features!('companies')
      empresa = create(:company, account: account, name: 'Empresa Exemplo')
      antiga = anterior(company: empresa)
      chegou = nova(company: empresa)

      expect(ligar(chegou)).to eq(antiga)
    end

    it 'com duas candidatas não escolhe nenhuma' do
      anterior
      anterior(numero: 'EX-000002', bem: nil)
      chegou = nova

      expect([ligar(chegou), chegou.reload.apolice_anterior_id]).to eq([nil, nil])
    end

    it 'a anterior que outra apólice já renovou não é candidata de novo' do
      antiga = anterior
      primeira = nova
      ligar(primeira)
      segunda = nova(numero: 'OS-777002')

      expect([ligar(segunda), segunda.reload.apolice_anterior_id, primeira.reload.apolice_anterior_id]).to eq([nil, nil, antiga.id])
    end

    it 'seguro de outra conta, com tudo igual, não é candidato' do
      outra = conta_com_carteira
      criar_apolice(create(:contact, account: outra, name: 'Marina Exemplo'), **da_anterior)
      chegou = nova

      expect([ligar(chegou), chegou.reload.apolice_anterior_id]).to eq([nil, nil])
    end

    it 'a que já está ligada não é ligada de novo' do
      antiga = anterior
      chegou = nova
      ligar(chegou)

      expect { ligar(chegou) }.not_to(change { [chegou.reload.apolice_anterior_id, chegou.eventos.count, antiga.eventos.count] })
    end
  end

  describe 'o que a ligação faz' do
    let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }

    it 'anota a história da nova com o número da anterior, e a anterior sem card fica renovada' do
      antiga = anterior
      chegou = nova

      ligar(chegou)

      expect(chegou.eventos.sole).to have_attributes(tipo: 'apolice_nova', user_id: admin.id, valores: { 'anterior' => 'EX-000001' })
      expect(antiga.reload).to have_attributes(renovado_em: agora, nao_renovou_em: nil)
      expect(antiga.eventos.sole).to have_attributes(tipo: 'renovou', user_id: admin.id)
    end

    it 'fecha como ganho o card de renovação aberto da anterior, e é o card que deixa o seguro renovado' do
      antiga = anterior
      card = por_em_renovacao(antiga, ajustes)
      chegou = nova

      ligar(chegou)

      expect(card.reload.status).to eq('won')
      expect(antiga.reload.renovado_em).to eq(agora)
      expect(antiga.eventos.order(:id).pluck(:tipo)).to eq(%w[card_nasceu renovou])
      expect(Carteira::Selo.de(chegou.reload, hoje: hoje)).to eq('ativo')
    end

    it 'a anterior que já estava renovada continua com o desfecho que tinha, sem passo repetido' do
      antiga = anterior
      card = por_em_renovacao(antiga, ajustes)
      Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform
      travel 2.days
      chegou = nova

      ligar(chegou)

      expect(antiga.reload.renovado_em).to eq(agora)
      expect(antiga.eventos.order(:id).pluck(:tipo)).to eq(%w[card_nasceu renovou])
      expect(chegou.reload.apolice_anterior_id).to eq(antiga.id)
    end

    it 'quem trouxe diz qual foi a anterior: liga mesmo com outra candidata por perto, sem repetir o passo que já foi anotado' do
      antiga = anterior
      anterior(numero: 'EX-000002', bem: nil)
      chegou = nova

      described_class.new(chegou, user: admin).com(antiga, anotar: false)

      expect(chegou.reload.apolice_anterior_id).to eq(antiga.id)
      expect([chegou.eventos.count, antiga.reload.renovado_em]).to eq([0, agora])
    end
  end
end
