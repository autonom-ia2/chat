require 'rails_helper'

# Nome curto da página (#1282, #1299): formato sem regex, nomes do sistema, sugestão a partir do título e unicidade
# dentro da conta (duas contas podem ter páginas com o mesmo nome; a conferência nunca olha a outra conta).
RSpec.describe Crm::BookingV2::ShortName do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:page) { build_booking_world(account: account).profile }
  let(:other_page) { build_booking_world(account: other_account).profile }
  let(:second_page) { create_booking_profile(account: account, host: page.default_assignee) }

  describe '.format_problem' do
    it 'aceita letras minúsculas, números e hífen no meio, de 3 a 40 caracteres' do
      ['abc', 'clinica-viva', 'dr-ana-2', '123', 'a' * 40].each { |name| expect(described_class.format_problem(name)).to be_nil, name }
    end

    it 'diz o que impede cada nome ruim' do
      {
        'ab' => 'too_short', '' => 'too_short', ('a' * 41) => 'too_long', 'Clinica' => 'invalid_chars', 'clínica' => 'invalid_chars',
        'clinica viva' => 'invalid_chars', 'clinica_viva' => 'invalid_chars', 'a/b/c' => 'invalid_chars', 'a.b.c' => 'invalid_chars',
        '-clinica' => 'hyphen_edge', 'clinica-' => 'hyphen_edge', 'book' => 'reserved', 'admin' => 'reserved', 'api' => 'reserved',
        'app' => 'reserved', 'super-admin' => 'reserved'
      }.each { |name, problem| expect(described_class.format_problem(name)).to eq(problem), name.inspect }
    end

    it 'guarda os nomes do sistema pedidos, mesmo os que o formato já barra' do
      expect(described_class::RESERVED).to include('a', 'b', 'book', 'app', 'api', 'admin', 'super_admin')
    end
  end

  describe '.problem' do
    it 'acusa o nome que já é de outra página da conta e libera para a própria página' do
      page.update!(short_name: 'clinica-viva')

      expect(described_class.problem('clinica-viva', account_id: account.id, except_id: second_page.id)).to eq('taken')
      expect(described_class.problem('  Clinica-Viva ', account_id: account.id)).to eq('taken')
      expect(described_class.problem('clinica-viva', account_id: account.id, except_id: page.id)).to be_nil
      expect(described_class.problem('clinica-nova', account_id: account.id)).to be_nil
    end

    it 'não olha as páginas de outra conta: o mesmo nome está livre para ela' do
      page.update!(short_name: 'clinica-viva')

      expect(described_class.problem('clinica-viva', account_id: other_account.id)).to be_nil
      expect(described_class.problem('clinica-viva', account_id: other_account.id, except_id: other_page.id)).to be_nil
    end
  end

  describe '.suggest' do
    def suggest(title, **)
      described_class.suggest(title, account_id: account.id, **)
    end

    it 'tira acento, espaço e pontuação do título' do
      expect(suggest('Avaliação Gratuita!')).to eq('avaliacao-gratuita')
      expect(suggest('  Dr. João & Cia_Ltda  ')).to eq('dr-joao-cia-ltda')
    end

    it 'soma um número quando o nome já é de outra página da conta' do
      page.update!(short_name: 'conversa-de-30-min')
      expect(suggest('Conversa de 30 min')).to eq('conversa-de-30-min-2')

      second_page.update!(short_name: 'conversa-de-30-min-2')
      expect(suggest('Conversa de 30 min')).to eq('conversa-de-30-min-3')
      expect(suggest('Conversa de 30 min', except_id: page.id)).to eq('conversa-de-30-min')
    end

    it 'não soma número por causa de página de outra conta' do
      other_page.update!(short_name: 'conversa-de-30-min')

      expect(suggest('Conversa de 30 min')).to eq('conversa-de-30-min')
    end

    it 'sempre devolve um nome válido: título vazio, curto, do sistema ou comprido demais' do
      ['', '!!!', 'Eu', 'Admin', 'book', 'x' * 80, "#{'palavra ' * 12}fim", '日本語'].each do |title|
        name = suggest(title)
        expect(described_class.format_problem(name)).to be_nil, "#{title.inspect} -> #{name.inspect}"
      end
      expect(suggest('')).to eq('agenda')
      expect(suggest('Admin')).to eq('agenda-admin')
    end

    it 'respeita os 40 caracteres, sem hífen na ponta, também com o número' do
      title = "#{'a' * 39} bcd"
      expect(suggest(title)).to eq('a' * 39)

      page.update!(short_name: 'a' * 39)
      expect(suggest(title)).to eq("#{'a' * 38}-2")
    end
  end

  describe 'no modelo' do
    it 'grava em minúsculas e trata vazio como sem nome' do
      page.update!(short_name: '  Clinica-Viva ')
      expect(page.reload.short_name).to eq('clinica-viva')

      page.update!(short_name: '')
      expect(page.reload.short_name).to be_nil
    end

    it 'recusa nome ruim, do sistema e o que já é de outra página da conta' do
      second_page.update!(short_name: 'clinica-viva')

      { 'ab' => 'too_short', 'clínica' => 'invalid_chars', 'admin' => 'reserved', 'clinica-viva' => 'taken' }.each do |name, problem|
        page.short_name = name
        expect(page).not_to be_valid, name
        expect(page.errors[:short_name]).to eq([problem])
      end
    end

    it 'aceita em duas contas o mesmo nome de página' do
      page.update!(short_name: 'clinica-viva')

      expect { other_page.update!(short_name: 'clinica-viva') }.not_to raise_error
      expect(Crm::AgentBookingProfile.where(short_name: 'clinica-viva').pluck(:account_id)).to contain_exactly(account.id, other_account.id)
    end

    it 'não dá nome curto a página antiga' do
      inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
      legacy = create_booking_profile(account: account, host: page.default_assignee, page_version: Crm::AgentBookingProfile::LEGACY_PAGE,
                                      inbox: inbox)

      legacy.short_name = 'pagina-antiga'
      expect(legacy).not_to be_valid
    end

    it 'deixa várias páginas sem nome curto na mesma conta' do
      expect([page.short_name, second_page.short_name]).to eq([nil, nil])
    end

    # Duas gravações do mesmo nome ao mesmo tempo passam as duas pela validação: quem decide é o índice único.
    it 'tem índice único por conta no banco: o mesmo nome na conta não entra nem pulando a validação' do
      page.update!(short_name: 'clinica-viva')

      # Em transação própria: o erro do banco desfaz só a tentativa, não o exemplo inteiro.
      attempt = -> { Crm::AgentBookingProfile.transaction(requires_new: true) { second_page.update_column(:short_name, 'clinica-viva') } } # rubocop:disable Rails/SkipsModelValidations

      expect { attempt.call }.to raise_error(ActiveRecord::RecordNotUnique, /index_crm_agent_booking_profiles_on_account_and_short_name/)
      expect(Crm::AgentBookingProfile.where(short_name: 'clinica-viva').pluck(:id)).to eq([page.id])
    end

    it 'devolve o erro de validação, e não o do banco, quando o índice barra uma gravação simultânea' do
      page.update!(short_name: 'clinica-viva')
      allow(described_class).to receive(:problem).and_return(nil)

      expect { second_page.update!(short_name: 'clinica-viva') }.to raise_error(ActiveRecord::RecordInvalid)
      expect(second_page.errors[:short_name]).to eq(['taken'])
    end

    it 'não tem mais o índice único global' do
      indexes = ActiveRecord::Base.connection.indexes(:crm_agent_booking_profiles).index_by(&:name)
      per_account = indexes['index_crm_agent_booking_profiles_on_account_and_short_name']

      expect(indexes).not_to have_key('index_crm_agent_booking_profiles_on_short_name')
      expect(per_account).to have_attributes(columns: %w[account_id short_name], unique: true)
    end
  end
end
