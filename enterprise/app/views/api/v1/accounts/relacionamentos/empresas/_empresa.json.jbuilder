# Uma empresa como as telas novas de Relacionamentos leem (#2894). Datas em segundos, como a empresa de hoje.
# #3078 — e a foto e a cidade, que a linha da lista e o cabeçalho da ficha mostram (a lista de Empresas de hoje
# mostrava a foto).
json.id empresa.id
json.name empresa.name
json.domain empresa.domain
json.cnpj empresa.additional_attributes.to_h['cnpj']
json.city empresa.additional_attributes.to_h['city']
json.thumbnail empresa.avatar_url
json.created_at empresa.created_at.to_i
json.contacts_count empresa.contacts_count
json.customers_count empresa.customers_count
json.last_activity_at empresa.last_activity_at&.to_i
