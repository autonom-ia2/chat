module CustomExceptions::CustomFilter
  class InvalidAttribute < CustomExceptions::Base
    def message
      I18n.t('errors.custom_filters.invalid_attribute', key: @data[:key], allowed_keys: @data[:allowed_keys].join(','))
    end
  end

  class InvalidOperator < CustomExceptions::Base
    def message
      I18n.t('errors.custom_filters.invalid_operator', attribute_name: @data[:attribute_name], allowed_keys: @data[:allowed_keys].join(','))
    end
  end

  class InvalidQueryOperator < CustomExceptions::Base
    def message
      I18n.t('errors.custom_filters.invalid_query_operator')
    end
  end

  class InvalidValue < CustomExceptions::Base
    def message
      I18n.t('errors.custom_filters.invalid_value', attribute_name: @data[:attribute_name])
    end
  end

  # #2271: o filtro por campanha aceita até Crm::AnuncioDeOrigem::Ids::MAX_IDS ids (cada um é conferido nos toques da conta).
  class TooManyCampaigns < CustomExceptions::Base
    def message
      I18n.t('errors.custom_filters.too_many_campaigns', limit: @data[:limit])
    end

    def to_hash
      { error: message }
    end

    def http_status
      :unprocessable_entity
    end
  end
end
