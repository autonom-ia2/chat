# O campo `channel` das caixas, que muda com o tipo do canal (#900).
#
# `permitted_params(channel_attributes)` recebe os `EDITABLE_ATTRS` da classe
# do canal: na criação vem do `channel.type` que a pessoa manda, na edição do
# canal que a caixa já tem. Não há um formato só — há um por classe, e todas
# são enumeráveis. O `Espiao` executa o método uma vez para cada.
module Autonomia::Guide::Formatos::Canais
  CAMPO = 'channel'.freeze
  DEPENDE_DE = 'tipo do canal: na criação, o "type" enviado (o nome da classe em minúsculas: api, web_widget, email...); ' \
               'na edição, o canal que a caixa já tem'.freeze

  module_function

  def classes
    Rails.root.glob('app/models/channel/*.rb').map { |arquivo| "Channel::#{arquivo.basename('.rb').to_s.camelize}" }.sort
         .filter_map(&:safe_constantize)
         .select { |classe| classe.const_defined?(:EDITABLE_ATTRS, false) }
  end

  # Aplica quando o método do `permit` recebe argumento opcional e o que ele
  # permite tem `channel`: é o desenho do `InboxesController`.
  def aplica?(klass, metodo, arvore)
    return false unless arvore[CAMPO]&.dig(:forma) == :aninhado

    klass.instance_method(metodo).parameters.any? { |tipo, _| tipo == :opt }
  rescue NameError
    false
  end

  # { 'Channel::Api' => árvore dos campos de channel } — só as classes em que
  # o método executou.
  def por_tipo(espiao, metodo, conta)
    classes.each_with_object({}) do |classe, tipos|
      registro = espiao.permits(metodo, conta: conta, argumentos: [classe::EDITABLE_ATTRS])
      next unless registro

      campos = registro.filter_map { |(_caminho, filtros)| ::Autonomia::Guide::Formatos::Filtros.arvore(filtros)[CAMPO] }.first
      tipos[classe] = campos[:campos] if campos&.dig(:campos)
    end
  end
end
