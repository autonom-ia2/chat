# Dados fictícios da bateria de planilhas (#1246). Nada aqui é de cliente: nomes e empresas
# vêm do Faker com semente fixa, e telefones, CPFs e e-mails são gerados. A mesma semente
# gera sempre as mesmas planilhas, para comparar rodadas.
#
# Cada célula de contato vem com o julgamento de uma pessoa ("dá para falar com ela por aqui?"),
# separado do que o motor aceita. É essa diferença que a bateria mede nas linhas.
module BaseDeClientesEval::Dados
  DDDS = %w[11 12 13 15 16 19 21 22 24 27 31 32 34 35 41 43 44 47 48 51 53 54 61 62 65 67 71 73 79 81 83 84 85 86 91 92 98].freeze
  DOMINIOS = %w[gmail.com hotmail.com outlook.com yahoo.com.br uol.com.br terra.com.br empresa.com.br].freeze
  STATUS = ['Ativo', 'Inativo', 'Prospect', 'Cancelado', 'Em negociação'].freeze
  CIDADES = ['São Paulo', 'Campinas', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba', 'Porto Alegre', 'Recife', 'Salvador', 'Fortaleza',
             'Goiânia'].freeze

  Celula = Struct.new(:valor, :alcanca, keyword_init: true)

  module_function

  # O app só declara pt_BR; os nomes brasileiros do Faker estão em pt-BR.
  def semear!(semente = 1246)
    I18n.available_locales = I18n.available_locales | [:'pt-BR']
    Faker::Config.locale = 'pt-BR'
    Faker::Config.random = Random.new(semente)
    @rng = Random.new(semente)
  end

  def rng
    @rng ||= Random.new(1246)
  end

  def sorteio(lista)
    lista[rng.rand(lista.size)]
  end

  def chance(probabilidade)
    rng.rand < probabilidade
  end

  def digitos(quantidade)
    Array.new(quantidade) { rng.rand(10) }.join
  end

  def nome
    Faker::Name.name
  end

  def primeiro_nome
    Faker::Name.first_name
  end

  def sobrenome
    Faker::Name.last_name
  end

  def empresa
    Faker::Company.name
  end

  def cidade
    sorteio(CIDADES)
  end

  def email_de(nome_pessoa)
    base = I18n.transliterate(nome_pessoa.to_s).downcase.split.first(2).join('.').delete('^a-z.')
    "#{base.presence || 'contato'}#{rng.rand(100)}@#{sorteio(DOMINIOS)}"
  end

  # Celular brasileiro: DDD + 9 + 8 dígitos.
  def celular_digitos
    "#{sorteio(DDDS)}9#{rng.rand(6..9)}#{digitos(7)}"
  end

  # Formatos que aparecem em planilha de verdade: (ddd, número de 9 dígitos) -> texto.
  CELULAR_FORMATOS = {
    mascara: ->(ddd, n) { "(#{ddd}) #{n[0, 5]}-#{n[5..]}" },
    e164: ->(ddd, n) { "+55#{ddd}#{n}" },
    com55: ->(ddd, n) { "55#{ddd}#{n}" },
    digitos: ->(ddd, n) { "#{ddd}#{n}" },
    espacos: ->(ddd, n) { "#{ddd} #{n[0]} #{n[1, 4]}-#{n[5..]}" },
    pontos: ->(ddd, n) { "#{ddd}.#{n[0, 5]}.#{n[5..]}" },
    zero_ddd: ->(ddd, n) { "0#{ddd} #{n[0, 5]}-#{n[5..]}" },
    sem9: ->(ddd, n) { "(#{ddd}) #{n[1, 4]}-#{n[5..]}" },
    sem9_digitos: ->(ddd, n) { "#{ddd}#{n[1..]}" },
    e164_espacos: ->(ddd, n) { "+55 #{ddd} #{n[0, 5]}-#{n[5..]}" }
  }.freeze

  # alcanca: uma pessoa conseguiria mandar WhatsApp para esse número? Sim, em todos os formatos.
  def celular(formato = :mascara)
    digitos_celular = celular_digitos
    Celula.new(valor: CELULAR_FORMATOS.fetch(formato).call(digitos_celular[0, 2], digitos_celular[2..]), alcanca: true)
  end

  def celular_misto
    celular(sorteio(CELULAR_FORMATOS.keys))
  end

  def fixo
    Celula.new(valor: "(#{sorteio(DDDS)}) #{rng.rand(2..5)}#{digitos(3)}-#{digitos(4)}", alcanca: false)
  end

  def email(nome_pessoa = nome)
    Celula.new(valor: email_de(nome_pessoa), alcanca: true)
  end

  def cpf(mascara: true)
    d = digitos(11)
    mascara ? "#{d[0, 3]}.#{d[3, 3]}.#{d[6, 3]}-#{d[9, 2]}" : d
  end

  def cnpj
    d = digitos(14)
    "#{d[0, 2]}.#{d[2, 3]}.#{d[5, 3]}/#{d[8, 4]}-#{d[12, 2]}"
  end

  def cep
    d = digitos(8)
    "#{d[0, 5]}-#{d[5, 3]}"
  end

  def data_br(anos_atras = 0..40)
    dia = Date.new(2026, 10, 10) - rng.rand(anos_atras.min * 365..(anos_atras.max * 365) + 1)
    dia.strftime('%d/%m/%Y')
  end

  def valor_br
    inteiro = rng.rand(100..99_999)
    milhares = inteiro.to_s.reverse.chars.each_slice(3).map(&:join).join('.').reverse
    "R$ #{milhares},#{digitos(2)}"
  end

  def status
    sorteio(STATUS)
  end

  def sim_nao
    chance(0.8) ? 'Sim' : 'Não'
  end
end
