require 'rails_helper'

# #2185: excluir uma função com gente pede o destino dessas pessoas (outra função ou sem função), e mover e excluir
# acontecem juntos. Antes, quem tinha a função virava agente comum em silêncio.
RSpec.describe 'Deleting a custom role with people (#2185)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:role) { create(:custom_role, account: account, permissions: %w[conversation_view]) }
  let(:destination) { create(:custom_role, account: account, permissions: %w[conversation_view contact_view]) }
  let!(:holder) { member_of(role) }

  before { account.enable_features!('custom_roles') }

  def member_of(custom_role)
    user = create(:user, account: account, role: :agent)
    membership = user.account_users.find_by(account: account)
    membership.update!(custom_role: custom_role)
    membership
  end

  def delete_role(as:, **params)
    delete "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}", params: params, headers: as.create_new_auth_token, as: :json
  end

  it 'refuses without a destination and changes nothing' do
    delete_role(as: admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('destination_required')
    expect(CustomRole.exists?(role.id)).to be(true)
    expect(holder.reload.custom_role_id).to eq(role.id)
  end

  it 'moves the people to the destination role, deletes the role and records both' do
    delete_role(as: admin, destination_role_id: destination.id)

    expect(response).to have_http_status(:ok)
    expect(CustomRole.exists?(role.id)).to be(false)
    expect(holder.reload.custom_role_id).to eq(destination.id)
    change = Enterprise::AuditLog.where(auditable_type: 'AccountUser', auditable_id: holder.id, action: 'update').order(:id).last
    expect(change.audited_changes['custom_role_id']).to eq([role.id, destination.id])
    expect(change.user).to eq(admin)
    expect(Enterprise::AuditLog.where(auditable_type: 'CustomRole', auditable_id: role.id, action: 'destroy')).to exist
  end

  it "leaves the people without a role when the destination is 'none'" do
    delete_role(as: admin, destination_role_id: 'none')

    expect(response).to have_http_status(:ok)
    expect(CustomRole.exists?(role.id)).to be(false)
    expect(holder.reload.custom_role_id).to be_nil
    changes = Enterprise::AuditLog.where(auditable_type: 'AccountUser', auditable_id: holder.id, action: 'update')
    expect(changes.map { |audit| audit.audited_changes['custom_role_id'] }).to include([role.id, nil])
  end

  it 'refuses a role of another account, the role itself and the administrator without revealing them' do
    other_role = create(:custom_role, account: create(:account), permissions: %w[conversation_view])

    [other_role.id, role.id, 'administrator', [destination.id]].each do |value|
      delete_role(as: admin, destination_role_id: value)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('destination_invalid')
    end
    expect(CustomRole.exists?(role.id)).to be(true)
    expect(holder.reload.custom_role_id).to eq(role.id)
  end

  it 'refuses a destination the person deleting could not hand out' do
    builder = create(:user, account: account, role: :agent)
    builder.account_users.find_by(account: account)
           .update!(custom_role: create(:custom_role, account: account, permissions: %w[custom_role_manage conversation_view]))

    delete_role(as: builder, destination_role_id: destination.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('destination_invalid')
    expect(CustomRole.exists?(role.id)).to be(true)
    expect(holder.reload.custom_role_id).to eq(role.id)

    # 'none' segue a mesma régua (#2317): quem exclui não alcança as chaves do "Sem função".
    delete_role(as: builder, destination_role_id: 'none')

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('out_of_reach')
    expect(holder.reload.custom_role_id).to eq(role.id)
  end

  # Alguém ganha a função enquanto ela é excluída: sem a releitura travada, o `dependent: :nullify` deixaria essa pessoa
  # como agente comum em silêncio. Tudo volta e a resposta pede para tentar de novo.
  it 'undoes everything when someone gets the role while it is being deleted' do
    latecomer = create(:user, account: account, role: :agent).account_users.find_by(account: account)
    # rubocop:disable RSpec/AnyInstance, Rails/SkipsModelValidations
    allow_any_instance_of(AccountUser).to receive(:update!).and_wrap_original do |original, *args|
      original.call(*args).tap { latecomer.update_column(:custom_role_id, role.id) }
    end
    # rubocop:enable RSpec/AnyInstance, Rails/SkipsModelValidations

    delete_role(as: admin, destination_role_id: destination.id)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('changed_meanwhile')
    expect(CustomRole.exists?(role.id)).to be(true)
    expect(holder.reload.custom_role_id).to eq(role.id)
  end

  # Quem ganha a função depois da trava é barrado pela chave estrangeira: a exclusão volta e pede para tentar de novo.
  it 'answers 409 when the foreign key refuses the deletion' do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(CustomRole).to receive(:destroy!).and_raise(ActiveRecord::InvalidForeignKey)
    # rubocop:enable RSpec/AnyInstance

    delete_role(as: admin, destination_role_id: destination.id)

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('changed_meanwhile')
    expect(holder.reload.custom_role_id).to eq(role.id)
  end

  # Duas gravações do mesmo nome ao mesmo tempo: a segunda bate no índice e recebe o erro do campo nome, não 500.
  it 'answers 422 on the name field when the unique index refuses the name' do
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(CustomRole).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
    # rubocop:enable RSpec/AnyInstance

    post "/api/v1/accounts/#{account.id}/custom_roles",
         params: { custom_role: { name: 'Vendas', permissions: %w[conversation_view] } },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['attributes']).to eq(['name'])
  end

  it 'deletes a role nobody has without a destination' do
    empty_role = create(:custom_role, account: account, permissions: %w[conversation_view])

    delete "/api/v1/accounts/#{account.id}/custom_roles/#{empty_role.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(CustomRole.exists?(empty_role.id)).to be(false)
  end
end
