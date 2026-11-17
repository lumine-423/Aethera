/* Project-owned narrow transport; no SillyTavern APIs and no world-state writes. */
(() => {
  'use strict';
  const CHANNEL = 'sigil-rolecard-rpg';
  const allowedOrigins = new Set(['http://127.0.0.1:8765', 'http://localhost:8765']);
  const query = new URLSearchParams(location.search);
  const origin = query.get('parent_origin');
  const token = query.get('token');
  const enabled = allowedOrigins.has(origin) && /^[A-Za-z0-9-]{16,96}$/.test(token || '') && parent !== window;
  const pending = [];
  function send(payload) {
    if (enabled) parent.postMessage({channel: CHANNEL, version: 1, token, ...payload}, origin);
  }
  addEventListener('message', event => {
    if (!enabled || event.source !== parent || event.origin !== origin) return;
    const value = event.data;
    if (!value || value.channel !== CHANNEL || value.version !== 1 || value.token !== token || !['start_task','restore_task'].includes(value.type)) return;
    let length;
    try { length = JSON.stringify(value).length; } catch { return; }
    if (length > 8192 || pending.length >= 16) return;
    const r = value.request;
    if (!r || r.protocol_version !== 1 || r.task_id !== 'probe.basic' || !['manual', 'story'].includes(r.source) ||
        typeof r.request_id !== 'string' || !/^[A-Za-z0-9._:-]{1,96}$/.test(r.request_id) ||
        Object.keys(r).some(key => !['protocol_version', 'request_id', 'task_id', 'source'].includes(key))) {
      send({type: 'request_rejected', request_id: '', reason: 'invalid_transport_request'});
      return;
    }
    const request = {protocol_version: 1, request_id: r.request_id, task_id: r.task_id, source: r.source};
    if (value.type === 'restore_task') {
      const checkpoint = value.checkpoint;
      const versions = {'technical-fixture-01':['attack','guard'],'technical-fixture-02':['attack','guard','liberate','ultimate']};
      const commands = Object.hasOwn(versions,checkpoint?.content_version) ? versions[checkpoint.content_version] : null;
      if (!checkpoint || !commands ||
          !Array.isArray(checkpoint.commands) || checkpoint.commands.length > 32 ||
          checkpoint.commands.some(command => !commands.includes(command)) ||
          !checkpoint.request || Object.keys(checkpoint.request).length !== 4 ||
          Object.keys(request).some(key => checkpoint.request[key] !== request[key])) return;
      pending.push({type:'restore_task',request,checkpoint});
    } else pending.push({type:'start_task',request});
  });
  window.rolecardRpgBridge = Object.freeze({
    drain_commands() { return JSON.stringify(pending.splice(0)); },
    emit_response(raw) {
      if (typeof raw !== 'string' || raw.length > 8192) return;
      let response;
      try { response = JSON.parse(raw); } catch { return; }
      if (response && ['engine_ready', 'task_ack', 'checkpoint', 'task_result', 'request_rejected'].includes(response.type)) send(response);
    },
  });
})();
