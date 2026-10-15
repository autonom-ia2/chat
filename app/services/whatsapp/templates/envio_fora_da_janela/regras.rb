# Regras de uso de um modelo fora da janela (épico #1585, decisões do Rodrigo de 15/10/2026):
# - modelo da conta (sem dono do sistema), qualquer categoria: usa;
# - modelo do sistema UTILITY: usa;
# - modelo do sistema MARKETING: só com a 2ª marca da autorização (Divulgação, `WhatsappTemplateConsent`);
# - criar: só com a 1ª marca (quem barra é o `Garantir`, `sem_consentimento`); para um tipo MARKETING, também a 2ª.
# MARKETING no envio: o contato que recusou mensagens (`ContactOptOut`) não recebe, e número +1 (EUA) não recebe modelo
# de marketing (regra da Meta, página de limite por pessoa); sem o contato, também não. O limite por pessoa da Meta
# (erro 131049) é do envio do Followup.
module Whatsapp::Templates::EnvioForaDaJanela::Regras
  Tipos = Whatsapp::Templates::EnvioForaDaJanela::Tipos
  CATEGORIAS = [Tipos::UTILITY, Tipos::MARKETING].freeze
  # Código de país +1 no número gravado (E.164). A Meta fala em números dos EUA; o +1 também é do Canadá e do Caribe, e
  # sem tabela de DDD não dá para separar: bloqueamos todo +1 (o conservador; o modelo de propaganda não sai).
  PREFIXO_EUA = '+1'.freeze

  module_function

  # nil quando pode usar; senão o motivo (chave de `crm.service_reminders.aviso.*`).
  def impedimento(account:, categoria:, sistema:)
    return 'formato' unless CATEGORIAS.include?(categoria.to_s.upcase)
    return unless sistema && categoria.to_s.upcase == Tipos::MARKETING

    'sem_consentimento_propaganda' unless WhatsappTemplateConsent.ativo?(account, :marketing)
  end

  # MARKETING sem contato não sai: sem ele não há como conferir a recusa nem o número.
  def impedimento_do_contato(contato, categoria)
    return if categoria.to_s.upcase != Tipos::MARKETING
    return 'sem_contato' if contato.nil?
    return 'contato_recusou' if contato.opted_out?

    'numero_eua' if contato.phone_number.to_s.start_with?(PREFIXO_EUA)
  end

  # Modelo do sistema: tem dono no perfil ou o nome é de um recurso da plataforma (`SystemTemplates`).
  def sistema?(nome, perfil)
    perfil&.system_owner.present? || Whatsapp::Templates::SystemTemplates.system?(nome)
  end

  # A linha vigente da autorização que vale para a categoria (para o registro do envio): a última, se for "ligou".
  def consentimento_vigente(account, categoria)
    marca = categoria.to_s.upcase == Tipos::MARKETING ? :marketing : :utility
    ultima = WhatsappTemplateConsent.ultima(account, marca)
    ultima.id if ultima&.acao == WhatsappTemplateConsent::LIGOU
  end
end
