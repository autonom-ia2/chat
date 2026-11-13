import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import { resumoDaTela } from '../../trazer/contagem';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
import PrecisamDeVoce from '../../components/trazer/PrecisamDeVoce.vue';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';

// #2896 — o servidor não aceitou o valor que a pessoa escreveu numa linha: a
// frase do motivo aparece na própria linha, como alerta, com o foco no campo, e
// só na linha dela.
withFullI18n('pt_BR');

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

const leitura = leituraDeExemplo('l1');

const problemaDe = linha => leitura.problemas.find(p => p.linha === linha);

const TELEFONE_RECUSADO =
  'Este telefone não parece um celular do Brasil. Confira o DDD e os dígitos.';

const EMAIL_RECUSADO = 'Este e-mail não parece certo.';

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('ProblemaDaLinha: o servidor recusou o valor', () => {
  const montar = (linha, extra = {}) =>
    mount(ProblemaDaLinha, {
      attachTo: document.body,
      props: { problema: problemaDe(linha), ...extra },
    });

  it('sem recusa não há frase nenhuma', () => {
    expect(montar(37).find('[role="alert"]').exists()).toBe(false);
  });

  it('e-mail: a frase certa aparece na linha, como alerta, e o foco vai ao campo', async () => {
    const w = montar(37);
    await w.setProps({ recusa: { linha: 37, motivo: 'invalid_email' } });
    await flushPromises();
    const alerta = w.get('[role="alert"]');
    expect(alerta.text()).toBe(EMAIL_RECUSADO);
    expect(document.activeElement).toBe(w.get('input').element);
    expect(w.get('input').attributes('aria-invalid')).toBe('true');
    expect(w.get('input').attributes('aria-describedby')).toBe(
      alerta.attributes('id')
    );
  });

  it('telefone: a frase do celular do Brasil, com o foco no campo do telefone', async () => {
    const w = montar(14);
    await w.setProps({
      recusa: { linha: 14, motivo: 'invalid_brazilian_mobile_number' },
    });
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toBe(TELEFONE_RECUSADO);
    expect(document.activeElement).toBe(w.get('form input').element);
  });

  it.each([
    [14, 'Confira este telefone e tente de novo.'],
    [37, 'Confira este e-mail e tente de novo.'],
    [62, 'Confira este nome e tente de novo.'],
    [143, 'Não consegui salvar esta linha. Tente de novo.'],
  ])(
    'motivo que a tela não conhece, na linha %s: a frase do campo',
    async (linha, frase) => {
      const w = montar(linha);
      await w.setProps({ recusa: { linha, motivo: 'coisa_nova' } });
      await flushPromises();
      expect(w.get('[role="alert"]').text()).toBe(frase);
    }
  );

  it('a frase some quando a pessoa mexe no campo e volta se o servidor recusar de novo', async () => {
    const w = montar(37);
    await w.setProps({ recusa: { linha: 37, motivo: 'invalid_email' } });
    await flushPromises();
    await w.get('input').setValue('rita@exemplo.com.br');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await w.setProps({ recusa: { linha: 37, motivo: 'invalid_email' } });
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toBe(EMAIL_RECUSADO);
  });

  it('já nasce com a frase quando a recusa já existe', async () => {
    const w = montar(37, { recusa: { linha: 37, motivo: 'invalid_email' } });
    await flushPromises();
    expect(w.get('[role="alert"]').text()).toBe(EMAIL_RECUSADO);
  });
});

describe('PrecisamDeVoce e TelaConferir: a recusa vai só para a linha dela', () => {
  it('PrecisamDeVoce entrega a recusa à linha certa', async () => {
    const w = mount(PrecisamDeVoce, {
      attachTo: document.body,
      props: {
        problemas: leitura.problemas,
        recusa: { linha: 37, motivo: 'invalid_email' },
      },
    });
    await flushPromises();
    expect(w.get('[data-linha="37"] [role="alert"]').text()).toBe(
      EMAIL_RECUSADO
    );
    expect(w.findAll('[role="alert"]')).toHaveLength(1);
  });

  it('TelaConferir repassa a recusa do conserto', async () => {
    const w = mount(TelaConferir, {
      attachTo: document.body,
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
        recusaDoConserto: {
          linha: 14,
          motivo: 'invalid_brazilian_mobile_number',
        },
      },
    });
    await flushPromises();
    expect(w.get('[data-linha="14"] [role="alert"]').text()).toBe(
      TELEFONE_RECUSADO
    );
  });

  it('TelaConferir repassa a troca com o campo da informação nova', async () => {
    const w = mount(TelaConferir, {
      props: {
        leitura,
        resumo: resumoDaTela(leitura),
        total: resumoDaTela(leitura).entram,
      },
    });
    const campo = { nome: 'Nascimento', para_que_serve: '' };
    await w
      .getComponent(OQueVouGuardar)
      .vm.$emit('trocar', 'Aniversário', 'informacao', campo);
    expect(w.emitted('trocar')).toEqual([['Aniversário', 'informacao', campo]]);
  });
});
