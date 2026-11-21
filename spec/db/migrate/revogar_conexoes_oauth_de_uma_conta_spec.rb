require 'rails_helper'
require Rails.root.join('db/migrate/20261121140000_revogar_conexoes_oauth_de_uma_conta.rb')

# #3106 — a conexão feita quando valia uma conta só não ganha as outras contas sem novo consentimento: a migration a
# desativa (revoked_at), sem apagar nada, e o down não reativa.
RSpec.describe RevogarConexoesOauthDeUmaConta do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:application) { Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/callback', confidential: false) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def token(**campos)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, account_id: account.id,
                                    scopes: 'conversations:read', expires_in: 3600, **campos)
  end

  def autorizacao
    Doorkeeper::AccessGrant.create!(application: application, resource_owner_id: user.id, account_id: account.id,
                                    scopes: 'conversations:read', expires_in: 600, redirect_uri: 'https://claude.ai/callback')
  end

  it 'desativa as conexões e autorizações ativas, sem apagar nenhuma' do
    ativo = token
    grant = autorizacao

    described_class.new.up

    expect(ativo.reload.revoked_at).to be_present
    expect(grant.reload.revoked_at).to be_present
    expect(Doorkeeper::AccessToken.count).to eq(1)
  end

  it 'não mexe na data de quem já estava desativado' do
    antes = 2.days.ago.change(usec: 0)
    desativado = token(revoked_at: antes)

    described_class.new.up

    expect(desativado.reload.revoked_at).to eq(antes)
  end

  it 'o down não reativa nada' do
    ativo = token
    migration = described_class.new
    migration.up
    migration.down

    expect(ativo.reload.revoked_at).to be_present
  end

  it 'a tarefa pós-troca desativa só o que foi criado até o momento dado' do
    velho = token(created_at: 1.hour.ago)
    novo = token

    OauthConexoesAntigas.revogar!(ate: 30.minutes.ago)

    expect(velho.reload.revoked_at).to be_present
    expect(novo.reload.revoked_at).to be_nil
  end
end
