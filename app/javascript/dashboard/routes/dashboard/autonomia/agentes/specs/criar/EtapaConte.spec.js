import { mount } from '@vue/test-utils';
import EtapaConte from '../../components/criar/EtapaConte.vue';

const falas = [
  { de: 'assistente', texto: 'Que tipo de negócio é o seu?', chave: 't0' },
];

const montar = props =>
  mount(EtapaConte, {
    props: {
      falas,
      estadoDoMaterial: material => material.estado,
      ...props,
    },
    attachTo: document.body,
  });

describe('EtapaConte', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('shows the AI turn and names who speaks for screen readers', () => {
    const wrapper = montar();
    const fala = wrapper.get('[data-fala="assistente"]');
    expect(fala.text()).toContain('Que tipo de negócio é o seu?');
    expect(fala.get('.sr-only').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONTE.ASSISTENTE'
    );
    expect(wrapper.get('[data-conversa]').attributes('role')).toBe('log');
  });

  it('offers the ideas only before the first answer, and an idea fills the field (does not send)', async () => {
    const wrapper = montar({ ideias: ['Loja de roupas', 'Confeitaria'] });
    const ideias = wrapper.get('[data-ideias]');
    expect(ideias.attributes('aria-label')).toBe('AGENTS.JORNADA.COMUM.IDEIAS');

    await ideias.findAll('button')[1].trigger('click');
    expect(wrapper.emitted('enviar')).toBeUndefined();
    expect(wrapper.get('textarea').element.value).toBe('Confeitaria');

    await wrapper.setProps({ respostas: 1 });
    expect(wrapper.find('[data-ideias]').exists()).toBe(false);
  });

  it('holds the ideas until the first Builder question arrives (#1369)', async () => {
    const wrapper = montar({
      falas: [],
      pensando: true,
      ideias: ['Loja de roupas', 'Confeitaria'],
    });
    expect(wrapper.find('[data-pensando]').exists()).toBe(true);
    expect(wrapper.find('[data-ideias]').exists()).toBe(false);

    // A abertura falhou: sem pergunta, sem ideias.
    await wrapper.setProps({ pensando: false, falhou: true });
    expect(wrapper.find('[data-ideias]').exists()).toBe(false);

    await wrapper.setProps({ falas, falhou: false });
    expect(wrapper.find('[data-ideias]').exists()).toBe(true);
  });

  it('sends what was typed, with optional attachments, and clears the field', async () => {
    const wrapper = montar();
    await wrapper.get('textarea').setValue('Loja de roupas');
    await wrapper.get('form').trigger('submit');

    expect(wrapper.emitted('enviar')[0][0]).toEqual({
      texto: 'Loja de roupas',
      anexos: [],
    });
    expect(wrapper.get('textarea').element.value).toBe('');
  });

  it('shows the draft the page fills in (v-model), so the person completes it', async () => {
    const wrapper = montar({ rascunho: 'Perguntei: Quanto custa?' });
    expect(wrapper.get('textarea').element.value).toBe(
      'Perguntei: Quanto custa?'
    );
    await wrapper.get('textarea').setValue('Outro texto');
    expect(wrapper.emitted('update:rascunho').at(-1)).toEqual(['Outro texto']);
  });

  it('keeps the clip optional and offers it again after the first answer', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-anexar]').exists()).toBe(true);
    expect(wrapper.find('[data-linha-anexo]').exists()).toBe(false);

    await wrapper.setProps({ respostas: 1 });
    expect(wrapper.get('[data-linha-anexo]').text()).toContain(
      'AGENTS.JORNADA.CRIAR.CONTE.ANEXO_FRASE'
    );
    await wrapper.setProps({ fechada: true });
    expect(wrapper.find('[data-linha-anexo]').exists()).toBe(false);
  });

  // #2489 — o arquivo não subiu enquanto o turno esperava: a conversa diz qual e o que fazer.
  it('says which file did not upload, as an alert', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-falha-ao-subir]').exists()).toBe(false);

    await wrapper.setProps({ falhaAoSubir: { nome: 'tabela.pdf' } });
    const falha = wrapper.get('[data-falha-ao-subir]');
    expect(falha.attributes('role')).toBe('alert');
    expect(falha.text()).toBe('AGENTS.JORNADA.CRIAR.CONTE.NAO_SUBIU');
  });

  it('shows "thinking", then "taking longer", and asks to wait while the AI answers', async () => {
    const wrapper = montar({ pensando: true });
    expect(wrapper.find('[data-pensando]').exists()).toBe(true);
    expect(wrapper.find('[data-demorando]').exists()).toBe(false);
    expect(wrapper.get('[data-espere]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONTE.ESPERE'
    );
    // O campo não é desabilitado (o foco não cai no body); só o Enviar espera.
    expect(wrapper.get('textarea').attributes('disabled')).toBeUndefined();

    await wrapper.setProps({ demorando: true });
    expect(wrapper.get('[data-demorando]').attributes('role')).toBe('status');
  });

  it('turns a failure into a card that keeps what was told, with one way out', async () => {
    const wrapper = montar({ falhou: true });
    const erro = wrapper.get('[data-erro-conversa]');
    expect(erro.text()).toContain('AGENTS.JORNADA.CRIAR.CONTE.ERRO');
    expect(erro.text()).toContain('AGENTS.JORNADA.CRIAR.CONTE.ERRO_GARANTIA');

    await erro.get('button').trigger('click');
    expect(wrapper.emitted('tentarDeNovo')).toHaveLength(1);
  });

  it('renders the materials in the conversation, and "Tirar" removes one', async () => {
    const material = {
      id: 1,
      nome: 'Tabela.pdf',
      tipo: 'arquivo',
      estado: 'atencao',
    };
    const wrapper = montar({
      falas: [...falas, { de: 'material', material, chave: 'm1' }],
    });
    const caixa = wrapper.get('[data-material]');
    expect(caixa.attributes('data-estado')).toBe('atencao');

    await caixa.get('[data-tirar]').trigger('click');
    expect(wrapper.emitted('tirar')[0][0]).toEqual(material);
  });

  it('shows the example hint in the first field of "do meu jeito"', async () => {
    const wrapper = montar({ exemploDoCampo: 'Ex.: responder dúvidas' });
    expect(wrapper.get('textarea').attributes('placeholder')).toBe(
      'Ex.: responder dúvidas'
    );
    await wrapper.setProps({ respostas: 1 });
    expect(wrapper.get('textarea').attributes('placeholder')).toBe(
      'AGENTS.JORNADA.COMPOSITOR.ESCREVA'
    );
  });

  // #2881 — agente pronto por ramo: duas perguntas, e as ideias e o exemplo do campo acompanham cada uma.
  it('with a short interview, keeps the ideas and the field hint of the question of the turn after the first answer', async () => {
    const wrapper = montar({
      ideiasEmTodaPergunta: true,
      respostas: 1,
      ideias: ['Porto, Allianz e Tokio Marine', 'Decido depois'],
      exemploDoCampo: 'Escreva os nomes das seguradoras',
    });

    expect(wrapper.get('[data-ideias]').findAll('button')).toHaveLength(2);
    expect(wrapper.get('textarea').attributes('placeholder')).toBe(
      'Escreva os nomes das seguradoras'
    );
    await wrapper.get('[data-ideias]').findAll('button')[1].trigger('click');
    expect(wrapper.emitted('enviar')).toBeUndefined();
    expect(wrapper.get('textarea').element.value).toBe('Decido depois');

    // Enquanto o Construtor pensa, e depois que a conversa fecha, as ideias somem.
    await wrapper.setProps({ pensando: true });
    expect(wrapper.find('[data-ideias]').exists()).toBe(false);
    await wrapper.setProps({ pensando: false, fechada: true });
    expect(wrapper.find('[data-ideias]').exists()).toBe(false);
  });

  it('invites to tell more, quietly, once the conversation closed (computer)', async () => {
    const wrapper = montar({ fechada: true });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CRIAR.CONTE.MAIS');
    await wrapper.setProps({ celular: true });
    expect(wrapper.text()).not.toContain('AGENTS.JORNADA.CRIAR.CONTE.MAIS');
  });

  it('pins the field to the bottom on the phone, with the bar above it', () => {
    const wrapper = mount(EtapaConte, {
      props: { falas, estadoDoMaterial: () => 'lendo', celular: true },
      slots: { barra: '<button data-barra>Ver o exemplo</button>' },
    });
    const doca = wrapper.get('[data-barra]').element.parentElement;
    expect(doca.className).toContain('fixed');
    expect(doca.className).toContain('bottom-0');
  });

  it('never renders a native select', () => {
    expect(montar().find('select').exists()).toBe(false);
  });
});
