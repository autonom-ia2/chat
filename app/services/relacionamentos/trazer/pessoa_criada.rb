# "Trazer minha lista" (#2896): a pessoa que a lista criou, como a lista a deixou. O "Desfazer" só tira quem a lista
# trouxe e em quem ninguém tocou, e editar a ficha é tocar: quem teve qualquer coisa da ficha mudada depois da lista (o
# nome, o telefone, a empresa, a relação, uma informação, o tipo) fica (Relacionamentos::Trazer::QuemFica).
#
# Para reconhecer isso sem guardar a ficha, a gravação anota o resumo com segredo do que a linha deixou na pessoa
# (Relacionamentos::CampoPreenchido, campo `pessoa_criada`), lido do banco logo depois de a linha escrever tudo: o que
# se compara no Desfazer passa pelo mesmo caminho. Quando uma linha de baixo da mesma lista completa a pessoa que uma
# linha de cima criou, o resumo é refeito: foi a lista que mexeu, não alguém.
#
# O resumo cobre TODAS as colunas de `contacts`, menos a lista fechada das que o sistema mantém sozinho (`DE_FORA`). A
# coluna que for criada depois entra no resumo sem ninguém lembrar dela: o erro possível é deixar na base quem podia
# sair, nunca apagar quem alguém editou. Assim entram, sem lista à mão, o que a API de contatos aceita gravar, a relação
# (interessado, parceiro, não é negócio), o bloqueio, a recusa, a marca de cliente e o que mais uma pessoa ou o cliente
# muda. O valor vazio e o valor igual ao padrão da coluna não entram: são o mesmo que a coluna não existir, e por isso
# a coluna nova, que nasce vazia ou no padrão em todo mundo, não muda o resumo de quem a lista já anotou.
#
# Dos dois conjuntos de chave e valor (`additional_attributes` e `custom_attributes`) entra tudo, sem os vazios, em
# qualquer nível. De `additional_attributes` só ficam de fora as chaves que o sistema grava sem ninguém editar a ficha
# (`DO_SISTEMA`). A foto não segura ninguém: não é coluna da ficha.
#
# O nome da empresa escrito na ficha (`company_name`) é um valor como os outros: entra sempre, com o que estiver
# escrito, tenha a pessoa empresa ligada ou não. Consequência aceita: quando alguém RENOMEIA A EMPRESA, o sistema
# regrava esse nome na ficha de cada pessoa dela (Companies::SyncContactNamesJob), o resumo delas muda e todas passam a
# contar como ficha editada: FICAM na base quando a lista é desfeita, mesmo sem ninguém ter mexido nelas. O erro é para
# o lado de não apagar. Tentar adivinhar se o nome é cópia do da empresa erra para o outro lado: apaga quem teve o nome
# apagado ou trocado à mão.
#
# A pessoa sem anotação (a lista trazida antes de existir a anotação, ou pela tela antiga, que nunca anota) fica: não
# há com o que comparar, e o Desfazer não apaga quem não dá para provar que ninguém editou. O Desfazer de uma lista sem
# anotação nenhuma não tira ninguém.
class Relacionamentos::Trazer::PessoaCriada
  Campo = Relacionamentos::CampoPreenchido
  # As colunas de `contacts` que ficam fora do resumo: só as que o sistema mantém sozinho. Na dúvida, a coluna entra.
  # - id e account_id: a chave da linha e a conta, que não mudam;
  # - created_at e updated_at: os carimbos do banco; toda gravação move o segundo, inclusive as do sistema;
  # - last_activity_at: movida pela mensagem que chega (e aí há conversa, que segura por outra regra);
  # - location e country_code: cópias da cidade e do país de `additional_attributes`, refeitas a cada gravação
  #   (Contacts::SyncAttributes).
  DE_FORA = %w[id account_id created_at updated_at last_activity_at location country_code].freeze
  ADICIONAIS = 'additional_attributes'.freeze
  # O que o sistema grava sozinho em `additional_attributes`, sem ninguém editar a ficha:
  # - last_avatar_sync_at e avatar_url_hash: as marcas da busca da foto
  #   (Avatar::AvatarFromUrlJob#update_avatar_sync_attributes). Todo contato salvo com e-mail ganha essa busca uns 30
  #   segundos depois (Avatarable#fetch_avatar_from_gravatar), e as marcas são gravadas tenha ela achado foto ou não:
  #   dentro do resumo, nenhuma pessoa que a lista criou com e-mail sairia;
  # - external: o código da pessoa no CRM de fora, guardado pela integração quando ela manda o contato para lá
  #   (Crm::BaseProcessorService#store_external_id).
  DO_SISTEMA = %w[last_avatar_sync_at avatar_url_hash external].freeze

  # As colunas que entram no resumo, em ordem de nome.
  def self.colunas
    @colunas ||= (Contact.column_names - DE_FORA).sort.freeze
  end

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
    colunas = self.class.colunas
    Contact.where(account_id: @conta_id, id: ids).pluck(:id, *colunas).to_h { |id, *valores| [id, resumivel(colunas.zip(valores).to_h)] }
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

  # coluna => valor, em ordem de coluna, só do que não está vazio nem no padrão da coluna.
  def resumivel(ficha)
    padroes = Contact.column_defaults
    sem_o_do_sistema = ficha.merge(ADICIONAIS => ficha[ADICIONAIS].to_h.except(*DO_SISTEMA))
    sem_o_do_sistema.transform_values { |valor| normal(valor) }.reject { |coluna, valor| vazio?(valor) || valor == normal(padroes[coluna]) }
  end

  # O valor na forma que é resumida. No conjunto, vazio e ausente são a mesma coisa, em qualquer nível (a tela de edição
  # manda as redes sociais em branco), e a ordem das chaves não importa; ele continua sendo um conjunto, para não se
  # confundir com uma lista de pares. A data vai com o instante exato que o banco guarda.
  def normal(valor)
    case valor
    when Hash then valor.transform_values { |dentro| normal(dentro) }.reject { |_chave, dentro| vazio?(dentro) }.sort.to_h
    when Time, ActiveSupport::TimeWithZone then Campo.instante(valor)
    else valor
    end
  end

  def vazio?(valor)
    valor.nil? || valor == '' || valor == {} || valor == []
  end
end
