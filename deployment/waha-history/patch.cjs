'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const BASE_BODY_BEFORE = `const body = {
            content: content,
            message_type: type,
            private: private_,
            attachments: message.attachments,
            content_attributes: {
                in_reply_to: replyTo,
            },
        };`;

const BASE_BODY_AFTER = `const body = {
            content: content,
            message_type: type,
            private: private_,
            attachments: message.attachments,
            content_attributes: {
                in_reply_to: replyTo,
            },
        };
        if (this.repo && this.repo.config && this.repo.config.chat2youHistoryOnboarding === true) {
            body.source_id = payload.id;
            body.external_created_at = payload.timestamp;
        }`;

const VERSION_BEFORE = `exports.VERSION = {
    version: '2026.9.2',
    engine: (0, config_1.getEngineName)(),
    tier: getWAHAVersion(),
    browser: getBrowser(),
    platform: getPlatform(),
    worker: getWorker(),
};`;

const VERSION_AFTER = `exports.VERSION = {
    version: '2026.9.2',
    engine: (0, config_1.getEngineName)(),
    tier: getWAHAVersion(),
    browser: getBrowser(),
    platform: getPlatform(),
    worker: getWorker(),
    chat2youHistorySourceIds: 'v1',
    chat2youHistoryFirstConnectionTimestamp: 'v1',
};`;

const SESSION_STATUS_PROCESS_BEFORE = `    async Process(job, info) {
        const container = await this.DIContainer(job, job.data.app);
        const handler = new SessionStatusHandler(container.ContactConversationService(), container.Locale(), container.WAHASelf());
        return await handler.handle(job.data.event);
    }`;

const SESSION_STATUS_PROCESS_AFTER = `    async Process(job, info) {
        const container = await this.DIContainer(job, job.data.app);
        const handler = new SessionStatusHandler(container.ContactConversationService(), container.Locale(), container.WAHASelf());
        const event = job.data.event;
        const historyOnboarding = handler.repo.config && handler.repo.config.chat2youHistoryOnboarding === true;
        if (historyOnboarding && event.payload && event.payload.status === enums_dto_1.WAHASessionStatus.WORKING) {
            const timestamp = event.chat2youHistoryWorkingAtMs;
            if (timestamp === null || timestamp === undefined) {
                return await handler.handle(event);
            }
            if (!Number.isSafeInteger(timestamp) || timestamp <= 0) {
                throw new Error('waha_history_working_timestamp_invalid');
            }
            await handler.repo.registerHistoryConnection(event.session, timestamp);
        }
        return await handler.handle(event);
    }`;

const CONTACT_CONVERSATION_REGISTER_BEFORE = `    async ConversationByContact(contactInfo) {`;

const CONTACT_CONVERSATION_REGISTER_AFTER = `    async registerHistoryConnection(session, workingAtMs) {
        if (!Number.isSafeInteger(workingAtMs) || workingAtMs <= 0) {
            throw new Error('waha_history_working_timestamp_invalid');
        }
        return this.accountAPI.inboxes.update({
            accountId: this.config.accountId,
            id: this.config.inboxId,
            data: {
                waha_history_connection: {
                    session: session,
                    working_at_ms: workingAtMs,
                },
            },
        });
    }
    async ConversationByContact(contactInfo) {`;

const CONFIG_DTO_CLASS_BEFORE = `class ChatWootAppConfig {
    constructor() {
        this.linkPreview = LinkPreview.OFF;
        this.locale = exports.DEFAULT_LOCALE;
    }
    static _OPENAPI_METADATA_FACTORY() {
        return { url: { required: true, type: () => String }, accountId: { required: true, type: () => Number }, accountToken: { required: true, type: () => String }, inboxId: { required: true, type: () => Number }, inboxIdentifier: { required: true, type: () => String }, linkPreview: { required: false, default: LinkPreview.OFF, enum: require("./config.dto").LinkPreview }, locale: { required: true, type: () => String, default: exports.DEFAULT_LOCALE }, templates: { required: false, type: () => Object }, commands: { required: false, type: () => require("./config.dto").ChatWootCommandsConfig }, conversations: { required: false, type: () => require("./config.dto").ChatWootConversationsConfig } };
    }
}
exports.ChatWootAppConfig = ChatWootAppConfig;`;

const CONFIG_DTO_CLASS_AFTER = `class ChatWootAppConfig {
    constructor() {
        this.linkPreview = LinkPreview.OFF;
        this.locale = exports.DEFAULT_LOCALE;
        this.chat2youHistoryOnboarding = false;
    }
    static _OPENAPI_METADATA_FACTORY() {
        return { url: { required: true, type: () => String }, accountId: { required: true, type: () => Number }, accountToken: { required: true, type: () => String }, inboxId: { required: true, type: () => Number }, inboxIdentifier: { required: true, type: () => String }, linkPreview: { required: false, default: LinkPreview.OFF, enum: require("./config.dto").LinkPreview }, locale: { required: true, type: () => String, default: exports.DEFAULT_LOCALE }, templates: { required: false, type: () => Object }, commands: { required: false, type: () => require("./config.dto").ChatWootCommandsConfig }, conversations: { required: false, type: () => require("./config.dto").ChatWootConversationsConfig }, chat2youHistoryOnboarding: { required: false, type: () => Boolean, default: false } };
    }
}
exports.ChatWootAppConfig = ChatWootAppConfig;`;

const CONFIG_DTO_LOCALE_DECORATOR_BEFORE = `__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], ChatWootAppConfig.prototype, "locale", void 0);`;

const CONFIG_DTO_LOCALE_DECORATOR_AFTER = `__decorate([
    (0, class_validator_1.IsString)(),
    __metadata("design:type", String)
], ChatWootAppConfig.prototype, "locale", void 0);
__decorate([
    (0, class_validator_1.IsOptional)(),
    (0, class_validator_1.IsBoolean)(),
    __metadata("design:type", Boolean)
], ChatWootAppConfig.prototype, "chat2youHistoryOnboarding", void 0);`;

const SESSION_ABC_STATUS_BEFORE = `        this._statusData = data;
        this.status$.next({ status: status, data: data });`;

const SESSION_ABC_STATUS_AFTER = `        const chat2youTimestamp = Date.now();
        if (status === enums_dto_1.WAHASessionStatus.SCAN_QR_CODE) {
            this.chat2youQrObserved = true;
        }
        if (status === enums_dto_1.WAHASessionStatus.WORKING && !Number.isSafeInteger(this.chat2youFirstWorkingAtMs)) {
            this.chat2youFirstWorkingAtMs = chat2youTimestamp;
            this.chat2youFirstWorkingHadQr = this.chat2youQrObserved === true;
        }
        this._statusData = data;
        this.status$.next({ status: status, data: data });`;

const QUEUE_SERVICE_LISTEN_BEFORE = `    listenEvents(app, session) {
        const config = (0, DIContainer_1.ChatWootConfigDefaults)(app.config);
        const events = (0, base_1.ListenEventsForChatWoot)(config);
        for (const event of events) {
            const obs$ = session.getEventObservable(event);
            obs$.subscribe(async (payload) => {
                const data = (0, manager_abc_1.populateSessionInfo)(event, session)(payload);
                await this.addJobToQueue(event, data, app.id);
            });
        }
    }`;

const QUEUE_SERVICE_LISTEN_AFTER = `    async historyWorkingData(config, app, session, data) {
        if (config.chat2youHistoryOnboarding !== true ||
            data.event !== enums_dto_1.WAHAEvents.SESSION_STATUS ||
            data.payload.status !== enums_dto_1.WAHASessionStatus.WORKING) {
            return data;
        }
        const queue = this.getQueueForEvent(data.event);
        if (!queue || typeof app.id !== 'string' || app.id.length === 0) {
            throw new Error('waha_history_queue_configuration_invalid');
        }
        const key = \`chat2you:waha:first-working:v2:\${app.id}\`;
        const client = await queue.client;
        let stored = await client.get(key);
        if (stored === null) {
            const timestamp = session.chat2youFirstWorkingAtMs;
            if (session.chat2youFirstWorkingHadQr !== true ||
                !Number.isSafeInteger(timestamp) || timestamp <= 0) {
                data.chat2youHistoryWorkingAtMs = null;
                return data;
            }
            const result = await client.set(key, String(timestamp), 'NX');
            stored = result === 'OK' ? String(timestamp) : await client.get(key);
        }
        if (typeof stored !== 'string' || !Number.isSafeInteger(Number(stored)) || Number(stored) <= 0) {
            throw new Error('waha_history_timestamp_store_invalid');
        }
        data.chat2youHistoryWorkingAtMs = Number(stored);
        return data;
    }
    listenEvents(app, session) {
        const config = (0, DIContainer_1.ChatWootConfigDefaults)(app.config);
        const events = (0, base_1.ListenEventsForChatWoot)(config);
        for (const event of events) {
            const obs$ = session.getEventObservable(event);
            obs$.subscribe(async (payload) => {
                let data = (0, manager_abc_1.populateSessionInfo)(event, session)(payload);
                data = await this.historyWorkingData(config, app, session, data);
                await this.addJobToQueue(event, data, app.id);
            });
        }
    }`;

const MESSAGE_CREATED_POST_SEND_BEFORE = `        if (this.config.conversations.syncMessageStatus) {
            await this.syncStatus(message, parts);
        }
        return results;
    }
    async syncStatus(message, parts) {`;

const MESSAGE_CREATED_POST_SEND_AFTER = `        if (this.config && this.config.chat2youHistoryOnboarding === true && parts > 0) {
            await this.syncSourceIds(message, parts);
        }
        if (this.config.conversations.syncMessageStatus) {
            await this.syncStatus(message, parts);
        }
        return results;
    }
    async syncSourceIds(message, parts) {
        const whatsapp = await this.mappingService.getWhatsAppMessage({
            conversation_id: message.conversation.id,
            message_id: message.id,
        });
        const sourceIds = whatsapp.map((part) => (0, ids_1.SerializeWhatsAppKey)(part));
        if (whatsapp.length !== parts ||
            sourceIds.some((id) => typeof id !== 'string' || id.length === 0) ||
            new Set(sourceIds).size !== sourceIds.length) {
            throw new Error('waha_source_mapping_incomplete');
        }
        await this.statusService.linkSourceIds({
            conversation_id: message.conversation.id,
            message_id: message.id,
            source_ids: sourceIds,
        });
    }
    async syncStatus(message, parts) {`;

const MESSAGE_STATUS_SERVICE_BEFORE = `    cleanup(removeAfter) {`;

const MESSAGE_STATUS_SERVICE_AFTER = `    async linkSourceIds(message) {
        return this.contactConversationService
            .ConversationById(message.conversation_id)
            .updateMessageSourceIds(message.message_id, message.source_ids);
    }
    cleanup(removeAfter) {`;

const CONVERSATION_UPDATE_STATUS_BEFORE = `    async activity(text) {`;

const CONVERSATION_UPDATE_STATUS_AFTER = `    async updateMessageSourceIds(messageId, sourceIds) {
        const data = { 'waha_source_ids[]': sourceIds };
        return this.accountAPI.messages.update({
            accountId: this.accountId,
            conversationId: this.conversationId,
            messageId: messageId,
            data: data,
        });
    }
    async activity(text) {`;

const MANAGER_ABC_CONSTRUCTOR_BEFORE = `    constructor(log, config, gowsConfigService, appsService) {
        this.log = log;
        this.config = config;
        this.gowsConfigService = gowsConfigService;
        this.appsService = appsService;
        this.WAIT_SESSION_RUNNING_INTERVAL = 500;
        this.WAIT_SESSION_RUNNING_TIMEOUT = 5000;
        this.WAIT_STATUS_INTERVAL = 500;
        this.WAIT_STATUS_TIMEOUT = 10000;
        this.lock = new AsyncLock({
            timeout: 5000,
            maxPending: Infinity,
            maxExecutionTime: 30000,
        });
        this.log.setContext(SessionManager.name);
    }
    startPredefinedSessions() {
        const startSessions = this.config.startSessions;
        startSessions.forEach((sessionName) => {
            this.withLock(sessionName, async () => {
                const log = this.log.logger.child({ session: sessionName });
                log.info(\`Restarting PREDEFINED session...\`);
                await this.start(sessionName).catch((error) => {
                    log.error(\`Failed to start PREDEFINED session: \${error}\`);
                    log.error(error.stack);
                });
            });
        });
    }`;

const MANAGER_ABC_CONSTRUCTOR_AFTER = `    constructor(log, config, gowsConfigService, appsService) {
        this.log = log;
        this.config = config;
        this.gowsConfigService = gowsConfigService;
        this.appsService = appsService;
        this.WAIT_SESSION_RUNNING_INTERVAL = 500;
        this.WAIT_SESSION_RUNNING_TIMEOUT = 5000;
        this.WAIT_STATUS_INTERVAL = 500;
        this.WAIT_STATUS_TIMEOUT = 10000;
        this.lock = new AsyncLock({
            timeout: 5000,
            maxPending: Infinity,
            maxExecutionTime: 30000,
        });
        const rawSkipAutoStartSessions = process.env.WAHA_AUTO_START_SKIP_SESSIONS_JSON;
        if (!rawSkipAutoStartSessions) {
            throw new Error('WAHA_AUTO_START_SKIP_SESSIONS_JSON is required');
        }
        let skipAutoStartSessions;
        try {
            skipAutoStartSessions = JSON.parse(rawSkipAutoStartSessions);
        } catch {
            throw new Error('WAHA_AUTO_START_SKIP_SESSIONS_JSON must be a JSON array');
        }
        if (!Array.isArray(skipAutoStartSessions) ||
            skipAutoStartSessions.some((sessionName) => typeof sessionName !== 'string' || sessionName.length === 0)) {
            throw new Error('WAHA_AUTO_START_SKIP_SESSIONS_JSON must contain only non-empty strings');
        }
        this.skipAutoStartSessions = new Set(skipAutoStartSessions);
        this.log.setContext(SessionManager.name);
    }
    startPredefinedSessions() {
        const startSessions = this.config.startSessions;
        startSessions.forEach((sessionName) => {
            if (this.skipAutoStartSessions.has(sessionName)) {
                return;
            }
            this.withLock(sessionName, async () => {
                const log = this.log.logger.child({ session: sessionName });
                log.info(\`Restarting PREDEFINED session...\`);
                await this.start(sessionName).catch((error) => {
                    log.error(\`Failed to start PREDEFINED session: \${error}\`);
                    log.error(error.stack);
                });
            });
        });
    }`;

const MANAGER_CORE_RESTART_BEFORE = `    async restartStoppedSessions(sessions) {
        await (0, promiseTimeout_1.sleep)(1000);
        const sleepS = this.config.autoStartDelaySeconds;
        this.log.info(\`Restarting sessions with delay of \${sleepS} seconds...\`);
        const sleepMs = this.config.autoStartDelaySeconds * 1000;
        for (const sessionName of sessions) {
            const log = this.log.logger.child({ session: sessionName });
            await this.withLock(sessionName, async () => {
                log.info(\`Restarting STOPPED session...\`);
                await this.start(sessionName).catch((error) => {
                    log.error(\`Failed to start STOPPED session: \${error}\`);
                    log.error(error.stack);
                });
            })
                .catch((error) => {
                log.error(\`Failed to restart STOPPED session: \${error}\`);
                log.error(error.stack);
            });
            await (0, promiseTimeout_1.sleep)(sleepMs);
        }
        this.log.info(\`STOPPED sessions have been restarted.\`);
    }`;

const MANAGER_CORE_RESTART_AFTER = `    async restartStoppedSessions(sessions) {
        await (0, promiseTimeout_1.sleep)(1000);
        const sleepS = this.config.autoStartDelaySeconds;
        this.log.info(\`Restarting sessions with delay of \${sleepS} seconds...\`);
        const sleepMs = this.config.autoStartDelaySeconds * 1000;
        for (const sessionName of sessions) {
            if (this.skipAutoStartSessions.has(sessionName)) {
                continue;
            }
            const log = this.log.logger.child({ session: sessionName });
            await this.withLock(sessionName, async () => {
                log.info(\`Restarting STOPPED session...\`);
                await this.start(sessionName).catch((error) => {
                    log.error(\`Failed to start STOPPED session: \${error}\`);
                    log.error(error.stack);
                });
            })
                .catch((error) => {
                log.error(\`Failed to restart STOPPED session: \${error}\`);
                log.error(error.stack);
            });
            await (0, promiseTimeout_1.sleep)(sleepMs);
        }
        this.log.info(\`STOPPED sessions have been restarted.\`);
    }`;

const PATCHES = [
  {
    relativePath: 'app/dist/apps/chatwoot/consumers/waha/base.js',
    originalSha256: '63475a6e0ac4f714d815e6fd07c27bc8849c6eabda1001faa007098709c39f10',
    before: BASE_BODY_BEFORE,
    after: BASE_BODY_AFTER,
  },
  {
    relativePath: 'app/dist/version.js',
    originalSha256: '91859392794b5bfdfd633e7dce77a3749b0e8d8216d949493f15801ec2730e38',
    before: VERSION_BEFORE,
    after: VERSION_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/consumers/waha/session.status.js',
    originalSha256: '6293fc3887a1201a5d251044bfc9a65d6ed46ed74f18cc984137175f7981d0c7',
    before: SESSION_STATUS_PROCESS_BEFORE,
    after: SESSION_STATUS_PROCESS_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/client/ContactConversationService.js',
    originalSha256: '2e9671bc1fbbe46e8597a9437bfb3ea3912edf33ad5e9baeb7c99b874b90decc',
    before: CONTACT_CONVERSATION_REGISTER_BEFORE,
    after: CONTACT_CONVERSATION_REGISTER_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/dto/config.dto.js',
    originalSha256: 'd5e7a1f883f93134372ecf15ac174d696fb6f219a1a64ccc5c9fcf4eb82e30e7',
    replacements: [
      { before: CONFIG_DTO_CLASS_BEFORE, after: CONFIG_DTO_CLASS_AFTER },
      { before: CONFIG_DTO_LOCALE_DECORATOR_BEFORE, after: CONFIG_DTO_LOCALE_DECORATOR_AFTER },
    ],
  },
  {
    relativePath: 'app/dist/core/abc/session.abc.js',
    originalSha256: '6e976be9376e82dda93bd3a2670840245be06d1d0ea1601ed6e27b68de65f4e3',
    before: SESSION_ABC_STATUS_BEFORE,
    after: SESSION_ABC_STATUS_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/services/ChatWootWAHAQueueService.js',
    originalSha256: 'a0d42f54af317c7b9aea696aca9fa36b712849f64e63fbb29ee7f1697c95c020',
    before: QUEUE_SERVICE_LISTEN_BEFORE,
    after: QUEUE_SERVICE_LISTEN_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/consumers/inbox/message_created.js',
    originalSha256: '7417b6f049b87482de35e14ac4c43aff187ffb28a291edb5aff865120b4ac04a',
    before: MESSAGE_CREATED_POST_SEND_BEFORE,
    after: MESSAGE_CREATED_POST_SEND_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/services/MessageStatusService.js',
    originalSha256: '530102b3079f35cf7e1392ae1c431b01c67806344e7485751110c6c41f8b12ca',
    before: MESSAGE_STATUS_SERVICE_BEFORE,
    after: MESSAGE_STATUS_SERVICE_AFTER,
  },
  {
    relativePath: 'app/dist/apps/chatwoot/client/Conversation.js',
    originalSha256: '857bc73880a485eec6d78b7b8c1f831e20e855bca884a999a6172aeb9d34484d',
    before: CONVERSATION_UPDATE_STATUS_BEFORE,
    after: CONVERSATION_UPDATE_STATUS_AFTER,
  },
  {
    relativePath: 'app/dist/core/abc/manager.abc.js',
    originalSha256: 'fab7bb659cc540064ecfd31ce540a84be24fe59e3a79c26e7c74306251b4ba29',
    before: MANAGER_ABC_CONSTRUCTOR_BEFORE,
    after: MANAGER_ABC_CONSTRUCTOR_AFTER,
  },
  {
    relativePath: 'app/dist/core/manager.core.js',
    originalSha256: '0ae6f8f133de460f2726c1bd471841eb6c991f6e5dace4af3dcb0bb4e84a9152',
    before: MANAGER_CORE_RESTART_BEFORE,
    after: MANAGER_CORE_RESTART_AFTER,
  },
];

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function countOccurrences(text, needle) {
  let count = 0;
  let offset = 0;
  while (true) {
    const index = text.indexOf(needle, offset);
    if (index === -1) return count;
    count += 1;
    offset = index + needle.length;
  }
}

function replaceExactly(text, before, after, label) {
  const occurrences = countOccurrences(text, before);
  if (occurrences !== 1) {
    throw new Error(`${label}: expected exactly one original block, found ${occurrences}`);
  }

  return text.replace(before, after);
}

function absolutePath(root, relativePath) {
  return path.join(root, relativePath);
}

function replacementsFor(patch) {
  if (Array.isArray(patch.replacements)) return patch.replacements;
  return [{ before: patch.before, after: patch.after }];
}

function assertSyntax(source, label) {
  try {
    new vm.Script(source, { filename: label });
  } catch (error) {
    throw new Error(`${label}: patched JavaScript syntax error: ${error.message}`);
  }
}

function evaluateCommonJs(source, stubs, label, environment = {}) {
  const module = { exports: {} };
  const context = {
    Buffer,
    JSON,
    Promise,
    Set,
    console,
    process: { env: environment },
    module,
    exports: module.exports,
    require: name => {
      if (!(name in stubs)) throw new Error(`self-test: unexpected require ${name}`);
      return stubs[name];
    },
  };

  vm.runInNewContext(source, context, { filename: label });
  return module.exports;
}

async function runAutoStartGuardSelfTest(managerAbcSource, managerCoreSource) {
  const AsyncLock = class {
    acquire(_name, fn) {
      return fn();
    }
  };
  const commonStubs = {
    '@nestjs/common': {
      NotFoundException: class NotFoundException extends Error {},
      UnprocessableEntityException: class UnprocessableEntityException extends Error {},
    },
    './EngineBootstrap': { NoopEngineBootstrap: class NoopEngineBootstrap {} },
    '../engines/gows/GowsBootstrap': { GowsBootstrap: class GowsBootstrap {} },
    '../../utils/promiseTimeout': {
      sleep: async () => {},
      waitUntil: async () => true,
      promiseTimeout: async (_timeout, promise) => promise,
    },
    '../../version': { VERSION: {} },
    lodash: { defaults: (target, ...sources) => Object.assign(target, ...sources) },
    rxjs: { of: () => {}, merge: () => {} },
    '../../structures/enums.dto': {
      WAHAEngine: { GOWS: 'GOWS', NOWEB: 'NOWEB', WPP: 'WPP', WEBJS: 'WEBJS' },
      WAHASessionStatus: { WORKING: 'WORKING' },
    },
    'async-lock': AsyncLock,
  };
  const environment = {};
  const { SessionManager } = evaluateCommonJs(managerAbcSource, commonStubs, 'manager.abc.js', environment);
  const log = {
    setContext: () => {},
    info: () => {},
    logger: {
      child: () => ({ info: () => {}, error: () => {} }),
    },
  };
  const invalidInputs = [
    { value: undefined, error: 'required' },
    { value: '{', error: 'JSON array' },
    { value: '{}', error: 'non-empty strings' },
    { value: '[1]', error: 'non-empty strings' },
    { value: '[""]', error: 'non-empty strings' },
  ];
  for (const input of invalidInputs) {
    if (input.value === undefined) {
      delete environment.WAHA_AUTO_START_SKIP_SESSIONS_JSON;
    } else {
      environment.WAHA_AUTO_START_SKIP_SESSIONS_JSON = input.value;
    }
    let thrown = null;
    try {
      new SessionManager(log, {}, {}, {});
    } catch (error) {
      thrown = error;
    }
    assert(thrown && thrown.message.includes(input.error), 'invalid skip list did not fail before startup');
    if (input.value !== undefined) {
      assert(!thrown.message.includes(input.value), 'invalid skip list leaked its value');
    }
  }

  environment.WAHA_AUTO_START_SKIP_SESSIONS_JSON = '["blocked","blocked"]';
  const manager = new SessionManager(log, { startSessions: ['blocked', 'working'] }, {}, {});
  assert(manager.skipAutoStartSessions.size === 1, 'duplicate skip names were not safely deduplicated');

  let lockCalls = 0;
  let childCalls = 0;
  const starts = [];
  manager.withLock = (_name, fn) => {
    lockCalls += 1;
    return fn();
  };
  manager.log.logger.child = () => {
    childCalls += 1;
    return { info: () => {}, error: () => {} };
  };
  manager.start = async name => {
    starts.push(name);
  };
  manager.startPredefinedSessions();
  assert(lockCalls === 1, 'predefined blocked session acquired a lock');
  assert(childCalls === 1, 'predefined blocked session created a logger');
  assert(starts.length === 1 && starts[0] === 'working', 'predefined working session did not start normally');
  await manager.start('blocked');
  assert(starts.length === 2 && starts[1] === 'blocked', 'manual start was incorrectly filtered');

  const noopClass = class {};
  class DefaultMap extends Map {
    constructor(factory) {
      super();
      this.factory = factory;
    }

    get(key) {
      if (!this.has(key)) this.set(key, this.factory(key));
      return super.get(key);
    }
  }
  const coreStubs = {
    '@nestjs/common': {
      Injectable: () => target => target,
      Inject: () => () => {},
    },
    '../apps/app_sdk/services/IAppsService': { AppsService: noopClass },
    './config/GowsEngineConfigService': { GowsEngineConfigService: noopClass },
    './config/NowebEngineConfigService': { NowebEngineConfigService: noopClass },
    './config/WPPEngineConfigService': { WPPEngineConfigService: noopClass },
    './config/WebJSEngineConfigService': { WebJSEngineConfigService: noopClass },
    './engines/gows/session.gows.core': { WhatsappSessionGoWSCore: noopClass },
    './engines/noweb/session.noweb.core': { WhatsappSessionNoWebCore: noopClass },
    './engines/wpp/session.wpp.core': { WhatsappSessionWPPCore: noopClass },
    './engines/webjs/session.webjs.core': { WhatsappSessionWebJSCore: noopClass },
    './helpers.proxy': {},
    './media/MediaManager': { MediaManager: noopClass },
    './media/MediaStorageFactory': { MediaStorageFactory: noopClass },
    './storage/LocalSessionAuthRepository': { LocalSessionAuthRepository: noopClass },
    './storage/LocalSessionConfigRepository': { LocalSessionConfigRepository: noopClass },
    './storage/LocalStoreCore': { LocalStoreCore: noopClass },
    './storage/mongo/MongoApiKeyRepository': { MongoApiKeyRepository: noopClass },
    './storage/mongo/MongoSessionAuthRepository': { MongoSessionAuthRepository: noopClass },
    './storage/mongo/MongoSessionConfigRepository': { MongoSessionConfigRepository: noopClass },
    './storage/mongo/MongoSessionMeRepository': { MongoSessionMeRepository: noopClass },
    './storage/mongo/MongoSessionWorkerRepository': { MongoSessionWorkerRepository: noopClass },
    './storage/mongo/MongoStore': { MongoStore: noopClass },
    './storage/psql/PsqlConnectionConfig': { parsePsql: () => ({}) },
    './storage/psql/PsqlApiKeyRepository': { PsqlApiKeyRepository: noopClass },
    './storage/psql/PsqlSessionAuthRepository': { PsqlSessionAuthRepository: noopClass },
    './storage/psql/PsqlSessionConfigRepository': { PsqlSessionConfigRepository: noopClass },
    './storage/psql/PsqlSessionMeRepository': { PsqlSessionMeRepository: noopClass },
    './storage/psql/PsqlSessionWorkerRepository': { PsqlSessionWorkerRepository: noopClass },
    './storage/psql/PsqlStore': { PsqlStore: noopClass },
    './storage/sqlite3/Sqlite3ApiKeyRepository': { Sqlite3ApiKeyRepository: noopClass },
    './storage/sqlite3/Sqlite3SessionMeRepository': { Sqlite3SessionMeRepository: noopClass },
    './storage/sqlite3/Sqlite3SessionWorkerRepository': { Sqlite3SessionWorkerRepository: noopClass },
    '../utils/DefaultMap': { DefaultMap },
    '../utils/logging': { getPinoLogLevel: () => 'info' },
    '../utils/promiseTimeout': {
      sleep: async () => {},
      promiseTimeout: async (_timeout, promise) => promise,
    },
    '../utils/reactive/complete': { complete: () => {} },
    '../utils/reactive/SwitchObservable': { SwitchObservable: noopClass },
    '../config': { getNamespace: () => 'all', getSessionNamespace: () => 'gows' },
    '../version': { VERSION: { version: 'self-test' }, getEngineName: () => 'NOWEB' },
    lodash: { defaults: (target, ...sources) => Object.assign(target, ...sources), keyBy: () => ({}) },
    mongodb: { MongoClient: noopClass },
    'nestjs-pino': { PinoLogger: noopClass },
    rxjs: {
      Subject: noopClass,
      merge: () => {},
      of: () => {},
      retry: () => () => {},
      share: () => () => {},
    },
    'rxjs/operators': {},
    '../config.service': { WhatsappConfigService: noopClass },
    '../structures/enums.dto': {
      WAHAEngine: { GOWS: 'GOWS', NOWEB: 'NOWEB', WPP: 'WPP', WEBJS: 'WEBJS' },
      WAHAEvents: { SESSION_STATUS: 'SESSION_STATUS' },
    },
    './abc/manager.abc': { SessionManager },
    './config/EngineConfigService': { EngineConfigService: noopClass },
    '../plugins/SessionPluginsService': { SessionPluginsService: noopClass },
  };
  const { SessionManagerCore } = evaluateCommonJs(managerCoreSource, coreStubs, 'manager.core.js', environment);
  const coreLog = {
    setContext: () => {},
    info: () => {},
    logger: { child: () => ({ info: () => {}, error: () => {} }) },
  };
  const core = new SessionManagerCore(
    { autoStartDelaySeconds: 0 },
    { getDefaultEngineName: () => 'NOWEB' },
    {},
    {},
    {},
    {},
    coreLog,
    {},
    {},
    {}
  );
  let coreLockCalls = 0;
  let coreChildCalls = 0;
  const coreStarts = [];
  core.withLock = (_name, fn) => {
    coreLockCalls += 1;
    return fn();
  };
  core.log.logger.child = () => {
    coreChildCalls += 1;
    return { info: () => {}, error: () => {} };
  };
  core.start = async name => {
    coreStarts.push(name);
  };
  await core.restartStoppedSessions(['blocked', 'working']);
  assert(coreLockCalls === 1, 'automatic blocked session acquired a lock');
  assert(coreChildCalls === 1, 'automatic blocked session created a logger');
  assert(coreStarts.length === 1 && coreStarts[0] === 'working', 'automatic working session did not start normally');
  await core.start('blocked');
  assert(coreStarts.length === 2 && coreStarts[1] === 'blocked', 'manual core start was incorrectly filtered');
}

function runMessageHandlerSelfTest(source, statusSource, conversationSource) {
  const stubs = {
    '@nestjs/bullmq': { Processor: () => target => target },
    '../../../app_sdk/constants': { JOB_CONCURRENCY: 1 },
    './base': {
      ChatWootInboxMessageConsumer: class ChatWootInboxMessageConsumer {},
      LookupAndCheckChatId: async () => '5511999999999@c.us',
    },
    '../QueueName': { QueueName: { INBOX_MESSAGE_CREATED: 'inbox_message_created' } },
    '../../waha': {
      EngineHelper: {
        WhatsAppMessageKeys: message => {
          const info = message._data.Info;
          return {
            timestamp: new Date(new Date(info.Timestamp).getTime()),
            from_me: info.IsFromMe,
            chat_id: info.Chat,
            message_id: info.ID,
            participant: info.Sender || null,
          };
        },
      },
    },
    '../../../app_sdk/waha/WAHASelf': { WAHASessionAPI: class WAHASessionAPI {} },
    '../../messages/to/whatsapp/markdown': { MarkdownToWhatsApp: value => value },
    '../../messages/to/whatsapp/mentions': { parseMentionsFromText: value => ({ text: value, mentions: null }) },
    '../../../../core/abc/manager.abc': {},
    '../../../../modules/rmutex/rmutex.service': { RMutexService: class RMutexService {} },
    '../../../../utils/promiseTimeout': { sleep: async () => {} },
    'nestjs-pino': { PinoLogger: class PinoLogger {} },
    '../../client/ids': {
      SerializeWhatsAppKey: value => {
        const parts = [Boolean(value.from_me), value.chat_id, value.message_id];
        if (value.participant) parts.push(value.participant);
        return parts.join('_');
      },
    },
    '../../i18n/templates': { TKey: { CW_TO_WA_MESSAGE_TEXT: 'text', CW_TO_WA_MESSAGE_MEDIA_CAPTION: 'caption' } },
    '../../dto/config.dto': { LinkPreview: { LQ: 'LQ', HQ: 'HQ' } },
    '../../../../core/utils/jids': { isJidGroup: () => false, toCusFormat: value => value },
    'mime-types': { lookup: () => null },
  };
  const { MessageHandler } = evaluateCommonJs(source, stubs, 'message_created.js');
  if (typeof MessageHandler !== 'function') throw new Error('self-test: MessageHandler export missing');

  const { MessageStatusService } = evaluateCommonJs(
    statusSource,
    {
      '../client/types': { MessageStatus: { DELIVERED: 'delivered', READ: 'read' } },
      '../../../structures/enums.dto': { WAMessageAck: { DEVICE: 1, READ: 2 } },
    },
    'MessageStatusService.js'
  );
  const { Conversation } = evaluateCommonJs(
    conversationSource,
    { './types': { MessageType: { INCOMING: 'incoming', OUTGOING: 'outgoing', ACTIVITY: 'activity' } } },
    'Conversation.js'
  );
  if (typeof MessageStatusService !== 'function' || typeof Conversation !== 'function') {
    throw new Error('self-test: outbound link exports missing');
  }

  let sends = 0;
  const maps = [];
  const links = [];
  let patchAttempts = 0;
  const mappingService = {
    async getMappingByChatwootCombinedKeyAndPart(_key, part) {
      return maps.find(mapping => mapping.part === part) || null;
    },
    async map(_chatwoot, whatsapp, part) {
      maps.push({
        part,
        message_id: whatsapp.message_id,
        chat_id: whatsapp.chat_id,
        from_me: whatsapp.from_me,
        participant: whatsapp.participant,
      });
    },
    async getWhatsAppMessage() {
      return maps.slice().sort((left, right) => left.part - right.part);
    },
  };
  const providerMessage = index => ({
    id: `provider-${index}`,
    _data: {
      Info: {
        Timestamp: `2026-10-06T00:00:0${index}.000Z`,
        IsFromMe: true,
        Chat: '16505550000@c.us',
        ID: `RAW-${index}`,
        Sender: null,
      },
    },
  });
  const session = {
    readMessages: async () => {},
    startTyping: async () => {},
    stopTyping: async () => {},
    sendText: async () => {
      sends += 1;
      return providerMessage(sends);
    },
    sendFile: async () => {
      sends += 1;
      return providerMessage(sends);
    },
  };
  const accountAPI = {
    messages: {
      async update(request) {
        patchAttempts += 1;
        links.push({
          ids: request.data['waha_source_ids[]'].slice(),
          accountId: request.accountId,
          conversationId: request.conversationId,
          messageId: request.messageId,
        });
        if (patchAttempts === 1) throw new Error('identity_patch_failed');
        return { ok: true };
      },
    },
  };
  const conversation = new Conversation(accountAPI, 9, 42);
  const contactConversationService = { ConversationById: () => conversation };
  const statusService = new MessageStatusService(mappingService, {}, contactConversationService);
  const logger = { debug: () => {}, error: () => {}, info: () => {}, warn: () => {} };
  const locale = { key: () => ({ render: ({ content }) => content }) };
  const config = {
    chat2youHistoryOnboarding: true,
    conversations: { syncMessageStatus: false },
    linkPreview: 'OFF',
  };
  const handler = new MessageHandler(mappingService, logger, session, config, locale, statusService);
  const body = {
    id: 77,
    content: 'self-test',
    content_type: 'text',
    content_attributes: {},
    attachments: [
      { data_url: 'https://files.example.test/first.bin', file_type: 'document' },
      { data_url: 'https://files.example.test/second.bin', file_type: 'document' },
    ],
    created_at: '2026-10-06T00:00:00.000Z',
    conversation: { id: 42 },
  };

  let firstError;
  return handler.handle(body)
    .then(() => {
      throw new Error('self-test: first identity link unexpectedly succeeded');
    })
    .catch(error => {
      if (error.message !== 'identity_patch_failed') throw error;
      firstError = error;
    })
    .then(() => handler.handle(body))
    .then(second => {
      const expectedRawIds = ['RAW-1', 'RAW-2', 'RAW-3'];
      const expectedIds = expectedRawIds.map(id => `true_16505550000@c.us_${id}`);
      if (!firstError) throw new Error('self-test: first identity link did not fail');
      if (sends !== 3) throw new Error(`self-test: expected three provider sends, got ${sends}`);
      if (
        maps.length !== expectedIds.length ||
        maps.map(mapping => mapping.message_id).join(',') !== expectedRawIds.join(',')
      ) {
        throw new Error('self-test: text and attachments were not mapped once each');
      }
      if (patchAttempts !== 2) throw new Error(`self-test: expected two identity PATCH attempts, got ${patchAttempts}`);
      if (
        links.length !== 2 ||
        links.some(link => link.ids.join(',') !== expectedIds.join(',') ||
          link.accountId !== 9 || link.conversationId !== 42 || link.messageId !== 77)
      ) {
        throw new Error('self-test: source link was not retried with the existing mappings');
      }
      if (!Array.isArray(second) || second.length !== 0) {
        throw new Error('self-test: retry unexpectedly sent a provider message');
      }
      return true;
    });
}

async function runSessionStatusSelfTest(source) {
  const order = [];
  const registered = [];
  const repo = {
    config: { chat2youHistoryOnboarding: true },
    registerHistoryConnection: async (session, timestamp) => {
      order.push(`register:${session}:${timestamp}`);
      registered.push({ session, timestamp });
    },
  };
  const BaseConsumer = class {};
  const stubs = {
    '@nestjs/bullmq': { Processor: () => target => target },
    '../../../app_sdk/constants': { JOB_CONCURRENCY: 1 },
    '../../client/messages': {},
    '../../client/types': {},
    '../QueueName': { QueueName: { WAHA_SESSION_STATUS: 'waha_session_status' } },
    './base': { ChatWootWAHABaseConsumer: BaseConsumer },
    '../../emoji': {},
    '../../../../core/abc/manager.abc': { SessionManager: class {} },
    '../../../../modules/rmutex/rmutex.service': { RMutexService: class {} },
    '../../../../structures/enums.dto': {
      WAHASessionStatus: { WORKING: 'WORKING', STOPPED: 'STOPPED' },
    },
    'nestjs-pino': { PinoLogger: class {} },
    '../../i18n/templates': { TKey: {} },
    '../../../../utils/promiseTimeout': { waitUntil: async () => false },
  };
  const exported = evaluateCommonJs(source, stubs, 'session.status.js');
  const { WAHASessionStatusConsumer, SessionStatusHandler } = exported;
  if (typeof WAHASessionStatusConsumer !== 'function' || typeof SessionStatusHandler !== 'function') {
    throw new Error('self-test: session status exports missing');
  }
  SessionStatusHandler.prototype.handle = async () => {
    order.push('handle');
  };
  const consumer = new WAHASessionStatusConsumer({}, {}, {});
  consumer.DIContainer = async () => ({
    ContactConversationService: () => repo,
    Locale: () => ({}),
    WAHASelf: () => ({}),
  });

  await consumer.Process({
    data: {
      app: 'chatwoot',
      event: {
        session: 'session-a',
        chat2youHistoryWorkingAtMs: 1_760_000_000_123,
        payload: { status: 'WORKING', statuses: [{ status: 'WORKING', timestamp: 1_760_000_000_123 }] },
      },
    },
  }, {});
  assert(order.join('|') === 'register:session-a:1760000000123|handle', 'WORKING timestamp was not registered before normal handling');
  assert(registered.length === 1, 'valid WORKING event was not registered exactly once');

  await consumer.Process({
    data: {
      app: 'chatwoot',
      event: { session: 'session-a', payload: { status: 'STOPPED', statuses: [{ status: 'STOPPED', timestamp: 2 }] } },
    },
  }, {});
  assert(order.join('|').endsWith('|handle|handle'), 'non-WORKING status changed live handling');
  assert(registered.length === 1, 'non-WORKING status registered a cutoff');

  await consumer.Process({
    data: {
      app: 'chatwoot',
      event: { session: 'session-a', payload: { status: 'WORKING', statuses: [] } },
    },
  }, {});
  assert(order.join('|').endsWith('|handle|handle|handle'), 'missing canonical timestamp changed live handling');
  assert(registered.length === 1, 'missing canonical timestamp registered a cutoff');

  let invalidError;
  try {
    await consumer.Process({
      data: {
        app: 'chatwoot',
        event: {
          session: 'session-a',
          chat2youHistoryWorkingAtMs: '1760000000123',
          payload: { status: 'WORKING', statuses: [] },
        },
      },
    }, {});
  } catch (error) {
    invalidError = error;
  }
  assert(invalidError && invalidError.message === 'waha_history_working_timestamp_invalid', 'malformed WORKING event did not fail closed');
  assert(order.join('|').endsWith('|handle|handle|handle'), 'malformed WORKING event reached the normal handler');

  const legacyRepo = {
    config: { chat2youHistoryOnboarding: false },
    registerHistoryConnection: async () => {
      throw new Error('legacy app must not register history');
    },
  };
  consumer.DIContainer = async () => ({
    ContactConversationService: () => legacyRepo,
    Locale: () => ({}),
    WAHASelf: () => ({}),
  });
  await consumer.Process({
    data: {
      app: 'legacy-chatwoot',
      event: {
        session: 'session-legacy',
        payload: { status: 'WORKING', statuses: [{ status: 'WORKING', timestamp: 1_760_000_000_456 }] },
      },
    },
  }, {});
}

async function runHistoryTimestampQueueSelfTest(source) {
  const values = new Map();
  const gets = [];
  const sets = [];
  const redis = {
    async get(key) {
      gets.push(key);
      return values.has(key) ? values.get(key) : null;
    },
    async set(key, value, mode) {
      sets.push([key, value, mode]);
      if (values.has(key)) return null;
      values.set(key, value);
      return 'OK';
    },
  };
  const jobs = [];
  const queue = {
    client: Promise.resolve(redis),
    add: async (name, data) => jobs.push({ name, data }),
  };
  const stubs = {
    '@nestjs/common': { Injectable: () => target => target },
    '../consumers/waha/base': { ListenEventsForChatWoot: () => ['SESSION_STATUS'] },
    '../../../core/abc/manager.abc': {
      populateSessionInfo: (event, session) => payload => ({ event, session: session.name, payload }),
    },
    '../../../structures/enums.dto': {
      WAHAEvents: { SESSION_STATUS: 'SESSION_STATUS' },
      WAHASessionStatus: { WORKING: 'WORKING' },
    },
    '../consumers/QueueName': { QueueName: { WAHA_SESSION_STATUS: 'waha_session_status' } },
    './QueueRegistry': { QueueRegistry: class QueueRegistry {} },
    '../di/DIContainer': { ChatWootConfigDefaults: config => config },
  };
  const { ChatWootWAHAQueueService } = evaluateCommonJs(source, stubs, 'ChatWootWAHAQueueService.js');
  if (typeof ChatWootWAHAQueueService !== 'function') {
    throw new Error('self-test: ChatWoot queue service export missing');
  }
  const service = new ChatWootWAHAQueueService({
    queue: () => queue,
  });
  const app = { id: 'app-uuid', config: { chat2youHistoryOnboarding: true } };
  const noQr = await service.historyWorkingData(
    app.config,
    app,
    { chat2youFirstWorkingAtMs: 100, chat2youFirstWorkingHadQr: false },
    { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
  );
  assert(noQr.chat2youHistoryWorkingAtMs === null, 'WORKING before QR was not held without a history timestamp');
  assert(sets.length === 0, 'WORKING before QR wrote the canonical timestamp');

  const first = await service.historyWorkingData(
    app.config,
    app,
    { chat2youFirstWorkingAtMs: 200, chat2youFirstWorkingHadQr: true },
    { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
  );
  assert(first.chat2youHistoryWorkingAtMs === 200, 'first QR-backed WORKING timestamp was not canonicalized');
  assert(sets.length === 1 && sets[0][0] === 'chat2you:waha:first-working:v2:app-uuid' &&
    sets[0][1] === '200' && sets[0][2] === 'NX', 'canonical timestamp did not use SET NX without a TTL');

  const afterRestart = await service.historyWorkingData(
    app.config,
    app,
    { chat2youFirstWorkingAtMs: 300, chat2youFirstWorkingHadQr: false },
    { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
  );
  assert(afterRestart.chat2youHistoryWorkingAtMs === 200, 'existing canonical timestamp was overwritten after restart');

  const subscribers = [];
  service.listenEvents(app, {
    name: 'session-a',
    getEventObservable: () => ({ subscribe: callback => subscribers.push(callback) }),
  });
  await subscribers[0]({ status: 'WORKING' });
  assert(jobs.length === 1 && jobs[0].data.event.chat2youHistoryWorkingAtMs === 200,
    'status queue job did not receive the canonical timestamp');

  const legacy = await service.historyWorkingData(
    { chat2youHistoryOnboarding: false },
    app,
    { chat2youFirstWorkingAtMs: 400, chat2youFirstWorkingHadQr: true },
    { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
  );
  assert(!Object.prototype.hasOwnProperty.call(legacy, 'chat2youHistoryWorkingAtMs'), 'legacy App was enriched with history state');

  const live = await service.historyWorkingData(
    app.config,
    app,
    { chat2youFirstWorkingAtMs: 450, chat2youFirstWorkingHadQr: true },
    { event: 'MESSAGE_ANY', payload: { status: 'WORKING' } }
  );
  assert(!Object.prototype.hasOwnProperty.call(live, 'chat2youHistoryWorkingAtMs'), 'non-status event was enriched with history state');

  const raceValues = new Map();
  let raceSet = true;
  const raceQueue = {
    client: Promise.resolve({
      async get(key) {
        return raceValues.has(key) ? raceValues.get(key) : null;
      },
      async set(key) {
        raceSet = false;
        raceValues.set(key, '250');
        return null;
      },
    }),
  };
  const raceService = new ChatWootWAHAQueueService({ queue: () => raceQueue });
  const race = await raceService.historyWorkingData(
    app.config,
    app,
    { chat2youFirstWorkingAtMs: 300, chat2youFirstWorkingHadQr: true },
    { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
  );
  assert(!raceSet && race.chat2youHistoryWorkingAtMs === 250, 'SET NX race did not read the winning canonical value');

  values.set('chat2you:waha:first-working:v2:app-uuid', 'invalid');
  let invalidError;
  try {
    await service.historyWorkingData(
      app.config,
      app,
      { chat2youFirstWorkingAtMs: 500, chat2youFirstWorkingHadQr: true },
      { event: 'SESSION_STATUS', payload: { status: 'WORKING' } }
    );
  } catch (error) {
    invalidError = error;
  }
  assert(invalidError && invalidError.message === 'waha_history_timestamp_store_invalid', 'invalid canonical Redis state did not fail closed');
  assert(gets.length >= 5, 'canonical timestamp was not read from Redis for each status event');
}

async function runHistoryConnectionClientSelfTest(source) {
  const requests = [];
  const stubs = {
    '@figuro/chatwoot-sdk': { ApiError: class ApiError extends Error {} },
    './ContactService': { AvatarUpdateMode: { IF_MISSING: 'if_missing' } },
    './Conversation': { Conversation: class Conversation {} },
    '../contacts/InboxContactInfo': { InboxContactInfo: class InboxContactInfo {} },
    '../cache/ConversationCache': { CacheForConfig: () => new Map() },
    '../const': { AttributeKey: {} },
  };
  const { ContactConversationService } = evaluateCommonJs(source, stubs, 'ContactConversationService.js');
  if (typeof ContactConversationService !== 'function') {
    throw new Error('self-test: contact conversation service export missing');
  }
  const accountAPI = {
    inboxes: {
      update: async request => {
        requests.push(request);
        return { ok: true };
      },
    },
  };
  const service = new ContactConversationService(
    { accountId: 7, inboxId: 8 },
    {},
    {},
    accountAPI,
    {},
    {}
  );
  await service.registerHistoryConnection('session-a', 1_760_000_000_123);
  assert(requests.length === 1, 'history connection did not perform exactly one inbox update');
  assert(
    requests[0].accountId === 7 && requests[0].id === 8 &&
      requests[0].data.waha_history_connection.session === 'session-a' &&
      requests[0].data.waha_history_connection.working_at_ms === 1_760_000_000_123,
    'history connection update used an unexpected account/inbox payload'
  );

  let invalidError;
  try {
    await service.registerHistoryConnection('session-a', '1760000000123');
  } catch (error) {
    invalidError = error;
  }
  assert(invalidError && invalidError.message === 'waha_history_working_timestamp_invalid', 'invalid timestamp was not rejected');
  assert(requests.length === 1, 'invalid timestamp reached the inbox API');
}

function runConfigDtoSelfTest(source) {
  const decorator = () => () => {};
  const stubs = {
    '@nestjs/swagger': { ApiPropertyOptional: decorator },
    'class-validator': {
      IsBoolean: decorator,
      IsEnum: decorator,
      IsNumber: decorator,
      IsOptional: decorator,
      IsString: decorator,
      ValidateNested: decorator,
    },
    'class-transformer': { Type: decorator },
    '../../../nestjs/validation/IsDynamicObject': { IsDynamicObject: decorator },
    '../services/ConversationSelector': { ConversationSort: {} },
    '../client/types': { ConversationStatus: {} },
  };
  const { ChatWootAppConfig } = evaluateCommonJs(source, stubs, 'config.dto.js');
  const config = new ChatWootAppConfig();
  assert(config.chat2youHistoryOnboarding === false, 'legacy Chatwoot config did not default onboarding off');
}

function runSessionTimestampSelfTest(source) {
  assert(
    source.indexOf('const chat2youTimestamp = Date.now()') < source.indexOf('this.status$.next'),
    'first WORKING timestamp was captured after status emission'
  );
  assert(source.includes(', (0, rxjs_1.timestamp)(),'), 'public status timestamp pipeline was changed');
  assert(source.includes('this.status$.next({ status: status, data: data });'), 'public status payload was changed');
  assert(
    source.includes('this.chat2youFirstWorkingHadQr = this.chat2youQrObserved === true'),
    'first WORKING did not capture the QR prerequisite'
  );
  let now = 1000;
  const setStatus = vm.runInNewContext(`(function(status, data) {
    ${SESSION_ABC_STATUS_AFTER}
  })`, {
    Date: { now: () => now },
    Number,
    enums_dto_1: { WAHASessionStatus: { SCAN_QR_CODE: 'SCAN_QR_CODE', WORKING: 'WORKING' } },
  });
  const state = { events: [], status$: { next: event => state.events.push(event) } };
  setStatus.call(state, 'SCAN_QR_CODE', null);
  now = 2000;
  setStatus.call(state, 'WORKING', null);
  now = 3000;
  setStatus.call(state, 'WORKING', null);
  assert(state.chat2youFirstWorkingAtMs === 2000, 'first WORKING timestamp was overwritten');
  assert(state.chat2youFirstWorkingHadQr === true, 'SCAN_QR_CODE prerequisite was not retained');
  assert(!Object.prototype.hasOwnProperty.call(state.events[1], 'chat2youTimestamp') &&
    !Object.prototype.hasOwnProperty.call(state.events[2], 'chat2youTimestamp'),
    'private timestamp leaked into the public status payload');

  const noQrState = { events: [], status$: { next: event => noQrState.events.push(event) } };
  now = 4000;
  setStatus.call(noQrState, 'WORKING', null);
  assert(noQrState.chat2youFirstWorkingAtMs === 4000 && noQrState.chat2youFirstWorkingHadQr === false,
    'WORKING without QR was not captured as a failed prerequisite');
}

function preparePatch(root, patch) {
  const filename = absolutePath(root, patch.relativePath);
  const stat = fs.lstatSync(filename);
  if (!stat.isFile()) {
    throw new Error(`${patch.relativePath}: expected a regular file`);
  }

  const original = fs.readFileSync(filename);
  const actualSha256 = sha256(original);
  if (actualSha256 !== patch.originalSha256) {
    throw new Error(
      `${patch.relativePath}: original SHA256 mismatch (expected ${patch.originalSha256}, got ${actualSha256})`
    );
  }

  const source = original.toString('utf8');
  if (!Buffer.from(source, 'utf8').equals(original)) {
    throw new Error(`${patch.relativePath}: original bytes are not valid UTF-8`);
  }

  const patched = replacementsFor(patch).reduce((current, replacement, index) => (
    replaceExactly(current, replacement.before, replacement.after, `${patch.relativePath}#${index + 1}`)
  ), source);
  return { filename, patch, patched };
}

function patchFiles(root = '/') {
  const resolvedRoot = path.resolve(root);
  // Prepare every file before writing any file, so a changed second artifact
  // cannot leave a partially patched image behind.
  const prepared = PATCHES.map(patch => preparePatch(resolvedRoot, patch));

  for (const item of prepared) {
    fs.writeFileSync(item.filename, item.patched, 'utf8');
    const finalSha256 = sha256(fs.readFileSync(item.filename));
    if (finalSha256 === item.patch.originalSha256) {
      throw new Error(`${item.patch.relativePath}: patch produced the original SHA256`);
    }
    console.log(`${item.patch.relativePath}: ${item.patch.originalSha256} -> ${finalSha256}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(`self-test: ${message}`);
}

async function selfTest(root = null) {
  const bodyFixture = `${BASE_BODY_BEFORE}\n`;
  const bodyExpected = `${BASE_BODY_AFTER}\n`;
  assert(
    replaceExactly(bodyFixture, BASE_BODY_BEFORE, BASE_BODY_AFTER, 'body') === bodyExpected,
    'body replacement differs from the expected contract'
  );
  assert(
    bodyExpected.includes('body.source_id = payload.id') &&
      bodyExpected.includes('body.external_created_at = payload.timestamp') &&
      bodyExpected.includes('chat2youHistoryOnboarding'),
    'body contract fields are missing'
  );

  const versionFixture = `${VERSION_BEFORE}\n`;
  const versionExpected = `${VERSION_AFTER}\n`;
  assert(
    replaceExactly(versionFixture, VERSION_BEFORE, VERSION_AFTER, 'version') === versionExpected,
    'version replacement differs from the expected contract'
  );
  assert(
    versionExpected.includes("chat2youHistorySourceIds: 'v1'") &&
      versionExpected.includes("chat2youHistoryFirstConnectionTimestamp: 'v1'"),
    'history capability markers are missing'
  );

  let duplicateFailed = false;
  try {
    replaceExactly(`${BASE_BODY_BEFORE}\n${BASE_BODY_BEFORE}`, BASE_BODY_BEFORE, BASE_BODY_AFTER, 'body');
  } catch (error) {
    duplicateFailed = error.message.includes('expected exactly one original block');
  }
  assert(duplicateFailed, 'duplicate body block did not fail closed');

  let alreadyPatchedFailed = false;
  try {
    replaceExactly(BASE_BODY_AFTER.replace(BASE_BODY_BEFORE, 'already patched body'), BASE_BODY_BEFORE, BASE_BODY_AFTER, 'body');
  } catch (error) {
    alreadyPatchedFailed = error.message.includes('found 0');
  }
  assert(alreadyPatchedFailed, 'already-patched body did not fail closed');

  if (root) {
    const wrongHashPatch = { ...PATCHES[0], originalSha256: '0'.repeat(64) };
    let hashMismatchFailed = false;
    try {
      preparePatch(path.resolve(root), wrongHashPatch);
    } catch (error) {
      hashMismatchFailed = error.message.includes('original SHA256 mismatch');
    }
    assert(hashMismatchFailed, 'original hash mismatch did not fail closed');

    const prepared = PATCHES.map(patch => preparePatch(path.resolve(root), patch));
    prepared.forEach(item => assertSyntax(item.patched, item.patch.relativePath));
    const messageCreated = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/consumers/inbox/message_created.js'
    );
    const statusService = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/services/MessageStatusService.js'
    );
    const conversation = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/client/Conversation.js'
    );
    const managerAbc = prepared.find(
      item => item.patch.relativePath === 'app/dist/core/abc/manager.abc.js'
    );
    const managerCore = prepared.find(
      item => item.patch.relativePath === 'app/dist/core/manager.core.js'
    );
    const sessionStatus = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/consumers/waha/session.status.js'
    );
    const contactConversation = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/client/ContactConversationService.js'
    );
    const base = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/consumers/waha/base.js'
    );
    const configDto = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/dto/config.dto.js'
    );
    const sessionAbc = prepared.find(
      item => item.patch.relativePath === 'app/dist/core/abc/session.abc.js'
    );
    const queueService = prepared.find(
      item => item.patch.relativePath === 'app/dist/apps/chatwoot/services/ChatWootWAHAQueueService.js'
    );
    assert(
      base.patched.includes('this.repo.config.chat2youHistoryOnboarding') &&
        base.patched.includes('body.source_id = payload.id') &&
        base.patched.includes('body.external_created_at = payload.timestamp'),
      'live source IDs are not gated by the onboarding capability'
    );
    assert(
      configDto.patched.includes('chat2youHistoryOnboarding') &&
        sessionAbc.patched.includes('const chat2youTimestamp = Date.now()') &&
        sessionAbc.patched.includes('chat2youFirstWorkingHadQr') &&
        queueService.patched.includes("client.set(key, String(timestamp), 'NX')"),
      'provider timestamp capability patch is incomplete'
    );
    runConfigDtoSelfTest(configDto.patched);
    runSessionTimestampSelfTest(sessionAbc.patched);
    await runMessageHandlerSelfTest(messageCreated.patched, statusService.patched, conversation.patched);
    await runSessionStatusSelfTest(sessionStatus.patched);
    await runHistoryTimestampQueueSelfTest(queueService.patched);
    await runHistoryConnectionClientSelfTest(contactConversation.patched);
    await runAutoStartGuardSelfTest(managerAbc.patched, managerCore.patched);
  }

  console.log('self-test: ok');
}

if (require.main === module) {
  if (process.argv[2] === '--self-test') {
    selfTest(process.argv[3] || null).catch(error => {
      console.error(error.message);
      process.exitCode = 1;
    });
  } else {
    patchFiles(process.argv[2] || process.env.WAHA_ROOT || '/');
  }
}

module.exports = {
  BASE_BODY_AFTER,
  BASE_BODY_BEFORE,
  CONVERSATION_UPDATE_STATUS_AFTER,
  CONVERSATION_UPDATE_STATUS_BEFORE,
  MESSAGE_CREATED_POST_SEND_AFTER,
  MESSAGE_CREATED_POST_SEND_BEFORE,
  MESSAGE_STATUS_SERVICE_AFTER,
  MESSAGE_STATUS_SERVICE_BEFORE,
  CONTACT_CONVERSATION_REGISTER_AFTER,
  CONTACT_CONVERSATION_REGISTER_BEFORE,
  CONFIG_DTO_CLASS_AFTER,
  CONFIG_DTO_CLASS_BEFORE,
  CONFIG_DTO_LOCALE_DECORATOR_AFTER,
  CONFIG_DTO_LOCALE_DECORATOR_BEFORE,
  SESSION_ABC_STATUS_AFTER,
  SESSION_ABC_STATUS_BEFORE,
  SESSION_STATUS_PROCESS_AFTER,
  SESSION_STATUS_PROCESS_BEFORE,
  MANAGER_ABC_CONSTRUCTOR_AFTER,
  MANAGER_ABC_CONSTRUCTOR_BEFORE,
  MANAGER_CORE_RESTART_AFTER,
  MANAGER_CORE_RESTART_BEFORE,
  PATCHES,
  VERSION_AFTER,
  VERSION_BEFORE,
  countOccurrences,
  patchFiles,
  replaceExactly,
  selfTest,
  sha256,
};
