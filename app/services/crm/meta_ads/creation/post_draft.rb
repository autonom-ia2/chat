# O rascunho de impulsionar post (#2198 PR 2, #2339), revalidado antes de qualquer chamada à Meta. Usa as mesmas regras
# do anúncio novo para chave, nome, Página, público, valor e datas (Crm::MetaAds::Creation::Draft); no lugar de mídia,
# texto e destino, o post escolhido. Que o post é da Página (ou do Instagram dela) e pode ser impulsionado se confere
# no criar, relido na Meta (Crm::MetaAds::Creation::Posts#find!).
#
# - Post do Instagram: com número do WhatsApp na conta, o número é obrigatório e o anúncio leva o botão do WhatsApp
#   (`destination: WHATSAPP`, onde aparece Automático). Sem número, engajamento no post (`ON_POST`).
# - Post da Página: `ON_POST`, só no Facebook, sem número (botão do WhatsApp em post da Página não está confirmado).
class Crm::MetaAds::Creation::PostDraft < Crm::MetaAds::Creation::Draft
  def validate!
    source = post_source
    number = post_whatsapp_number(source)
    @values = {
      kind: 'post', idempotency_key: idempotency_key, name: name, page_id: page_id, post_source: source, post_id: post_id,
      whatsapp_number: number, destination: number ? 'WHATSAPP' : 'ON_POST', placement: source == 'facebook' ? 'FACEBOOK' : 'AUTO',
      special_category: flag(:special_category), recreate_unconfirmed: flag(:recreate_unconfirmed), **audience, **budget
    }
    self
  end

  private

  def post_source
    value = @params[:post_source].to_s
    Crm::MetaAds::Creation::Posts::SOURCES.include?(value) ? value : fail!('invalid_post')
  end

  # Só dígitos (Instagram) ou Página_post (Facebook): o id vai no corpo do criativo, nunca em texto livre.
  def post_id
    value = @params[:post_id].to_s
    value.split('_', -1).all? { |part| Crm::MetaAds::Creation::Ids.numeric?(part) } && value.present? ? value : fail!('invalid_post')
  end

  def post_whatsapp_number(source)
    return if source == 'facebook'

    numbers = Crm::MetaAds::Creation::Options.whatsapp_numbers(@account).pluck(:id)
    return if numbers.empty?

    numbers.include?(@params[:whatsapp_number].to_s) ? @params[:whatsapp_number].to_s : fail!('invalid_whatsapp_number')
  end
end
