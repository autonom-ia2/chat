# O Guia CONSULTANDO o formato de uma ação antes de montar o corpo (#900).
#
# Antes ele chutava nome de campo. Na conta 18, ao criar uma função
# personalizada, mandou uma permissão que não existe; a plataforma descartou
# calada e respondeu 200. O formato sai do próprio código
# (`Autonomia::Guide::Formatos`): envelope, campos, tipos, obrigatórios e os
# valores que cada lista aceita. Não chama a plataforma nem muda nada.
class Autonomia::Agents::Tools::Native::GuiaFormato < Autonomia::Agents::Tools::Native::Base
  class << self
    def slug
      'formato_da_acao'
    end

    def description
      'Diz o que uma ação de escrita aceita: onde vão os campos, quais existem, de que tipo, quais são ' \
        'obrigatórios e quais valores cada lista aceita. Consulte ANTES de executar_acao ou propor_acao e ' \
        'monte o corpo só com o que vier aqui. Não muda nada na conta.'
    end

    def params
      [
        { 'name' => 'acao', 'type' => 'string',
          'description' => 'A ação, em linguagem de rota: "POST custom_roles", "PATCH inboxes/:id", ' \
                           '"POST crm/pipelines".' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    acao = @params['acao'].to_s.strip
    return fora_do_catalogo(acao) unless @operador.acoes.catalogo.include?(acao)

    formato = ::Autonomia::Guide::Formatos.resumo_para_o_modelo(acao)
    return sem_formato(acao) if formato.nil?

    [formato, (sem_volta unless @operador.acoes.desfazivel?(acao))].compact.join("\n")
  end

  private

  # Ação errada volta com as que existem para o recurso, como em executar_acao.
  def fora_do_catalogo(acao)
    existentes = ::Autonomia::Guide::Rotas.vizinhas(@operador.acoes.catalogo, acao)
    vizinhas = existentes.any? ? " Para isto, o que existe é: #{existentes.join(', ')}." : ''
    "\"#{acao}\" não é uma ação da plataforma.#{vizinhas}"
  end

  # Ação nova que ainda não passou pelo gerador. Não dá para afirmar nada.
  def sem_formato(acao)
    "Não tenho o formato de \"#{acao}\". Mande só os campos que a pessoa disse, com os nomes que a leitura " \
      'da conta mostra, e confira no retorno o que foi gravado.'
  end

  def sem_volta
    'Esta ação não tem desfazer: use propor_acao, para a pessoa confirmar na tela.'
  end

  def recusa_sem_contexto
    'Não consigo consultar o formato agora porque não sei quem está pedindo.'
  end
end
