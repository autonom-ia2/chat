# CIDADES E ESTADOS (#2858, F1): a lista oficial de estados e a de municípios de um estado, do IBGE.
#   - principal: a API de localidades do IBGE; reserva: BrasilAPI (que repassa o IBGE).
#   - a lista do IBGE vem inteira (os 853 municípios de MG passam de 256 KB): teto de 1 MB só aqui, e ao modelo vão só
#     os nomes, com o total e no máximo MAX_CIDADES; a busca pelo nome filtra antes do teto.
# Termos: serviço de dados do IBGE, aberto e sem chave, sem limite publicado. A divisão territorial muda raramente:
# cache de 30 dias.
module Autonomia::FerramentasProntas::Fontes::Cidades
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  MAX_CIDADES = 200
  MAX_BYTES_IBGE = 1.megabyte

  module_function

  # Os nomes em ordem alfabética (sem acento e sem caixa).
  def cidades(sigla, nomes)
    ordem = nomes.sort_by { |nome| Autonomia::FerramentasProntas::Lista.comparavel(nome) }
    Autonomia::FerramentasProntas::Ufs.com_nome(sigla).merge('cidades' => ordem)
  end

  # Um estado da lista da fonte (IBGE e BrasilAPI têm o mesmo formato). Fora do formato: falha, e a reserva tenta.
  def estado(item)
    falha = Autonomia::FerramentasProntas::Provedor::Falha
    raise falha, 'resposta_invalida' unless item.is_a?(Hash) && item['sigla'].present? && item['nome'].present?

    regiao = item['regiao']
    { 'uf' => item['sigla'].to_s.strip, 'nome' => item['nome'].to_s.strip, 'regiao' => regiao.is_a?(Hash) ? regiao['nome'] : nil }.compact
  end

  def estados(itens)
    { 'estados' => itens.map { |item| estado(item) }.sort_by { |item| Autonomia::FerramentasProntas::Lista.comparavel(item['nome']) } }
  end

  def refinar(dados, params)
    return dados unless dados.key?('cidades')

    achadas = Autonomia::FerramentasProntas::Lista.filtrar(dados['cidades'], params['busca']) { |nome| nome }
    return if achadas.empty?

    dados.except('cidades').merge(Autonomia::FerramentasProntas::Lista.cortar(achadas, 'cidades', MAX_CIDADES))
  end

  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado (ex.: ac, sp).', opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase),
                     deduza: 'mande a sigla de 2 letras do estado, que sai do nome do estado ou da cidade que o cliente disse.')
  BUSCA = Parametro.new(nome: 'busca', local: true, descricao: 'Parte do nome da cidade, para conferir se ela existe no estado. Opcional.') do |valor|
    Parametro.texto_curto(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'cidades', slug: 'pronta_cidades', nome: 'Cidades e estados', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'A lista oficial do IBGE: os estados do Brasil e os municípios de um estado.',
    consultas: [
      Consulta.new(nome: 'estados', descricao: 'os 27 estados, com sigla e região', provedores: [Ibge, BrasilApi],
                   validade: 30.days, prazo_por_fonte: 3, prazo_total: 6),
      Consulta.new(nome: 'cidades', descricao: 'os municípios de um estado; pede uf e aceita busca pelo nome',
                   obrigatorios: [UF], opcionais: [BUSCA], provedores: [Ibge, BrasilApi], validade: 30.days,
                   prazo_por_fonte: 4, prazo_total: 8, refinar: method(:refinar))
    ],
    limite_diario: 500,
    termos: 'IBGE (serviço de dados aberto, sem chave) e BrasilAPI de reserva. Cache de 30 dias.'
  )
end
