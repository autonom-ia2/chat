# A foto do computador para um cartão do carrossel na conversa (#1716) é temporária, só para o envio (decisão do
# Rodrigo, 16/10/2026). A que foi usada num envio fica marcada (`conversation_sent`, `ConversationSend`): a conversa
# mostra o que foi enviado com ela (`template_params.enviado`). A que nunca foi usada sai depois de um dia, junto com a
# referência dela, que também expira em um dia (`HeaderMedia::URL_TTL`).
class Whatsapp::Templates::PurgeConversationUploadsJob < ApplicationJob
  queue_as :scheduled_jobs

  RETENTION = Whatsapp::Templates::HeaderMedia::URL_TTL
  BATCH = 500

  def perform
    unused.find_each(batch_size: BATCH) do |blob|
      next if blob.metadata['conversation_sent'] == true

      blob.purge_later
    end
  end

  private

  def unused
    ActiveStorage::Blob.unattached.where(created_at: ...RETENTION.ago)
                       .where("(active_storage_blobs.metadata::jsonb ->> 'conversation_upload') = 'true'")
  end
end
