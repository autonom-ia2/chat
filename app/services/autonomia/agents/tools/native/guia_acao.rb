# O Guia PROPONDO uma mudança na conta (issue #568).
#
# Esta ferramenta não executa nada, e isso não é detalhe de implementação: é a
# proteção. Ela monta o pedido, confere que a pessoa pode fazer aquilo, e devolve
# a frase que ela vai ler. A tela mostra o resumo com os botões, e só o clique
# em Confirmar chama o endpoint que grava — por outra rota, noutro request.
#
# Antes isto era decidido por um modelo separado, em paralelo à redação da
# resposta: o texto e o botão discordavam na tela ("não consigo fazer isso por
# você" com o Confirmar logo abaixo). Agora quem propõe é quem escreve.
class Autonomia::Agents::Tools::Native::GuiaAcao < Autonomia::Agents::Tools::Native::Base
  class << self
    def slug
      'propor_acao'
    end

    def description
      'Prepara uma mudança na conta para a pessoa confirmar na tela. NÃO executa: depois de chamar, ' \
        'a tela mostra o resumo com os botões Confirmar e Cancelar logo abaixo da sua resposta. ' \
        'Use quando ela pedir para você FAZER algo (criar, alterar, apagar). Só funciona para quem ' \
        'administra a conta.'
    end

    def params
      [
        { 'name' => 'acao', 'type' => 'string',
          'description' => 'A ação, em linguagem de rota, exatamente como está no catálogo que você ' \
                           'recebeu: "POST crm/pipelines", "PATCH inboxes/:id", "DELETE labels/:id".' },
        { 'name' => 'descricao', 'type' => 'string',
          'description' => 'UMA frase curta, no idioma da pessoa, dizendo o que vai acontecer — é o que ' \
                           'ela lê antes de confirmar. Nunca suavize: apagar se diz apagar.' },
        { 'name' => 'caminho_json', 'type' => 'string', 'required' => false,
          'description' => 'Preenche os ":id" da rota, como objeto JSON: {"id":"12"}. Sem isso, alterar ' \
                           'ou apagar não tem como apontar para o registro certo.' },
        { 'name' => 'corpo_json', 'type' => 'string', 'required' => false,
          'description' => 'Os campos a gravar, como objeto JSON: {"name":"Comercial"}. Use os nomes de ' \
                           'campo da própria plataforma, e só valores que a pessoa disse.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    dados = { caminho: objeto('caminho_json'), corpo: objeto('corpo_json'),
              descricao: @params['descricao'].to_s }
    nao_lidos = @operador.nao_lidos(dados[:caminho])
    return sem_leitura(nao_lidos) if nao_lidos.any?

    descricao = @operador.acoes.descrever(@params['acao'].to_s, dados)
    @operador.propor(nome: @params['acao'].to_s, dados: dados, descricao: descricao)

    confirmada(descricao)
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    # A recusa da própria plataforma, em português, volta PARA O MODELO — que
    # pergunta o que falta em vez de prometer o que não vai acontecer.
    "#{e.message}#{vizinhas}"
  end

  private

  # As ações que EXISTEM para o recurso que ele tentou. O catálogo de escrita
  # tem 16.245 caracteres e não cabe no prompt de toda pergunta; aqui ele chega
  # no único momento em que faz falta — quando o modelo errou o nome —, e só o
  # pedaço que interessa.
  def vizinhas
    recurso = @params['acao'].to_s.split(' ', 2).last.to_s
    return '' if recurso.blank?

    base = recurso.split('/').first
    existentes = @operador.acoes.catalogo.select { |acao| acao.split(' ', 2).last.to_s.start_with?(base) }
    return '' if existentes.blank?

    " Para isto, o que existe é: #{existentes.join(', ')}."
  end

  def objeto(nome)
    texto = @params[nome].to_s.strip
    return {} if texto.blank?

    valores = JSON.parse(texto)
    valores.is_a?(Hash) ? valores.deep_symbolize_keys : {}
  rescue JSON::ParserError
    {}
  end

  # O que o modelo precisa saber depois de propor: está pronto, a tela já mostra
  # os valores, e repetir os valores na resposta empurra o botão para fora da
  # vista de quem vai clicar.
  def confirmada(descricao)
    "Proposta preparada. A tela já está mostrando \"#{descricao[:frase]}\" com os botões de confirmar e " \
      'cancelar logo abaixo da sua resposta. Responda em UMA frase curta dizendo que é só confirmar ali ' \
      'embaixo; não repita os valores e não diga que você não faz alterações.'
  end

  # Alterar ou apagar aponta para UM registro, e o id dele sai de uma leitura da
  # conta — nunca de um número chutado ou digitado. É o que troca a antiga regra
  # "com o nome sozinho eu não aponto" (#593): o nome se resolve lendo.
  def sem_leitura(nao_lidos)
    "Não preparei a ação: #{nao_lidos.map { |nome, valor| "#{nome} #{valor}" }.join(', ')} não veio de nenhuma " \
      'leitura da conta nesta conversa. Leia a conta, ache o registro pelo nome que a pessoa disse e use o id ' \
      'que veio; se houver mais de um, pergunte qual; se não houver, diga que não existe.'
  end

  def recusa_sem_contexto
    'Não consigo preparar a ação agora porque não sei quem está pedindo. Explique como a pessoa faz na tela.'
  end
end
