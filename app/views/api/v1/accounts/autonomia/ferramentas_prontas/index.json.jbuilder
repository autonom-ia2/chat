json.fontes @fontes do |fonte|
  json.chave fonte.chave
end
json.incluidas @incluidas do |pronta|
  json.partial! 'api/v1/accounts/autonomia/ferramentas_prontas/pronta', pronta: pronta
end
