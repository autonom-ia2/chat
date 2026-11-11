# #2858 F5: a base baixada leva `atualizado_em` (o dia em que a cópia que vale entrou), para o "atualizado em…" do
# cartão; nil enquanto ela não foi baixada. As outras fontes não levam o campo.
atualizacoes = Autonomia::FerramentasProntas::Bases::Estado.atualizacoes
bases = Autonomia::FerramentasProntas::Bases.importadores.map(&:chave)
json.fontes @fontes do |fonte|
  json.chave fonte.chave
  json.atualizado_em atualizacoes[fonte.chave]&.to_date&.iso8601 if bases.include?(fonte.chave)
end
json.incluidas @incluidas do |pronta|
  json.partial! 'api/v1/accounts/autonomia/ferramentas_prontas/pronta', pronta: pronta
end
