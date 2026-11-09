# Um item do passo "para cada item" (#2414 G24, #2771): o contato e o card dele. Uma instância por rodada, que conta o
# que fez em todos os itens.
#
# - O contato sai da mesma linha do Importar contatos (CampaignImports::ContactRow), como quem ligou: achado pelo
#   telefone (com ou sem o nono dígito), senão criado com o nome e o telefone. O contato que já existe só ganha o que não
#   tem; nome e telefone preenchidos nunca são trocados. A exceção da D4 A (o telefone vindo da IA) vale só por essa
#   régua. O item sem telefone vira um contato só com o nome. O telefone que não é celular do Brasil
#   (CampaignImports::PhoneNormalizer, o mesmo do import) pula o item: um contato só com o nome duplicaria quem já existe.
# - Os outros campos (a data de nascimento do exemplo 8) vão para o contato como as colunas extras do Importar contatos
#   (ContactImports::CustomAttributes): a chave do campo é o cabeçalho da coluna, o atributo que não existe nasce como
#   texto, o atributo com tipo (data, número) converte o valor ou o deixa de fora, e o contato só ganha o que não tem.
# - A empresa é a do solicitante (o contato da conversa, quem mandou a lista), pelo mesmo CompanyLinker do import: vai
#   para o contato sem empresa; o de outra empresa fica como está (decisão e).
# - O card nasce na etapa pelo "criar card" (PassoDeCard), ligado só ao contato. O card aberto do contato no mesmo funil
#   já conta, e o item pula com `card_ja_existe`, sem duplicar.
# - O solicitante não fica no card: o card não tem campo para isso, e o histórico da execução já liga a conversa dele
#   aos cards (`card_ids`).
class Autonomia::Automacao::ItemDoParaCada
  NOME = ::Autonomia::Automacao::PassoParaCada::NOME
  TELEFONE = 'telefone'.freeze
  Negado = Struct.new(:motivo)

  attr_reader :contagem

  def initialize(execucao:, passo:, etapa:, acesso:, solicitante:)
    @execucao = execucao
    @passo = passo
    @etapa = etapa
    @acesso = acesso
    @empresa = solicitante.try(:company)&.name
    @contagem = { 'cards_criados' => 0, 'contatos_novos' => 0, 'empresas_ligadas' => 0, 'pulados' => {}, 'card_ids' => [] }
  end

  # nil, ou o Negado quando quem ligou perdeu a permissão no meio: a automação pausa.
  def abrir(valores)
    telefone = telefone(valores[TELEFONE])
    return pular('telefone_invalido') if telefone == false

    linha_do_item = { name: valores[NOME], phone_number: telefone, email: nil, company_name: @empresa }
    extras = valores.except(NOME, TELEFONE).compact
    atributos if extras.any? && linha.allowed?
    # Contato, empresa e atributos juntos, como na savepoint de cada linha do import.
    escrito = ActiveRecord::Base.transaction { linha.write(linha_do_item).tap { |feito| gravar_extras(feito.contact, extras) } }
    contar_contato(escrito)
    card(escrito.contact)
  rescue ::CampaignImports::ContactRow::NotAllowed
    Negado.new('quem_ligou_sem_permissao_importar')
  rescue ActiveRecord::RecordInvalid
    pular('contato_recusado')
  end

  private

  def card(contato)
    passo = { 'id' => @passo['id'], 'etapa_id' => @etapa.id }
    resultado = ::Autonomia::Automacao::PassoDeCard.new(execucao: @execucao, passo: passo, alvo: contato, acesso: @acesso).executar
    return Negado.new(resultado.motivo) if resultado.tipo == :sem_acesso
    return pular(resultado.motivo) unless resultado.tipo == :ok

    @contagem['cards_criados'] += 1
    @contagem['card_ids'] << resultado.dados['card_id']
    nil
  end

  # O número no formato do import, nil sem telefone, false quando não é celular do Brasil.
  def telefone(texto)
    return if texto.blank?

    ::CampaignImports::PhoneNormalizer.normalize!(texto).phone_number
  rescue ::CampaignImports::PhoneNormalizer::Error
    false
  end

  def contar_contato(escrito)
    @contagem['contatos_novos'] += 1 unless escrito.existing
    @contagem['empresas_ligadas'] += 1 if escrito.company&.linked?
  end

  def pular(motivo)
    @contagem['pulados'][motivo] = @contagem['pulados'].fetch(motivo, 0) + 1
    nil
  end

  def gravar_extras(contato, extras)
    atributos.merge!(contato, extras) if extras.any?
  end

  # Uma vez por rodada, antes do 1º item com campo extra: cria os atributos de texto que ainda não existem.
  def atributos
    @atributos ||= ::ContactImports::CustomAttributes.for_columns(@execucao.account, chaves_extras).tap(&:prepare!)
  end

  def chaves_extras = Array(@passo['campos']).pluck('chave') - [NOME, TELEFONE]

  def linha
    @linha ||= ::CampaignImports::ContactRow.new(@execucao.account, account_user: @acesso.account_user, linker: linker)
  end

  def linker = (::CampaignImports::CompanyLinker.new(@execucao.account) if @empresa)
end
