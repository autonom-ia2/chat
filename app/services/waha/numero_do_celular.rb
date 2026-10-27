# #2211 — o número do WhatsApp do celular de uma caixa API ligada ao WAHA, para a tela mostrar por onde a mensagem sai.
# A sessão WAHA nasce com o número, só dígitos (Waha::InboxProvisioner). Fora do WAHA, ou sessão com outro nome: nil.
module Waha::NumeroDoCelular
  module_function

  def de(channel)
    return unless channel.try(:waha_provider?)

    sessao = channel.additional_attributes.to_h['session'].to_s
    return if sessao.empty? || !sessao.delete('0-9').empty?

    "+#{sessao}"
  end
end
