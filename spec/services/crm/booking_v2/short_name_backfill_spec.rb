require 'rails_helper'

# Preenchimento do endereço curto das páginas que já existiam (#1299), o que a migration `BackfillBookingShortNames`
# roda no deploy: página sem nome ganha, página com nome fica como está, e rodar de novo não muda nada.
RSpec.describe Crm::BookingV2::ShortNameBackfill do
  let(:account) { create(:account, name: 'Clínica Viva') }
  let(:world) { build_booking_world(account: account, host_name: 'Ana Souza') }
  let(:page) { world.profile }

  def new_page(of_account, host, **)
    create_booking_profile(account: of_account, host: host, **)
  end

  # Como antes do deploy: páginas existem, nenhuma conta tem endereço (gravar página pelo modelo já cria o da conta).
  def run_as_before_deploy
    Crm::BookingAccountAddress.delete_all
    described_class.run
  end

  def snapshot
    {
      addresses: Crm::BookingAccountAddress.order(:id).pluck(:id, :account_id, :name, :updated_at),
      pages: Crm::AgentBookingProfile.order(:id).pluck(:id, :short_name, :updated_at),
      people: Crm::AgentBookingLink.order(:id).pluck(:id, :metadata, :updated_at)
    }
  end

  it 'dá à página sem nome o endereço da conta e um nome a partir do título' do
    page.update!(title: 'Avaliação Gratuita')
    before_update = page.reload.updated_at

    result = run_as_before_deploy

    expect(result.to_a).to eq([1, 1, []])
    expect(Crm::BookingAccountAddress.pluck(:account_id, :name)).to eq([[account.id, 'clinica-viva']])
    expect(page.reload).to have_attributes(short_name: 'avaliacao-gratuita', updated_at: before_update)
  end

  it 'mantém o nome da página que já tem, e ainda assim nomeia as outras da conta' do
    page.update!(short_name: 'meu-nome', title: 'Consulta')
    other = new_page(account, world.host, title: 'Consulta')

    run_as_before_deploy

    expect(page.reload.short_name).to eq('meu-nome')
    expect(other.reload.short_name).to eq('consulta')
  end

  it 'conta em que todas as páginas já têm nome: só ganha o endereço da conta, e o link curto passa a valer' do
    page.update_column(:short_name, 'meu-nome') # rubocop:disable Rails/SkipsModelValidations
    before_update = page.reload.updated_at

    expect(run_as_before_deploy.to_a).to eq([1, 0, []])

    expect(Crm::BookingAccountAddress.pluck(:account_id, :name)).to eq([[account.id, 'clinica-viva']])
    expect(page.reload).to have_attributes(short_name: 'meu-nome', updated_at: before_update)
    expect(Crm::BookingV2::ShortLink.path_for(page)).to eq('/a/clinica-viva/meu-nome')
  end

  it 'conta que já tem endereço fica com ele, e as páginas sem nome dela ganham nome' do
    page.update_column(:short_name, nil) # rubocop:disable Rails/SkipsModelValidations
    Crm::BookingAccountAddress.find_by!(account_id: account.id).update!(name: 'meu-endereco')

    expect(described_class.run.to_a).to eq([1, 1, []])
    expect(Crm::BookingAccountAddress.pluck(:name)).to eq(['meu-endereco'])
    expect(page.reload.short_name).to eq('conversa-de-30-min')
  end

  it 'numera duas páginas com o mesmo título na conta, na ordem em que foram criadas' do
    page.update!(title: 'Consulta')
    second = new_page(account, world.host, title: 'Consulta')
    third = new_page(account, world.host, title: 'consulta!')

    run_as_before_deploy

    expect([page, second, third].map { |item| item.reload.short_name }).to eq(%w[consulta consulta-2 consulta-3])
  end

  it 'numera o endereço de duas contas com o mesmo nome, e as páginas delas podem repetir o nome' do
    other_account = create(:account, name: 'Clínica Viva')
    other_page = build_booking_world(account: other_account).profile
    [page, other_page].each { |item| item.update!(title: 'Consulta') }

    run_as_before_deploy

    # As contas passam em ordem de id: a mais antiga fica com o nome, a outra com o número.
    expect(Crm::BookingAccountAddress.pluck(:account_id, :name))
      .to contain_exactly([other_account.id, 'clinica-viva'], [account.id, 'clinica-viva-2'])
    expect([page, other_page].map { |item| item.reload.short_name }).to eq(%w[consulta consulta])
  end

  it 'dá "agenda" na frente à conta e à página com nome do sistema, e um nome válido a título vazio' do
    account.update!(name: 'Admin')
    page.update!(title: 'Book')
    blank = new_page(account, world.host, title: nil)

    run_as_before_deploy

    expect(Crm::BookingAccountAddress.pluck(:name)).to eq(['agenda-admin'])
    expect([page, blank].map { |item| item.reload.short_name }).to eq(%w[agenda-book agenda])
  end

  it 'dá apelido às pessoas da página com um link por pessoa, sem trocar o de quem já tem' do
    colleague = create(:user, account: account, role: :agent, name: 'Bruno Lima')
    Crm::BookingV2::PagePeople.new(page).assign!([world.host.id, colleague.id])
    links = page.agent_booking_links.order(:id).to_a
    links.first.update_column(:metadata, { 'short_name' => 'aninha' }) # rubocop:disable Rails/SkipsModelValidations
    links.last.update_column(:metadata, {}) # rubocop:disable Rails/SkipsModelValidations

    run_as_before_deploy

    expect(links.map { |link| Crm::BookingV2::PersonNames.for(link.reload) }).to eq(%w[aninha bruno])
  end

  it 'não troca o nome que alguém salvou na página entre a leitura e a gravação' do
    page.update_column(:short_name, nil) # rubocop:disable Rails/SkipsModelValidations
    allow(Crm::BookingV2::ShortName).to receive(:suggest).and_wrap_original do |original, *args, **options|
      Crm::AgentBookingProfile.where(id: page.id).update_all(short_name: 'escolhido-agora') # rubocop:disable Rails/SkipsModelValidations
      original.call(*args, **options)
    end

    expect(described_class.run.to_a).to eq([0, 0, []])
    expect(page.reload.short_name).to eq('escolhido-agora')
  end

  it 'tenta a conta de novo uma vez quando bate numa trava com o painel' do
    page.update_column(:short_name, nil) # rubocop:disable Rails/SkipsModelValidations
    calls = 0
    allow(Crm::BookingV2::ShortName).to receive(:suggest).and_wrap_original do |original, *args, **options|
      calls += 1
      raise ActiveRecord::Deadlocked, 'impasse de teste' if calls == 1

      original.call(*args, **options)
    end

    expect(run_as_before_deploy.to_a).to eq([1, 1, []])
    expect(page.reload.short_name).to eq('conversa-de-30-min')
  end

  it 'não toca página antiga (page_version 1)' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    legacy = create_booking_profile(account: account, host: world.host, page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox)

    run_as_before_deploy

    expect(legacy.reload.short_name).to be_nil
  end

  it 'nomeia mesmo a página que hoje não passaria em outra validação' do
    page.update_column(:duration_minutes, 0) # rubocop:disable Rails/SkipsModelValidations
    expect(page.reload).not_to be_valid

    run_as_before_deploy

    expect(page.reload.short_name).to eq('conversa-de-30-min')
  end

  it 'rodar de novo não muda nada' do
    page
    new_page(account, world.host, title: 'Consulta')
    build_booking_world(account: create(:account, name: 'Clínica Viva')).profile

    expect(run_as_before_deploy.to_a).to eq([2, 3, []])
    first = snapshot

    travel_to(1.hour.from_now) do
      expect(described_class.run.to_a).to eq([0, 0, []])
    end
    expect(snapshot).to eq(first)
  end

  it 'a conta que falha é desfeita inteira, entra no relatório e não para as outras' do
    other_account = create(:account, name: 'Outra Conta')
    other_page = build_booking_world(account: other_account).profile
    page
    allow(Crm::BookingV2::ShortName).to receive(:suggest).and_wrap_original do |original, title, **options|
      raise 'falha de teste' if options[:account_id] == account.id

      original.call(title, **options)
    end

    result = run_as_before_deploy

    expect(result.to_a).to eq([1, 1, [account.id]])
    expect(page.reload.short_name).to be_nil
    expect(Crm::BookingAccountAddress.pluck(:account_id)).to eq([other_account.id])
    expect(other_page.reload.short_name).to eq('conversa-de-30-min')
  end

  it 'a migration roda o preenchimento e o `down` não apaga nada' do
    require Rails.root.join('db/migrate/20261017100100_backfill_booking_short_names')
    page
    migration = BackfillBookingShortNames.new
    migration.verbose = false
    Crm::BookingAccountAddress.delete_all

    migration.up
    expect(page.reload.short_name).to eq('conversa-de-30-min')

    migration.down
    expect(page.reload.short_name).to eq('conversa-de-30-min')
    expect(Crm::BookingAccountAddress.count).to eq(1)
  end
end
