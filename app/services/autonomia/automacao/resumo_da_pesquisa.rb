# O resumo da "Pesquisa de satisfação" (#2936) na lista de automações: a média das notas e quantas pessoas responderam,
# por automação. A nota fica no contato (`additional_attributes.pesquisas.<automação>`, PassoDePesquisa), a última de
# cada pessoa por automação, então cada pessoa conta uma vez. Só números: nenhum nome, nenhum comentário.
#
# Uma consulta só para as automações da página que têm o passo, nos contatos da conta que já responderam alguma
# pesquisa: o índice parcial idx_contacts_com_pesquisa guarda só esses, com o mesmo filtro da consulta (o `jsonb_typeof`
# abaixo; mudou um, mude o outro). Sem pesquisa na página, nenhuma consulta.
module Autonomia::Automacao::ResumoDaPesquisa
  PESQUISAS = ::Autonomia::Automacao::PassoDePesquisa::POR_AUTOMACAO
  TIPO = ::Autonomia::Automacao::PassosQueEsperam::PESQUISA
  CASAS = 1

  module_function

  # { automacao_id => { media:, respostas: } }; a automação com o passo e sem resposta ainda leva { media: nil, respostas: 0 }.
  def das(conta, automacoes)
    ids = automacoes.select { |automacao| com_pesquisa?(automacao) }.map(&:id)
    return {} if ids.empty?

    lidas = contagens(conta, ids)
    ids.index_with { |id| lidas.fetch(id.to_s, { media: nil, respostas: 0 }) }
  end

  def com_pesquisa?(automacao)
    receita = automacao.versao_ativa&.receita
    receita.is_a?(Hash) && ::Autonomia::Automacao::Receita.new(receita, conta: nil, account_user: nil).passos.any? { |passo| passo['tipo'] == TIPO }
  end

  def contagens(conta, ids)
    linhas = conta.contacts.where("jsonb_typeof(contacts.additional_attributes -> '#{PESQUISAS}') = 'object'")
                  .joins(Arel.sql("CROSS JOIN LATERAL jsonb_each(contacts.additional_attributes -> '#{PESQUISAS}') AS pesquisa"))
                  .where(pesquisa: { key: ids.map(&:to_s) })
                  .group('pesquisa.key')
                  .pluck(Arel.sql('pesquisa.key'), Arel.sql("AVG((pesquisa.value ->> 'nota')::numeric)"), Arel.sql('COUNT(*)'))
    linhas.to_h { |chave, media, total| [chave, { media: media&.to_f&.round(CASAS), respostas: total }] }
  end
end
