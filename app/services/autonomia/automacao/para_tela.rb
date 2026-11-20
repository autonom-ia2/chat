# O que a tela da Automação livre recebe de cada automação (#2414 F5): a lista, o editor, ligar e desligar. Saiu do
# AutomacoesController no #2556, quando o editor ganhou o aviso das datas e a classe passou do tamanho.
#
# A receita vai como a pessoa pode ver (Versao#receita_para_tela, #2597): por isso pede quem está vendo.
module Autonomia::Automacao::ParaTela
  module_function

  # `pausa` (#2572): o motivo com que o motor a desligou, para a tela mostrar "Assumir e religar". Ligar e desligar
  # respondem sem ela: ligada não está pausada, e a tela só oferece desligar a que está ligada.
  def de(automacao, account_user, receita: false, pausa: nil)
    versao = automacao.versao_ativa
    {
      id: automacao.id, nome: automacao.nome, ativa: automacao.ativa, origem: automacao.origem, bloco: automacao.bloco,
      ligada_por: automacao.ligada_por&.slice(:id, :name), atualizada_em: automacao.updated_at,
      pausa: ::Autonomia::Automacao::Pausa.para_tela(pausa),
      versao: versao && { id: versao.id, numero: versao.numero, autor_id: versao.autor_id, criada_em: versao.created_at,
                          receita: (versao.receita_para_tela(account_user) if receita) }.compact
    }
  end

  # O editor (abrir e salvar): com a receita, a pausa e, do gatilho de data, os cards ou contatos que ficaram de fora
  # pela data escrita em outro formato (#2556). Só no editor: na lista, seria uma leitura no Redis por automação.
  def do_editor(automacao, account_user, **extra)
    pausa = ::Autonomia::Automacao::Pausa.das([automacao])[automacao.id]
    datas = ::Autonomia::Automacao::Tempo::DatasInvalidas.para_tela(automacao)
    de(automacao, account_user, receita: true, pausa: pausa).merge({ datas_invalidas: datas, **extra }.compact)
  end
end
