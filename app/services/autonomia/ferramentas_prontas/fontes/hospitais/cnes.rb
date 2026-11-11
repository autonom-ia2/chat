# Os estabelecimentos de saúde de uma cidade na API de dados abertos do Ministério da Saúde (CNES). Só dígitos vão no
# endereço: o código do município (6 dígitos) e o código do tipo de unidade, os dois das nossas tabelas. Só os ativos
# (`status=1`). Sai o que for de pessoa física (natureza jurídica do grupo 4, código "4000" no CNES); do resto, só o
# que ajuda o cliente a chegar lá: nome, tipo, endereço, bairro, CEP, telefone e o código CNES.
class Autonomia::FerramentasProntas::Fontes::Hospitais::Cnes < Autonomia::FerramentasProntas::Provedor
  NOME = 'cnes'.freeze
  HOST = 'apidadosabertos.saude.gov.br'.freeze
  PESSOA_FISICA = '4'.freeze
  # Como a lista veio (`paginas`) -> as marcas da resposta. A `pagina_falhou` sai no `refinar` e não chega ao agente.
  AMOSTRAS = { inteira: {}, teto: { 'amostra' => true }, falhou: { 'amostra' => true, 'pagina_falhou' => true } }.freeze
  # O nome de cada tipo de unidade (`/cnes/tipounidades`, lido em 10/11/2026).
  TIPOS = {
    1 => 'Posto de saúde', 2 => 'Unidade básica de saúde', 4 => 'Policlínica', 5 => 'Hospital geral',
    7 => 'Hospital especializado', 15 => 'Unidade mista', 20 => 'Pronto-socorro geral', 21 => 'Pronto-socorro especializado',
    22 => 'Consultório', 32 => 'Unidade móvel fluvial', 36 => 'Clínica ou centro de especialidade', 39 => 'Exames e diagnóstico',
    40 => 'Unidade móvel terrestre', 42 => 'Unidade móvel de urgência', 43 => 'Farmácia', 50 => 'Vigilância em saúde',
    60 => 'Cooperativa de profissionais de saúde', 61 => 'Centro de parto normal', 62 => 'Hospital-dia',
    64 => 'Central de regulação', 67 => 'Laboratório central de saúde pública', 68 => 'Central de gestão em saúde',
    69 => 'Hemocentro', 70 => 'CAPS (atenção psicossocial)', 71 => 'Apoio à saúde da família',
    72 => 'Atenção à saúde indígena', 73 => 'Pronto atendimento', 74 => 'Academia da saúde', 75 => 'Telessaúde',
    76 => 'Regulação de urgências', 77 => 'Atenção domiciliar (home care)', 78 => 'Atenção em regime residencial',
    79 => 'Oficina ortopédica', 80 => 'Laboratório de saúde pública', 81 => 'Regulação do acesso',
    82 => 'Central de transplantes', 83 => 'Prevenção e promoção da saúde', 84 => 'Central de abastecimento',
    85 => 'Centro de imunização'
  }.freeze

  # A amostra que veio de uma página que falhou (`pagina_falhou`) não vai ao cache: a próxima consulta tenta a lista de
  # novo (revisão do #2906; antes ficava 7 dias). A amostra do teto de páginas é sempre a mesma, e vai.
  def self.validade_da_resposta(dados)
    dados['pagina_falhou'] ? 0 : validade
  end

  def consultar(_consulta, params)
    municipio = municipio(params)
    lidos, situacao = paginas(municipio.codigo_cnes, params['tipo'])
    estabelecimentos = lidos.reject { |item| pessoa_fisica?(item) }
    raise NaoEncontrado if estabelecimentos.empty?

    { 'cidade' => municipio.nome }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(municipio.uf))
                                  .merge('estabelecimentos' => estabelecimentos.map { |item| estabelecimento(item) })
                                  .merge(AMOSTRAS.fetch(situacao))
  end

  private

  def municipio(params)
    municipios = Autonomia::FerramentasProntas::Municipios
    achado = params['codigo_ibge'] ? municipios.por_codigo_cnes(params['codigo_ibge']) : municipios.buscar(params['uf'], params.fetch('cidade'))
    achado || raise(Falha, 'municipio_desconhecido')
  end

  # A API devolve POR_PAGINA por vez: as páginas seguintes até a que vem incompleta (a lista acabou) ou até
  # `MAX_PAGINAS` (varredura F21/F22: a "santa casa" estava depois da primeira página). Falha numa página depois da
  # primeira (o prazo da consulta acabando): o que já veio serve, como amostra. -> [itens, :inteira | :teto | :falhou]
  def paginas(codigo, tipo)
    hospitais = Autonomia::FerramentasProntas::Fontes::Hospitais
    lidos = []
    hospitais::MAX_PAGINAS.times do |pagina|
      itens = pagina(codigo, tipo, pagina * hospitais::POR_PAGINA)
      lidos.concat(itens)
      return [lidos, :inteira] if itens.size < hospitais::POR_PAGINA
    rescue Falha
      raise if lidos.empty?

      return [lidos, :falhou]
    end
    [lidos, :teto]
  end

  def pagina(codigo, tipo, deslocamento)
    lista!(objeto!(get(caminho(codigo, tipo, deslocamento)))['estabelecimentos']).map { |item| objeto!(item) }
  end

  def caminho(codigo, tipo, deslocamento)
    hospitais = Autonomia::FerramentasProntas::Fontes::Hospitais
    base = "/cnes/estabelecimentos?codigo_municipio=#{codigo}&status=1&limit=#{hospitais::POR_PAGINA}"
    base = "#{base}&codigo_tipo_unidade=#{hospitais::TIPOS.fetch(tipo)}" if tipo
    "#{base}&offset=#{deslocamento.to_i}"
  end

  # O CEP com o traço, como nas outras fontes (varredura P14).
  def cep(item)
    digitos = Autonomia::FerramentasProntas::Parametro.digitos(item['codigo_cep_estabelecimento'], 8)
    digitos ? "#{digitos[0, 5]}-#{digitos[5, 3]}" : texto(item['codigo_cep_estabelecimento'])
  end

  def pessoa_fisica?(item)
    item['descricao_natureza_juridica_estabelecimento'].to_s.strip.start_with?(PESSOA_FISICA)
  end

  def estabelecimento(item)
    {
      'nome' => exigir!(texto(item['nome_fantasia']) || texto(item['nome_razao_social'])),
      'tipo' => TIPOS[item['codigo_tipo_unidade'].to_i], 'endereco' => endereco(item),
      'bairro' => texto(item['bairro_estabelecimento']), 'cep' => cep(item),
      'telefone' => texto(item['numero_telefone_estabelecimento']), 'cnes' => exigir!(texto(item['codigo_cnes'])).rjust(7, '0')
    }.compact
  end

  def endereco(item)
    [texto(item['endereco_estabelecimento']), texto(item['numero_estabelecimento'])].compact.join(', ').presence
  end
end
