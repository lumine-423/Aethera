import test from 'node:test';
import assert from 'node:assert/strict';
import {HostCoordinator,contextKey,createTavernStore} from '../web/host-coordinator.mjs';
const context={card_id:'card-1',chat_id:'chat-1',branch_id:'branch-a'};
const binding={message_id:3,swipe_id:0,content_fingerprint:'content-hash-1',event_key:'test-event'};
function memoryStore(){const data=new Map();return {fail:false,data,read(key){return structuredClone(data.get(key)??null);},write(key,revision,next){if(this.fail)throw Error('disk_full');if((data.get(key)?.revision??0)!==revision)throw Error('stale_revision');data.set(key,structuredClone(next));}};}
function checkpoint(request,commands=['attack','attack','attack'],terminal=''){return {request,commands,terminal,content_version:'technical-fixture-01'};}
function result(request){return {request_id:request.request_id,task_id:request.task_id,source:request.source,result_id:request.request_id+':result',content_version:'technical-fixture-01',outcome:'victory',turns:3,player_hp:4,enemy_hp:0};}

test('new coordinator resumes an active request and checkpoint after reload',()=>{
 const store=memoryStore();const a=new HostCoordinator(store,context,()=> 'one');const {request}=a.openManual();
 a.saveCheckpoint(request.request_id,checkpoint(request,['attack']));
 const b=new HostCoordinator(store,context);assert.equal(b.resumeCommand().type,'restore_task');assert.equal(b.resumeCommand().checkpoint.commands.length,1);
 assert.throws(()=>b.openManual(),/battle_busy/);
});
test('story identity persists and completed event cannot open a second battle',()=>{
 const store=memoryStore();const a=new HostCoordinator(store,context,()=> 'story-one');const opened=a.openStory(binding);
 a.saveCheckpoint(opened.request.request_id,checkpoint(opened.request));a.commit(result(opened.request));
 const b=new HostCoordinator(store,context,()=> 'must-not-be-used');const repeated=b.openStory(binding);
 assert.equal(repeated.request.request_id,'story-one');assert.equal(repeated.result.outcome,'victory');assert.equal(b.summary().length,1);
});
test('contexts isolate identical story identities and reject stale host writes',()=>{
 const store=memoryStore();const a=new HostCoordinator(store,context,()=> 'a');a.openStory(binding);
 const b=new HostCoordinator(store,{...context,branch_id:'branch-b'},()=> 'b');assert.equal(b.resumeCommand(),null);b.openStory(binding);
 const c=new HostCoordinator(store,{...context,chat_id:'chat-2'});assert.equal(c.resumeCommand(),null);
 assert.notEqual(contextKey(context),contextKey({...context,card_id:'card-2'}));
});
test('result is committed once after durable checkpoint, not before',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'r');const {request}=a.openManual();
 assert.throws(()=>a.commit(result(request)),/result_without_checkpoint/);
 a.saveCheckpoint(request.request_id,checkpoint(request));
 assert.deepEqual(a.commit(result(request)),{duplicate:false,total:1});
 assert.deepEqual(new HostCoordinator(store,context).commit(result(request)),{duplicate:true,total:1});
 assert.throws(()=>a.commit({...result(request),outcome:'defeat'}),/result_conflict/);
});
test('write failure preserves retryable active state; retry does not duplicate result',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'r');const {request}=a.openManual();a.saveCheckpoint('r',checkpoint(request));
 store.fail=true;assert.throws(()=>a.commit(result(request)),/disk_full/);assert.equal(a.inspect().active_id,'r');assert.equal(a.summary().length,0);
 store.fail=false;assert.equal(a.commit(result(request)).total,1);assert.equal(a.inspect().active_id,null);
});
test('v2 released result persists with checkpoint; version cannot change mid-request',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'forms');const {request}=a.openManual();
 const cp={...checkpoint(request,['liberate','ultimate','attack']),content_version:'technical-fixture-02'};
 a.saveCheckpoint('forms',cp);
 assert.throws(()=>a.saveCheckpoint('forms',checkpoint(request)),/checkpoint_version_change/);
 assert.throws(()=>a.commit(result(request)),/result_without_checkpoint/);
 const modern={...result(request),content_version:'technical-fixture-02',actor_id:'rin',form_id:'released',energy:20};
 assert.equal(a.commit(modern).total,1);assert.equal(new HostCoordinator(store,context).commit(modern).duplicate,true);
});
test('v1 checkpoint cannot gain v2 commands or injected logical form',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'legacy');const {request}=a.openManual();
 assert.throws(()=>a.saveCheckpoint('legacy',checkpoint(request,['liberate'])),/invalid_checkpoint_commands/);
 assert.throws(()=>a.saveCheckpoint('legacy',{...checkpoint(request,['attack']),form_id:'released'}),/unexpected_checkpoint_field/);
});
test('checkpoint validation is key-order independent and monotonic',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'r');const {request}=a.openManual();
 const reordered=Object.fromEntries(Object.entries(request).reverse());a.saveCheckpoint('r',checkpoint(reordered,['attack']));
 assert.throws(()=>a.saveCheckpoint('r',checkpoint(request,[])),/checkpoint_regression/);
 assert.throws(()=>a.saveCheckpoint('r',{...checkpoint(request),player_hp:999}),/unexpected_checkpoint_field/);
 assert.throws(()=>a.saveCheckpoint('r',checkpoint({...request,source:'story'})),/checkpoint_mismatch/);
});
test('unknown schema is preserved and rejected, never silently reset',()=>{
 const store=memoryStore();store.data.set(contextKey(context),{schema_version:999,revision:1});
 assert.throws(()=>new HostCoordinator(store,context),/invalid_journal/);assert.equal(store.data.get(contextKey(context)).schema_version,999);
});
test('corrupt persisted links are rejected without resetting the saved document',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'r');a.openManual();
 const saved=structuredClone(store.data.get(contextKey(context)));saved.active_id='missing';store.data.set(contextKey(context),saved);
 assert.throws(()=>new HostCoordinator(store,context),/invalid_journal_links/);assert.equal(store.data.get(contextKey(context)).active_id,'missing');
 saved.active_id='r';saved.requests.r.request.source='injected';store.data.set(contextKey(context),saved);
 assert.throws(()=>new HostCoordinator(store,context),/invalid_journal_links/);
});
test('completed records and story bindings must refer to registered matching requests',()=>{
 const store=memoryStore(),a=new HostCoordinator(store,context,()=> 'r');const opened=a.openStory(binding);
 a.saveCheckpoint('r',checkpoint(opened.request));a.commit(result(opened.request));
 const saved=structuredClone(store.data.get(contextKey(context)));delete saved.results.r;store.data.set(contextKey(context),saved);
 assert.throws(()=>new HostCoordinator(store,context),/invalid_journal_links/);
});
test('Tavern adapter preserves unrelated variables and guards identity/revision',()=>{
 let variables={stat_data:{player:{hp:77}},unrelated:{keep:true}};let active=true;
 const api={getVariables:()=>structuredClone(variables),updateVariablesWith(fn,option){assert.equal(option.type,'chat');variables=fn(structuredClone(variables));}};
 const store=createTavernStore(api,()=>{if(!active)throw Error('context_changed');});
 const a=new HostCoordinator(store,context,()=> 'r');a.openManual();assert.deepEqual(variables.stat_data,{player:{hp:77}});assert.deepEqual(variables.unrelated,{keep:true});
 active=false;assert.throws(()=>a.openStory(binding),/context_changed/);active=true;
 assert.throws(()=>store.write(contextKey(context),0,{}),/stale_revision/);
});
