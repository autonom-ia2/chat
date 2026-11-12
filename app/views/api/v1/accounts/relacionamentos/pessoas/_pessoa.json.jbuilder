# Uma pessoa como as telas novas de Relacionamentos leem (#2894). Datas em segundos, como o contato de hoje.
json.id pessoa.id
json.name pessoa.name
json.email pessoa.email
json.phone_number pessoa.phone_number
json.thumbnail pessoa.avatar_url
json.blocked pessoa.blocked
json.contact_type pessoa.contact_type
json.customer_since pessoa.customer_since&.to_i
json.last_activity_at pessoa.last_activity_at&.to_i
json.created_at pessoa.created_at.to_i
json.additional_attributes pessoa.additional_attributes
json.custom_attributes pessoa.custom_attributes
# Lê as marcações já carregadas (Consulta#com_o_que_a_linha_usa); label_list faria uma consulta por pessoa.
json.labels(pessoa.label_taggings.reject(&:tagger_id).filter_map { |marcacao| marcacao.tag&.name })
json.company_id pessoa.company_id if Current.account.feature_enabled?('companies')
json.opted_out_at pessoa.opted_out_at&.to_i
json.opt_out_source pessoa.opt_out_source
