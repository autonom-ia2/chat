/* eslint-disable no-await-in-loop, no-restricted-syntax -- Each fixture lifecycle is intentionally sequential. */

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const publisher = new URL(
  '../../scripts/instagram_testers/session_publisher.rb',
  import.meta.url
);
const secret = 'SYNTHETIC_PRIVATE_PAYLOAD_DO_NOT_PRINT';
const limit = 2 * 1024 * 1024;
const request = { type: 'session', operation: 'version', session: secret };
const response = { type: 'session', version: null };
const failure = 'Instagram session publication failed\n';
const executorEvents = ['boot', 'load_runner', 'executor_start'];
const successEvents = [
  ...executorEvents,
  'call',
  'serialize',
  'executor_complete',
  'at_exit',
];

// Only the copied CLI executes. The application, environment and service are
// synthetic; no Rails, Bundler, database, publisher transport or inherited
// config is loaded.
async function fixture(
  t,
  {
    boot = '',
    runner = '',
    start = '',
    complete = '',
    call = '',
    serialize = '',
  } = {}
) {
  const root = await mkdtemp(join(tmpdir(), 'session-publisher-stdio-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'scripts/instagram_testers'), { recursive: true });
  await mkdir(join(root, 'config'));
  const script = join(root, 'scripts/instagram_testers/session_publisher.rb');
  await copyFile(publisher, script);
  await writeFile(
    join(root, 'config/application.rb'),
    `
module Rails
  class Configuration
    attr_accessor :eager_load

    def initialize
      @eager_load = true
      @before_initialize = nil
    end

    def before_initialize(&block)
      @before_initialize = block
    end

    def initialize_application(app)
      @before_initialize&.call(app)
    end
  end

  @config = Configuration.new

  def self.application
    self
  end

  def self.config
    @config
  end

  def self.initialize!
    @config.initialize_application(self)
  end
end
`
  );
  await writeFile(
    join(root, 'config/environment.rb'),
    `
require 'json'
$lifecycle = ['boot']
puts '${secret}: boot stdout'
STDOUT.write("${secret}: direct boot stdout\\n")
warn '${secret}: boot stderr'
STDERR.write("${secret}: direct boot stderr\\n")
at_exit do
  $lifecycle << 'at_exit'
  File.write('lifecycle.json', JSON.generate({
    events: $lifecycle,
    protocol_closed: TOPLEVEL_BINDING.eval('protocol_stdout.closed? && protocol_stderr.closed?'),
    executor_active: !!$executor_active
  }))
  puts '${secret}: late stdout'
  STDOUT.write("${secret}: direct late stdout\\n")
  warn '${secret}: late stderr'
  STDERR.write("${secret}: direct late stderr\\n")
end
${boot}
class Numeric
  def megabytes; self * 1024 * 1024; end
end
module Rails
  def self.application; self; end
  def self.load_runner
    $lifecycle << 'load_runner'
    puts '${secret}: runner stdout'
    warn '${secret}: runner stderr'
    ${runner}
    $runner_loaded = true
  end
  def self.executor; self; end
  def self.wrap(source:)
    raise '${secret}: wrong runner source' unless source == 'application.runner.railties'
    $lifecycle << 'executor_start'
    puts '${secret}: executor stdout'
    warn '${secret}: executor stderr'
    ${start}
    $executor_active = true
    begin
      yield
    ensure
      $executor_active = false
      $lifecycle << 'executor_complete'
      puts '${secret}: completion stdout'
      warn '${secret}: completion stderr'
      ${complete}
    end
  end
end
Rails.application.initialize!
File.write('eager_load.json', JSON.generate({ eager_load: Rails.application.config.eager_load }))
module Instagram
  module Testers
    class Error < StandardError; end
  end
  module Automation
    class SessionPublisher
      def call(request)
        raise '${secret}: missing runner lifecycle' unless $runner_loaded && $executor_active
        $lifecycle << 'call'
        File.write('called.json', JSON.generate(request))
        puts '${secret}: call stdout'
        warn '${secret}: call stderr'
        ${call}
        result = { type: 'session', version: nil }
        def result.to_json
          raise '${secret}: serialization outside executor' unless $executor_active
          $lifecycle << 'serialize'
          ${serialize}
          super
        end
        result
      end
    end
  end
end
`
  );
  return {
    run(input = JSON.stringify(request), args = []) {
      const result = spawnSync('/usr/bin/ruby', [script, ...args], {
        cwd: root,
        env: {},
        input,
        encoding: 'utf8',
        timeout: 5000,
        maxBuffer: 64 * 1024,
      });
      assert.equal(result.error, undefined);
      assert.equal(result.signal, null);
      assert.equal(result.stdout.includes(secret), false);
      assert.equal(result.stderr.includes(secret), false);
      return result;
    },
    called: () => readFile(join(root, 'called.json'), 'utf8'),
    eagerLoad: () => readFile(join(root, 'eager_load.json'), 'utf8'),
    async lifecycle(events) {
      assert.deepEqual(
        JSON.parse(await readFile(join(root, 'lifecycle.json'), 'utf8')),
        { events, protocol_closed: true, executor_active: false }
      );
    },
  };
}

test('publisher disables eager loading before environment initialization', async t => {
  const cli = await fixture(t);
  const result = cli.run();
  assert.equal(result.status, 0);
  assert.deepEqual(JSON.parse(await cli.eagerLoad()), { eager_load: false });
});

test('publisher boot hook uses Rails config without a global ENV toggle', async () => {
  const source = await readFile(publisher, 'utf8');
  assert.ok(source.includes("require_relative '../../config/application'"));
  assert.ok(source.includes('Rails.application.config.before_initialize'));
  assert.equal(source.includes('ENV['), false);
});

test('success emits one JSON line despite boot, call and at_exit logs', async t => {
  const cli = await fixture(t);
  const result = cli.run();
  assert.equal(result.status, 0);
  assert.equal(result.stdout, `${JSON.stringify(response)}\n`);
  assert.equal(result.stderr, '');
  assert.deepEqual(JSON.parse(await cli.called()), request);
  await cli.lifecycle(successEvents);
});

test('channel mode reuses one boot and runs each frame inside its executor', async t => {
  const cli = await fixture(t);
  const input = `${JSON.stringify(request)}\n${JSON.stringify(request)}\n`;
  const result = cli.run(input, ['--channel']);
  assert.equal(result.status, 0);
  assert.equal(
    result.stdout,
    `${JSON.stringify(response)}\n${JSON.stringify(response)}\n`
  );
  assert.equal(result.stderr, '');
  await cli.lifecycle([
    'boot',
    'load_runner',
    'executor_start',
    'call',
    'serialize',
    'executor_complete',
    'executor_start',
    'call',
    'serialize',
    'executor_complete',
    'at_exit',
  ]);
});

test('channel mode rejects incomplete and oversized frames before executor work', async t => {
  for (const input of [
    JSON.stringify(request),
    JSON.stringify(request).padEnd(limit + 1, ' ') + '\n',
  ]) {
    const cli = await fixture(t);
    const result = cli.run(input, ['--channel']);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, failure);
    await cli.lifecycle(['boot', 'load_runner', 'at_exit']);
  }
});

[
  ['boot exception', { boot: `raise '${secret}: boot failure'` }],
  ['boot load error', { boot: `raise LoadError, '${secret}: load failure'` }],
  [
    'boot syntax error',
    { boot: `raise SyntaxError, '${secret}: syntax failure'` },
  ],
  ['runner exception', { runner: `raise '${secret}: runner failure'` }],
  [
    'runner load error',
    { runner: `raise LoadError, '${secret}: runner failure'` },
  ],
  [
    'executor start exception',
    { start: `raise '${secret}: executor failure'` },
  ],
  [
    'executor completion exception',
    { complete: `raise '${secret}: completion failure'` },
  ],
  [
    'typed call rejection',
    { call: `raise Instagram::Testers::Error, request.fetch('session')` },
  ],
  ['call exception', { call: `raise request.fetch('session')` }],
  ['JSON serialization', { serialize: `raise '${secret}: JSON failure'` }],
].forEach(([name, options]) => {
  test(`${name} emits only the fixed error and suppresses late logs`, async t => {
    const cli = await fixture(t, options);
    const result = cli.run();
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, failure);
    if (options.boot || options.runner || options.start)
      await assert.rejects(cli.called(), { code: 'ENOENT' });
    else assert.deepEqual(JSON.parse(await cli.called()), request);
    let events;
    if (options.boot) events = ['boot', 'at_exit'];
    else if (options.runner) events = ['boot', 'load_runner', 'at_exit'];
    else if (options.start) events = [...executorEvents, 'at_exit'];
    else if (options.call)
      events = [...executorEvents, 'call', 'executor_complete', 'at_exit'];
    else events = successEvents;
    await cli.lifecycle(events);
  });
});

['', `{"session":"${secret}"`, `${JSON.stringify(request)}\n${secret}`].forEach(
  input => {
    test(`invalid JSON (${input.length} bytes) never calls the service or exposes input`, async t => {
      const cli = await fixture(t);
      const result = cli.run(input);
      assert.equal(result.status, 2);
      assert.equal(result.stdout, '');
      assert.equal(result.stderr, failure);
      await assert.rejects(cli.called(), { code: 'ENOENT' });
      await cli.lifecycle([...executorEvents, 'executor_complete', 'at_exit']);
    });
  }
);

test('exactly 2 MiB reaches the typed service without truncating input', async t => {
  const cli = await fixture(t);
  const input = JSON.stringify(request).padEnd(limit, ' ');
  assert.equal(Buffer.byteLength(input), limit);
  const result = cli.run(input);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, `${JSON.stringify(response)}\n`);
  assert.equal(result.stderr, '');
  assert.deepEqual(JSON.parse(await cli.called()), request);
  await cli.lifecycle(successEvents);
});

test('more than 2 MiB is rejected before parsing or calling the service', async t => {
  const cli = await fixture(t);
  const input = JSON.stringify(request).padEnd(limit + 1, ' ');
  assert.equal(Buffer.byteLength(input), limit + 1);
  const result = cli.run(input);
  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, failure);
  await assert.rejects(cli.called(), { code: 'ENOENT' });
  await cli.lifecycle([...executorEvents, 'executor_complete', 'at_exit']);
});

test('restricted wrapper invokes the Ruby CLI so it controls output before Rails boot', async () => {
  const source = await readFile(
    new URL(
      '../../scripts/instagram_testers/runtime/forced-publisher.sh',
      import.meta.url
    ),
    'utf8'
  );
  assert.ok(
    source.includes(
      'bundle exec ruby scripts/instagram_testers/session_publisher.rb 2>/dev/null'
    )
  );
  assert.equal(source.includes('rails runner'), false);
});
