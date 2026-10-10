# Agendamento v2 (#1187, J8-A9): quem sai da conta não pode deixar reunião futura sem responsável.
# Registro aditivo no modelo do upstream (sem editar app/models/account_user.rb); a regra mora em
# Crm::BookingV2::OrphanReassigner, num job (a remoção nunca falha por causa de uma reunião).
# Membros de integração não atendem reuniões e ficam de fora.
#
# Enfileirar também não pode derrubar a remoção (fila fora do ar, Redis caído): o erro fica no log com a classe e
# os ids, e a pessoa sai da conta do mesmo jeito.
Rails.application.config.to_prepare do
  AccountUser.after_destroy_commit(unless: :integration?) do |account_user|
    Crm::BookingV2::OrphanReassignJob.perform_later(account_user.account_id, account_user.user_id)
  rescue StandardError => e
    Rails.logger.error(
      "[booking_v2] orphan reassign not enqueued for user #{account_user.user_id} in account #{account_user.account_id}: #{e.class.name}"
    )
  end
end
