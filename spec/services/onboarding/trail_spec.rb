require 'rails_helper'

RSpec.describe Onboarding::Trail do
  describe '.passos' do
    it 'carrega os nove passos da trilha, em ordem' do
      expect(described_class.passos.map(&:id)).to eq(
        %w[perfil chave_ia canal primeira_resposta funil equipe agente_ia campanha configuracoes]
      )
      expect(described_class.passos.map(&:ordem)).to eq((0..8).to_a)
    end

    it 'só marca como pulável o que a operação pode dispensar' do
      expect(described_class.passos.select(&:pulavel?).map(&:id)).to contain_exactly('equipe', 'agente_ia', 'configuracoes')
    end

    it 'aponta cada passo para uma regra de verificação que existe' do
      expect(described_class.passos.map(&:verificacao).map(&:to_sym)).to all(be_in(Onboarding::Progress::REGRAS.keys))
    end

    it 'agrupa os passos nas três etapas da tela, na ordem' do
      expect(described_class.passos.map(&:etapa).chunk_while { |a, b| a == b }.map(&:first)).to eq(%w[ligar organizar crescer])
    end

    it 'mostra ao agente só o que é trabalho dele' do
      expect(described_class.para_perfil('agent').map(&:id)).to eq(%w[perfil primeira_resposta])
      expect(described_class.para_perfil('administrator').size).to eq(9)
    end
  end

  describe 'validação do arquivo' do
    def carregar(passos)
      allow(YAML).to receive(:safe_load_file).with(described_class::PATH).and_return({ 'passos' => passos })
      described_class.recarregar!
    end

    after { described_class.instance_variable_set(:@passos, nil) }

    let(:passo_valido) do
      {
        'id' => 'perfil', 'ordem' => 0, 'titulo' => 'Seu perfil', 'por_que' => 'Porque sim',
        'rota' => 'profile_settings_index', 'alvo_destaque' => 'sidebar-profile-menu',
        'verificacao' => 'perfil_configurado', 'fluxos_guia' => [], 'artigo' => '00.02',
        'etapa' => 'ligar', 'minutos' => 2, 'acao' => 'Ajustar meu perfil',
        'pulavel' => false, 'perfis' => ['administrator'], 'pre_requisitos' => []
      }
    end

    it 'aceita um passo completo' do
      expect { carregar([passo_valido]) }.not_to raise_error
    end

    it 'recusa passo sem campo obrigatório' do
      expect { carregar([passo_valido.except('titulo')]) }
        .to raise_error(described_class::InvalidDefinition, /sem os campos: titulo/)
    end

    it 'recusa verificação sem regra no serviço de progresso' do
      expect { carregar([passo_valido.merge('verificacao' => 'inventada')]) }
        .to raise_error(described_class::InvalidDefinition, /verificação sem regra/)
    end

    it 'recusa perfil desconhecido' do
      expect { carregar([passo_valido.merge('perfis' => ['gerente'])]) }
        .to raise_error(described_class::InvalidDefinition, /perfil desconhecido/)
    end

    it 'recusa id repetido' do
      expect { carregar([passo_valido, passo_valido.merge('ordem' => 1)]) }
        .to raise_error(described_class::InvalidDefinition, /id repetido/)
    end

    it 'recusa pulavel fora de true ou false' do
      expect { carregar([passo_valido.merge('pulavel' => 'sim')]) }
        .to raise_error(described_class::InvalidDefinition, /pulavel fora/)
    end

    it 'recusa etapa fora das três da tela' do
      expect { carregar([passo_valido.merge('etapa' => 'vender')]) }
        .to raise_error(described_class::InvalidDefinition, /etapa fora/)
    end

    it 'recusa minutos que não sejam inteiro positivo' do
      expect { carregar([passo_valido.merge('minutos' => 0)]) }
        .to raise_error(described_class::InvalidDefinition, /minutos fora/)
      expect { carregar([passo_valido.merge('minutos' => '5')]) }
        .to raise_error(described_class::InvalidDefinition, /minutos fora/)
    end

    it 'recusa artigo que não existe na Central de Ajuda' do
      expect { carregar([passo_valido.merge('artigo' => '00.99')]) }
        .to raise_error(described_class::InvalidDefinition, /artigo inexistente/)
    end

    it 'recusa dependência de passo que não vem antes' do
      segundo = passo_valido.merge('id' => 'chave_ia', 'ordem' => 1, 'artigo' => '00.03')

      expect { carregar([passo_valido.merge('depende_de' => 'chave_ia'), segundo]) }
        .to raise_error(described_class::InvalidDefinition, /depende de "chave_ia"/)
      expect { carregar([passo_valido, segundo.merge('depende_de' => 'inventado')]) }
        .to raise_error(described_class::InvalidDefinition, /depende de "inventado"/)
      expect { carregar([passo_valido, segundo.merge('depende_de' => 'perfil')]) }.not_to raise_error
    end
  end
end
