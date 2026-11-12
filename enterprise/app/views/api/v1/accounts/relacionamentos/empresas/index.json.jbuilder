json.itens do
  json.array! @consulta.itens, partial: 'api/v1/accounts/relacionamentos/empresas/empresa', as: :empresa
end
json.total @consulta.total
json.tem_mais @consulta.tem_mais?
