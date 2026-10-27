# Formulários instantâneos dos anúncios (#2195), parte do Meta::AdsGraphClient: mesmas regras de token, versão e limpeza
# de erro (usa o `get`/`post`/`each_page` privados dele). Tudo aqui, menos `pages_with_tokens`, roda com o token da
# Página, que sai do token do cliente na hora e nunca é guardado.
module Meta::AdsGraphClient::LeadForms
  LEAD_FORM_FIELDS = 'id,name,status,leads_count'.freeze
  LEAD_FORM_QUESTION_FIELDS = 'id,questions{key,label}'.freeze
  LEAD_FIELDS = 'id,created_time,ad_id,ad_name,campaign_name,form_id,field_data'.freeze
  LEAD_FORMS_LIMIT = 100
  LEADS_PAGE_LIMIT = 100
  # A Meta guarda o lead por 90 dias. 500 páginas de 100 (50 mil leads) é o teto de segurança da leitura em segundo
  # plano: passando dele, quem chama recebe truncated e avisa.
  LEADS_MAX_PAGES = 500

  # Páginas que a pessoa concedeu, com o token de cada uma (pages_show_list). O token só segue para o cliente da Graph.
  def pages_with_tokens
    get('me/accounts', fields: 'id,name,access_token', limit: Meta::AdsGraphClient::Management::PAGES_LIMIT)
  end

  # pages_manage_ads + leads_retrieval.
  def leadgen_forms(page_id)
    get("#{page_id}/leadgen_forms", fields: LEAD_FORM_FIELDS, limit: LEAD_FORMS_LIMIT)
  end

  # As perguntas do formulário, para o card mostrar "Para quando?" e não "quando".
  def lead_form_questions(form_id)
    get(form_id.to_s, fields: LEAD_FORM_QUESTION_FIELDS)
  end

  # Quem preencheu desde `since` (leads_retrieval), página a página até o fim. Devolve o último Result e se parou no
  # teto com mais páginas na Meta (truncated).
  def each_form_lead(form_id, since:)
    filtering = [{ field: 'time_created', operator: 'GREATER_THAN', value: since.to_i }].to_json
    pages = 0
    result = each_page("#{form_id}/leads", { fields: LEAD_FIELDS, filtering: filtering, limit: LEADS_PAGE_LIMIT },
                       max_pages: LEADS_MAX_PAGES) do |batch|
      pages += 1
      yield batch
    end
    [result, result.ok && pages == LEADS_MAX_PAGES && result.data.to_h.dig('paging', 'next').present?]
  end

  # Um lead pelo id que o webhook leadgen traz (leads_retrieval).
  def lead(leadgen_id)
    get(leadgen_id.to_s, fields: LEAD_FIELDS)
  end

  # Apps assinados na Página e os campos de cada um (pages_manage_metadata).
  def subscribed_apps(page_id)
    get("#{page_id}/subscribed_apps")
  end

  # Troca a lista inteira de campos do app na Página.
  def subscribe_page(page_id, fields)
    post("#{page_id}/subscribed_apps", subscribed_fields: fields.join(','))
  end

  def unsubscribe_page(page_id)
    request(:delete, "#{page_id}/subscribed_apps")
  end
end
