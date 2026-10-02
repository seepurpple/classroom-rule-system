// Run against a production build with AGENT_BROWSER_CLI=/path/to/agent-browser.js.
// API responses are synthetic; this check never reads or changes student records.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

const cli=process.env.AGENT_BROWSER_CLI;
assert.ok(cli,'Set AGENT_BROWSER_CLI to the agent-browser JS entry point');
const base=process.env.PETCLASS_URL||'http://localhost:3016';
const session='petclass-navigation-regression';
function browser(...args){
 const result=spawnSync(process.execPath,[cli,'--session',session,...args],{encoding:'utf8',timeout:45000});
 assert.equal(result.status,0,result.stderr||result.stdout);
 return result.stdout;
}
const now=new Date().toISOString();
const student={number:1,roleId:'fixture-librarian'};
const classroom={roles:[{id:'fixture-librarian',name:'도서 정리',capacity:1,salary:300}],shopItems:[],students:[student],applications:[],ledger:[],publicLedger:[],applicationCounts:{},applicationStudentCount:0,seatSelectionRemaining:3,applicationsOpen:false,deadline:now};
const state={needsSetup:false,user:{id:'fixture-user',name:'선생님',role:'teacher'},className:'1학년 3반',balance:0,version:0,claimedStarter:false,students:[],pets:[],inventory:[],logs:[],orders:[],ledger:[],products:[],updatedAt:now};

try{
 browser('open',base);
 browser('network','route','**/api/classroom','--body',JSON.stringify({data:{...classroom,base:classroom}}));
 for(const role of ['teacher','student']){
  state.user.role=role;
  state.user.name=role==='teacher'?'선생님':'01번 학생';
  if(role==='student')browser('network','unroute','**/api/farm');
  browser('network','route','**/api/farm','--body',JSON.stringify({state}));
  browser('reload');
  browser('wait','.role-assignees');
  browser('errors','--clear');
  browser('console','--clear');
  assert.match(browser('get','text','.role-assignees'),/도서 정리[\s\S]*학생 01/);
  if(role==='teacher'){
   browser('find','role','button','click','--name','학생 역할');
   browser('wait','.roster-grid select');
   assert.equal(browser('eval','document.querySelector(".roster-grid select").value').trim(),'"fixture-librarian"');
  }else{
   browser('find','role','button','click','--name','역할 신청 →');
   browser('wait','.apply-page, .closed-page');
  }
  browser('open',base+'/classroom');
  browser('wait','--url',base+'/');
  assert.equal(browser('errors').trim(),'','Unexpected browser page error');
  assert.doesNotMatch(browser('console'),/RSC prefetch setup error/);
 }
 console.log('PASS: merged classroom views in PetClass, assigned role display, /classroom redirect, no navigation or prefetch errors');
}finally{
 browser('close');
}
