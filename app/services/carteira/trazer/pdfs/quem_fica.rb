# "Trazer por PDFs" (E6.3, #2899): das pessoas que um lote de PDFs criou, quais o "Desfazer" não apaga. As regras são as
# do Desfazer da planilha (Relacionamentos::Trazer::QuemFica: conversa, card, nota, etiqueta, campanha, outra lista,
# agenda, memória, lead, recusa, seguro que continua na carteira), lidas pelas mesmas fontes. Muda só:
#
# - quem o lote criou: a pessoa marcada no item ao trazer (Carteira::ItemLido::PESSOA_NOVA). Item que a guarda já
#   limpou não marca mais ninguém, e a pessoa fica;
# - "teve a ficha editada": o nome, o telefone ou o e-mail já não são os que o lote deixou, ou alguém pôs informação
#   nela (atributos). Na dúvida, fica;
# - nenhuma importação de planilha deixa de segurar (o lote não é importação).
#
# seguros_ja_desfeitos: o Desfazer pergunta depois de a parte dos seguros rodar; aí todo seguro que ainda existe segura a
# pessoa. A prévia, que roda antes, desconta os seguros que vão sair (Carteira::Trazer::Pdfs::SegurosDoLote#saem).
class Carteira::Trazer::Pdfs::QuemFica < Relacionamentos::Trazer::QuemFica
  SegurosQueFicam = Struct.new(:que_ficam)

  # rubocop:disable Lint/MissingSuper
  def initialize(leitura, seguros_ja_desfeitos: false)
    @leitura = leitura
    @conta = leitura.account
    todos = Carteira::Apolice.where(account_id: @conta.id)
    ficam = seguros_ja_desfeitos ? todos : todos.where.not(id: Carteira::Trazer::Pdfs::SegurosDoLote.new(leitura).saem.select(:id))
    @seguros = SegurosQueFicam.new(ficam)
  end
  # rubocop:enable Lint/MissingSuper

  # Bloco a bloco, das pessoas que o lote criou e que ainda existem: os ids das que saem e os das que ficam.
  def em_blocos
    criadas.each_slice(BLOCO) do |ids|
      existem = @conta.contacts.where(id: ids).ids
      ficam = entre(existem)
      yield existem.reject { |id| ficam.include?(id) }, ficam.to_a
    end
  end

  # Os ids das pessoas que o lote criou.
  def criadas
    itens_das_criadas.distinct.pluck(:contact_id)
  end

  def entre(ids)
    return Set.new if ids.empty?

    seguradas = onde_aparece.flat_map { |registros, coluna| registros.where(coluna => ids).distinct.pluck(coluna) }.to_set
    seguradas.merge(tocadas(ids - seguradas.to_a))
  end

  private

  def itens_das_criadas
    @leitura.itens.where(estado: 'trazido').where.not(contact_id: nil)
            .where('carteira_leitura_itens.campos ->> ? IS NOT NULL', Carteira::ItemLido::PESSOA_NOVA)
  end

  def que_nao_seguram
    Relacionamentos::Trazer::Situacao.desfeitas(@conta.campaign_imports).ids
  end

  # As pessoas cuja ficha não é mais a que o lote deixou.
  def tocadas(ids)
    como_nasceram = itens_das_criadas.where(contact_id: ids).index_by(&:contact_id)
    @conta.contacts.where(id: ids).reject { |pessoa| como_nasceu?(pessoa, como_nasceram[pessoa.id]) }.map(&:id)
  end

  def como_nasceu?(pessoa, item)
    return false unless item

    lido = Carteira::ItemLido.new(item)
    telefone = lido.certo('segurado_telefone')
    pessoa.name.to_s.strip == lido.certo('segurado_nome').to_s.strip &&
      pessoa.phone_number.to_s == (telefone ? Crm::BookingV2::PhoneLookup.normalize(telefone) : nil).to_s &&
      pessoa.email.to_s.downcase == lido.certo('segurado_email').to_s.strip.downcase &&
      pessoa.additional_attributes.blank? && pessoa.custom_attributes.blank?
  end
end
