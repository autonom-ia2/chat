# O Open Insurance Brasil (fonte única: não há outro lugar oficial com os produtos de todas as seguradoras). O host
# declarado é o do diretório; o de cada seguradora sai dele, na hora (`Seguradora`).
#   - seguradoras: o índice do diretório, com os ramos de cada marca (sem os endereços);
#   - produtos: as marcas com a seguradora no nome e o ramo publicado, no máximo MAX_MARCAS chamadas, cada uma com o
#     prazo curto da consulta. A que não responde sai em `nao_responderam` (e no log, com o motivo); nenhuma respondeu:
#     falha (`seguradora_nao_respondeu`). Achada, mas sem o ramo: a resposta diz que ela não publica e quais ramos publica.
class Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::OpenInsurance < Autonomia::FerramentasProntas::Provedor
  NOME = 'openinsurance'.freeze
  HOST = 'data.directory.opinbrasil.com.br'.freeze
  MAX_MARCAS = 2
  MAX_OUTRAS = 10
  SEM_O_RAMO = 'A seguradora não publica produtos deste ramo no Open Insurance. Os ramos que ela publica estão em ' \
               'ramos_publicados.'.freeze

  def consultar(consulta, params)
    indice = Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Diretorio.indice do
      get(Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Diretorio::CAMINHO,
          max_bytes: Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Diretorio::MAX_BYTES)
    end
    consulta.nome == 'seguradoras' ? seguradoras(indice) : produtos(indice, params)
  end

  private

  def fonte
    Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras
  end

  def seguradoras(indice)
    { 'seguradoras' => indice.map { |marca| marca.slice('nome', 'empresa').merge('ramos' => marca['ramos'].keys) } }
  end

  def produtos(indice, params)
    ramo = params.fetch('ramo')
    marcas = fonte.achar(indice, params.fetch('seguradora'))
    raise NaoEncontrado if marcas.empty?

    com_o_ramo = marcas.select { |marca| marca['ramos'].key?(ramo) }
    return sem_o_ramo(marcas, ramo) if com_o_ramo.empty?

    respostas, falhas = chamar(com_o_ramo.first(MAX_MARCAS), ramo)
    raise Falha, 'seguradora_nao_respondeu' if respostas.empty?

    outras = com_o_ramo.drop(MAX_MARCAS).pluck('nome').first(MAX_OUTRAS)
    { 'ramo' => fonte.rotulo(ramo), 'seguradoras' => respostas, 'nao_responderam' => falhas.presence,
      'outras_com_o_nome' => outras.presence }.compact
  end

  def chamar(marcas, ramo)
    marcas.each_with_object([[], []]) do |marca, (respostas, falhas)|
      respostas << fonte::Seguradora.new(marca, marca['ramos'].fetch(ramo), prazo: @prazo, cliente: @cliente).produtos
    rescue Falha => e
      Rails.logger.warn("[autonomia][pronta] produtos_seguradoras: a seguradora não respondeu marca=#{marca['nome']} motivo=#{e.motivo}")
      falhas << marca['nome']
    end
  end

  def sem_o_ramo(marcas, ramo)
    publicados = marcas.flat_map { |marca| marca['ramos'].keys }.uniq.map { |item| fonte.rotulo(item) }
    { 'ramo' => fonte.rotulo(ramo), 'seguradoras' => [], 'observacao' => SEM_O_RAMO,
      'ramos_publicados' => publicados, 'encontradas' => marcas.pluck('nome').first(MAX_OUTRAS) }
  end
end
