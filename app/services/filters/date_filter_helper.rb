# Filtro de data no fuso da conta (#3151). "Criada em" e "Última atividade" são horários; o filtro manda um dia
# (`YYYY-MM-DD`). Antes o dia era comparado em UTC (`created_at::date`), e para uma conta no Brasil o "dia 20" ia das
# 21h do dia 19 às 21h do dia 20. Agora o dia vira o começo dele no fuso da conta, convertido para UTC, e a coluna é
# comparada direto (o Postgres usa o índice). Desenho da consulta do upstream #15843; o fuso é o da conta, nunca o do
# navegador (regra da plataforma, #954/#1568), e vale para todo filtro, pasta salva e API, sem campo novo.
#
# Quem liga: Conversations::FilterService e Contacts::FilterService (e as subclasses), devolvendo o fuso em
# `fuso_dos_filtros_de_data`. Sem ele (automações), tudo fica como antes: dia em UTC e "hoje" do servidor.
module Filters::DateFilterHelper
  TIMESTAMP_ATTRIBUTES = %w[created_at last_activity_at].freeze

  # O fuso da conta (Configurações grava custom_attributes.timezone, copiado para reporting_timezone). Sem fuso, o
  # padrão da plataforma (Crm::Timezone::Resolver), o mesmo dos filtros do link e dos relatórios do CRM.
  def self.fuso_da_conta(account)
    ActiveSupport::TimeZone[account&.reporting_timezone.to_s] ||
      ActiveSupport::TimeZone[Crm::Timezone::Resolver.default_timezone]
  end

  def fuso_dos_filtros_de_data
    nil
  end

  def date_filter(current_filter, query_hash, filter_operator_value)
    column = "#{filter_config[:table_name]}.#{query_hash[:attribute_key]}"
    return "#{column} #{filter_operator_value} #{query_hash[:query_operator]}" if filtro_de_data_no_fuso?(query_hash)

    "(#{column})::#{current_filter['data_type']} #{filter_operator_value} #{query_hash[:query_operator]}"
  end

  def filtro_de_data_no_fuso?(query_hash)
    fuso_dos_filtros_de_data.present? && TIMESTAMP_ATTRIBUTES.include?(query_hash[:attribute_key].to_s)
  end

  # "Depois de 19/11" quer dizer a partir do começo de 20/11; "antes de 20/11", até o começo de 20/11.
  def limite_no_fuso(query_hash, current_index, data)
    depois = query_hash[:filter_operator] == 'is_greater_than'
    dia = depois ? data.next_day : data
    @filter_values["value_#{current_index}"] = fuso_dos_filtros_de_data.local(dia.year, dia.month, dia.day).utc
    "#{depois ? '>=' : '<'} :value_#{current_index}"
  end

  def days_before_filter_query(query_hash, current_index)
    days = Integer(query_hash['values'][0].to_s, 10, exception: false)
    # UI supports 1..998 days; anything else would silently coerce into an
    # unintended cutoff (negative => future date matching everything)
    raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: query_hash['attribute_key']) unless days&.between?(1, 998)

    date = (fuso_dos_filtros_de_data || Time.zone).today - days.days
    updated_query_hash = query_hash.to_h.with_indifferent_access.merge(
      values: [date.strftime],
      filter_operator: 'is_less_than'
    )

    lt_gt_filter_query(updated_query_hash, current_index)
  end
end
