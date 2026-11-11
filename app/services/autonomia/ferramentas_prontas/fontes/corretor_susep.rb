# CORRETOR NA SUSEP (#2858, F4): se um corretor de seguros (pessoa física ou jurídica) está habilitado na SUSEP, com a
# situação, o número do registro e os ramos (os "produtos" que ele pode vender). O agente escolhe a consulta:
#   - por_documento: pelo CPF ou pelo CNPJ (conferidos pelos dígitos antes de sair);
#   - por_nome: pelo começo do nome (a SUSEP procura nomes que COMEÇAM com o texto), com o tipo de pessoa opcional.
# A busca pelo número do registro não existe na consulta pública: o parâmetro é ignorado e a SUSEP devolve a base inteira.
#
# O endpoint é o da consulta pública de corretores (www2.susep.gov.br/safe/corretores), SEM documentação. Por isso:
#   - o formato é conferido a cada resposta (`susep/formato.rb`). Mudou (campo que sumiu, ou o filtro foi ignorado e
#     voltou corretor de outro documento ou de outro nome): a fonte responde "não consegui", com um ALERTA no log, sem
#     quebrar; o spec `fontes_lote2_seguros_spec` trava o formato esperado;
#   - cache de 12 horas (a situação muda pouco, e a fonte não aguenta muito tráfego).
# Dado pessoal: ao modelo vão só nome, situação, registro e ramos. Nunca o `corretorId` nem o documento (nem o mascarado).
# Termos: consulta pública da SUSEP, sem chave, sem termo nem limite publicado.
module Autonomia::FerramentasProntas::Fontes::CorretorSusep
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MIN_NOME = 3

  module_function

  # CPF com os dígitos que conferem, ou CNPJ válido (numérico ou alfanumérico).
  def documento(valor)
    cpf = Parametro.digitos(valor, 11)
    return cpf if cpf && Autonomia::FerramentasProntas::Fontes::Cpf.valido?(cpf)

    Parametro.cnpj(valor)
  end

  def pessoa_fisica?(documento)
    documento.length == 11
  end

  DOCUMENTO = Parametro.new(nome: 'documento', descricao: 'O CPF ou o CNPJ do corretor, como o cliente escreveu.',
                            pergunte: 'o CPF ou o CNPJ completo do corretor (ou use a consulta por_nome)') do |valor|
    documento(valor)
  end
  NOME = Parametro.new(nome: 'nome', descricao: 'O começo do nome do corretor ou da corretora (ao menos 3 letras).',
                       pergunte: 'o nome do corretor ou da corretora') do |valor|
    texto = Parametro.texto_curto(valor)
    texto if texto && texto.length >= MIN_NOME
  end
  TIPO_PESSOA = Parametro.new(nome: 'tipo_pessoa', descricao: 'pf (pessoa física) ou pj (corretora). Opcional.', opcoes: %w[pf pj],
                              deduza: 'pj quando o nome é de empresa (corretora, Ltda), pf quando é de pessoa; sem certeza, deixe vazio.')

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'corretor_susep', slug: 'pronta_corretor_susep', nome: 'Corretor na SUSEP', flag: FLAG,
    descricao: 'Se um corretor de seguros está habilitado na SUSEP: a situação (ativo, suspenso), o número do registro e ' \
               'os ramos em que ele pode atuar.',
    consultas: [
      Consulta.new(nome: 'por_documento', descricao: 'pelo CPF ou CNPJ do corretor', obrigatorios: [DOCUMENTO],
                   provedores: [Susep], validade: 12.hours, prazo_por_fonte: 5, prazo_total: 5),
      Consulta.new(nome: 'por_nome', descricao: 'pelo começo do nome; aceita tipo_pessoa', obrigatorios: [NOME],
                   opcionais: [TIPO_PESSOA], provedores: [Susep], validade: 12.hours, prazo_por_fonte: 5, prazo_total: 5)
    ],
    limite_diario: 500,
    termos: 'Consulta pública de corretores da SUSEP (endpoint sem documentação, sem chave e sem limite publicado). ' \
            'Formato conferido a cada resposta, com alerta no log quando muda. Cache de 12 horas.'
  )
end
