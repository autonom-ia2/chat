# A mensagem de prova mudou (#1601; decisão N3 do Rodrigo: só o mínimo, sem retenção).
#
# APAGADA (pela equipe, `deleted`, ou retirada pelo cliente, `deleted_by_contact_at`): a mensagem sai da prova de cada
# fato; o fato que ficou sem prova deixa de valer (a versão expira).
#
# EDITADA pelo cliente (o texto mudou): cada fato vivo que ela provava é conferido de novo contra o texto novo (o mesmo
# `contido?` do A9, com o texto dos anexos). Continua no texto: nada muda. Não está mais (e decisão, que é texto livre,
# sempre): a mensagem sai da prova (versão nova, `codigo:recalculo`; sem outra prova, o fato deixa de valer). Quando
# algum fato saiu, o card é reavaliado de carona (opção A do Rodrigo, 17/10): a avaliação seguinte vê o texto novo e
# grava o valor novo pelo caminho normal do Escritor. Ex.: "2002" editado para "2022": o 2002 deixa de valer na hora e o
# 2022 entra na próxima avaliação. Edição que não mexe em fato não reavalia nada.
module Crm::Memoria::Recalcular
  MARCAS_DE_APAGADA = %w[deleted deleted_by_contact_at].freeze

  module_function

  # -> 'apagada', 'editada' ou nil, pela mudança DESTE update (o recibo de lido de uma mensagem já apagada não conta).
  def evento(message, mudancas)
    return if message.nil?

    mudancas = mudancas.to_h.stringify_keys
    return 'apagada' if apagada_agora?(mudancas['content_attributes'])

    'editada' if message.incoming? && mudancas.key?('content')
  end

  def apagada_agora?(mudanca)
    return false unless mudanca.is_a?(Array) && mudanca.size == 2

    antes, depois = mudanca.map { |valor| marcas(valor) }
    MARCAS_DE_APAGADA.any? { |marca| depois[marca].present? && antes[marca].blank? }
  end

  # `content_attributes` é JSON gravado como texto dentro do json: pode chegar como String.
  def marcas(valor)
    valor = JSON.parse(valor) if valor.is_a?(String)
    valor.is_a?(Hash) ? valor.stringify_keys : {}
  rescue JSON::ParserError
    {}
  end

  def mensagem_apagada!(message)
    da_prova(message).find_each { |fato| tirar_a_prova!(fato, message) }
  end

  def mensagem_editada!(message)
    textos = [Crm::Memoria::Normal.texto_da_mensagem(message)]
    tocados = da_prova(message).find_each.reject { |fato| ainda_vale?(fato, textos) }
    return if tocados.empty?

    tocados.each { |fato| tirar_a_prova!(fato, message) }
    reavaliar((tocados.map(&:card) + [Crm::Assunto.funil_atual(message.conversation)]).compact.uniq)
  end

  def da_prova(message)
    Crm::MemoriaFato.vivos.where(account_id: message.account_id).where('prova_message_ids @> ARRAY[?]::bigint[]', message.id)
  end

  def ainda_vale?(fato, textos)
    return false if fato.tipo == 'decisao'

    Crm::Memoria::Normal.contido?(fato.valor, textos) &&
      (fato.item_ref.blank? || Crm::Memoria::Normal.contido?(fato.item_ref, textos))
  end

  # A versão expira; sobrando prova, nasce outra só com as que ficaram, e o trecho é recopiado da mais nova delas.
  def tirar_a_prova!(fato, message)
    restantes = fato.prova_message_ids - [message.id]
    Crm::MemoriaFato.transaction do
      fato.update!(expirado_em: Time.current, prova_trecho: restantes.empty? ? nil : fato.prova_trecho)
      next if restantes.empty?

      Crm::MemoriaFato.create!(fato.attributes.except('id', 'created_at', 'updated_at', 'idempotency_key', 'expirado_em')
                                   .merge('prova_message_ids' => restantes, 'prova_trecho' => trecho_de(restantes),
                                          'versao' => fato.versao + 1, 'substitui_id' => fato.id, 'registrado_em' => Time.current,
                                          'gerado_por' => 'codigo:recalculo'))
    end
  end

  def trecho_de(ids)
    mais_nova = Message.where(id: ids).includes(:attachments).reorder(id: :desc).first
    mais_nova && Crm::Memoria::Normal.texto_da_mensagem(mais_nova).first(Crm::MemoriaFato::VALOR_MAXIMO)
  end

  def reavaliar(cards)
    cards.select(&:open?).each { |card| Crm::Ai::Observer.new(card: card).schedule_evaluation }
  end
end
