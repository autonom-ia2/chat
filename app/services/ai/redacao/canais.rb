# Os canais do redator (`Ai::Redacao::Escrever`, #1354): cada um registra o prompt (`prompts/<canal>.md`, depois do
# bloco comum `prompts/comum.md`), o schema (núcleo comum + campos do canal), a conferência estrutural e a
# normalização da saída. Canal conhecido sem implementação ainda responde "não suportado" com erro claro:
# `whatsapp_modelo` é da sessão Modelos WhatsApp (fase E, #1333), `email` fica para depois.
module Ai::Redacao::Canais
  class NaoSuportado < StandardError; end

  REGISTRO = {
    'whatsapp_texto' => 'Ai::Redacao::Canais::WhatsappTexto',
    # #1335: campanha para quem falou nas últimas 24 h (Modelos WhatsApp G).
    'whatsapp_campanha' => 'Ai::Redacao::Canais::WhatsappCampanha',
    'whatsapp_modelo' => nil,
    'email' => nil
  }.freeze

  def self.conhecido?(canal)
    REGISTRO.key?(canal.to_s)
  end

  def self.suportado?(canal)
    REGISTRO[canal.to_s].present?
  end

  def self.para(canal)
    canal = canal.to_s
    raise NaoSuportado, "canal desconhecido: #{canal}" unless conhecido?(canal)
    raise NaoSuportado, "canal ainda não suportado: #{canal}" unless suportado?(canal)

    REGISTRO[canal].constantize
  end
end
