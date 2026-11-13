# "Trazer minha lista" (#2896): a pessoa que a lista criou, como a lista a deixou. O "Desfazer" só tira quem a lista
# trouxe e em quem ninguém tocou, e editar a ficha é tocar: quem teve o nome, o telefone, o e-mail, a cidade, a empresa,
# uma informação ou o tipo (lead, cliente) mudados depois da lista fica (Relacionamentos::Trazer::QuemFica).
#
# Para reconhecer isso sem guardar a ficha, a gravação anota o resumo com segredo do que a linha deixou na pessoa
# (Relacionamentos::CampoPreenchido, campo `pessoa_criada`), lido do banco logo depois de a linha escrever tudo: o que
# se compara no Desfazer passa pelo mesmo caminho. Quando uma linha de baixo da mesma lista completa a pessoa que uma
# linha de cima criou, o resumo é refeito: foi a lista que mexeu, não alguém.
#
# Só entra o que alguém muda na ficha (`COLUNAS`, e de `additional_attributes` só a cidade). O tipo entra porque quem
# a lista criou já nasce lead (tem telefone ou e-mail) e daí só muda por decisão de alguém: marcar ou desmarcar cliente.
# A última atividade e o resto, que mudam sozinhos, ficam de fora.
#
# A pessoa sem anotação (a lista trazida antes de existir a anotação, ou pela tela antiga, que nunca anota) fica: não
# há com o que comparar, e o Desfazer não apaga quem não dá para provar que ninguém editou. O Desfazer de uma lista sem
# anotação nenhuma não tira ninguém.
class Relacionamentos::Trazer::PessoaCriada
  Campo = Relacionamentos::CampoPreenchido
  CIDADE = ContactImports::Trazer::DestinosDaLinha::CIDADE
  COLUNAS = %i[name phone_number email company_id contact_type additional_attributes custom_attributes].freeze

  def initialize(importacao)
    @importacao = importacao
    @conta_id = importacao.account_id
  end

  # O que a pessoa tem agora, na forma que é resumida. id: uma pessoa da conta, que existe.
  def conteudo(id)
    conteudos([id]).fetch(id)
  end

  # { id => conteúdo }, só das pessoas que ainda existem. Uma consulta.
  def conteudos(ids)
    Contact.where(account_id: @conta_id, id: ids).pluck(:id, *COLUNAS).to_h { |id, *colunas| [id, resumivel(COLUNAS.zip(colunas).to_h)] }
  end

  # Uma linha de baixo completou a pessoa que esta lista criou: o resumo passa a ser o de agora. Quem não foi criada por
  # esta lista não tem anotação, e nada acontece.
  def refazer(id)
    anotacao = anotacoes([id]).first
    return if anotacao.nil?

    anotacao.update!(valor_posto_hash: Campo.resumo(anotacao.campaign_import_row_id, Campo::PESSOA_CRIADA, conteudo(id)))
  end

  # ids: pessoas da conta. Devolve o conjunto das que não dá para dizer que estão como a lista as deixou: as que alguém
  # editou depois e as que a lista não anotou. Duas consultas, quantas forem as pessoas.
  def tocadas(ids)
    return Set.new if ids.empty?

    anotadas = anotacoes(ids).index_by(&:contact_id)
    conteudos(ids).filter_map { |id, atual| id unless anotadas[id]&.mesmo_valor?(atual) }.to_set
  end

  private

  def anotacoes(ids)
    Campo.da_importacao(@importacao).where(campo: Campo::PESSOA_CRIADA, contact_id: ids)
  end

  # Vazio e ausente são a mesma coisa, e a ordem das informações não importa.
  def resumivel(ficha)
    informacoes = ficha[:custom_attributes].to_h.reject { |_chave, valor| valor.nil? || valor == '' }
    [ficha[:name].presence, ficha[:phone_number].presence, ficha[:email].presence, ficha[:company_id], ficha[:contact_type],
     ficha[:additional_attributes].to_h[CIDADE].presence, informacoes.sort]
  end
end
