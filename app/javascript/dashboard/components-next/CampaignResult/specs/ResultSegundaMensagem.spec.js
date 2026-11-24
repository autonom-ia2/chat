import { mount } from '@vue/test-utils';
import ResultSegundaMensagem from '../ResultSegundaMensagem.vue';

// #3101 — a segunda mensagem do "Mandar de novo" no resultado da primeira campanha.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores, n) => {
      const partes = [chave];
      if (valores) partes.push(JSON.stringify(valores));
      if (n !== undefined) partes.push(`#${n}`);
      return partes.join(' ');
    },
    locale: { value: 'pt_BR' },
  }),
}));

const NS = 'REENVIO_HORARIO.RESULTADO';
const RouterLinkStub = {
  props: ['to'],
  template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
};

const montar = segunda =>
  mount(ResultSegundaMensagem, {
    props: {
      segunda: {
        dias: 3,
        quem: 'nao_respondeu',
        previsto_em: null,
        campanha: null,
        ...segunda,
      },
    },
    global: { stubs: { 'router-link': RouterLinkStub } },
  });

describe('ResultSegundaMensagem', () => {
  it('enviada: quantos receberam e responderam, com o caminho para a campanha nova', () => {
    const w = montar({
      status: 'enviado',
      campanha: {
        channel: 'sms',
        id: 42,
        name: 'Parcela · segunda mensagem',
        processing: false,
        receberam: 12,
        responderam: 1,
      },
    });

    const frase = w.get('[data-frase]').text();
    expect(frase).toContain(`${NS}.ENVIADA`);
    expect(frase).toContain(`${NS}.RECEBERAM {\\"n\\":\\"12\\"} #12`);
    expect(frase).toContain(`${NS}.RESPONDERAM {\\"n\\":\\"1\\"} #1`);
    const link = w.get('[data-ver-segunda]');
    expect(link.text()).toBe('Parcela · segunda mensagem');
    expect(JSON.parse(link.attributes('data-to'))).toEqual({
      name: 'campaigns_journey_result',
      params: { channel: 'sms', campaignId: '42' },
    });
    expect(w.find('[data-saindo]').exists()).toBe(false);
  });

  it('enviada e ainda saindo: avisa que os números crescem', () => {
    const w = montar({
      status: 'enviado',
      campanha: {
        channel: 'whatsapp_api',
        id: 7,
        name: 'X · segunda mensagem',
        processing: true,
        receberam: 0,
        responderam: 0,
      },
    });
    expect(w.get('[data-saindo]').text()).toBe(`${NS}.SAINDO`);
  });

  it('enviada, mas a campanha nova foi apagada: diz isso, sem caminho', () => {
    const w = montar({ status: 'enviado' });
    expect(w.get('[data-frase]').text()).toBe(`${NS}.APAGADA`);
    expect(w.find('[data-ver-segunda]').exists()).toBe(false);
  });

  it('aguardando sem data: sai N dias depois que a primeira terminar', () => {
    const w = montar({ status: 'aguardando' });
    const frase = w.get('[data-frase]').text();
    expect(frase).toContain(`${NS}.AGUARDANDO_SEM_DATA`);
    expect(frase).toContain('"dias":3');
    expect(frase).toContain(
      'REENVIO_HORARIO.REENVIO.QUEM_RESUMO.NAO_RESPONDEU'
    );
    expect(frase).toContain('#3');
  });

  it('aguardando com data: diz quando sai, para quem nem leu', () => {
    const w = montar({
      status: 'aguardando',
      quem: 'nao_leu',
      previsto_em: Math.floor(Date.UTC(2030, 0, 15, 15, 0) / 1000),
    });
    const frase = w.get('[data-frase]').text();
    expect(frase).toContain(`${NS}.AGUARDANDO_DATA`);
    expect(frase).toContain('DUAS_VERSOES.QUANDO.DIA');
    expect(frase).toContain('REENVIO_HORARIO.REENVIO.QUEM_RESUMO.NAO_LEU');
  });

  it.each([
    ['sem_ninguem', 'SEM_NINGUEM'],
    ['cancelado', 'CANCELADO'],
    ['falhou', 'FALHOU'],
  ])('%s: diz por que não saiu, sem caminho', (status, chave) => {
    const w = montar({ status });
    expect(w.attributes('data-segunda-mensagem')).toBe(status);
    expect(w.get('[data-frase]').text()).toBe(`${NS}.${chave}`);
    expect(w.find('[data-ver-segunda]').exists()).toBe(false);
  });
});
