json.itens do
  json.array! @consulta.itens, partial: 'api/v1/accounts/relacionamentos/pessoas/pessoa', as: :pessoa
end
json.total @consulta.total
json.tem_mais @consulta.tem_mais?
