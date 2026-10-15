# Modelos que a própria plataforma usa (#1330): a tela de Modelos mostra o selo "Usado pelo sistema" e a API nova não
# apaga nem altera nenhum deles (duplicar pode). Decidido pelo nome técnico exato que cada recurso cria ou procura:
# - agendamento: os avisos prontos (`Crm::BookingV2::NoticeTemplates::Catalog.names`);
# - anúncios: resumo e alerta do relatório da Meta (`Crm::MetaAds::WhatsappReport::TemplateStatus::NAMES`);
# - satisfação: a pesquisa de satisfação do Chatwoot (`customer_satisfaction_survey_<caixa>[_<versão>]`);
# - avisos por finalidade (#1518): os prontos que o `Garantir` cria (`Finalidades`), com o dono de cada um (cobrança).
module Whatsapp::Templates::SystemTemplates
  module_function

  def owner_for(name)
    name = name.to_s
    return 'agendamento' if Crm::BookingV2::NoticeTemplates::Catalog.names.include?(name)
    return 'anuncios' if Crm::MetaAds::WhatsappReport::TemplateStatus::NAMES.value?(name)

    finalidade = Whatsapp::Templates::Finalidades.dono_de(name)
    return finalidade if finalidade

    'satisfacao' if name.start_with?(CsatTemplateNameService::CSAT_BASE_NAME)
  end

  def system?(name)
    owner_for(name).present?
  end
end
