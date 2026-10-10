require 'rails_helper'

# SONDA (não altera nada): documenta o papel do AccountUser depois de logins
# repetidos por SSO. Usada para levar evidência ao dono do módulo de auth.
RSpec.describe Autonomia::Sso::Provisioner do
  let(:account) { create(:account) }
  let(:identity_email) { 'agente@corretora.com.br' }
  let(:identity_user_id) { 'sso-user-agente' }
  let(:context) do
    {
      'user' => {
        'id' => identity_user_id,
        'email' => identity_email,
        'name' => 'Agente Convidado'
      }
    }
  end

  def pending_invitation!(role)
    account.update!(
      custom_attributes: (account.custom_attributes || {}).merge(
        'autonomia_pending_agent_invitations' => {
          identity_email => {
            'email' => identity_email,
            'name' => 'Agente Convidado',
            'role' => role,
            'created_at' => Time.current.iso8601
          }
        }
      )
    )
  end

  def role_after_login
    user = described_class.new(context: context).perform
    AccountUser.find_by!(account: account.reload, user: user).role
  end

  it 'aplica o papel do convite no primeiro login' do
    pending_invitation!('agent')

    expect(role_after_login).to eq('agent')
  end

  it 'mostra qual papel fica no segundo login, já sem convite pendente' do
    pending_invitation!('agent')
    primeiro = role_after_login
    segundo = role_after_login

    expect(primeiro).to eq('agent')
    # Se este falhar dizendo 'administrator', é escalonamento de privilégio.
    expect(segundo).to eq('agent')
  end
end
