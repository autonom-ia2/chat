# Rede de segurança da conversão de vídeo (#2370, `VideoConversion`): passado o tempo do pedido, apaga o vídeo original
# que ficou (job perdido num deploy, pedido expirado, falha ao apagar). Só blob marcado como original de conversão.
class Whatsapp::Templates::VideoConversionCleanupJob < ApplicationJob
  queue_as :low

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    blob.purge if blob&.metadata&.dig('video_conversion')
  end
end
