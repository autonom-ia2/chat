# Agendamento v2 (#1187, J8-A9): quem sai da conta não pode deixar reunião futura sem responsável.
# Registro aditivo no modelo do upstream (sem editar app/models/account_user.rb); a regra mora em
# Crm::BookingV2::OrphanReassigner, num job (a remoção nunca falha por causa de uma reunião).
# Membros de integração não atendem reuniões e ficam de fora.
Rails.application.config.to_prepare do
  AccountUser.after_destroy_commit(unless: :integration?) do |account_user|
    Crm::BookingV2::OrphanReassignJob.perform_later(account_user.account_id, account_user.user_id)
  end
end
