# A busca do "+" da conversa (#1702) com o TIPO do lugar no detalhe, para o `Crm::BookingV2::GeocodificarLocaisJob`
# decidir se o lugar é preciso, e sem o cache de lá (aqui é um pedido por endereço pendente). O
# `ConversaCanal::BuscaDeLugar#details` do "+" fica como está.
class Crm::BookingV2::GeocodificarLocaisJob::Busca < ConversaCanal::BuscaDeLugar
  CAMPOS_DO_DETALHE = "#{DETAILS_FIELD_MASK},types,primaryType".freeze

  # -> { latitude, longitude, tipos, tipo_principal }
  def details(place_id)
    body = request('details') do
      HTTParty.get("#{PLACE_DETAILS_ENDPOINT}/#{place_id}", query: locale_params.merge(sessao_params),
                                                            headers: headers(CAMPOS_DO_DETALHE), timeout: TIMEOUT_SECONDS)
    end

    { latitude: body.dig('location', 'latitude'), longitude: body.dig('location', 'longitude'),
      tipos: Array(body['types']), tipo_principal: body['primaryType'] }
  end
end
