# Um item do passo "para cada item" (#2414 G24, #2771): o contato e o card dele. Uma instância por rodada, que conta o
# que fez em todos os itens.
#
# - O contato sai da mesma linha do Importar contatos (CampaignImports::ContactRow), como quem ligou: achado pelo
#   telefone (com ou sem o nono dígito), senão criado com o nome e o telefone. O contato que já existe só ganha o que não
#   tem; nome e telefone preenchidos nunca são trocados. A exceção da D4 A (o telefone vindo da IA) vale só por essa
#   régua. O item sem telefone vira um contato só com o nome. O telefone que não é celular do Brasil
#   (CampaignImports::PhoneNormalizer, o mesmo do import) pula o item: um contato só com o nome duplicaria quem já existe.
#   Cada item vira uma linha do registro de importação da rodada (ImportacaoDoParaCada): a lista aparece em
#   Contatos > Importações, com quem entrou e quem ficou de fora (decisão 15).
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

  # passo: a receita do passo, com o `etapa_id` da etapa já conferida.
  def initialize(execucao:, passo:, acesso:, solicitante:, importacao:)
    @execucao = execucao
    @importacao = importacao
    @passo = passo
    @acesso = acesso
    @empresa = solicitante.try(:company)&.name
    @contagem = { 'cards_criados' => 0, 'contatos_novos' => 0, 'empresas_ligadas' => 0, 'pulados' => {}, 'card_ids' => [] }
  end

  # nil, ou o Negado quando quem ligou perdeu a permissão no meio: a automação pausa. O atributo que a conta recusa criar
  # não é do contato: levanta a Falha (`atributo_recusado`) e o passo falha, em vez de pular cada item.
  # numero: a posição do item na lista (1, 2…), a linha dele no registro de importação.
  def abrir(valores, numero)
    telefone = telefone(valores[TELEFONE])
    return de_fora(numero, valores, ::Autonomia::Automacao::ImportacaoDoParaCada::TELEFONE_INVALIDO, 'telefone_invalido') if telefone == false

    extras = valores.except(NOME, TELEFONE).compact
    preparar_atributos if extras.any? && linha.allowed?
    escrever(numero, valores, { name: valores[NOME], phone_number: telefone, email: nil, company_name: @empresa }, extras)
  rescue ::CampaignImports::ContactRow::NotAllowed
    Negado.new('quem_ligou_sem_permissao_importar')
  end

  private

  # Contato, empresa e atributos juntos, como na savepoint de cada linha do import.
  # A linha da importação fica fora do rescue: não conseguir gravá-la é falha do passo, não contato recusado.
  def escrever(numero, valores, linha_do_item, extras)
    escrito = contato(linha_do_item, extras)
    return de_fora(numero, valores, ::Autonomia::Automacao::ImportacaoDoParaCada::CONTATO_RECUSADO, 'contato_recusado') if escrito.nil?

    @importacao.entrou(numero, escrito, nome: valores[NOME], telefone: linha_do_item[:phone_number])
    contar_contato(escrito)
    card(escrito.contact)
  end

  # O ContactRow::Result, ou nil quando a conta recusa o contato.
  def contato(linha_do_item, extras)
    ActiveRecord::Base.transaction { linha.write(linha_do_item).tap { |feito| gravar_extras(feito.contact, extras) } }
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # O item fica de fora da importação (com o motivo dela) e pula (com o motivo do registro da execução).
  def de_fora(numero, valores, motivo_da_importacao, motivo)
    @importacao.ficou_de_fora(numero, nome: valores[NOME], telefone_escrito: valores[TELEFONE], motivo: motivo_da_importacao)
    pular(motivo)
  end

  def card(contato)
    passo = { 'id' => @passo['id'], 'etapa_id' => @passo['etapa_id'] }
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
    @atributos.merge!(contato, extras) if extras.any?
  end

  # Uma vez por rodada, antes do 1º item com campo extra: cria os atributos de texto que ainda não existem.
  def preparar_atributos
    @atributos ||= ::ContactImports::CustomAttributes.for_columns(@execucao.account, chaves_extras).tap do |atributos|
      @importacao.atributos_criados(atributos.prepare!)
    end
  rescue ActiveRecord::RecordInvalid
    raise ::Autonomia::Automacao::PassoDeIa::Falha.new(:permanente, 'atributo_recusado')
  end

  def chaves_extras = Array(@passo['campos']).pluck('chave') - [NOME, TELEFONE]

  def linha
    @linha ||= ::CampaignImports::ContactRow.new(@execucao.account, account_user: @acesso.account_user, linker: linker)
  end

  def linker = (::CampaignImports::CompanyLinker.new(@execucao.account) if @empresa)
end
