require 'rails_helper'

# Nome curto da página (#1282): formato sem regex, nomes do sistema, sugestão a partir do título e unicidade na
# instalação inteira (duas contas não dividem um nome).
RSpec.describe Crm::BookingV2::ShortName do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:page) { build_booking_world(account: account).profile }
  let(:other_page) { build_booking_world(account: other_account).profile }

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
    it 'acusa o nome que já tem dono em OUTRA conta e libera para a própria página' do
      page.update!(short_name: 'clinica-viva')

      expect(described_class.problem('clinica-viva', except_id: other_page.id)).to eq('taken')
      expect(described_class.problem('  Clinica-Viva ', except_id: other_page.id)).to eq('taken')
      expect(described_class.problem('clinica-viva', except_id: page.id)).to be_nil
      expect(described_class.problem('clinica-nova')).to be_nil
    end
  end

  describe '.suggest' do
    it 'tira acento, espaço e pontuação do título' do
      expect(described_class.suggest('Avaliação Gratuita!')).to eq('avaliacao-gratuita')
      expect(described_class.suggest('  Dr. João & Cia_Ltda  ')).to eq('dr-joao-cia-ltda')
    end

    it 'soma um número quando o nome já tem dono' do
      page.update!(short_name: 'conversa-de-30-min')
      expect(described_class.suggest('Conversa de 30 min')).to eq('conversa-de-30-min-2')

      other_page.update!(short_name: 'conversa-de-30-min-2')
      expect(described_class.suggest('Conversa de 30 min')).to eq('conversa-de-30-min-3')
      expect(described_class.suggest('Conversa de 30 min', except_id: page.id)).to eq('conversa-de-30-min')
    end

    it 'sempre devolve um nome válido: título vazio, curto, do sistema ou comprido demais' do
      ['', '!!!', 'Eu', 'Admin', 'book', 'x' * 80, "#{'palavra ' * 12}fim", '日本語'].each do |title|
        name = described_class.suggest(title)
        expect(described_class.format_problem(name)).to be_nil, "#{title.inspect} -> #{name.inspect}"
      end
      expect(described_class.suggest('')).to eq('agenda')
      expect(described_class.suggest('Admin')).to eq('agenda-admin')
    end
  end

  describe 'no modelo' do
    it 'grava em minúsculas e trata vazio como sem nome' do
      page.update!(short_name: '  Clinica-Viva ')
      expect(page.reload.short_name).to eq('clinica-viva')

      page.update!(short_name: '')
      expect(page.reload.short_name).to be_nil
    end

    it 'recusa nome ruim, do sistema e o que já é de outra conta' do
      other_page.update!(short_name: 'clinica-viva')

      { 'ab' => 'too_short', 'clínica' => 'invalid_chars', 'admin' => 'reserved', 'clinica-viva' => 'taken' }.each do |name, problem|
        page.short_name = name
        expect(page).not_to be_valid, name
        expect(page.errors[:short_name]).to eq([problem])
      end
    end

    it 'não dá nome curto a página antiga' do
      inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
      legacy = create_booking_profile(account: account, host: page.default_assignee, page_version: Crm::AgentBookingProfile::LEGACY_PAGE,
                                      inbox: inbox)

      legacy.short_name = 'pagina-antiga'
      expect(legacy).not_to be_valid
    end

    it 'deixa várias páginas sem nome curto' do
      expect(page.short_name).to be_nil
      expect(other_page.short_name).to be_nil
    end

    # Duas contas gravando o mesmo nome ao mesmo tempo passam as duas pela validação: quem decide é o índice único.
    it 'tem índice único no banco: o mesmo nome em duas contas não entra nem pulando a validação' do
      page.update!(short_name: 'clinica-viva')

      # Em transação própria: o erro do banco desfaz só a tentativa, não o exemplo inteiro.
      attempt = -> { Crm::AgentBookingProfile.transaction(requires_new: true) { other_page.update_column(:short_name, 'clinica-viva') } } # rubocop:disable Rails/SkipsModelValidations

      expect { attempt.call }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(Crm::AgentBookingProfile.where(short_name: 'clinica-viva').pluck(:account_id)).to eq([account.id])
    end
  end
end
