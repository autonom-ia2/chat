# As perguntas que a conferência de "Trazer minha lista" (#2896) faz à pessoa:
# - "São clientes?", sempre;
# - "Quais destes querem dizer cliente?", quando uma coluna diz quem é cliente e a resposta não é "sim, todas";
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
#   tenha marcado pela tela das colunas. Só uma coluna diz quem é cliente (Relacionamentos::Trazer::TrocarDestino);
# - "algumas" sem nenhuma coluna "cliente" (a pessoa mandou a coluna para outro lugar) deixa de valer: a pergunta volta
#   sem resposta.
#
# "Quais destes querem dizer cliente?" traz os valores da coluna, contados (ContactImports::Trazer::ValoresDeCliente): a
# tela mostra o texto e devolve as chaves. A escolha guardada vale sempre que existe: quem muda a coluna que diz quem é
# cliente a apaga (ContactImports::Trazer::Conferencia#gravar), e a leitura da planilha apaga a que aponta um valor que
# sumiu. Sem a escolha a lista não é trazida, e o "Trazer" ainda confere, sob a trava, que os valores escolhidos
# continuam entre os da coluna (`falta_valores_cliente?`): nunca se traz com meia escolha.
class Relacionamentos::Trazer::Perguntas
  SIM_TODAS = 'sim_todas'.freeze
  ALGUMAS = 'algumas'.freeze
  CLIENTE = ContactImports::Trazer::Cliente::DESTINO
  VALORES_CLIENTE = ContactImports::Trazer::Cliente::RESPOSTA
  # A resposta => o destino em que ela põe a coluna.
  DESTINO_DO_TELEFONE = {
    'da_pessoa' => 'telefone', 'da_empresa' => Relacionamentos::Trazer::Colunas::TELEFONE_DA_EMPRESA,
    'nao_usar' => Relacionamentos::Trazer::Colunas::NAO_GUARDAR
  }.freeze

  def initialize(importacao)
    @importacao = importacao
  end

  def call
    [{ id: 'clientes' }, valores_cliente, telefone].compact
  end

  # { id: 'valores_cliente', coluna: 'Já é cliente?', indice: 4, preenchidas: 35, valores: [{ chave:, valor:, linhas: }],
  #   outros: { valores: 7, linhas: 9 } } ou nil.
  def valores_cliente
    indice = coluna_dos_valores
    return if indice.nil?

    { id: VALORES_CLIENTE, coluna: colunas.titulo(indice), indice: indice }.merge(valores_de_cliente.da_coluna(indice).deep_symbolize_keys)
  end

  # A coluna a que "Quais destes querem dizer cliente?" se refere, ou nil quando a pergunta não existe.
  def coluna_dos_valores
    coluna_cliente unless respostas['clientes'] == SIM_TODAS
  end

  # Falta a escolha, ou ela aponta um valor que a coluna não tem mais entre os mostrados.
  def falta_valores_cliente?
    indice = coluna_dos_valores
    return false if indice.nil?

    chaves = Array(respostas.dig(VALORES_CLIENTE, 'chaves'))
    respostas[VALORES_CLIENTE].nil? || (chaves.any? && !valores_de_cliente.tem?(indice, chaves))
  end

  # { id: 'telefone', coluna: 'Fone 2', indice: 2 } ou nil.
  def telefone
    indice = coluna_respondida || telefone_duvidoso
    indice && { id: 'telefone', coluna: colunas.titulo(indice), indice: indice }
  end

  # O que a pessoa respondeu e ainda vale, como a tela mandou: sem a coluna do telefone, que é assunto do servidor.
  def respostas_da_tela
    da_tela = coluna_respondida ? clientes.merge(respostas.slice('telefone')) : clientes
    coluna_dos_valores.nil? ? da_tela : da_tela.merge(respostas.slice(VALORES_CLIENTE))
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
    colunas.indices_do_destino(CLIENTE).first
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

  # Um leitor só: o arquivo da contagem é baixado uma vez por objeto.
  def valores_de_cliente
    @valores_de_cliente ||= ContactImports::Trazer::ValoresDeCliente.new(@importacao)
  end
end
