json.partial! 'api/v1/accounts/relacionamentos/empresas/empresa', empresa: @empresa
# #3078 — o que só a ficha mostra: a descrição e os campos personalizados da empresa.
json.description @empresa.description
json.custom_attributes @empresa.custom_attributes.to_h
