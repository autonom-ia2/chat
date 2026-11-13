import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AvisosDaLeitura from '../../components/trazer/AvisosDaLeitura.vue';
import { ETAPAS } from '../../trazer/etapas';
import { MARCADOR, lida, noConferir } from './apoioDaTela';

// #2896, Fatia 2 — os avisos fixos sobre a leitura, ditos como alerta no topo da
// tela de conferir (e da pergunta, quando a pessoa cai nela):
//   - o servidor desfez a última mudança, porque com ela não sobraria ninguém
//     (`aviso: "mudanca_desfeita"` na leitura, até a próxima escrita que dê certo);
//   - a lista mudou por fora e a tela mostrou como está agora (`mudou`).
withFullI18n('pt_BR');

const DESFEITA =
  'Não fiz essa mudança: com ela não sobraria ninguém com telefone ou e-mail. Deixei como estava.';
const MUDOU =
  'Esta lista mudou enquanto você conferia. Mostrei como está agora.';
const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);
const montar = props => mount(AvisosDaLeitura, { props });

describe('AvisosDaLeitura', () => {
  it('sem aviso nem mudança, não mostra nada', () => {
    const w = montar({});
    expect(w.findAll('[role="alert"]')).toHaveLength(0);
    expect(w.text()).toBe('');
  });

  it('a mudança desfeita é dita como alerta', () => {
    const w = montar({ aviso: 'mudanca_desfeita' });
    const alerta = marca(w, 'mudanca-desfeita');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(DESFEITA);
  });

  it('aviso que a tela não conhece não vira frase', () => {
    expect(montar({ aviso: 'outra_coisa' }).text()).toBe('');
  });

  it('a lista que mudou por fora é dita como alerta', () => {
    const w = montar({ mudou: true });
    const alerta = marca(w, 'lista-mudou');
    expect(alerta.attributes('role')).toBe('alert');
    expect(alerta.text()).toBe(MUDOU);
  });

  it('os dois juntos: duas frases', () => {
    const w = montar({ aviso: 'mudanca_desfeita', mudou: true });
    expect(w.findAll('[role="alert"]')).toHaveLength(2);
  });
});

describe('o aviso acompanha a leitura', () => {
  const DESFEITA_NA_LEITURA = lida({ aviso: 'mudanca_desfeita' });

  it('chega com a leitura que volta da troca e continua enquanto a chave vier', async () => {
    const { tela } = await noConferir(lida(), {
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR),
      retomar: vi.fn().mockResolvedValue(DESFEITA_NA_LEITURA),
      deixarDeFora: vi.fn().mockResolvedValue(DESFEITA_NA_LEITURA),
    });
    expect(tela.leitura.value.aviso).toBeUndefined();
    await tela.trocarDestino(1, 'nao_guardar');
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
    expect(tela.leitura.value.aviso).toBe('mudanca_desfeita');
    await tela.deixarDeFora(14);
    expect(tela.leitura.value.aviso).toBe('mudanca_desfeita');
  });

  it('some quando a leitura volta sem a chave', async () => {
    const { tela } = await noConferir(DESFEITA_NA_LEITURA, {
      deixarDeFora: vi.fn().mockResolvedValue(lida()),
    });
    expect(tela.leitura.value.aviso).toBe('mudanca_desfeita');
    await tela.deixarDeFora(14);
    expect(tela.leitura.value.aviso).toBeUndefined();
  });
});
