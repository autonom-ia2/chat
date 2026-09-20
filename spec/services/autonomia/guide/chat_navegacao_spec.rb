require 'rails_helper'

# Em 20/09/2026 o botão "ir para a tela" sumiu de TODAS as respostas em produção,
# junto com o destaque do elemento e o diagnóstico do estado real da conta. Causa:
# o leitor de campo do KB ancorava em "nav_target:" no começo da linha, e o
# gerador escreve "- nav_target:", como item de lista. Devolvia nil nos 163
# blocos, sem erro nenhum.
#
# O CI passou verde porque nenhum spec Ruby tocava `resolve_navigation`, e um
# spec com bloco escrito à mão teria repetido o mesmo engano do código: eu
# inventaria o formato em vez de ler o que o gerador produz.
#
# Por isso este arquivo lê o KB DE VERDADE. Se o formato do gerador mudar, ou o
# leitor voltar a errar, ele falha aqui — não em produção.
RSpec.describe Autonomia::Guide::Chat do
  let(:kb) { Rails.root.join('lib/operator_guide/guia-produto.md').read }

  # Um fluxo real, com nav_target real, do arquivo que vai para o modelo.
  let(:bloco_do_funil) do
    kb.split("\n### ").find { |b| b.start_with?('Criar funis') } or
      raise 'fluxo de funil não encontrado no KB — o teste precisa de um bloco real'
  end

  let(:chat) { described_class.new(account: nil, user: nil, message: 'Como crio um funil no CRM?') }

  describe 'ler campo do KB' do
    it 'lê o campo escrito como item de lista, que é como o gerador escreve', :aggregate_failures do
      expect(chat.send(:campo, bloco_do_funil, 'nav_target')).to eq('crm_kanban_index')
      expect(chat.send(:campo, bloco_do_funil, 'highlight')).to be_present
    end

    it 'lê o campo em todos os fluxos do KB, não em alguns' do
      blocos = kb.split("\n### ").drop(1)
      sem_rota = blocos.count { |b| chat.send(:campo, b, 'nav_target').blank? }

      expect(sem_rota).to be < 10, "#{sem_rota} de #{blocos.size} fluxos ficaram sem nav_target"
    end

    it 'devolve nulo quando o campo realmente não existe' do
      expect(chat.send(:campo, bloco_do_funil, 'campo_que_nao_existe')).to be_nil
    end
  end

  describe 'a sugestão de navegação' do
    def resultado(confianca: 0.9, handoff: {})
      instance_double(Autonomia::Agents::AnswerResult, confidence: confianca, handoff: handoff,
                                                       used_knowledge: [{ content: "### #{bloco_do_funil}" }])
    end

    it 'sai do fluxo real e aponta a tela do CRM' do
      expect(chat.send(:resolve_navigation, resultado)[:route_name]).to eq('crm_kanban_index')
    end

    it 'não sugere tela quando a conversa vai para um humano' do
      expect(chat.send(:resolve_navigation, resultado(handoff: { should: true }))).to be_nil
    end

    it 'não sugere tela quando a resposta veio sem confiança' do
      expect(chat.send(:resolve_navigation, resultado(confianca: 0.1))).to be_nil
    end
  end
end
