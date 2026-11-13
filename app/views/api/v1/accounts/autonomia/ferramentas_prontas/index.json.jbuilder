# #2858 F5: a base baixada leva `atualizado_em` (o dia em que a cópia que vale entrou), para o "atualizado em…" do
# cartão; nil enquanto ela não foi baixada. E `em_preparacao`: nunca entrou e a primeira importação já falhou (o motivo
# fica no log, não vai à tela). As outras fontes não levam os campos.
atualizacoes = Autonomia::FerramentasProntas::Bases::Estado.atualizacoes
em_preparacao = Autonomia::FerramentasProntas::Bases::Estado.em_preparacao
bases = Autonomia::FerramentasProntas::Bases.importadores.map(&:chave)
json.fontes @fontes do |fonte|
  json.chave fonte.chave
  json.consultas fonte.consultas.size unless fonte.premium?
  json.premium @premium[fonte.chave] if @premium.key?(fonte.chave)
  if bases.include?(fonte.chave)
    json.atualizado_em atualizacoes[fonte.chave]&.to_date&.iso8601
    json.em_preparacao em_preparacao.include?(fonte.chave)
  end
end
json.incluidas @incluidas do |pronta|
  json.partial! 'api/v1/accounts/autonomia/ferramentas_prontas/pronta', pronta: pronta
end
