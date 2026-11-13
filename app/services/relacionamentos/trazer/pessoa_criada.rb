# "Trazer minha lista" (#2896): a pessoa que a lista criou, como a lista a deixou. O "Desfazer" só tira quem a lista
# trouxe e em quem ninguém tocou, e editar a ficha é tocar: quem teve o nome, o telefone, o e-mail, a cidade, a empresa,
# uma informação ou o tipo (lead, cliente) mudados depois da lista fica (Relacionamentos::Trazer::QuemFica).
#
# Para reconhecer isso sem guardar a ficha, a gravação anota o resumo com segredo do que a linha deixou na pessoa
# (Relacionamentos::CampoPreenchido, campo `pessoa_criada`), lido do banco logo depois de a linha escrever tudo: o que
# se compara no Desfazer passa pelo mesmo caminho. Quando uma linha de baixo da mesma lista completa a pessoa que uma
# linha de cima criou, o resumo é refeito: foi a lista que mexeu, não alguém.
#
# Entra tudo o que dá para escrever na ficha (`COLUNAS`): o que a API de contatos aceita gravar
# (Api::V1::Accounts::ContactsController#permitted_params) e o nome do meio e o sobrenome, que são colunas da ficha.
# De `additional_attributes` entra o conjunto inteiro, e não só a cidade: a biografia, o cargo, as redes sociais e o que
# mais alguém escrever ali, menos o que o sistema grava ali sozinho (`DO_SISTEMA`). Se o sistema passar a gravar outra
# chave sozinho depois da lista, a pessoa fica: o erro possível é deixar na base quem podia sair, nunca apagar quem
# alguém editou. A foto não segura ninguém: não é coluna da ficha, e as marcas que a busca dela deixa estão em
# `DO_SISTEMA`. O bloqueio segura a pessoa por outra regra (Relacionamentos::Trazer::QuemFica). O tipo entra porque quem
# a lista criou já nasce lead (tem telefone ou e-mail) e daí só muda por decisão de alguém: marcar ou desmarcar cliente.
# A última atividade e o resto, que mudam sozinhos, ficam de fora. O spec relacionamentos_trazer_ficha_editada_spec.rb
# percorre o que a API aceita, campo a campo: um campo novo aceito pela API sem cobertura quebra o spec.
#
# A pessoa sem anotação (a lista trazida antes de existir a anotação, ou pela tela antiga, que nunca anota) fica: não
# há com o que comparar, e o Desfazer não apaga quem não dá para provar que ninguém editou. O Desfazer de uma lista sem
# anotação nenhuma não tira ninguém.
class Relacionamentos::Trazer::PessoaCriada
  Campo = Relacionamentos::CampoPreenchido
  # Os textos da ficha: vazio e ausente são a mesma coisa.
  TEXTOS = %i[name middle_name last_name identifier phone_number email].freeze
  # Os dois conjuntos de chave e valor: os atributos adicionais e as informações da pessoa.
  CONJUNTOS = %i[additional_attributes custom_attributes].freeze
  COLUNAS = (TEXTOS + %i[company_id contact_type] + CONJUNTOS).freeze
  # O que o sistema grava sozinho em `additional_attributes`, sem ninguém editar a ficha: as marcas da busca da foto
  # (Avatar::AvatarFromUrlJob#update_avatar_sync_attributes). Todo contato salvo com e-mail ganha essa busca uns 30
  # segundos depois (Avatarable#fetch_avatar_from_gravatar), e as marcas são gravadas tenha ela achado foto ou não:
  # dentro do resumo, nenhuma pessoa que a lista criou com e-mail sairia.
  DO_SISTEMA = %w[last_avatar_sync_at avatar_url_hash].freeze

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

  def resumivel(ficha)
    TEXTOS.map { |coluna| ficha[coluna].presence } + [ficha[:company_id], ficha[:contact_type]] +
      CONJUNTOS.map { |coluna| sem_vazios(ficha[coluna].to_h.except(*DO_SISTEMA)) }
  end

  # Vazio e ausente são a mesma coisa, em qualquer nível (a tela de edição manda as redes sociais em branco), e a ordem
  # das chaves não importa. O conjunto vira uma lista de pares em ordem de chave.
  def sem_vazios(valor)
    return valor unless valor.is_a?(Hash)

    valor.transform_values { |dentro| sem_vazios(dentro) }.reject { |_chave, dentro| dentro.nil? || dentro == '' || dentro == [] }.sort
  end
end
