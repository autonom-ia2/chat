# As perguntas que a conferência de "Trazer minha lista" (#2896) faz à pessoa:
# - "São clientes?", sempre;
# - "De quem é esse telefone?", no máximo uma: para a coluna de telefone que o leitor sugeriu sem certeza.
#
# A resposta do telefone fica guardada com a coluna a que se referia (`options['trazer']['respostas']`) e só vale
# enquanto essa coluna está onde a resposta a pôs: telefone da pessoa, telefone da empresa ou "não guardar". Valendo, a
# pergunta continua na lista, respondida. Se a pessoa mandou a coluna para outro lugar pela tela das colunas (ou
# escolheu outra coluna para o telefone), a resposta antiga deixa de valer: a pergunta passa a ser sobre o telefone de
# agora, se ele for duvidoso, ou some.
#
# A resposta de "São clientes?" também acompanha as colunas, porque quem diz quem é cliente na gravação são elas
# (ContactImports::Trazer::DestinosDaLinha):
# - "sim, todas" vale sempre: todo mundo entra como cliente, com ou sem coluna marcada;
# - fora disso, havendo coluna com o destino "cliente", a resposta é "algumas" com essa coluna, mesmo que a pessoa a
#   tenha marcado pela tela das colunas. Com mais de uma marcada, vale a da resposta enquanto ela for "cliente"; senão,
#   a primeira da planilha;
# - "algumas" sem nenhuma coluna "cliente" (a pessoa mandou a coluna para outro lugar) deixa de valer: a pergunta volta
#   sem resposta.
class Relacionamentos::Trazer::Perguntas
  SIM_TODAS = 'sim_todas'.freeze
  ALGUMAS = 'algumas'.freeze
  CLIENTE = 'cliente'.freeze
  # A resposta => o destino em que ela põe a coluna.
  DESTINO_DO_TELEFONE = {
    'da_pessoa' => 'telefone', 'da_empresa' => Relacionamentos::Trazer::Colunas::TELEFONE_DA_EMPRESA,
    'nao_usar' => Relacionamentos::Trazer::Colunas::NAO_GUARDAR
  }.freeze

  def initialize(importacao)
    @importacao = importacao
  end

  def call
    [{ id: 'clientes' }, telefone].compact
  end

  # { id: 'telefone', coluna: 'Fone 2', indice: 2 } ou nil.
  def telefone
    indice = coluna_respondida || telefone_duvidoso
    indice && { id: 'telefone', coluna: colunas.titulo(indice), indice: indice }
  end

  # O que a pessoa respondeu e ainda vale, como a tela mandou: sem a coluna do telefone, que é assunto do servidor.
  def respostas_da_tela
    coluna_respondida ? clientes.merge(respostas.slice('telefone')) : clientes
  end

  private

  # A resposta de "São clientes?" como as colunas estão agora.
  def clientes
    return { 'clientes' => SIM_TODAS } if respostas['clientes'] == SIM_TODAS

    coluna = coluna_cliente
    return { 'clientes' => ALGUMAS, 'coluna_cliente' => coluna } if coluna

    respostas['clientes'] == ALGUMAS ? {} : respostas.slice('clientes')
  end

  def coluna_cliente
    marcadas = colunas.indices_do_destino(CLIENTE)
    marcadas.include?(respostas['coluna_cliente']) ? respostas['coluna_cliente'] : marcadas.first
  end

  # A coluna da resposta guardada, enquanto ela está no destino que a resposta lhe deu.
  def coluna_respondida
    indice = respostas['coluna_telefone']
    indice if indice && colunas.destino(indice) == DESTINO_DO_TELEFONE[respostas['telefone']]
  end

  def telefone_duvidoso
    alvo = @importacao.schema_resolution.to_h.dig('targets', 'phone').to_h
    alvo['column'] if alvo['confident'] == false
  end

  def respostas
    @respostas ||= ContactImports::Trazer::Conferencia.new(@importacao).respostas
  end

  def colunas
    @colunas ||= Relacionamentos::Trazer::Colunas.new(@importacao)
  end
end
