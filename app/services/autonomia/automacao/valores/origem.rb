# G65 (#2842): no ramo do "em outro registro" (G18), a filha lê o registro de origem, o alvo da mãe, com
# `origem.<caminho>` (`origem.contato.nome`: o João, cujo card ganho avisa a Maria). Só os campos e os atributos da
# conversa, do contato e do card, lidos na hora com a permissão de quem ligou (o valor protegido segue a regra dele). O
# resto é da execução da mãe (a mensagem do gatilho, a resposta, o envio, a agenda, a reunião, o texto da IA) e não
# passa. O salvar só aceita no ramo, e o caminho tem de valer no alvo do gatilho da mãe (Receita#problemas_da_origem).
#
# Saiu de `Valores` pelo tamanho dele, no padrão de Valores::Atributos; `Valores.da_origem?` segue sendo a porta.
module Autonomia::Automacao::Valores::Origem
  PREFIXO = 'origem.'.freeze
  BASES = %w[conversa contato card].freeze

  module_function

  def do_caminho?(caminho) = caminho.to_s.start_with?(PREFIXO)

  # "origem.contato.nome" => "contato.nome".
  def sem_prefixo(caminho) = caminho.to_s.delete_prefix(PREFIXO)

  # O passo lê o registro de origem em algum campo dele (texto, corpo, condição)? Os passos dos ramos ficam de fora: cada
  # um responde por si quando chega a vez dele (Executor, `origem_fora_do_alcance`).
  def no_passo?(passo) = lido_em?(passo.except(*::Autonomia::Automacao::Receita::RAMOS, 'caminhos', ::Autonomia::Automacao::Receita::NENHUM))

  def lido_em?(dado)
    case dado
    when Hash then dado.any? { |chave, valor| (chave == '$valor' && do_caminho?(valor)) || lido_em?(valor) }
    when Array then dado.any? { |item| lido_em?(item) }
    else false
    end
  end

  # O caminho (sem o prefixo) pode ser lido no registro de origem?
  def le?(caminho)
    valores = ::Autonomia::Automacao::Valores
    BASES.include?(caminho.to_s.split('.', 2).first) && (valores::CAMPOS.key?(caminho.to_s) || valores.atributo(caminho).present?)
  end
end
