// P2–P5: teacher accounts, admin approval, class picker, class creation/editing, isolation.
// Run: node --test tests/db/p2.test.mjs  (PGlite, no network, no production data)
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

const root = new URL("../../", import.meta.url);
const sql = p => readFileSync(new URL(p, root), "utf8");
const db = new PGlite();
await db.exec(sql("tests/db/pre-p1-schema.sql"));
await db.exec(`
alter table auth.users add column encrypted_password text, add column instance_id uuid, add column aud text, add column role text,
  add column email_confirmed_at timestamptz, add column raw_app_meta_data jsonb, add column updated_at timestamptz, add column confirmation_token text,
  add column recovery_token text, add column email_change_token_new text, add column email_change text, add column last_sign_in_at timestamptz, add column deleted_at timestamptz;
create table auth.identities(id uuid primary key default gen_random_uuid(),provider_id text not null,user_id uuid not null references auth.users on delete cascade,identity_data jsonb not null,provider text not null,last_sign_in_at timestamptz,created_at timestamptz,updated_at timestamptz);
create function extensions.gen_salt(t text,r int) returns text language sql as $$ select 'stub$' $$;
insert into auth.users(email,encrypted_password) values('seepurpple@gmail.com',extensions.crypt('admin-pass',extensions.gen_salt('bf'))),('202606@jeonnong.ms.kr',extensions.crypt('teacher-pass',extensions.gen_salt('bf')));
insert into private.petclass_config(key_hash) values(encode(extensions.digest('K','sha256'),'hex'));
insert into public.classroom_settings(id,application_deadline,teacher_password_hash) values(1,now()-interval '1 day',extensions.crypt('2456',extensions.gen_salt('bf')));
insert into public.classroom_roles values('leader','반장',2,900,1),('reading','다독이',2,350,4),('clean','깔끔이',3,400,5);
insert into public.classroom_students(student_no,access_code,role_id) select n,case when n=0 then '2456' else (1000+n*37)::text end,case n when 1 then 'leader' else null end from generate_series(0,25) n;
insert into public.point_entries(student_id,delta,title) select id,5000,'시작' from public.classroom_students;
insert into public.classroom_shop_items(id,name,price,note,icon,sort_order) values('food-s','별빛 한입',30,'','',1),('seat','학급 자리 선정권',1200,'','',2);
insert into private.petclass_products values('food-s','food',30);
insert into private.petclass_games(id,price,prizes) values('claw',700,'[{"name":"사탕","weight":100}]'),('gacha',1000,'[{"name":"사탕","weight":100}]'),('timing',500,'[]');
`);
await db.exec(sql("supabase/migrations/20261003130000_p1_class_scope.sql"));
await db.exec(sql("supabase/migrations/20261003150000_p2_accounts_classes.sql"));

const g = async (action, token, body = {}) => {
  try { return (await db.query("select public.petclass_gateway('K',$1,$2,$3::jsonb) r", [action, token, JSON.stringify(body)])).rows[0].r; }
  catch (e) { return { thrown: e.message }; }
};
const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const legacyClass = (await one("select id from private.classes")).id;
const DEFAULT_ROLES = [{ name: "반장", capacity: 2, salary: 900, ruleKey: "leader" }, { name: "다독이", capacity: 1, salary: 350, ruleKey: "reading" }, { name: "깔끔이", capacity: 2, salary: 400 }];

test("old 2456 teacher password and class-less student login are gone", async () => {
  assert.equal((await g("login", "", { role: "teacher", code: "2456", ip: "a" })).status, 400);
  assert.equal((await g("login", "", { role: "student", code: "1037", ip: "a" })).status, 400);
  assert.match((await g("teacherLogin", "", { email: "202606@jeonnong.ms.kr", password: "2456", ip: "a" })).error, /비밀번호/);
  assert.match((await g("teacherLogin", "", { email: "202606@jeonnong.ms.kr", ip: "a" })).error, /비밀번호/);
});

test("legacy teacher signs in by email and keeps the whole class", async () => {
  const r = await g("teacherLogin", "", { email: " 202606@JEONNONG.ms.kr ", password: "teacher-pass", ip: "a" });
  assert.equal(r.state.className, "1학년 3반");
  assert.equal(r.state.user.role, "teacher");
  assert.equal(r.state.students.length, 26);
  const snap = await g("legacy", r.token, { name: "teacher_snapshot", args: {} });
  assert.equal(snap.base.presets.length, 14);
  assert.equal(snap.base.presets.find(p => p.id === "harm-class").title, "3반 학생 피해");
  assert.equal(snap.base.payrollRules.length, 12);
  const list = await g("classList", "");
  assert.deepEqual(list.classes.map(c => c.name), ["1학년 3반"]);
  const s = await g("login", "", { code: "1037", classId: legacyClass, ip: "a" });
  assert.equal(s.state.user.studentNo, 1);
  assert.equal(s.state.className, "1학년 3반");
});

let newTeacher, classB;
test("sign-up waits for approval, admin approves, teacher creates a class", async () => {
  const bad = await g("signup", "", { email: "x@y.kr", password: "short", displayName: "새", className: "개멋진반", ip: "b" });
  assert.match(bad.error, /8~72/);
  assert.match((await g("signup", "", { email: "new@school.kr", password: "new-teacher-1", displayName: "새 선생님", className: "1학년3반", ip: "b" })).error, /이미 있는 반 이름/);
  const ok = await g("signup", "", { email: "New@School.kr", password: "new-teacher-1", displayName: "새 선생님", className: "개멋진반", ip: "b" });
  assert.match(ok.message, /승인/);
  assert.match((await g("signup", "", { email: "new@school.kr", password: "new-teacher-1", displayName: "x", className: "다른반", ip: "b" })).error, /이미 가입된/);
  assert.match((await g("signup", "", { email: "dup@school.kr", password: "new-teacher-1", displayName: "x", className: "개 멋진반", ip: "b" })).error, /이미 있는 반 이름/);
  assert.match((await g("teacherLogin", "", { email: "new@school.kr", password: "new-teacher-1", ip: "b" })).error, /승인을 기다리고/);

  const admin = await g("teacherLogin", "", { email: "seepurpple@gmail.com", password: "admin-pass", ip: "c" });
  assert.equal(admin.state.user.role, "admin");
  const list = await g("adminList", admin.token);
  const pending = list.accounts.find(a => a.email === "new@school.kr");
  assert.equal(pending.status, "pending");
  assert.equal(pending.requestedClassName, "개멋진반");
  assert.match((await g("adminReview", admin.token, { id: pending.id, approve: true })).message, /승인/);

  const t = await g("teacherLogin", "", { email: "new@school.kr", password: "new-teacher-1", ip: "b" });
  assert.equal(t.state.user.needsClass, true);
  assert.equal(t.state.user.requestedClassName, "개멋진반");
  assert.match((await g("classUpdate", t.token, { name: "x" })).thrown, /먼저 학급/);
  assert.match((await g("classCreate", t.token, { name: "1학년 3반", studentCount: 3, roles: DEFAULT_ROLES })).thrown, /이미 있는 반 이름/);
  const made = await g("classCreate", t.token, { name: "개멋진반", studentCount: 3, deadline: new Date(Date.now() + 864e5).toISOString(), roles: DEFAULT_ROLES });
  assert.equal(made.state.className, "개멋진반");
  assert.equal(made.state.students.length, 4);
  assert.equal(made.state.products.length, 4);
  assert.deepEqual(Object.keys(made.state.games).sort(), ["claw", "gacha", "timing"]);
  newTeacher = t.token;
  classB = made.state.user.classId;
  const snap = await g("legacy", newTeacher, { name: "teacher_snapshot", args: {} });
  assert.deepEqual(snap.base.roles.map(r => [r.name, r.ruleKey]), [["반장", "leader"], ["다독이", "reading"], ["깔끔이", null]]);
  assert.equal(snap.students.length, 3);
  assert.equal(new Set(snap.students.map(s => s.code)).size, 3);
  const test0 = made.state.students.find(s => s.studentNo === 0);
  assert.equal(test0.balance, 100000);
  assert.deepEqual((await g("classList", "")).classes.map(c => c.name).sort(), ["1학년 3반", "개멋진반"]);
});

test("students pick their class; the same code in two classes stays separate", async () => {
  const code = (await one("select access_code from public.classroom_students where class_id=$1 and student_no=1", [classB])).access_code;
  await db.query("update public.classroom_students set access_code='1037' where class_id=$1 and student_no=2 and $2<>'1037'", [classB, code]);
  const b = await g("login", "", { code: "1037", classId: classB, ip: "d" });
  const a = await g("login", "", { code: "1037", classId: legacyClass, ip: "d" });
  assert.equal(b.state.className, "개멋진반");
  assert.equal(a.state.className, "1학년 3반");
  assert.notEqual(b.state.user.id, a.state.user.id);
});

test("teacher B edits only class B; special roles keep their name", async () => {
  const roles = (await g("legacy", newTeacher, { name: "teacher_snapshot", args: {} })).base.roles;
  const leader = roles.find(r => r.ruleKey === "leader");
  assert.match((await g("roleSave", newTeacher, { id: leader.id, name: "회장", capacity: 2, salary: 900 })).thrown, /이름을 바꿀 수 없어요/);
  assert.match((await g("roleSave", newTeacher, { id: leader.id, name: "반장", capacity: 3, salary: 1000 })).message, /저장/);
  assert.match((await g("roleSave", newTeacher, { name: "화분이", capacity: 1, salary: 200 })).message, /저장/);
  assert.match((await g("roleSave", newTeacher, { name: "화분이", capacity: 1, salary: 200 })).thrown, /같은 이름/);
  const cleaner = roles.find(r => r.name === "깔끔이");
  assert.match((await g("roleDelete", newTeacher, { id: cleaner.id })).message, /삭제/);
  // Same role ids exist in class A ('leader'): nothing there may change.
  const before = await one("select json_agg(json_build_object('id',id,'name',name,'cap',capacity,'sal',salary) order by id) r from public.classroom_roles where class_id=$1", [legacyClass]);
  await g("roleSave", newTeacher, { id: "leader", name: "반장", capacity: 9, salary: 1 });
  await g("roleDelete", newTeacher, { id: "clean" });
  await g("presetDelete", newTeacher, { id: "praise" });
  await g("productLimit", newTeacher, { sku: "seat", monthlyLimit: "99" });
  assert.deepEqual(await one("select json_agg(json_build_object('id',id,'name',name,'cap',capacity,'sal',salary) order by id) r from public.classroom_roles where class_id=$1", [legacyClass]), before);
  assert.equal((await one("select count(*)::int n from private.class_point_presets where class_id=$1", [legacyClass])).n, 14);
  assert.equal((await one("select monthly_limit from public.classroom_shop_items where class_id=$1 and id='seat'", [legacyClass])).monthly_limit, 3);
  assert.match((await g("presetSave", newTeacher, { kind: "earn", title: "청소 칭찬", amount: "50", all: false })).message, /저장/);
  assert.equal((await one("select count(*)::int n from private.class_point_presets where class_id=$1", [classB])).n, 14);
});

test("fewer students deactivates trailing numbers; more brings them back with the same code", async () => {
  const code3 = (await one("select access_code from public.classroom_students where class_id=$1 and student_no=3", [classB])).access_code;
  assert.match((await g("classUpdate", newTeacher, { studentCount: 2 })).message, /저장/);
  assert.equal((await g("login", "", { code: code3, classId: classB, ip: "e" })).status, 401);
  const r = await g("classUpdate", newTeacher, { studentCount: 5, name: "개멋진 반", deadline: "" });
  assert.equal(r.state.className, "개멋진 반");
  assert.ok((await g("login", "", { code: code3, classId: classB, ip: "e" })).token);
  const snap = await g("legacy", newTeacher, { name: "teacher_snapshot", args: {} });
  assert.deepEqual(snap.students.map(s => s.number), [1, 2, 3, 4, 5]);
  assert.equal(new Set(snap.students.map(s => s.code)).size, 5);
  assert.equal(snap.base.studentCount, 5);
});

test("repeated wrong codes slow down one key without locking the class", async () => {
  for (let i = 0; i < 5; i++) assert.equal((await g("login", "", { code: "0000", classId: classB, ip: "f" })).status, 401);
  assert.equal((await g("login", "", { code: "0000", classId: classB, ip: "f" })).status, 429);
  const other = (await one("select access_code from public.classroom_students where class_id=$1 and student_no=1", [classB])).access_code;
  assert.ok((await g("login", "", { code: other, classId: classB, ip: "g" })).token, "another device is not blocked");
});

test("admin sees accounts only, never class data", async () => {
  const admin = await g("teacherLogin", "", { email: "seepurpple@gmail.com", password: "admin-pass", ip: "h" });
  const st = await g("state", admin.token);
  assert.deepEqual([st.students, st.ledger, st.products, st.orders, st.logs], [[], [], [], [], []]);
  assert.match((await g("legacy", admin.token, { name: "teacher_snapshot", args: {} })).thrown, /교사 인증/);
  assert.match((await g("points", admin.token, { studentIds: [], delta: 1, title: "x", requestId: "req-admin-000001" })).thrown, /교사 인증/);
  assert.match((await g("adminList", newTeacher)).thrown, /관리자만/);
  const list = await g("adminList", admin.token);
  assert.deepEqual(Object.keys(list.accounts[0]).sort(), ["className", "createdAt", "displayName", "email", "id", "note", "requestedClassName", "status", "studentCount"]);
});

test("temporary password, class reset and account delete", async () => {
  const admin = (await g("teacherLogin", "", { email: "seepurpple@gmail.com", password: "admin-pass", ip: "h" })).token;
  const id = (await one("select id from private.profiles where email='new@school.kr'")).id;
  assert.match((await g("adminSetPassword", admin, { id, password: "temp-pass-1" })).message, /임시 비밀번호/);
  assert.equal((await g("state", newTeacher)).user, null, "old session ends");
  const t = await g("teacherLogin", "", { email: "new@school.kr", password: "temp-pass-1", ip: "i" });
  assert.equal(t.state.className, "개멋진 반");
  assert.match((await g("changePassword", t.token, { current: "temp-pass-1", next: "my-own-pass" })).message, /바꿨/);

  const sid = (await one("select id from public.classroom_students where class_id=$1 and student_no=1", [classB])).id;
  await g("points", t.token, { studentIds: [sid], delta: 300, title: "칭찬", requestId: "req-reset-0000001" });
  assert.match((await g("adminResetClass", admin, { id, confirm: "개멋진반" })).thrown, /확인 문구/);
  assert.match((await g("adminResetClass", admin, { id, confirm: "개멋진 반" })).message, /초기화/);
  const after = await one("select (select count(*) from public.classroom_students where class_id=$1)::int students,(select coalesce(sum(delta),0) from public.point_entries e join public.classroom_students s on s.id=e.student_id where s.class_id=$1 and s.student_no>0)::int pts,(select count(*) from public.classroom_roles where class_id=$1)::int roles", [classB]);
  assert.deepEqual(after, { students: 6, pts: 0, roles: 3 });
  const legacyPts = (await one("select sum(delta)::int p from public.point_entries e join public.classroom_students s on s.id=e.student_id where s.class_id=$1", [legacyClass])).p;

  assert.ok((await g("adminExport", admin, { id })).export.students.length === 6);
  assert.match((await g("adminDeleteAccount", admin, { id, confirm: "개멋진 반" })).message, /계정 삭제/);
  assert.equal((await one("select count(*)::int n from private.classes where id=$1", [classB])).n, 0);
  assert.equal((await one("select count(*)::int n from auth.users where email='new@school.kr'")).n, 0);
  assert.equal((await one("select sum(delta)::int p from public.point_entries e join public.classroom_students s on s.id=e.student_id where s.class_id=$1", [legacyClass])).p, legacyPts, "other classes untouched");
  assert.equal((await g("state", t.token)).user, null);
  assert.equal((await one("select count(*)::int n from private.admin_audit")).n >= 4, true);
});

test("only the gateway is callable by anon and private tables stay closed", async () => {
  const fns = (await db.query(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and has_function_privilege('anon',p.oid,'execute')`)).rows.map(r => r.proname);
  assert.deepEqual(fns, ["petclass_gateway"]);
  const tables = (await db.query(`select tablename from pg_tables where schemaname='private' and has_table_privilege('anon',schemaname||'.'||tablename,'select')`)).rows;
  assert.deepEqual(tables, []);
});
