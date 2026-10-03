// P1 class scoping: the legacy class keeps working, and another class cannot be read or changed.
// Run: node --test tests/db/p1.test.mjs  (PGlite, no network, no production data)
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";

const root = new URL("../../", import.meta.url);
const sql = p => readFileSync(new URL(p, root), "utf8");
const db = new PGlite();
await db.exec(sql("tests/db/pre-p1-schema.sql"));
await db.exec(`
insert into auth.users(email) values('seepurpple@gmail.com'),('202606@jeonnong.ms.kr');
insert into private.petclass_config(key_hash) values(encode(extensions.digest('K','sha256'),'hex'));
insert into public.classroom_settings(id,application_deadline,teacher_password_hash) values(1,now()-interval '1 day',extensions.crypt('2456',extensions.gen_salt('bf')));
insert into public.classroom_roles values('leader','반장',2,900,1),('audit','지킴이',1,600,2),('bank','통장이',1,550,3),('reading','다독이',2,350,4),('clean','깔끔이',3,400,5);
insert into public.classroom_students(student_no,access_code,role_id) select n,case when n=0 then '2456' else (1000+n*37)::text end,case n when 1 then 'leader' when 2 then 'reading' else null end from generate_series(0,25) n;
insert into public.role_applications(student_id,role_id,preference) select id,'clean',1 from public.classroom_students where student_no in(3,4);
insert into public.point_entries(student_id,delta,title) select id,5000,'시작' from public.classroom_students;
insert into public.classroom_shop_items(id,name,price,note,icon,sort_order) values('food-s','별빛 한입',30,'','',1),('pet-choice-ticket','새 친구 초대권',1000,'','',2),('seat','학급 자리 선정권',1200,'','',3),('normal-draw-1','노멀 뽑기권',700,'','',4);
insert into private.petclass_products values('food-s','food',30),('pet-choice-ticket','ticket',null);
insert into private.petclass_games(id,price,prizes) values('claw',700,'[{"name":"사탕","weight":100}]'),('gacha',1000,'[{"name":"사탕","weight":100}]'),('timing',500,'[]');
insert into private.petclass_logs(student_id,actor,message) values(null,'선생님','옛 기록');
`);
const before = (await db.query(`select (select count(*) from public.classroom_students)::int s,(select sum(delta) from public.point_entries)::int p,(select count(*) from public.role_applications)::int a`)).rows[0];
await db.exec(sql("supabase/migrations/20261003130000_p1_class_scope.sql"));

const g = async (action, token, body = {}) => {
  try { return (await db.query("select public.petclass_gateway('K',$1,$2,$3::jsonb) r", [action, token, JSON.stringify(body)])).rows[0].r; }
  catch (e) { return { thrown: e.message }; }
};
const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const legacyClass = (await one("select id from private.classes")).id;
const afterMigration = await one(`select (select count(*) from public.classroom_students)::int s,(select sum(delta) from public.point_entries)::int p,(select count(*) from public.role_applications)::int a`);
const unscoped = {};
for (const t of ["classroom_students", "classroom_roles", "role_applications", "classroom_shop_items", "role_lottery_audit"])
  unscoped[t] = (await one(`select count(*)::int n from public.${t} where class_id is distinct from $1`, [legacyClass])).n;
const profilesAfterMigration = (await db.query("select email,role,approval_status from private.profiles order by email")).rows;

test("migration keeps every row and ties it to the legacy class", async () => {
  assert.deepEqual(afterMigration, before);
  const cls = await one("select name,student_count,(select email from private.profiles where id=teacher_id) owner from private.classes where id=$1", [legacyClass]);
  assert.deepEqual(cls, { name: "1학년 3반", student_count: 25, owner: "202606@jeonnong.ms.kr" });
  assert.deepEqual(profilesAfterMigration,
    [{ email: "202606@jeonnong.ms.kr", role: "teacher", approval_status: "approved" }, { email: "seepurpple@gmail.com", role: "admin", approval_status: "approved" }]);
  assert.deepEqual(Object.values(unscoped), [0, 0, 0, 0, 0]);
  assert.equal((await one("select monthly_limit from public.classroom_shop_items where id='seat'")).monthly_limit, 3);
  assert.equal((await one("select rule_key from public.classroom_roles where id='reading'")).rule_key, "reading");
});

test("sign-up trigger creates a pending profile", async () => {
  await db.exec("insert into auth.users(email,raw_user_meta_data) values('new@school.kr','{\"display_name\":\"새 선생님\",\"class_name\":\"2학년 1반\"}')");
  assert.deepEqual(await one("select display_name,role,approval_status,requested_class_name from private.profiles where email='new@school.kr'"), { display_name: "새 선생님", role: "teacher", approval_status: "pending", requested_class_name: "2학년 1반" });
});

test("only the gateway is callable by anon", async () => {
  const fns = (await db.query(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private') and has_function_privilege('anon',p.oid,'execute')`)).rows.map(r => r.proname);
  assert.deepEqual(fns, ["petclass_gateway"]);
});

// Legacy sign-in still works and lands in the legacy class.
const teacherA = (await g("login", "", { role: "teacher", code: "2456", limiter: "t" })).token;
const studentA6 = (await g("login", "", { role: "student", code: String(1000 + 6 * 37), limiter: "s" })).token;

test("legacy teacher and student flows are unchanged", async () => {
  assert.ok(teacherA && studentA6);
  const st = await g("state", teacherA);
  assert.equal(st.className, "1학년 3반");
  assert.equal(st.students.length, 26);
  assert.equal(st.products.length, 4);
  assert.deepEqual(Object.keys(st.games).sort(), ["claw", "gacha", "timing"]);
  const snap = await g("legacy", teacherA, { name: "teacher_snapshot", args: {} });
  assert.equal(snap.students.length, 25);
  assert.equal(snap.base.roles.length, 5);
  assert.equal(snap.applications.length, 2);
  const s = await g("state", studentA6);
  assert.equal(s.user.studentNo, 6);
  assert.equal(s.balance, 5000);
  const buy = await g("purchase", studentA6, { sku: "food-s", quantity: 2, expectedPrice: 30, requestId: "req-aaaaaaaaaaaa1" });
  assert.match(buy.message, /2개 구매 완료/);
  assert.equal((await g("state", studentA6)).inventory.length, 1);
  const pts = await g("points", teacherA, { studentIds: [s.user.id], delta: 100, title: "칭찬", requestId: "req-aaaaaaaaaaaa2" });
  assert.match(pts.message, /기록했어요/);
  const idt = await g("legacy", studentA6, { name: "identify_student", args: {} });
  assert.equal(idt.studentNo, 6);
});

test("monthly limit replaces the hard-coded seat rule and is per class", async () => {
  const tokens = [];
  for (const n of [7, 8, 9, 10]) tokens.push((await g("login", "", { role: "student", code: String(1000 + n * 37), limiter: "m" + n })).token);
  for (const [i, t] of tokens.entries()) {
    const r = await g("purchase", t, { sku: "seat", quantity: 1, expectedPrice: 1200, requestId: `req-seat-000000${i}` });
    if (i < 3) assert.match(r.message, /구매 완료/); else assert.match(r.thrown, /모두 소진/);
  }
});

// A second class whose student codes collide with the legacy class.
await db.exec(`
insert into auth.users(email) values('other@school.kr');
update private.profiles set display_name='B',approval_status='approved' where email='other@school.kr';
insert into private.classes(teacher_id,name,student_count) select id,'개멋진반',3 from private.profiles where email='other@school.kr';
`);
const classB = (await one("select id from private.classes where name='개멋진반'")).id;
await db.exec(`
insert into public.classroom_roles(class_id,id,name,capacity,salary) values('${classB}','leader','반장',1,100);
insert into public.classroom_students(class_id,student_no,access_code) select '${classB}',n,(1000+n*37)::text from generate_series(1,3) n;
insert into public.point_entries(student_id,delta,title) select id,700,'B 시작' from public.classroom_students where class_id='${classB}';
insert into public.classroom_shop_items(class_id,id,name,price,sort_order) values('${classB}','food-s','별빛 한입',55,1),('${classB}','seat','자리',10,2);
insert into private.petclass_products(class_id,sku,kind,xp) values('${classB}','food-s','food',30);
insert into private.petclass_games(class_id,id,price,prizes) values('${classB}','claw',300,'[{"name":"B상품","weight":100}]');
insert into public.teacher_sessions(token,expires_at,class_id) values('00000000-0000-0000-0000-0000000000b1',now()+interval '1 hour','${classB}');
insert into private.petclass_sessions(token_hash,teacher_token,expires_at,class_id) values(encode(extensions.digest('teacherB','sha256'),'hex'),'00000000-0000-0000-0000-0000000000b1',now()+interval '1 hour','${classB}');
`);
const snapshotB = async () => one(`select (select sum(delta) from public.point_entries e join public.classroom_students s on s.id=e.student_id where s.class_id=$1)::int pts,
  (select json_agg(price order by id) from public.classroom_shop_items where class_id=$1) prices,
  (select bool_or(archived) from public.classroom_shop_items where class_id=$1) archived,
  (select price from private.petclass_games where class_id=$1 and id='claw') claw,
  (select json_agg(role_id) from public.classroom_students where class_id=$1) roles,
  (select json_agg(access_code order by student_no) from public.classroom_students where class_id=$1) codes`, [classB]);

test("class B students sign in only with class B's id, even with colliding codes", async () => {
  const code = String(1000 + 1 * 37);
  const legacy = await g("login", "", { role: "student", code, limiter: "x1" });
  assert.equal((await g("state", legacy.token)).className, "1학년 3반");
  const b = await g("login", "", { role: "student", code, classId: classB, limiter: "x2" });
  const st = await g("state", b.token);
  assert.equal(st.className, "개멋진반");
  assert.equal(st.balance, 700);
  assert.deepEqual(st.products.map(p => [p.sku, p.price]), [["food-s", 55], ["seat", 10]]);
  assert.deepEqual(Object.keys(st.games), ["claw"]);
});

test("teacher A cannot read or change class B through any action", async () => {
  const bStudentIds = (await db.query("select id from public.classroom_students where class_id=$1", [classB])).rows.map(r => r.id);
  const bEntry = (await one("select e.id from public.point_entries e join public.classroom_students s on s.id=e.student_id where s.class_id=$1 limit 1", [classB])).id;
  const bStudent = await g("login", "", { role: "student", code: String(1000 + 2 * 37), classId: classB, limiter: "x3" });
  const bOrder = await g("purchase", bStudent.token, { sku: "food-s", quantity: 1, expectedPrice: 55, requestId: "req-bbbbbbbbbbbb1" });
  assert.match(bOrder.message, /구매 완료/);
  const orderId = (await one("select o.id from private.petclass_orders o join public.classroom_students s on s.id=o.student_id where s.class_id=$1", [classB])).id;
  const base = await snapshotB();

  const attempts = [
    ["points", { studentIds: bStudentIds, delta: 999, title: "침입", requestId: "req-attack-0001" }],
    ["refund", { orderId, note: "침입 환불", requestId: "req-attack-0002" }],
    ["commit", { studentId: bStudentIds[0], version: 0, data: { pets: [], inventory: [] }, fingerprint: "x", message: "침입", requestId: "req-attack-0003" }],
    ["price", { sku: "food-s", price: 1 }],
    ["removeProduct", { sku: "seat" }],
    ["reorderProducts", { skus: ["seat", "food-s"] }],
    ["gameConfig", { game: "claw", price: 1 }],
    ["legacy", { name: "teacher_update_point_entry", args: { p_entry_id: bEntry, p_delta: 1, p_title: "침입" } }],
    ["legacy", { name: "teacher_delete_point_entry", args: { p_entry_id: bEntry } }],
    ["legacy", { name: "teacher_assign_role", args: { p_student_no: 1, p_role_id: "leader" } }],
    ["legacy", { name: "teacher_update_code", args: { p_student_no: 1, p_code: "4321" } }],
    ["legacy", { name: "teacher_reset", args: { p_scope: "roles" } }],
    ["legacy", { name: "teacher_record_class_points", args: { p_delta: 5, p_title: "전체" } }],
  ];
  for (const [action, body] of attempts) await g(action, teacherA, body);
  assert.deepEqual(await snapshotB(), base);

  const st = await g("state", teacherA);
  assert.ok(st.students.every(s => !bStudentIds.includes(s.id)));
  assert.ok(st.ledger.every(e => e.title !== "B 시작"));
  assert.ok(st.orders.every(o => !bStudentIds.includes(o.student_id)));
  const snap = await g("legacy", teacherA, { name: "teacher_snapshot", args: {} });
  assert.ok(snap.ledger.every(e => e.title !== "B 시작"));

  const stB = await g("state", "teacherB");
  assert.equal(stB.className, "개멋진반");
  assert.equal(stB.students.length, 3);
  assert.ok(stB.ledger.every(e => e.title === "B 시작" || e.title === "별빛 한입"));
});

test("cross-class role references are impossible at the database level", async () => {
  const s = await one("select id from public.classroom_students where class_id=$1 limit 1", [classB]);
  await assert.rejects(db.query("insert into public.role_applications(class_id,student_id,role_id,preference) values($1,$2,'clean',1)", [classB, s.id]));
  await assert.rejects(db.query("insert into public.role_applications(class_id,student_id,role_id,preference) values($1,$2,'leader',1)", [legacyClass, s.id]));
  await assert.rejects(db.query("update public.classroom_students set role_id='clean' where id=$1", [s.id]));
});

test("product images resolve per class", async () => {
  await db.query("update public.classroom_shop_items set image='data:image/png;base64,QUFB' where class_id=$1 and id='food-s'", [classB]);
  assert.equal((await g("productImage", "", { sku: "food-s", classId: classB })).image, "data:image/png;base64,QUFB");
  assert.equal((await g("productImage", "", { sku: "food-s", classId: legacyClass })).image, null);
  const st = await g("state", "teacherB");
  assert.match(st.products.find(p => p.sku === "food-s").image, new RegExp(`c=${classB}&sku=food-s`));
});
