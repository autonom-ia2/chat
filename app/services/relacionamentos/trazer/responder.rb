# A pessoa respondeu às perguntas da conferência de "Trazer minha lista" (#2896). A tela manda as respostas que tem, e
# mandar de novo a mesma resposta não muda nada.
#
# - "São clientes?": `sim_todas` (todo mundo da lista vira cliente), `ainda_nao` (ninguém) ou `algumas`, com a coluna
#   da planilha que diz quem é (`coluna_cliente`, o índice): essa coluna passa a ter o destino "cliente". Com outra
#   resposta, a coluna que era "cliente" volta a ser informação. O que a tela recebe de volta acompanha as colunas
#   (Relacionamentos::Trazer::Perguntas): a coluna marcada ou desmarcada pela tela das colunas muda a resposta.
# - "De quem é esse telefone?", da coluna de telefone duvidosa: `da_pessoa` (continua sendo o telefone da pessoa, e
#   deixa de ser duvidosa), `da_empresa` (vira telefone da empresa) ou `nao_usar` (não é guardada). É a mesma troca de
#   destino da coluna (Relacionamentos::Trazer::TrocarDestino), com as mesmas recusas (`sem_contato`, `sem_empresa`).
#   A pergunta é sempre sobre a coluna de agora (Relacionamentos::Trazer::Perguntas): a resposta nunca mexe numa coluna
#   que a pessoa já mandou para outro lugar.
#
# Só os códigos e o índice da coluna ficam guardados (`options['trazer']['respostas']`). Tudo sob a trava da importação,
# e nada fica pela metade: a recusa desfaz o que o pedido já tinha mudado.
#
# A resposta que faz a planilha ser lida de novo guarda a conferência como estava no COMEÇO do pedido
# (ContactImports::Trazer::DesfazerMudanca): se a leitura nova falhar, tudo o que este pedido mudou é desfeito.
class Relacionamentos::Trazer::Responder
  Resultado = Relacionamentos::Trazer::TrocarDestino::Resultado
  CLIENTES = %w[sim_todas ainda_nao algumas].freeze
  ALGUMAS = Relacionamentos::Trazer::Perguntas::ALGUMAS
  CLIENTE = Relacionamentos::Trazer::Perguntas::CLIENTE
  DESTINO_DO_TELEFONE = Relacionamentos::Trazer::Perguntas::DESTINO_DO_TELEFONE

  # respostas: { 'clientes' =>, 'coluna_cliente' =>, 'telefone' => }, só as chaves que a tela mandou.
  def initialize(importacao, respostas)
    @importacao = importacao
    @clientes = respostas['clientes']&.to_s
    @coluna_cliente = Integer(respostas['coluna_cliente'].to_s, 10, exception: false)
    @telefone = respostas['telefone']&.to_s
  end

  def call
    resultado = nil
    @importacao.with_lock do
      resultado = responder
      raise ActiveRecord::Rollback if resultado.erro
    end
    @importacao.reload if resultado.erro
    resultado
  end

  private

  def responder
    erro = erro_do_pedido
    return Resultado.new(erro: erro) if erro

    @anterior = ContactImports::Trazer::DesfazerMudanca.copia(@importacao)
    telefone = @telefone ? responder_telefone : Resultado.new(revalida: false)
    return telefone if telefone.erro

    clientes = @clientes ? responder_clientes(lendo_de_novo: telefone.revalida) : telefone
    return clientes if clientes.erro

    conferencia.tirar(ContactImports::Trazer::DesfazerMudanca::AVISO)
    Resultado.new(revalida: telefone.revalida || clientes.revalida)
  end

  def erro_do_pedido
    return ContactImports::Trazer::Conferencia::VENCIDA if ContactImports::Trazer::Conferencia.vencida?(@importacao)
    return 'leitura_nao_pronta' unless @importacao.ready_to_confirm?
    return 'resposta_desconhecida' unless resposta_conhecida?(@clientes, CLIENTES) && resposta_conhecida?(@telefone, DESTINO_DO_TELEFONE.keys)

    erro_da_coluna_ou_da_pergunta
  end

  def resposta_conhecida?(resposta, conhecidas)
    resposta.nil? || conhecidas.include?(resposta)
  end

  def erro_da_coluna_ou_da_pergunta
    return 'coluna_desconhecida' if @clientes == ALGUMAS && colunas.chave_da_extra(@coluna_cliente).nil?

    'pergunta_desconhecida' if @telefone && pergunta_do_telefone.nil?
  end

  def pergunta_do_telefone
    @pergunta_do_telefone ||= Relacionamentos::Trazer::Perguntas.new(@importacao).telefone
  end

  def responder_telefone
    indice = pergunta_do_telefone.fetch(:indice)
    troca = trocar(indice, DESTINO_DO_TELEFONE.fetch(@telefone))
    guardar_respostas({ 'telefone' => @telefone, 'coluna_telefone' => indice }) unless troca.erro
    troca
  end

  # A coluna que era "cliente" volta a ser informação; com "algumas", a coluna escolhida vira "cliente". Voltar de "não
  # guardar" pede ler a planilha de novo, a não ser que a resposta do telefone já tenha pedido.
  def responder_clientes(lendo_de_novo:)
    escolhida = (@coluna_cliente if @clientes == ALGUMAS)
    destinos = conferencia.destinos.reject { |indice, destino| destino == CLIENTE && indice != escolhida.to_s }
    conferencia.gravar('destinos' => destinos)
    guardar_respostas({ 'clientes' => @clientes, 'coluna_cliente' => escolhida }.compact, tirar: ['coluna_cliente'])
    return Resultado.new(revalida: false) unless escolhida
    return trocar(escolhida, CLIENTE) unless lendo_de_novo

    conferencia.gravar('destinos' => conferencia.destinos.merge(escolhida.to_s => CLIENTE))
    Resultado.new(revalida: false)
  end

  def trocar(indice, destino)
    Relacionamentos::Trazer::TrocarDestino.new(@importacao, indice: indice, destino: destino, anterior: @anterior).call
  end

  def guardar_respostas(novas, tirar: [])
    conferencia.gravar('respostas' => conferencia.respostas.except(*tirar).merge(novas))
  end

  # Lidas de novo a cada uso: uma troca no meio do pedido muda as opções da importação.
  def conferencia
    ContactImports::Trazer::Conferencia.new(@importacao)
  end

  def colunas
    Relacionamentos::Trazer::Colunas.new(@importacao)
  end
end
