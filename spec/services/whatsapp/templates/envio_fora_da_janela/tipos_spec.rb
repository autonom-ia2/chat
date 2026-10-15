require 'rails_helper'

# Os tipos de mensagem fora da janela (#1587): lista fixa, nome estável por (caixa, tipo) e o selo do sistema pelo nome.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Tipos do
  it 'tem os tipos combinados com o Followup, com a categoria pelo propósito' do
    categorias = described_class.todos.to_h { |tipo| [tipo.chave, tipo.categoria] }

    expect(categorias).to eq(
      'cobranca_antes' => 'UTILITY', 'cobranca_no_dia' => 'UTILITY', 'cobranca_depois' => 'UTILITY',
      'andamento' => 'UTILITY', 'retorno' => 'UTILITY', 'retomar_contato' => 'MARKETING', 'deu_certo' => 'UTILITY'
    )
  end

  it 'a cobrança usa o pronto fixo do momento; os outros tipos a IA escreve com campos do catálogo' do
    expect(described_class.buscar('cobranca_no_dia').momento).to eq(:no_dia)
    expect(described_class.buscar(:andamento)).not_to be_cobranca
    expect(described_class.buscar('retomar_contato')).to be_propaganda
    described_class.todos.reject(&:cobranca?).each do |tipo|
      expect(tipo.campos).to all(satisfy { |campo| TemplateFields::Catalog.known?(campo) })
      expect(tipo.obrigatorios - tipo.campos).to be_empty
    end
  end

  it 'tipo desconhecido é erro de quem chama' do
    expect { described_class.buscar('promocao') }.to raise_error(described_class::Desconhecido)
  end

  it 'nome estável por caixa e tipo; recusado vira _v2' do
    inbox = instance_double(Inbox, id: 42)

    expect(described_class.nome(inbox, described_class.buscar('andamento'), 1)).to eq('c2y_andamento_42')
    expect(described_class.nome(inbox, described_class.buscar('retomar_contato'), 2)).to eq('c2y_retomar_contato_42_v2')
  end

  it 'reconhece pelo nome os modelos que ele cria (selo "Usado pelo sistema")' do
    expect(described_class.dono_de('c2y_andamento_42')).to eq('fora_da_janela')
    expect(described_class.dono_de('c2y_retomar_contato_7_v3')).to eq('fora_da_janela')
    expect(Whatsapp::Templates::SystemTemplates.owner_for('c2y_deu_certo_9_v2')).to eq('fora_da_janela')
    expect(described_class.dono_de('c2y_andamento')).to be_nil
    expect(described_class.dono_de('c2y_andamento_42_promo')).to be_nil
    expect(described_class.dono_de('c2y_promocao_42')).to be_nil
    expect(described_class.dono_de('andamento_42')).to be_nil
  end
end
