# A pessoa respondeu às perguntas da conferência de "Trazer minha lista" (#2896). A tela manda as respostas que tem, e
# mandar de novo a mesma resposta não muda nada.
#
# - "São clientes?": `sim_todas` (todo mundo da lista vira cliente), `ainda_nao` (ninguém) ou `algumas`, com a coluna
#   da planilha que diz quem é (`coluna_cliente`, o índice): essa coluna passa a ter o destino "cliente". Com outra
#   resposta, a coluna que era "cliente" volta a ser informação. O que a tela recebe de volta acompanha as colunas
#   (Relacionamentos::Trazer::Perguntas): a coluna marcada ou desmarcada pela tela das colunas muda a resposta.
# - "Quais destes querem dizer cliente?" (`valores_cliente`): toda linha com algo escrito na coluna, ou as chaves dos
#   valores que a pessoa marcou (Relacionamentos::Trazer::EscolhaDosValores). Pode vir sozinha ou junto de "São
#   clientes?": vale para a coluna como o pedido a deixa. Trocar essa coluna apaga a escolha.
# - "De quem é esse telefone?", da coluna de telefone duvidosa: `da_pessoa` (continua sendo o telefone da pessoa, e
#   deixa de ser duvidosa), `da_empresa` (vira telefone da empresa) ou `nao_usar` (não é guardada). É a mesma troca de
#   destino da coluna (Relacionamentos::Trazer::TrocarDestino), com as mesmas recusas (`sem_contato`, `sem_empresa`).
#   A pergunta é sempre sobre a coluna de agora (Relacionamentos::Trazer::Perguntas): a resposta nunca mexe numa coluna
#   que a pessoa já mandou para outro lugar.
#
# Só os códigos, o índice da coluna e as chaves dos valores ficam guardados (`options['trazer']['respostas']`). Tudo
# sob a trava da importação, e nada fica pela metade: a recusa desfaz o que o pedido já tinha mudado.
#
# A resposta que faz a planilha ser lida de novo guarda a conferência como estava no COMEÇO do pedido
# (ContactImports::Trazer::DesfazerMudanca): se a leitura nova falhar, tudo o que este pedido mudou é desfeito.
class Relacionamentos::Trazer::Responder
  Resultado = Relacionamentos::Trazer::TrocarDestino::Resultado
  CLIENTES = %w[sim_todas ainda_nao algumas].freeze
  ALGUMAS = Relacionamentos::Trazer::Perguntas::ALGUMAS
  CLIENTE = Relacionamentos::Trazer::Perguntas::CLIENTE
  DESTINO_DO_TELEFONE = Relacionamentos::Trazer::Perguntas::DESTINO_DO_TELEFONE

  VALORES_CLIENTE = Relacionamentos::Trazer::Perguntas::VALORES_CLIENTE

  # respostas: { 'clientes' =>, 'coluna_cliente' =>, 'telefone' =>, 'valores_cliente' => { 'modo' =>, 'chaves' => } }, só
  # as chaves que a tela mandou.
  def initialize(importacao, respostas)
    @importacao = importacao
    @clientes = respostas['clientes']&.to_s
    @coluna_cliente = Integer(respostas['coluna_cliente'].to_s, 10, exception: false)
    @telefone = respostas['telefone']&.to_s
    @valores = respostas[VALORES_CLIENTE] && Relacionamentos::Trazer::EscolhaDosValores.new(importacao, respostas[VALORES_CLIENTE])
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

    guardar_a_escolha_dos_valores
    Resultado.new(revalida: telefone.revalida || clientes.revalida)
  end

  # Por último: a resposta a "São clientes?" que troca a coluna apaga a escolha antiga, e a deste pedido é da nova. A
  # resposta que deu certo também apaga o aviso de uma mudança desfeita antes.
  def guardar_a_escolha_dos_valores
    guardar_respostas(VALORES_CLIENTE => @valores.para_guardar) if @valores
    conferencia.tirar(ContactImports::Trazer::DesfazerMudanca::AVISO)
  end

  def erro_do_pedido
    return ContactImports::Trazer::Conferencia::VENCIDA if ContactImports::Trazer::Conferencia.vencida?(@importacao)
    return 'leitura_nao_pronta' unless @importacao.ready_to_confirm?
    return 'resposta_desconhecida' unless respostas_conhecidas?

    erro_da_coluna_ou_da_pergunta || @valores&.erro(coluna_dos_valores)
  end

  def respostas_conhecidas?
    return false unless resposta_conhecida?(@clientes, CLIENTES) && resposta_conhecida?(@telefone, DESTINO_DO_TELEFONE.keys)

    @valores.nil? || @valores.conhecida?
  end

  # A coluna que diz quem é cliente como este pedido a deixa: a que ele aponta ou, sem resposta a "São clientes?", a de
  # agora. Nenhuma com "sim, todas" e "ainda não".
  def coluna_dos_valores
    return Relacionamentos::Trazer::Perguntas.new(@importacao).coluna_dos_valores if @clientes.nil?

    @coluna_cliente if @clientes == ALGUMAS
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
    guardar_respostas('clientes' => @clientes)
    return sem_coluna_cliente unless escolhida
    return trocar(escolhida, CLIENTE) unless lendo_de_novo

    conferencia.gravar('destinos' => conferencia.destinos.merge(escolhida.to_s => CLIENTE))
    Resultado.new(revalida: false)
  end

  # Nenhuma coluna diz mais quem é cliente: a contagem dos valores da que dizia sai junto.
  def sem_coluna_cliente
    ContactImports::Trazer::ValoresDeCliente.new(@importacao).apagar
    Resultado.new(revalida: false)
  end

  def trocar(indice, destino)
    Relacionamentos::Trazer::TrocarDestino.new(@importacao, indice: indice, destino: destino, anterior: @anterior).call
  end

  def guardar_respostas(novas)
    conferencia.gravar('respostas' => conferencia.respostas.merge(novas))
  end

  # Lidas de novo a cada uso: uma troca no meio do pedido muda as opções da importação.
  def conferencia
    ContactImports::Trazer::Conferencia.new(@importacao)
  end

  def colunas
    Relacionamentos::Trazer::Colunas.new(@importacao)
  end
end
