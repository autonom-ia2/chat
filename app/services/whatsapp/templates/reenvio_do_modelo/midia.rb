# O arquivo do topo e dos cartões do carrossel no reenvio (#1767). O link que a mensagem original gravou, quando é de um
# arquivo NOSSO (Active Storage), é assinado com prazo (`HeaderMedia::URL_TTL`) e pode ter vencido: aqui o mesmo arquivo
# ganha um link novo, como o disparo da campanha faz a cada envio (`HeaderMedia.signed_media`). Link de fora (o endereço
# que a pessoa digitou) vai como veio.
#
# Qual arquivo: pelo próprio link, lido como URI (sem regex):
#   /rails/active_storage/disk/<chave assinada>/<nome>         serviço de disco (só desenvolvimento e teste): a chave vem
#                                                               do verificador; vencida, não dá para ler (= sumiu)
#   /rails/active_storage/blobs/{redirect,proxy}/<id assinado>/<nome>  o id assinado do arquivo
#   https://<bucket>/<chave>?...                                nuvem (S3 e afins): a chave do arquivo, se existir
# Arquivo nosso que sumiu, ou de outra conta: `renovar` devolve nil (motivo `midia_indisponivel`).
module Whatsapp::Templates::ReenvioDoModelo::Midia
  RAILS_PATH = %w[rails active_storage].freeze
  SUMIU = :sumiu

  module_function

  # processed_params com os arquivos nossos de novo pela caixa de destino (id da mídia subido nela, #2367, ou link
  # assinado novo), ou nil quando um arquivo nosso sumiu.
  def renovar(processed, inbox)
    processed = processed.to_h
    header = renovado(processed['header'], inbox)
    cards = cartoes(processed).map { |card| cartao_renovado(card, inbox) }
    return if header == SUMIU || cards.include?(SUMIU)

    processed = processed.merge('header' => header) if processed.key?('header')
    cards.any? ? processed.merge('carousel' => processed['carousel'].merge('cards' => cards)) : processed
  end

  def cartoes(processed)
    carousel = processed['carousel']
    carousel.is_a?(Hash) ? Array(carousel['cards']) : []
  end

  def cartao_renovado(card, inbox)
    return card unless card.is_a?(Hash)

    header = renovado(card['header'], inbox)
    header == SUMIU ? SUMIU : card.merge('header' => header)
  end

  # O id gravado no envio original nunca é reaproveitado: vale para a caixa que subiu e vence em 30 dias (Meta).
  def renovado(header, inbox)
    return header unless header.is_a?(Hash)

    header = header.except('media_id')
    return header if header['media_url'].blank?

    blob, nosso = arquivo_do_link(header['media_url'].to_s)
    return header unless nosso
    return SUMIU unless blob && da_conta?(blob, inbox.account_id)

    header.merge(Whatsapp::Templates::HeaderMedia.dispatch_file(blob, inbox))
  end

  # [blob, nosso?]: link do caminho do Rails é sempre nosso (blob nil = sumiu); na nuvem, só quando a chave existe.
  def arquivo_do_link(url)
    partes = URI.parse(url).path.to_s.split('/').reject(&:empty?)
    return [blob_do_rails(partes), true] if partes.first(2) == RAILS_PATH

    blob = partes.last && ActiveStorage::Blob.find_by(key: partes.last)
    [blob, blob.present?]
  rescue URI::InvalidURIError
    [nil, false]
  end

  def blob_do_rails(partes)
    return ActiveStorage::Blob.find_signed(partes[-2]) unless partes[2] == 'disk'

    chave = ActiveStorage.verifier.verified(partes[3].to_s, purpose: :blob_key)
    chave.is_a?(Hash) ? ActiveStorage::Blob.find_by(key: chave.with_indifferent_access[:key]) : nil
  end

  # Subido para esta conta (upload dos Modelos) ou anexo de algo desta conta (perfil do modelo, anexo de mensagem).
  def da_conta?(blob, account_id)
    return true if blob.metadata['account_id'].to_s == account_id.to_s

    blob.attachments.any? { |attachment| attachment.record.try(:account_id) == account_id }
  end
end
